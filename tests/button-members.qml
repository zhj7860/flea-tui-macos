//@ pragma ShellId flea-button-members-test

import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "flea/js/Protocols.js" as Protocols
import "flea/js/TextSize.js" as TextSize
import "button-probe.js" as Probe
import "qml-probe.js" as QmlProbe

// tests/button-system.sh's second harness: the controls that took ButtonSystem040 A late, the protocol members, the picker's answers and marks, and the Copy to field, held to A's numbers.
ShellRoot {
    id: shell

    readonly property real rulingHover: 0.08
    readonly property real rulingPress: 0.14
    readonly property real rulingPressScale: 0.96
    readonly property real rulingDisabled: 0.55
    readonly property int rulingThick: 2
    readonly property int rulingHeight: 30
    readonly property int rulingSetGap: 4
    readonly property real alphaEpsilon: 0.002
    readonly property int parkX: 760
    readonly property int parkY: 1100
    readonly property int releaseOutside: -40
    readonly property int noDelay: 0
    readonly property int settleTicks: 4
    readonly property int tickMs: 16
    readonly property int outerTimeoutS: Number(Quickshell.env("BUTTONSYS_TIMEOUT_S")) || 60
    readonly property int capShare: 2
    readonly property int msPerSecond: 1000
    readonly property double startedAt: Date.now()
    readonly property int capMs: shell.outerTimeoutS * shell.msPerSecond / shell.capShare
    // The reference text size, where body is 14 and the control 30 (ButtonSystem040).
    readonly property int pinnedSize: 14
    readonly property string rootDir: Quickshell.env("BUTTONSYS_ROOT") || ""
    readonly property var states: ["rest", "hover", "focus", "pressed", "disabled"]

    property int checks: 0
    property var failures: []
    property var readings: ({})
    property int step: 0
    property int quiet: 0
    property real lastScale: -1
    property bool acted: false
    property var script: []
    property int cancels: 0
    property int accepts: 0
    property int plains: 0
    property var stepped: []

    function log(line) { QmlProbe.log("MEMBERS", line) }
    function check(name, actual, expected) { QmlProbe.checkLoud(shell, name, actual, expected) }
    function finish() {
        QmlProbe.logDone(shell)
        QmlProbe.stepPastEnd(shell)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
    function near(a, b) { return Math.abs(a - b) < shell.alphaEpsilon }
    function underRoot(path) {
        return shell.rootDir.length > 0 && path.indexOf(shell.rootDir + "/") === 0 && path.split("/").indexOf("..") < 0
    }

    // The five states of one control; each act leaves the pointer and keyboard as the state needs them.
    function seriesFor(key, item, avail, activations) {
        shell.readings[key] = {}
        function record(state) { return function () { shell.readings[key][state] = Probe.read(item) } }
        return [
            { item: item, name: key + ":rest", act: function () { parking.forceActiveFocus(); shell.park() }, record: record("rest") },
            { item: item, name: key + ":hover", act: function () { shell.hoverOn(item) }, record: record("hover") },
            { item: item, name: key + ":focus", act: function () { shell.park(); item.forceActiveFocus() }, record: record("focus") },
            { item: item, name: key + ":pressed", act: function () { parking.forceActiveFocus(); shell.hoverOn(item); shell.pressOn(item) }, record: record("pressed") },
            { item: item, name: key + ":released", act: function () { shell.releaseOff(item); shell.park() }, record: function () {
                shell.check(key + ": a press released outside does not activate", activations(), 0)
            } },
            { item: item, name: key + ":disabled", act: function () { avail(false) }, record: record("disabled") },
            { item: item, name: key + ":disabled-input", act: function () {
                item.forceActiveFocus(); shell.hoverOn(item); shell.pressOn(item); shell.releaseOff(item)
                driver.keyClick(Qt.Key_Return, Qt.NoModifier, shell.noDelay)
            }, record: function () {
                shell.check(key + ": a disabled control activates on neither pointer nor Return", activations(), 0)
                avail(true)
            } }
        ]
    }

    // A is one ladder (hover 8% and press 14% inside the frame, only the frame and wash shrink, disabled dims); focus is the control's own frame, no control holds a ring, and focus moves nothing. A picker answer keeps the control height and body size, its frame inside the answer row's insets.
    function ladder(key, ink, frame, focusFrame, sizes) {
        var r = shell.readings[key]
        var wantSizes = sizes || [shell.rulingHeight, shell.rulingHeight, Flea.Theme.font.body]
        for (var i = 0; i < shell.states.length; i++) {
            var state = shell.states[i]
            var drawnSizes = wantSizes.slice()
            if (state === "pressed") drawnSizes[1] -= 2 * Math.round(drawnSizes[1] * (1 - shell.rulingPressScale) / 2)
            shell.check(key + " " + state + ": outer height, frame height and label size", [r[state].outerHeight, r[state].frameHeight, r[state].labelSize], drawnSizes)
            var off = state === "disabled"
            var want = off ? Probe.rgba(Flea.Theme.color.mutedFrame) : state === "focus" ? focusFrame : frame
            shell.check(key + " " + state + ": the frame is one hairline in " + (off ? "muted" : state === "focus" ? "the focus frame" : frame), [r[state].frameColor, r[state].frameWidth], [want, Flea.Theme.spacing.hairline])
            shell.check(key + " " + state + ": the label inks " + (off ? "muted" : ink), r[state].ink, off ? Probe.rgba(Flea.Theme.color.muted) : ink)
            shell.check(key + " " + state + ": the wash lies inside the frame at its width, so the frame never changes",
                        [r[state].washInsetX, r[state].washInsetY, r[state].washShrink], [r[state].frameWidth, r[state].frameWidth, 2 * r[state].frameWidth])
        }
        shell.check(key + ": hover lays 8% of the ink and press 14% with an unscaled label",
                    [shell.near(r.hover.washAlpha, shell.rulingHover), shell.near(r.pressed.washAlpha, shell.rulingPress), r.pressed.scale], [true, true, 1])
        shell.check(key + ": no state holds a ring item, focus draws its own frame",
                    [r.rest.ringItem, r.hover.ringItem, r.pressed.ringItem, r.focus.ringItem, r.disabled.ringItem], [false, false, false, false, false])
        shell.check(key + ": focus moves nothing, the control, its frame and its label sit where they rest",
                    [r.focus.box, r.focus.frameBox, r.focus.labelBox], [r.rest.box, r.rest.frameBox, r.rest.labelBox])
        shell.check(key + ": disabled is 0.55", r.disabled.opacity, shell.rulingDisabled)
    }

    FloatingWindow {
        id: window
        implicitWidth: 800
        implicitHeight: 1200
        color: "#303030"

        Item {
            id: formHost
            width: 460
            height: 700
            Flea.NetworkForm { id: form; width: parent.width }
        }

        Item {
            id: fieldHost
            y: 720
            width: 460
            height: 80
            Flea.DialogField { id: referenceField; width: parent.width; label: "Reference" }
        }

        Item {
            id: pickerHost
            y: 820
            width: 800
            height: 160
            Flea.PickerChrome {
                id: chrome
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                picker: picker
            }
            Flea.PickerAnswers {
                id: answerRow
                anchors.top: chrome.bottom
                picker: picker
            }
        }

        // A plain primary dialog button, whose wash is held inside its frame in every state (the frame never lightens under it).
        Item {
            id: plainHost
            y: 1000
            width: 460
            height: 60
            Flea.DialogButton { id: plain; x: 20; y: 10; label: "Plain"; primary: true; onActivated: shell.plains += 1 }
            Flea.ProtocolChip { id: spare; x: 200; y: 10; label: "Spare" }
            Flea.CheckBox { id: emptyBox; x: 320; y: 10; value: "off" }
            Flea.CheckBox { id: fullBox; x: 360; y: 10; value: "on" }
        }

        // The Copy to dialog fills this host while it is open, and is shut when the pointer series run.
        Item {
            id: dialogHost
            width: 800
            height: 700
            Flea.MenuActionDialog { id: copyTo }
        }

        // Two trailing dialog buttons for the form's Tab walk, held out of every other check.
        Item {
            id: trailHost
            y: 1080
            width: 460
            height: 60
            Flea.DialogButton { id: trailA; x: 20; y: 10; label: "TrailA" }
            Flea.DialogButton { id: trailB; x: 200; y: 10; label: "TrailB" }
        }

        Item { id: parking; y: 1190; width: 10; height: 10; focus: true }

        TestEvent { id: driver }
    }

    // The picker's own face as PickerChrome and PickerAnswers read it; a Tab reports through stepFocus and moves nothing.
    QtObject {
        id: picker
        property var req: ({ mode: "open", title: "Choose file", app: "", accept: "", multiple: false, filters: [{ label: "Images" }] })
        property color edge: "#444444"
        property var marks: []
        property bool canAccept: true
        property bool collisionReview: false
        property var history: ["/a"]
        property bool backendUnavailable: false
        property bool submitting: false
        property bool saving: false
        property bool recent: false
        property bool answered: false
        property string path: "/home/x/y"
        property string home: "/home/x"
        property bool showHidden: false
        property bool listingFailed: false
        property int filterIndex: 0
        property string viewMode: "list"
        function stepFocus(from, back) { shell.stepped.push([from.name, back]) }
        function cancel() { shell.cancels += 1 }
        function accept() { shell.accepts += 1 }
        function control(name, item, available) { return { name: name } }
    }

    function centre(item) { return { x: item.width / 2, y: item.height / 2 } }
    function park() { driver.mouseMove(formHost, shell.parkX, shell.parkY, shell.noDelay, Qt.NoButton, Qt.NoModifier) }
    function hoverOn(item) { var c = shell.centre(item); driver.mouseMove(item, c.x, c.y, shell.noDelay, Qt.NoButton, Qt.NoModifier) }
    function pressOn(item) { var c = shell.centre(item); driver.mousePress(item, c.x, c.y, Qt.LeftButton, Qt.NoModifier, shell.noDelay) }
    function releaseOff(item) { driver.mouseRelease(item, shell.releaseOutside, shell.releaseOutside, Qt.LeftButton, Qt.NoModifier, shell.noDelay) }
    function settled(item) {
        var frame = Probe.find(item, "buttonFrame")
        var size = frame ? frame.width + frame.height : item.scale
        var same = size === shell.lastScale
        shell.lastScale = size
        shell.quiet = same ? shell.quiet + 1 : 0
        return shell.quiet >= shell.settleTicks
    }

    // The set: five members 30 tall at body 14, 4 apart, the current one framed and inked in foreground.
    function members() {
        var names = Protocols.PROTOCOLS
        var items = names.map(function (n) { return form.chipFor(n) })
        shell.check("the form draws every protocol as a member", items.every(function (i) { return i !== null }), true)
        shell.check("every member is 30 tall at body 14",
                    items.map(function (i) { var r = Probe.read(i); return [r.outerHeight, r.frameHeight, r.labelSize] }),
                    names.map(function () { return [shell.rulingHeight, shell.rulingHeight, Flea.Theme.font.body] }))
        var gaps = []
        for (var i = 1; i < items.length; i++) gaps.push(items[i].x - (items[i - 1].x + items[i - 1].width))
        shell.check("members sit 4 apart", gaps, gaps.map(function () { return shell.rulingSetGap }))
        var picked = Probe.read(items[0])
        var foreground = Probe.rgba(Flea.Theme.color.foreground)
        shell.check("the picked member keeps a foreground frame and label", [picked.frameColor, picked.ink, picked.washAlpha], [foreground, foreground, 0])
        shell.check("an unpicked member rests in a muted frame and label", [Probe.read(items[1]).frameColor, Probe.read(items[1]).ink],
                    [Probe.rgba(Flea.Theme.color.mutedFrame), Probe.rgba(Flea.Theme.color.muted)])
        shell.focusFrames(items)
        items[1].takeFocus()
        driver.keyClick(Qt.Key_Return, Qt.NoModifier, shell.noDelay)
        shell.check("Return on a focused member picks it", [form.protocol, items[1].picked, items[0].picked], ["SFTP", true, false])
        form.pick("SMB")
        shell.check("a member is no Tab stop of Qt's own", items[1].activeFocusOnTab, false)
    }

    // The password hint sits under the Password field on every protocol that takes credentials, and the form keeps one height through the five.
    function passwordHint() {
        var hint = "The password is not saved."
        var texts = [], heights = []
        Protocols.PROTOCOLS.forEach(function (name) {
            form.pick(name)
            form.forceLayout()
            texts.push(form.passwordHintText)
            heights.push(form.height)
        })
        shell.check("the password hint reads on SMB, SFTP, FTPS and WebDAV and is empty on NFS",
                    texts, Protocols.PROTOCOLS.map(function (name) { return name === "NFS" ? "" : hint }))
        shell.check("the form is one height through every protocol", heights.every(function (h) { return h === heights[0] }), true)
        form.pick("FTPS")
        form.forceLayout()
        var rows = Array.prototype.slice.call(form.children)
        var at = rows.findIndex(function (r) { return r.label === "Password" })
        var note = rows.find(function (r) { return r.text === hint })
        var after = rows.slice(at + 1).find(function (r) { return r !== note && r.visible && r.height > 0 })
        shell.check("the hint sits directly below the password field and above the next row",
                    at >= 0 && !!note && rows[at + 1] === note && note.y >= rows[at].y + rows[at].height && !!after && after.y >= note.y + note.height, true)
        form.pick("SMB")
    }

    // A focused set member, picked or not, is its own accent hairline frame where the accent has hue; a focused plain button is its foreground hairline frame; a disabled one never draws either.
    function focusFrames(items) {
        var c = Flea.Theme.color, rgba = Probe.rgba
        parking.forceActiveFocus()
        shell.check("an unfocused unpicked member's frame is muted and an unfocused picked one's is foreground", [Probe.read(items[1]).frameColor, Probe.read(items[0]).frameColor], [rgba(c.mutedFrame), rgba(c.foreground)])
        // The borders a resting control draws; focus adds none.
        var rest = [items[1], items[0], plain].map(Probe.shownBordered)
        var seen = [items[1], items[0], plain].map(Probe.focusRead)
        var h = Flea.Theme.spacing.hairline
        shell.check("a focused member draws the accent hairline frame and its own label; a focused plain button draws the foreground hairline frame; neither adds a border",
                    seen.map(function (r) { return [r.frameColor, r.frameWidth, r.ink, r.ringItem, r.borders] }),
                    [[rgba(c.accent), h, rgba(c.muted), false, rest[0]], [rgba(c.accent), h, rgba(c.foreground), false, rest[1]], [rgba(c.foreground), h, rgba(c.foreground), false, rest[2]]])
        spare.forceActiveFocus(); spare.available = false; spare.focused = true
        shell.check("a focused disabled member draws no accent and no thick frame", [Probe.read(spare).frameColor, Probe.read(spare).frameWidth], [rgba(c.mutedFrame), Flea.Theme.spacing.hairline])
        spare.focused = Qt.binding(function () { return spare.activeFocus }); spare.available = true
        parking.forceActiveFocus()
    }

    // A focused empty box draws its own foreground frame with no keyline; a focused filled box keeps its frame and shows a hairline keyline past a one-hairline gap; neither moves its outer size.
    function boxes() {
        var rgba = Probe.rgba, c = Flea.Theme.color
        parking.forceActiveFocus()
        emptyBox.focused = false; fullBox.focused = false
        var restEmpty = [emptyBox.width, emptyBox.height]
        var restFull = [fullBox.width, fullBox.height]
        shell.check("a resting empty box frames itself in muted", Probe.rgba(emptyBox.frameItem.border.color), rgba(c.mutedFrame))
        emptyBox.focused = true
        var eRing = Probe.find(emptyBox, "checkRing")
        shell.check("a focused empty box frames itself in the foreground", Probe.rgba(emptyBox.frameItem.border.color), rgba(c.foreground))
        shell.check("a focused empty box shows no keyline", eRing !== null && eRing.visible, false)
        shell.check("a focused empty box keeps its outer size", [emptyBox.width, emptyBox.height], restEmpty)
        emptyBox.focused = false
        fullBox.focused = true
        var fRing = Probe.find(fullBox, "checkRing")
        shell.check("a focused filled box keeps its foreground frame", Probe.rgba(fullBox.frameItem.border.color), rgba(c.foreground))
        shell.check("a focused filled box shows the keyline", fRing !== null && fRing.visible, true)
        var h = Flea.Theme.spacing.hairline
        shell.check("the keyline is one hairline past a one-hairline gap", fRing ? [fRing.border.width, fRing.x, fRing.y, fRing.width - fullBox.width] : null, [h, -2 * h, -2 * h, 4 * h])
        shell.check("a focused filled box keeps its outer size", [fullBox.width, fullBox.height], restFull)
        fullBox.focused = false
        parking.forceActiveFocus()
    }
    // A primary whose rest frame is already the foreground (stock kanagawa) draws its own frame 2 px wide on focus, inward, so focus stays visible and nothing grows or moves.
    function huePrimary() {
        var c = Flea.Theme.color, rgba = Probe.rgba
        parking.forceActiveFocus()
        Flea.Theme.applyColors(Probe.KANAGAWA_THEME)
        shell.check("kanagawa's accent frame is the foreground", rgba(c.accentFrame), rgba(c.foreground))
        var cool = Probe.read(plain)
        var coolBorders = Probe.shownBordered(plain)
        shell.check("a resting primary frames itself in one foreground hairline", [cool.frameColor, cool.frameWidth], [rgba(c.foreground), Flea.Theme.spacing.hairline])
        var warm = Probe.focusRead(plain)
        shell.check("a focused primary draws its own frame 2 px in the foreground, with no ring item and no added border",
                    [warm.frameColor, warm.frameWidth, warm.ringItem, warm.borders], [rgba(c.foreground), shell.rulingThick, false, coolBorders])
        shell.check("a focused primary sits exactly where it rests: control, frame and label", [warm.box, warm.frameBox, warm.labelBox], [cool.box, cool.frameBox, cool.labelBox])
        shell.check("a focused primary's wash lies inside the 2 px frame", [warm.washInsetX, warm.washInsetY, warm.washShrink], [shell.rulingThick, shell.rulingThick, 2 * shell.rulingThick])
        Flea.Theme.applyColors(Probe.COLOURED_THEME)
        parking.forceActiveFocus()
    }
    // The picker's answers are A's control; its marks wear no frame.
    function answers() {
        var cancel = answerRow.focusItems()[1]
        var accept = answerRow.focusItems()[2]
        var accentFrame = Probe.rgba(Flea.Theme.color.accentFrame)
        var muted = Probe.rgba(Flea.Theme.color.muted)
        var mutedFrame = Probe.rgba(Flea.Theme.color.mutedFrame)
        var foreground = Probe.rgba(Flea.Theme.color.foreground)
        shell.check("Cancel and Open are the one control", [cancel.label, accept.label, cancel.primary, accept.primary], ["Cancel", "Open", false, true])
        shell.check("the answers sit inside the answer row", [cancel.height <= answerRow.height, accept.height <= answerRow.height], [true, true])
        shell.check("the answer row is a hairline, the row padding twice and the 30 px control", answerRow.height, Flea.Theme.spacing.hairline + 2 * Flea.Theme.spacing.rowPaddingX + shell.rulingHeight)
        var focused = shell.readings.accept.focus
        var frame = Probe.find(accept, "buttonFrame")
        var box = frame ? frame.mapToItem(answerRow, 0, 0) : null
        if (box) shell.log("info answer row " + answerRow.height + " tall, frame from " + box.y + " to " + (box.y + frame.height) + ", the row's rule above " + Flea.Theme.spacing.hairline)
        shell.check("the focus frame stays inside the answer row, under its rule", box !== null && box.y >= Flea.Theme.spacing.hairline && box.y + frame.height <= answerRow.height, true)
        shell.check("the enabled primary is the accent frame, the secondary the muted one", [shell.readings.accept.rest.frameColor, shell.readings.cancel.rest.frameColor], [accentFrame, mutedFrame])
        var off = shell.readings.accept.disabled
        shell.check("a disabled Open is the muted frame and label at 0.55, with no wash", [off.frameColor, off.ink, off.opacity, off.frameFill], [mutedFrame, muted, shell.rulingDisabled, 0])
        shell.check("keyboard focus on Open is the foreground hairline frame with no ring item", [focused.ringItem, focused.frameColor, focused.frameWidth], [false, foreground, Flea.Theme.spacing.hairline])
        shell.check("the primary's resting wash is the 14% accent", shell.near(shell.readings.accept.rest.frameFill, shell.rulingPress), true)
        parking.forceActiveFocus()
        driver.mouseClick(cancel, cancel.width / 2, cancel.height / 2, Qt.LeftButton, Qt.NoModifier, shell.noDelay)
        shell.check("a click answers and takes no keyboard focus, so no focus frame", [shell.cancels, cancel.activeFocus, Probe.read(cancel).frameColor], [1, false, mutedFrame])
        cancel.forceActiveFocus()
        driver.keyClick(Qt.Key_Tab, Qt.NoModifier, shell.noDelay)
        driver.keyClick(Qt.Key_Backtab, Qt.ShiftModifier, shell.noDelay)
        shell.check("Tab and Shift Tab on an answer report to the picker's own order", shell.stepped, [["Cancel", false], ["Cancel", true]])
        shell.marks(mutedFrame, foreground)
    }
    // Back, Up and both view marks are frameless chrome marks: Back and Up rest in the foreground, the keyboard frames them, never boxed.
    function marks(muted, foreground) {
        var all = shell.markItems()
        shell.check("Back, Up and both view marks are chrome marks", all.every(function (m) { return !!m }), true)
        if (!all.every(function (m) { return !!m })) return
        shell.check("Back, Up and both view marks draw no frame", all.map(Probe.shownBordered), all.map(function () { return 0 }))
        shell.check("a mark's hit box is the strip's height and never under 24", all.map(function (m) { return m.height >= Flea.Theme.hitMin && m.height === Flea.Theme.chromeHeight }), all.map(function () { return true }))
        var back = chrome.focusItems()[0]
        var dim = all[3]
        shell.check("Back and Up rest in the foreground and name themselves", [shell.markInk(back), back.name, chrome.focusItems()[1].name], [foreground, "Back", "Parent folder"])
        shell.check("the unlit view mark rests muted before the keyboard reaches it", shell.markInk(dim), muted)
        dim.forceActiveFocus()
        shell.check("the keyboard lifts a muted mark to the foreground and frames it in the foreground", [shell.markInk(dim), Probe.shownBordered(dim), dim.ringItem.visible, dim.ringItem.border.width, Probe.rgba(dim.ringItem.border.color)], [foreground, 1, true, Flea.Theme.spacing.hairline, Probe.rgba(Flea.Theme.color.foreground)])
        parking.forceActiveFocus()
        picker.history = []
        shell.check("a mark with nowhere to go is disabled and out of the Tab walk", [back.enabled, back.available, back.activeFocusOnTab], [false, false, false])
        picker.history = ["/a"]
        var list = all[2]
        var grid = all[3]
        shell.check("the shown view's mark is lit in the foreground and the other muted", [shell.markInk(list), shell.markInk(grid)], [foreground, muted])
        shell.check("the view marks stay out of the Tab walk", [list.activeFocusOnTab, grid.activeFocusOnTab], [false, false])
        var filter = answerRow.focusItems()[0]
        shell.check("the filter trigger is as tall as the answers, in its own frame", [filter.height, Probe.bordered(filter) > 0], [shell.rulingHeight, true])
    }
    // Back, Up, List view, Grid view.
    function markItems() {
        var out = []
        var stack = [chrome]
        while (stack.length > 0) {
            var o = stack.pop()
            if (o.glyph !== undefined && o.accessName !== undefined && o.keyboardFocused !== undefined) out.push(o)
            var kids = o.children !== undefined ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
        }
        var order = ["arrow-left", "arrow-up", "list", "grid"]
        return order.map(function (g) { return out.filter(function (m) { return m.glyph === g })[0] })
    }
    function markInk(mark) {
        var stack = [mark]
        while (stack.length > 0) {
            var o = stack.pop()
            if (o.name === mark.glyph && o.color !== undefined) return Probe.rgba(o.color)
            for (var i = 0; i < o.children.length; i++) stack.push(o.children[i])
        }
        return ""
    }

    // The buttons follow the TLS box in the Tab ring: in order, wrapping, back, passing an unavailable one.
    function trailingWalk() {
        form.pick("FTPS")
        form.trailing = [trailA, trailB]
        var ring = form.focusRing()
        var first = ring[0]
        var tls = ring[ring.length - 3]
        shell.check("the ring ends in TLS then the two trailing buttons", [ring[ring.length - 2] === trailA, ring[ring.length - 1] === trailB], [true, true])
        tls.takeFocus()
        form.step(tls, 1)
        shell.check("Tab from TLS reaches the first trailing button", [trailA.activeFocus, form.focusName()], [true, "TrailA"])
        form.step(trailA, 1)
        shell.check("Tab reaches the second trailing button", [trailB.activeFocus, form.focusName()], [true, "TrailB"])
        form.step(trailB, 1)
        shell.check("Tab past the buttons wraps to the first chip", [first.activeFocus, first === form.chipFor(first.label)], [true, true])
        form.step(first, -1)
        shell.check("Backtab from the first chip returns to the second button", [trailB.activeFocus, form.focusName()], [true, "TrailB"])
        form.step(trailB, -1)
        shell.check("Backtab reaches the first trailing button", [trailA.activeFocus, form.focusName()], [true, "TrailA"])
        trailA.available = false
        tls.takeFocus()
        form.step(tls, 1)
        shell.check("an unavailable trailing button is passed over", [trailB.activeFocus, trailA.activeFocus, form.focusName()], [true, false, "TrailB"])
        trailA.available = true
        form.trailing = []
        form.pick("SMB")
        parking.forceActiveFocus()
    }

    // The Copy to, Move to and New file field is the height of the buttons beside it and of DialogField's own box.
    function field() {
        var out = []
        var actions = ["copyTo", "moveTo", "newFile"]
        for (var i = 0; i < actions.length; i++) {
            copyTo.open(actions[i], 1, "/box", null)
            var box = copyTo.fieldItem.parent
            var mid = copyTo.fieldItem.y + copyTo.fieldItem.height / 2
            out.push([box.height, copyTo.closeItem.height, copyTo.submitItem.height, Math.abs(mid - box.height / 2) < 1])
            copyTo.close()
        }
        var reference = referenceField.input.parent.height
        shell.check("the field is DialogField's own 30 beside 30 px buttons, its text centred", [reference, out],
                    [shell.rulingHeight, out.map(function () { return [shell.rulingHeight, shell.rulingHeight, shell.rulingHeight, true] })])
    }

    Timer {
        interval: shell.tickMs
        repeat: true
        running: true
        onTriggered: shell.advance()
    }

    function buildScript() {
        var chip = form.chipFor("SFTP")
        var steps = []
        steps = steps.concat(shell.seriesFor("member", chip, function (on) { if (chip.available !== undefined) chip.available = on }, function () { return form.protocol === "SMB" ? 0 : 1 }))
        var cancel = answerRow.focusItems()[1]
        var accept = answerRow.focusItems()[2]
        steps = steps.concat(shell.seriesFor("cancel", cancel, function (on) { if (cancel.available !== undefined) cancel.available = on }, function () { return shell.cancels }))
        steps = steps.concat(shell.seriesFor("accept", accept, function (on) { picker.canAccept = on }, function () { return shell.accepts }))
        steps = steps.concat(shell.seriesFor("plain", plain, function (on) { plain.available = on }, function () { return shell.plains }))
        steps.push({ item: parking, name: "check", act: function () {}, record: function () {
            shell.check("the harness draws at the reference text size", Flea.Theme.baseSize, shell.pinnedSize)
            shell.check("the harness runs with motion on, so the frame shrink is drawn", Flea.Theme.reducedMotion, false)
            var muted = Probe.rgba(Flea.Theme.color.muted)
            var mutedFrame = Probe.rgba(Flea.Theme.color.mutedFrame)
            shell.ladder("member", muted, mutedFrame, Probe.rgba(Flea.Theme.color.accent))
            shell.ladder("cancel", Probe.rgba(Flea.Theme.color.foreground), mutedFrame, Probe.rgba(Flea.Theme.color.foreground))
            shell.ladder("plain", Probe.rgba(Flea.Theme.color.foreground), Probe.rgba(Flea.Theme.color.accentFrame), Probe.rgba(Flea.Theme.color.foreground))
            shell.ladder("accept", Probe.rgba(Flea.Theme.color.foreground), Probe.rgba(Flea.Theme.color.accentFrame), Probe.rgba(Flea.Theme.color.foreground))
            shell.members()
            shell.passwordHint()
            shell.trailingWalk()
            shell.boxes()
            shell.answers()
            shell.field()
            shell.huePrimary()
        } })
        shell.script = steps
    }

    function advance() {
        if (Date.now() - shell.startedAt > shell.capMs) {
            shell.failures.push("the harness did not finish")
            shell.log("FAIL the harness did not finish at step " + shell.step)
            shell.finish()
            return
        }
        if (shell.step > shell.script.length) return
        if (shell.script.length === 0) {
            // Assigned only once the store lies under the root, because it may write on assignment.
            var inside = shell.underRoot(Flea.ViewState.store.path) && shell.underRoot(Quickshell.env("HOME") || "")
            shell.check("sandbox: the state file and HOME lie under the harness root", inside, true)
            if (!inside) { shell.finish(); return }
            Flea.ViewState.state = { display: { textSize: { mode: TextSize.nearest(shell.pinnedSize) } } }
            Flea.Theme.applyColors(Probe.COLOURED_THEME)
            shell.buildScript()
            return
        }
        if (shell.step === shell.script.length) { shell.finish(); return }
        var current = shell.script[shell.step]
        if (!shell.acted) {
            current.act()
            shell.acted = true
            shell.quiet = 0
            return
        }
        if (!shell.settled(current.item)) return
        current.record()
        shell.acted = false
        shell.step += 1
    }
}
