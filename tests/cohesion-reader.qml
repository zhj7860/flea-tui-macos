//@ pragma ShellId flea-cohesion-reader-test
import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Tabs.js" as Tabs
import "flea/js/Scroll.js" as Scroll
import QtTest

// the montage's reader names each control with a box inside the window, at rest and with a dialog open.
ShellRoot {
    id: root
    readonly property string fixture: Quickshell.env("HOME") + "/fixture"
    readonly property var pane: body.currentPane
    property int stage: 0
    property int ticks: 0
    property int checks: 0
    property var failures: []
    property double wheelAt: 0
    readonly property int wakeWaitMs: 3000
    property double sleepWaitAt: 0
    // A shown bar sleeps after Scroll.HOLD_MS and FADE_MS; twice that absorbs a loaded host.
    readonly property int sleepWaitMs: 2 * (Scroll.HOLD_MS + Scroll.FADE_MS)
    readonly property string closeMark: "Close permissions"

    function check(cond, label) {
        root.checks++
        if (!cond) { root.failures.push(label); console.log("COHREADER FAIL " + label) }
    }
    function ipcItem() {
        for (var i = 0; i < body.data.length; i++)
            if (String(body.data[i].item).indexOf("Ipc_") === 0) return body.data[i].item
        return null  // the seam is built after the first listing, and it is the item a Loader of the body holds
    }
    function read(tag) {
        var raw = root.ipcItem().seam.cohesionControls()
        var st = JSON.parse(raw)
        console.log("COHREADER " + tag + " controls=" + st.controls.length + " focus=" + JSON.stringify(st.focus))
        var kinds = {}
        for (var i = 0; i < st.controls.length; i++) {
            var c = st.controls[i]
            kinds[c.kind] = (kinds[c.kind] || 0) + 1
            root.check(c.w > 0 && c.h > 0 && c.x >= 0 && c.y >= 0 && c.x + c.w <= window.width && c.y + c.h <= window.height,
                tag + " " + c.kind + " '" + c.name + "' box inside the window: " + [c.x, c.y, c.w, c.h])
        }
        console.log("COHREADER " + tag + " kinds=" + JSON.stringify(kinds))
        return {st: st, kinds: kinds}
    }
    function report() {
        stepper.running = false
        console.log("COHREADER DONE checks=" + root.checks + " failed=" + root.failures.length)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    FloatingWindow {
        id: window
        implicitWidth: 1100
        implicitHeight: 700
        function rectOf(item) {
            if (!item) return ""
            var at = item.mapToItem(window.contentItem, 0, 0)
            return Math.round(at.x) + " " + Math.round(at.y) + " " + Math.round(item.width) + " " + Math.round(item.height)
        }
        Flea.WindowBody { id: body; host: window }
        TestEvent { id: driver }
    }

    Timer {
        id: stepper
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            root.ticks++
            if (root.ticks > 300) { root.check(false, "stage " + root.stage + " never completed"); root.report(); return }
            if (root.stage === 0) {
                if (pane.listInFlight || pane.path !== root.fixture || pane.listingState !== "ready" || root.ipcItem() === null) return
                var rest = root.read("window")
                root.check((rest.kinds.ChromeButton || 0) >= 3, "the chrome shows at least three marks")
                root.check(!!rest.st.focus && rest.st.focus.via === "item", "the focus at rest sits on the pane, which names no control: " + JSON.stringify(rest.st.focus))
                Tabs.openNew(pane, root.fixture)
                root.stage = 1
                return
            }
            if (root.stage === 1) {
                var tabs = root.read("tabs")
                root.check(tabs.kinds.TabBar === 1, "the current tab strip type is read")
                root.ipcItem().chrome.startEdit()
                root.stage = 2
                return
            }
            if (root.stage === 2) {
                var path = root.read("path")
                root.check(path.kinds.PathEntry === 1, "the current path entry type is read")
                root.check(!!path.st.focus && path.st.focus.kind === "PathEntry" && path.st.focus.via === "owner",
                    "path focus names its current owner: " + JSON.stringify(path.st.focus))
                root.ipcItem().chrome.closeEdit()
                pane.permissionsRequested(root.fixture + "/a.txt")
                root.stage = 3
                return
            }
            if (root.stage === 3) {
                var d = root.ipcItem().permissionsDialog
                if (!d || !d.opened || d.busy || !d.facts || d.facts.ok !== true) return
                var open = root.read("permissions")
                root.check((open.kinds.DialogButton || 0) >= 2, "Permissions shows its two buttons")
                root.check((open.kinds.CheckBox || 0) >= 9, "Permissions shows nine boxes")
                var values = open.st.controls.filter(function (c) { return c.kind === "CheckBox" }).map(function (c) { return c.value })
                root.check(values.indexOf("on") >= 0 && values.indexOf("off") >= 0, "the boxes report on and off: " + values)
                var primaries = open.st.controls.filter(function (c) { return c.kind === "DialogButton" && c.primary })
                root.check(primaries.length === 1, "one primary button: " + primaries.length)
                root.check(open.st.controls.every(function (c) { return c.kind !== "DialogButton" || (c.hoverable && c.pressable) }), "every dialog button reports hover and press")
                if (Quickshell.env("FLEA_COH_CAPTURE") === "true") {
                    var targets = open.st.controls.filter(function(c) { return c.surface === "PermissionsDialog" && c.exposed })
                    root.check(targets.filter(function(c) { return c.kind === "DialogButton" && c.pressLive }).length === 2, "capture buttons belong to the open Permissions surface")
                    root.check(targets.filter(function(c) { return c.kind === "CheckBox" && c.hoverLive && c.pressLive }).length === 9, "capture checkboxes read their parent's actual handlers")
                    root.check(targets.every(function(c) { return c.name !== "Back" && c.name !== "Parent folder" }), "window controls behind the dialog are excluded from its targets")
                }
                var focus = open.st.focus
                root.check(!!focus && (focus.via === "owner" || focus.via === "flag"), "the focus is found by the owner walk or the focused flag, not the fallback: " + JSON.stringify(focus))
                root.check(!!focus && (["DialogButton", "CheckBox"].indexOf(focus.kind) >= 0 || (focus.kind === "ChromeButton" && focus.name === root.closeMark)),
                    "the focus entry names a Permissions control, not a window mark: " + JSON.stringify(focus))
                if (Quickshell.env("FLEA_COH_CAPTURE") !== "true") { root.report(); return }
                d.close()
                Flea.ViewState.changeLeaf("preview", {column: true, loadOn: "automatic"})
                pane.chooseView("columns")
                for (var i = 0; i < pane.total; i++)
                    if (pane.rowFor(i) && pane.rowFor(i).n === "manual.pdf") { pane.setCursor(i, 0); break }
                root.stage = 4
                return
            }
            if (root.stage === 4) {
                if (root.ipcItem().permissionsDialog.visible) return
                if (!pane.columnsArea || pane.columnsArea.pdfPages() !== 2) return
                if (pane.columnsArea.previewColumn.swap.holding || pane.columnsArea.previewColumn.swap.capturing) return
                var state = JSON.parse(root.ipcItem().seam.cohesionControls())
                if (!state.previewColumns || !state.previewColumns.some(function(c) { return c.visible && c.drawn })) return
                // The bar must be asleep before the wheel, so only the wheel can expose it; the PDF load may still show it.
                var awake = state.controls.some(function(c) { return c.kind === "ViewportScrollBar" && c.surface === "PreviewColumn" && c.exposed })
                if (awake && root.sleepWaitAt === 0) root.sleepWaitAt = Date.now()
                if (awake && Date.now() - root.sleepWaitAt < root.sleepWaitMs) return
                root.check(!awake, "the Columns PDF bar sleeps before the wheel")
                var columns = root.read("columns").st
                root.check(columns.captureReader === "porttp4d", "the full window uses the current capture reader")
                root.check(columns.previewColumns.some(function(c) { return /^SelectionPreview_QML/.test(c.type) && c.loaded }),
                    "the reader walks the real loaded SelectionPreview under ColumnsArea and PreviewSwap")
                root.check(columns.controls.some(function(c) { return c.kind === "ViewportScrollBar" && c.surface === "PreviewColumn" }),
                    "the full Columns subtree exposes its actual PDF scrollbar identity")
                var frame = pane.columnsArea.frameItem(), preview = pane.columnsArea.previewColumn
                var centre = frame.mapToItem(preview, frame.width / 2, frame.height / 2)
                console.log("COHREADER_COLUMNS before=" + JSON.stringify(columns.scrollBars) + " preview=" + String(preview))
                driver.mouseMove(preview, centre.x, centre.y, 0, Qt.NoButton, Qt.NoModifier)
                driver.mouseWheel(preview, centre.x, centre.y, Qt.NoButton, Qt.NoModifier, 0, -120, 1)
                root.wheelAt = Date.now()
                root.stage = 5
                return
            }
            if (root.stage === 5) {
                var observed = JSON.parse(root.ipcItem().seam.cohesionControls())
                var bar = observed.controls.find(function(c) { return c.kind === "ViewportScrollBar" && c.surface === "PreviewColumn" && c.exposed })
                if (!bar && Date.now() - root.wheelAt < root.wakeWaitMs) return
                root.check(!!bar, "one wheel exposes the real Columns PDF bar through the native reader path")
                console.log("COHREADER_COLUMNS reader=" + observed.captureReader + " found=" + !!bar + " frame="
                    + root.ipcItem().seam.columnFrameRect() + " bars=" + JSON.stringify(observed.scrollBars))
                root.report()
            }
        }
    }
}
