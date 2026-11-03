//@ pragma ShellId flea-search-exit-columns-test

import QtQuick
import Quickshell
import "flea" as Flea

// Escape out of a live search in every view on the real Pane and backend, in case_searchnoblank's order, landing whole.
ShellRoot {
    id: root

    readonly property string fixture: Quickshell.env("EXITCOLS_DIR")
    readonly property int folderRows: 281
    readonly property int tickMs: 20
    readonly property int giveUpMs: 8000
    // One op per tick once the last op took effect; each op names what its effect looks like.
    readonly property var ops: [
        { open: true },
        { view: "list" }, { search: true }, { type: "nor" }, { type: "zzq" }, { backspace: 3 }, { exit: "list", below: false },
        { filter: "nor" }, { filterExit: true },
        { view: "columns" }, { search: true }, { type: "nor" }, { type: "zzq" }, { backspace: 3 }, { exit: "columns", below: true },
        { filter: "nor" }, { filterExit: true },
        { view: "grid" }, { search: true }, { type: "nor" }, { type: "zzq" }, { backspace: 3 }, { exit: "grid", below: true }
    ]
    property int at: 0
    property var awaiting: null
    property var queued: []
    property string queueMode: ""
    property string typed: ""
    property double stamp: Date.now()
    property double landedAt: 0
    property int checks: 0
    property int failures: 0
    property var pane: null
    property var keys: null
    property var before: null
    property int gen: 0
    property string startName: ""
    property int startIndex: -1
    property bool ticking: false

    function check(label, actual, expected) {
        root.checks += 1
        var ok = JSON.stringify(actual) === JSON.stringify(expected)
        if (!ok) root.failures += 1
        console.log("EXITCOLS " + (ok ? "PASS " : "FAIL ") + label + " got=" + JSON.stringify(actual) + " expected=" + JSON.stringify(expected))
    }
    // A ListView builds rows past its viewport with no done signal, so the quit waits for the pane's destruction, which cancels every queued build.
    property bool finished: false
    function finish() {
        if (root.finished) return
        root.finished = true
        root.stamp = Date.now()
        console.log("EXITCOLS DONE " + root.checks + " checks, " + root.failures + " failed")
        if (root.pane) root.pane.destroy()
    }
    // The name of the row a view draws at a listing index, or "" when no delegate is built for it.
    function drawnAt(index) {
        var item = root.pane.visibleItemFor(index)
        return item && item.visible && item.row ? item.row.n : ""
    }
    // The cursor's row, which a landing keeps on screen; a search begun on a lower file lands scrolled there and builds no row 0.
    function shownRow() { return root.drawnAt(root.pane.cursorIndex) }
    function cursorName() {
        var row = root.pane.rowFor(root.pane.cursorIndex)
        return row ? row.n : ""
    }
    function line() {
        var swap = root.pane.swap
        return "view=" + root.pane.viewMode + " inFlight=" + root.pane.listInFlight + " state=" + root.pane.listingState
            + " mode=" + JSON.stringify(root.pane.searchMode) + " leaving=" + root.pane.searchLeaving
            + " total=" + root.pane.total + " rows=" + root.pane.rows.length + " shown=" + JSON.stringify(root.shownRow())
            + " holding=" + swap.holding + " fellBack=" + swap.fellBack
    }
    function key(text) {
        if (text === "BS") root.keys.keyClick(Qt.Key_Backspace, Qt.NoModifier, -1)
        else if (text === "ESC") root.keys.keyClick(Qt.Key_Escape, Qt.NoModifier, -1)
        else root.keys.keyClickChar(text, Qt.NoModifier, -1)
    }
    // The landed folder as tests/ui.sh wait_listing sees it: the count, nothing out, and a row drawn at row 0 or the cursor.
    function landed() {
        return !root.pane.listInFlight && root.pane.searchMode.length === 0 && root.pane.total === root.folderRows
            && (root.drawnAt(0).length > 0 || root.shownRow().length > 0)
    }
    // The newest sent gen answered and its walk over, the case's wait_search_gen.
    function answered() { return root.pane.searchGen === root.gen && !root.pane.searchRunning && root.pane.searchSettledAt >= root.pane.searchKeyAt }
    // The exit's verdict once the folder has stood two more frames, against the swap's own counters.
    function exited(name) {
        if (!root.landed()) { root.landedAt = 0; return false }
        if (root.landedAt === 0) root.landedAt = Date.now()
        if (Date.now() - root.landedAt < 200) return false
        var after = root.pane.swap.describe()
        // The hold is the mechanism and does not depend on a frame drawing between the request and the landing.
        root.check(name + " exit held the walk until it landed", [after.holds - root.before.holds, after.last.end], [1, "landed"])
        root.check(name + " exit blankFrames", after.blankFrames, root.before.blankFrames)
        root.check(name + " exit fallbacks", after.fallbacks, root.before.fallbacks)
        // The walk landed inside the cap with no loading mark drawn, so no rows line waited out a minimum.
        root.check(name + " exit waits", [typeof after.waits, after.waits - root.before.waits], ["number", 0])
        root.check(name + " exit state", [root.pane.searchLeaving, root.pane.listInFlight, root.pane.listingState], [false, false, "ready"])
        root.check(name + " exit cursor file", root.cursorName(), root.startName)
        root.check(name + " exit draws the cursor row", root.shownRow(), root.startName)
        return true
    }

    FloatingWindow {
        id: win
        implicitWidth: 1400
        implicitHeight: 800
        color: Flea.Theme.color.background
    }
    Flea.Backend { id: realBackend }
    Component {
        id: paneComponent
        Flea.Pane {
            width: 1400
            height: 800
            backend: realBackend
        }
    }

    Timer {
        interval: root.tickMs
        running: true
        repeat: true
        onTriggered: {
            // A key event spins the event loop, so a tick can fire inside an op; a nested op would run twice.
            if (root.ticking) return
            root.ticking = true
            try { root.tick() } finally { root.ticking = false }
        }
    }

    function tick() {
        if (root.finished) {
            if (root.pane === null) Qt.exit(root.failures > 0 ? 1 : 0)
            else if (Date.now() - root.stamp > root.giveUpMs) { console.log("EXITCOLS FAIL the pane outlived its destroy, so the probe never quit"); Qt.exit(1) }
            return
        }
        if (Date.now() - root.stamp > root.giveUpMs) {
            root.check("probe completes", "timeout at op " + root.at + " " + JSON.stringify(root.ops[root.at - 1]) + " " + (root.pane ? root.line() : ""), "complete")
            root.finish()
            return
        }
        if (root.awaiting !== null && !root.awaiting()) return
        root.awaiting = null
        if (root.queued.length > 0) {
            root.strike(root.queued.shift())
            root.stamp = Date.now()
            return
        }
        if (root.at >= root.ops.length) {
            root.finish()
            return
        }
        root.stamp = Date.now()
        root.run(root.ops[root.at])
        root.at += 1
    }

    // One stroke from the queue, with the wait its own answer owes: a gen for the search, the query for the filter.
    function strike(text) {
        root.key(text)
        if (root.queueMode === "search") {
            root.gen += 1
            var sent = root.gen
            root.awaiting = function () { return root.pane.searchGen === sent && root.answered() }
            return
        }
        root.typed += text
        var query = root.typed
        root.awaiting = function () { return root.pane.filterQuery === query }
    }

    function run(op) {
        if (op.open) {
            Flea.ViewState.changeKey("view", "list")
            root.pane = paneComponent.createObject(win.contentItem)
            root.keys = Qt.createQmlObject("import QtTest; TestEvent {}", root.pane.listArea)
            root.pane.open(root.fixture)
            root.awaiting = function () { return root.landed() }
        } else if (op.view !== undefined) {
            root.keys.keyClick(op.view === "list" ? Qt.Key_1 : op.view === "columns" ? Qt.Key_2 : Qt.Key_3, Qt.ControlModifier, -1)
            root.awaiting = function () { return root.pane.viewMode === op.view && root.landed() }
        } else if (op.search) {
            root.pane.listArea.forceActiveFocus()
            root.gen = root.pane.searchGen
            root.startName = root.cursorName()
            root.startIndex = root.pane.cursorIndex
            root.key("f")
            root.awaiting = function () { return root.pane.searchMode === "typing" }
        } else if (op.type !== undefined || op.backspace !== undefined) {
            root.queueMode = "search"
            root.queued = op.type !== undefined ? op.type.split("") : new Array(op.backspace).fill("BS")
        } else if (op.exit !== undefined) {
            root.check(op.exit + " search began below row 0", root.startIndex > 0, op.below)
            root.check(op.exit + " search stands with results", root.pane.total > 0 && root.pane.total < root.folderRows, true)
            root.before = root.pane.swap.describe()
            root.key("ESC")
            root.awaiting = function () { return root.exited(op.exit) }
        } else if (op.filter !== undefined) {
            root.key("/")
            root.queueMode = "filter"
            root.typed = ""
            root.queued = op.filter.split("")
            root.awaiting = function () { return root.pane.filterTyping }
        } else if (op.filterExit) {
            root.key("ESC")
            root.awaiting = function () { return root.pane.filterQuery === "" && !root.pane.filterTyping }
        }
    }
}
