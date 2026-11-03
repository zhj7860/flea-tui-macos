//@ pragma ShellId flea-navcost-test
import QtQuick
import QtTest
import Quickshell
import "flea" as Flea

// Navcost: cursor steps and a rows landing serialize no held row, and the menu identity and the retry line keep their content rule.
ShellRoot {
    id: root
    readonly property string fixture: Quickshell.env("FLEA_NAVCOST_DIR") || ""
    readonly property int files: Number(Quickshell.env("FLEA_NAVCOST_FILES") || "0")
    readonly property int steps: 8
    property int checks: 0
    property int failures: 0
    // Rows passed through JSON.stringify, counted by each wrapped row's toJSON; an object never reassigned, so a binding that serializes rows does not depend on the count.
    readonly property var tally: ({ rows: 0 })
    property int phase: 0
    property var pane: null

    function check(name, actual, expected) {
        checks += 1
        if (actual !== expected) {
            failures += 1
            console.log("NAVCOST FAIL " + name + " got=" + actual + " expected=" + expected)
        } else console.log("NAVCOST ok " + name)
    }
    function finish() {
        console.log("NAVCOST DONE " + checks + " checks, " + failures + " failed")
        Qt.quit()
    }
    // The same fields the backend sent, plus a counter that JSON.stringify calls once per row it serializes.
    function counted(row) {
        var copy = {}
        for (var key in row) copy[key] = row[key]
        copy.toJSON = function () {
            root.tally.rows += 1
            var plain = {}
            for (var field in this) if (field !== "toJSON") plain[field] = this[field]
            return plain
        }
        return copy
    }
    function renamed(rows, at, name) {
        return rows.map(function (row, i) {
            var copy = root.counted(row)
            if (i === at) copy.n = name
            return copy
        })
    }

    FloatingWindow {
        id: win
        implicitWidth: 900
        implicitHeight: 700
        Flea.Backend { id: probeBackend }
        Component {
            id: paneComponent
            Flea.Pane {
                width: 900
                height: 700
                backend: probeBackend
            }
        }
        TestEvent { id: keys }
    }

    function advance() {
        if (phase === 0) {
            pane = paneComponent.createObject(win.contentItem)
            pane.open(fixture)
            phase = 1
        } else if (phase === 1) {
            if (pane.listInFlight || pane.total !== files || pane.rows.length !== files) return
            check("the listing is held whole", pane.held, 0)
            check("the list view is up", pane.viewMode, "list")
            pane.rows = pane.rows.map(counted)
            pane.listArea.forceActiveFocus()
            phase = 2
        } else if (phase === 2) {
            var before = pane.menuSelectionIdentity()
            var cursor = pane.cursorIndex
            tally.rows = 0
            for (var i = 0; i < steps; i++) keys.keyClick(Qt.Key_Down, Qt.NoModifier, -1)
            check("Down moved the cursor through the key path", pane.cursorIndex, cursor + steps)
            check("rows serialized over " + steps + " cursor steps", tally.rows, 0)
            check("a cursor step changes the identity", pane.menuSelectionIdentity() !== before, true)
            for (var j = 0; j < steps; j++) keys.keyClick(Qt.Key_Up, Qt.NoModifier, -1)
            check("the same rows and cursor give the same identity", pane.menuSelectionIdentity(), before)
            // Positive control: the counter sees a real serialization, so the zero above is not a dead counter.
            tally.rows = 0
            JSON.stringify(pane.rows)
            check("the counter sees every held row", tally.rows, files)
            var original = pane.rows
            tally.rows = 0
            pane.rows = renamed(original, 3, "renamed-row.txt")
            check("a rows landing serializes no held row", tally.rows, 0)
            check("a changed row changes the identity", pane.menuSelectionIdentity() !== before, true)
            check("the first identity read serializes the held rows once", tally.rows, files)
            pane.menuSelectionIdentity()
            check("a second read with the same rows serializes none", tally.rows, files)
            pane.rows = renamed(original, -1, "")
            check("the same row content gives the same identity", pane.menuSelectionIdentity(), before)
            // The retry line goes when the identity moves off the one it was written for, and only then.
            pane.wire.retrySelectionIdentity = pane.menuSelectionIdentity()
            pane.wire.retrySelectionText = "retry"
            pane.rows = renamed(original, -1, "")
            check("new rows with the same content keep the retry line", pane.retrySelectionText, "retry")
            pane.rows = renamed(original, 3, "renamed-row.txt")
            check("a changed row clears the retry line", pane.retrySelectionText, "")
            phase = 3
            finish()
        }
    }

    Timer { interval: 100; running: root.phase < 3; repeat: true; onTriggered: root.advance() }
    Timer { interval: 15000; running: true; onTriggered: { console.log("NAVCOST FAIL stalled in phase " + root.phase); Qt.quit() } }
}
