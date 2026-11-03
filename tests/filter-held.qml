//@ pragma ShellId flea-filter-held-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Filter.js" as Filter

// The first "/" key over a drawn window whose rows all still match, on the real Pane and backend in list, columns and grid: counts the delegates it creates and destroys, and each drawn one keeps its row.
ShellRoot {
    id: root

    readonly property string fixture: Quickshell.env("FILTERHELD_DIR")
    readonly property int folderRows: 250
    readonly property int matchRows: 150
    readonly property int tickMs: 20
    readonly property int giveUpMs: 10000
    readonly property var ops: [
        { open: true },
        { view: "list" }, { home: true }, { slash: true }, { key: "list" }, { escape: true },
        { view: "columns" }, { home: true }, { slash: true }, { key: "columns" }, { escape: true },
        { view: "grid" }, { home: true }, { slash: true }, { key: "grid" }, { escape: true }
    ]
    property int at: 0
    property var awaiting: null
    property double stamp: Date.now()
    property var failures: []
    property var results: []
    property var pane: null
    property var keys: null
    property var before: ({})
    property int tagged: 0
    property double settledAt: 0
    property bool ticking: false

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

    function fail(text) { root.failures.push(text) }
    function landed() { return !root.pane.listInFlight && root.pane.total === root.folderRows && root.pane.rows.length > 0 }
    // The view the filter narrows: the list or grid itself, or the active column's own list in Columns.
    function view() {
        if (root.pane.viewMode === "columns") return root.pane.columnsArea ? root.pane.columnsArea.activeColumn().viewport : null
        return root.pane.listArea
    }
    // Drawn delegates only: a pooled one past the count reads listing row -1 and draws nothing.
    function drawn() {
        var out = []
        var v = root.view()
        var kids = v ? v.contentItem.children : []
        for (var i = 0; i < kids.length; i++)
            if (kids[i].listingIndex !== undefined && kids[i].listingIndex >= 0 && kids[i].visible && kids[i].row) out.push(kids[i])
        return out
    }
    // Every delegate under the view, pooled ones included, so a destroyed one is told apart from a pooled one.
    function all() {
        var out = []
        var v = root.view()
        var kids = v ? v.contentItem.children : []
        for (var i = 0; i < kids.length; i++) if (kids[i].listingIndex !== undefined) out.push(kids[i])
        return out
    }
    // Waits until a stretch of quiet frames has passed, so the coalesce and settle timers have run.
    function settle(ms) {
        root.settledAt = Date.now() + ms
        root.awaiting = function () { return Date.now() >= root.settledAt }
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
        if (Date.now() - root.stamp > root.giveUpMs) {
            root.fail("timeout at op " + root.at + " " + JSON.stringify(root.ops[root.at - 1]))
            root.finish()
            return
        }
        if (root.awaiting !== null && !root.awaiting()) return
        root.awaiting = null
        if (root.at >= root.ops.length) {
            root.finish()
            return
        }
        root.stamp = Date.now()
        root.run(root.ops[root.at])
        root.at += 1
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
            root.awaiting = function () { return root.pane.viewMode === op.view && root.landed() && root.view() !== null && root.drawn().length > 0 }
        } else if (op.home) {
            root.pane.listArea.forceActiveFocus()
            Filter.setCursorView(root.pane, 0)
            root.settle(400)
        } else if (op.slash) {
            root.keys.keyClickChar("/", Qt.NoModifier, -1)
            root.awaiting = function () {
                if (!root.pane.filterTyping) return false
                root.settle(300)
                return false
            }
        } else if (op.key !== undefined) {
            root.press(op.key)
        } else if (op.escape) {
            root.keys.keyClick(Qt.Key_Escape, Qt.NoModifier, -1)
            root.awaiting = function () { return !root.pane.filterTyping && root.pane.filterQuery === "" }
        }
    }

    // Names every delegate, keeps the row each drawn one shows, types "k", and counts once the frames have settled.
    function press(name) {
        root.before = {}
        var items = root.all()
        for (var i = 0; i < items.length; i++) {
            root.tagged += 1
            items[i].objectName = "held" + root.tagged
        }
        var ds = root.drawn()
        for (var j = 0; j < ds.length; j++) {
            root.before[ds[j].objectName] = ds[j].row.n
            if (ds[j].row.n.toLowerCase().indexOf("k") < 0) root.fail(name + " draws " + ds[j].row.n + " before the key, which k does not match")
        }
        var tags = {}
        for (var a = 0; a < items.length; a++) tags[items[a].objectName] = true
        var drawnBefore = ds.length
        root.keys.keyClickChar("k", Qt.NoModifier, -1)
        root.settledAt = Date.now() + 400
        root.awaiting = function () {
            if (root.pane.filterQuery !== "k" || Date.now() < root.settledAt) return false
            var now = root.all()
            var made = 0
            var seen = {}
            for (var b = 0; b < now.length; b++) {
                if (!tags[now[b].objectName]) made += 1
                seen[now[b].objectName] = true
            }
            var gone = 0
            for (var tag in tags) if (!seen[tag]) gone += 1
            var after = root.drawn()
            var moved = 0
            for (var c = 0; c < after.length; c++) {
                var was = root.before[after[c].objectName]
                if (was !== undefined && was !== after[c].row.n) moved += 1
            }
            var v = root.view()
            var line = name + " drawn=" + drawnBefore + " made=" + made + " gone=" + gone + " moved=" + moved + " count=" + v.count + " shown=" + root.pane.shownTotal
            root.results.push(line)
            console.log("FILTERHELD " + line)
            if (drawnBefore < 8) root.fail(name + " drew " + drawnBefore + " rows before the key, too few to count")
            if (root.pane.shownTotal !== root.matchRows || v.count !== root.matchRows) root.fail(name + " narrowed to " + v.count + " of " + root.pane.shownTotal + ", want " + root.matchRows)
            if (made !== 0) root.fail(name + " first key created " + made + " delegates over a window of " + drawnBefore + " rows that still match, want 0")
            if (gone !== 0) root.fail(name + " first key destroyed " + gone + " delegates, want 0")
            if (moved !== 0) root.fail(name + " first key moved " + moved + " drawn delegates to another row, want 0")
            if (after.length !== drawnBefore) root.fail(name + " draws " + after.length + " rows after the key, want " + drawnBefore)
            return true
        }
    }

    function finish() {
        for (var f = 0; f < root.failures.length; f++) console.log("FILTERHELD FAIL " + root.failures[f])
        if (root.failures.length === 0 && root.results.length === 3) console.log("FILTERHELD PASS " + root.results.join("; "))
        console.log("FILTERHELD DONE views=" + root.results.length + " failures=" + root.failures.length)
        Qt.exit(root.failures.length > 0 ? 1 : 0)
    }
}
