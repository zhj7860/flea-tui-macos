import QtQuick
import "js/ControlReader.js" as ControlReader

// Installed only in the capture fixture's UI copy; observes real handlers, clipped targets and filter-menu rows without changing rendering.
QtObject {
    function read(quick, top, kinds, alias): string {
        // Sample input, ControlReader.read's JSON: {"focus":{"kind":"DialogButton","via":"owner"},"controls":[{"kind":"DialogButton","name":"Open","x":900,"y":612,"w":96,"h":32}]}
        var state = JSON.parse(ControlReader.read(quick, top, kinds, alias))
        state.captureReader = "porttp4d"
        state.previewColumns = []
        state.scrollBars = []
        var menus = JSON.parse(ControlReader.read(quick, top, /^(MenuRow|CardScroll|ViewportScrollBar)_QML/, {})).controls
        for (var m = 0; m < menus.length; m++) {
            var menu = menus[m]
            if (!state.controls.some(function(c) { return c.kind === menu.kind && c.x === menu.x && c.y === menu.y }))
                state.controls.push(menu)
        }
        function handler(item, name) {
            var data = item.data || []
            // Sample input: String(data[i]) === "QQuickTapHandler(0x55d0c8a1b2c0)"
            for (var i = 0; i < data.length; i++)
                if (data[i] && String(data[i]).indexOf(name) === 0) return data[i]
            return null
        }
        function describe(item, entry) {
            var left = 0, up = 0, right = top.width, bottom = top.height, surface = ""
            for (var owner = item; owner; owner = owner.parent) {
                // Sample input: String(owner) === "SettingsPanel_QML_214(0x55d0c8a1b2c0)"
                var match = String(owner).match(/^(PermissionsDialog|NetworkDialog|SettingsPanel|ContextMenu|Preview|PreviewColumn|SelectionPreview|KeymapSheet|OpenWithDialog|ConvertDialog|MenuActionDialog|CollideConfirm|TrashConfirm|TrashView|TransferCard)_QML/)
                if (!surface && match) surface = match[1] === "SelectionPreview" ? "PreviewColumn" : match[1]
                if (owner.clip) {
                    var point = owner.mapToItem(null, 0, 0)
                    left = Math.max(left, point.x); up = Math.max(up, point.y)
                    right = Math.min(right, point.x + owner.width); bottom = Math.min(bottom, point.y + owner.height)
                }
            }
            entry.surface = surface
            entry.targetX = entry.x + Math.floor(entry.w / 2)
            entry.targetY = entry.y + Math.floor(entry.h / 2)
            if (entry.kind === "ViewportScrollBar") {
                var knob = item.knobItem, centre = knob.mapToItem(null, knob.width / 2, knob.height / 2)
                entry.name = item.vertical ? "Vertical scroll bar" : "Horizontal scroll bar"
                entry.value = item.vertical ? "vertical" : "horizontal"
                entry.targetX = Math.round(centre.x); entry.targetY = Math.round(centre.y)
                entry.hoverable = true; entry.hovered = item.inLane
                entry.pressable = true; entry.pressed = item.dragging
            }
            if (entry.kind === "CardScroll") entry.name = "Keys body"
            entry.exposed = entry.targetX >= left && entry.targetX < right && entry.targetY >= up && entry.targetY < bottom
            if (entry.kind === "ViewportScrollBar")
                entry.exposed = entry.exposed && item.shown && item.knobItem.parent.opacity > 0
            var pointer = item
            if (entry.kind === "CheckBox" && item.parent && item.parent.hovered !== undefined) pointer = item.parent
            var hover = handler(pointer, "QQuickHoverHandler"), tap = handler(pointer, "QQuickTapHandler")
            if (hover) { entry.hoverable = true; entry.hovered = hover.hovered === true }
            if (tap) { entry.pressable = true; entry.pressed = tap.pressed === true }
            entry.hoverLive = entry.hoverable && (!hover || hover.enabled)
            entry.pressLive = entry.pressable && (!tap || tap.enabled)
            if (entry.kind === "MenuRow") {
                entry.name = String(item.entry.label || "")
                entry.focused = item.current === true
                entry.value = String(item.entry.action || "")
                entry.exposed = entry.exposed && !item.isSeparator
                if (entry.focused) state.focus = Object.assign({}, entry, {via: "menu"})
            }
            if (entry.kind === "SettingsRow") entry.value = String(item.kind)
        }
        function walk(item) {
            if (!item) return
            // Sample input: String(item) is "SelectionPreview_QML_123(0x55d0c0a8)"; the type is the text before "(".
            if (/^(PreviewColumn|SelectionPreview)_QML/.test(String(item)))
                state.previewColumns.push({type: String(item).split("(")[0], visible: item.visible, opacity: item.opacity,
                    loaded: item.pdfLoaded(), drawn: item.pdfDrawn})
            if (String(item).indexOf("ViewportScrollBar_QML") === 0) {
                var at = item.mapToItem(null, 0, 0)
                state.scrollBars.push({x: Math.round(at.x), y: Math.round(at.y), visible: item.visible, opacity: item.opacity,
                    shown: item.shown, overflow: item.overflow, content: item.contentLength, viewport: item.viewportLength,
                    position: item.contentPosition})
            }
            if (!item.visible || item.opacity <= 0) return
            // Sample input: String(item) === "DialogButton_QML_88(0x55d0c8a1b2c0)", or "MenuRow_QML_40(0x55d0c8a1b2c0)"
            var point = item.mapToItem(null, 0, 0), name = String(item)
            var match = name.match(kinds) || name.match(/^(MenuRow|CardScroll|ViewportScrollBar)_QML/)
            var menu = name.indexOf("MenuRow_QML") === 0
            if (match || menu) {
                var kind = match ? (alias[match[1]] || match[1]) : "MenuRow"
                for (var i = 0; i < state.controls.length; i++) {
                    var entry = state.controls[i]
                    if (entry.kind === kind && entry.x === Math.round(point.x) && entry.y === Math.round(point.y))
                        describe(item, entry)
                }
            }
            if (name.indexOf("MediaStrip_QML") === 0 && item.playItem) {
                var play = item.playItem, at = play.mapToItem(null, 0, 0)
                var media = {kind: "MediaPlay", name: item.playing ? "Pause" : "Play", x: Math.round(at.x), y: Math.round(at.y),
                    w: Math.round(play.width), h: Math.round(play.height), enabled: play.enabled, focused: play.activeFocus,
                    hovered: false, pressed: false, hoverable: false, pressable: false, value: "", primary: false, destructive: false, member: false}
                describe(play, media)
                state.controls.push(media)
            }
            for (var j = 0; j < item.children.length; j++) walk(item.children[j])
        }
        walk(top)
        state.controls = state.controls.filter(function(c) {
            return (c.kind !== "CardScroll" || c.surface === "KeymapSheet")
                && (c.kind !== "ViewportScrollBar" || c.surface === "PreviewColumn")
        })
        return JSON.stringify(state)
    }
}
