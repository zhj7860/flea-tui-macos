//@ pragma ShellId flea-raildrop-undo-test
import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "flea/js/Drag.js" as Drag

// A real pane receives a rail drop with the keyboard on the rail, then undoes it through Qt's key delivery.
ShellRoot {
    id: root
    readonly property string fixture: Quickshell.env("RAILDROP_FIXTURE")
    readonly property var pane: body.currentPane
    property int stage: 0
    property int leg: 0
    property int checks: 0
    property int failed: 0
    property int ticks: 0
    property bool stepping: false
    property bool transferred: false
    property bool undone: false
    property var offer: null

    function check(label, actual, expected) {
        root.checks += 1
        if (actual !== expected) root.failed += 1
        console.log("RAILUNDO " + (actual === expected ? "ok " : "FAIL ") + label + " got=" + actual + " expected=" + expected)
    }
    function finish() {
        stepper.stop()
        console.log("RAILUNDO DONE checks=" + root.checks + " failed=" + root.failed)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
    function receiver(item) {
        if (item.sidebar === root.pane.sidebar && typeof item.dropAt === "function") return item
        for (var i = 0; i < item.children.length; i++) {
            var found = root.receiver(item.children[i])
            if (found) return found
        }
        return null
    }
    function drop() {
        var sidebar = root.pane.sidebar
        var index = sidebar.entries.findIndex(function (entry) { return entry.label === "Favorite" })
        if (index < 0) return false
        var target = root.receiver(sidebar)
        if (!target) return false
        var row = sidebar.railItemFor(index)
        if (!row) return false
        var at = row.mapToItem(sidebar, row.width / 2, row.height / 2)
        var marker = Drag.markerPayload([0], false, root.pane.path, root.pane.backend.dirDev, true, false, root.pane.backend.heldListing)
        var offer = { x: at.x, y: at.y, urls: [Drag.uriFor(root.pane.path + "/a.txt")], proposedAction: Qt.CopyAction,
            getDataAsString: function (type) { return type === Drag.ROWS_MIME ? marker : "" },
            accept: function (action) { root.check("accepted rail drop", action, Qt.CopyAction) } }
        root.pane.focusView = "rail"
        sidebar.forceActiveFocus()
        root.check("keyboard starts on the rail", root.pane.focusView, "rail")
        root.offer = offer
        target.enterAt(offer)
        return true
    }

    Connections {
        target: root.pane.backend
        function onTransferDone(id, ok, failed) {
            root.check("rail transfer completed", ok + "|" + failed, "1|0")
            root.transferred = true
        }
        function onUndone(op, ok) {
            root.check("keyboard reverses the journal entry", op + "|" + ok, "move|true")
            root.undone = true
        }
    }
    FloatingWindow {
        id: window
        implicitWidth: 1000
        implicitHeight: 650
        Flea.WindowBody { id: body; host: window }
        Item { anchors.fill: parent; TestEvent { id: driver } }
    }
    Timer {
        id: stepper
        interval: 40
        running: true
        repeat: true
        onTriggered: {
            if (root.stepping) return
            root.stepping = true
            try {
                root.ticks += 1
                var ready = !root.pane.listInFlight && root.pane.path === root.fixture + "/source" && root.pane.listingState === "ready"
                if (root.stage === 0 && ready && root.pane.sidebar && root.drop()) {
                    root.stage = 3
                    root.ticks = 0
                } else if (root.stage === 3) {
                    var target = root.receiver(root.pane.sidebar)
                    if (target.held && target.held.dev > 0) {
                        root.stage = 1
                        target.dropAt(root.offer)
                        root.check("accepted drop returns keyboard to the listing", root.pane.focusView, "list")
                        root.check("accepted drop restores actual listing focus", root.pane.listArea.activeFocus, true)
                        root.ticks = 0
                    }
                } else if (root.stage === 1 && root.transferred && ready) {
                    root.stage = 2
                    driver.keyClick(Qt.Key_Z, root.leg === 0 ? Qt.NoModifier : Qt.ControlModifier, -1)
                    console.log("RAILUNDO KEY " + (root.leg === 0 ? "z" : "Ctrl+Z") + " view=" + root.pane.focusView + " owner=" + root.pane.Window.window.activeFocusItem)
                    root.ticks = 0
                } else if (root.stage === 2 && root.undone && ready) {
                    root.check("undo restores the source row", root.pane.total, 3)
                    if (root.leg === 1) { root.finish(); return }
                    root.leg += 1
                    root.transferred = false
                    root.undone = false
                    root.stage = 0
                    root.ticks = 0
                }
                if (root.ticks > 100) {
                    root.check("keyboard undo completes at stage " + root.stage, false, true)
                    root.finish()
                }
            } finally { root.stepping = false }
        }
    }
}
