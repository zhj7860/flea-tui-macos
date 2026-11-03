//@ pragma ShellId flea-columnshidden-test

import QtQuick
import Quickshell
import Quickshell.Io
import "flea" as Flea

// A Columns view kept behind the list or the grid keeps its rows until a new row count reaches it, and its return is whole in one frame.
ShellRoot {
    id: root

    readonly property string fixture: Quickshell.env("COLHID_DIR")
    // More than one round only for a timing run; the first round alone carries the search.
    readonly property int rounds: { var n = parseInt(Quickshell.env("COLHID_ROUNDS") || "1", 10); return n > 0 ? n : 1 }
    readonly property int folderRows: 283
    readonly property int deepRow: 200
    readonly property int movedRow: 230
    readonly property int stepRow: 260
    readonly property int tickMs: 20
    readonly property int settleMs: 300
    readonly property int giveUpMs: 10000
    readonly property var ops: root.buildOps()
    property int at: 0
    property var awaiting: null
    property var queued: []
    property double stamp: Date.now()
    property double calmFrom: 0
    property int checks: 0
    property int failures: 0
    property var pane: null
    property var keys: null
    property int gen: 0
    property string startName: ""
    // The place and census read at a hide, the rows held then, and every row a hidden column made since.
    property var hiddenFrom: null
    property var seenRows: []
    property var made: null
    property var watchers: []
    // The return being watched frame by frame, see onAfterAnimating.
    property var watch: null
    // A listing opened or a cursor moved behind the kept Columns view, timed to the frame that draws it.
    property var land: null
    property bool ticking: false
    property bool finished: false

    function buildOps() {
        var out = [{ open: "" }, { view: "columns" }]
        for (var r = 0; r < root.rounds; r++) {
            out.push({ cursorName: "sub" }, { hide: "list" }, { back: "folder" }, { cursor: 3 }, { hide: "list" }, { back: "top" },
                { cursor: root.deepRow, scroll: true }, { hide: "list" }, { back: "kept" },
                { hide: "list" }, { cursor: root.stepRow }, { back: "cursor" },
                { hide: "list" }, { open: "/sub" }, { open: "/empty" }, { open: "" }, { cursor: root.movedRow })
            if (r === 0)
                out.push({ search: true }, { type: "nor" }, { exit: true })
            out.push({ back: "moved" }, { hide: "grid" }, { open: "/sub" }, { open: "/empty" }, { open: "" },
                { cursor: root.movedRow }, { back: "moved-grid" },
                { hide: "list" }, { touch: true }, { touch: false }, { back: "moved-count" })
        }
        out.push({ open: "/hop/sixty", rows: 60 }, { open: "/hop/empty", rows: 0 }, { open: "/hop/three", rows: 3 }, { hide: "grid", pool: true }, { back: "kept-pool" })
        return out
    }

    function check(label, actual, expected) {
        root.checks += 1
        var ok = JSON.stringify(actual) === JSON.stringify(expected)
        if (!ok) root.failures += 1
        console.log("COLHID " + (ok ? "PASS " : "FAIL ") + label + " got=" + JSON.stringify(actual) + " expected=" + JSON.stringify(expected))
    }
    // The pane goes first and the quit waits for it, so no row build it started is in flight when the engine goes.
    function finish() {
        if (root.finished) return
        root.finished = true
        console.log("COLHID DONE " + root.checks + " checks, " + root.failures + " failed")
        if (root.pane) root.pane.destroy()
    }
    function key(text) {
        if (text === "ESC") root.keys.keyClick(Qt.Key_Escape, Qt.NoModifier, -1)
        else root.keys.keyClickChar(text, Qt.NoModifier, -1)
    }
    function viewKey(view) { root.keys.keyClick(view === "list" ? Qt.Key_1 : view === "grid" ? Qt.Key_3 : Qt.Key_2, Qt.ControlModifier, -1) }
    function drawnAt(index) {
        var item = root.pane.visibleItemFor(index)
        return item && item.visible && item.row ? item.row.n : ""
    }
    function cursorName() {
        var row = root.pane.rowFor(root.pane.cursorIndex)
        return row ? row.n : ""
    }
    function landed(path, rows) {
        return !root.pane.listInFlight && root.pane.searchMode.length === 0 && root.pane.path === root.fixture + path
            && root.pane.total === rows && (rows === 0 || root.drawnAt(root.pane.cursorIndex).length > 0)
    }
    // Holds once the predicate has stood for settleMs, so asynchronous row builds have had their time.
    function calm(ok) {
        if (!ok) { root.calmFrom = 0; return false }
        if (root.calmFrom === 0) root.calmFrom = Date.now()
        return Date.now() - root.calmFrom >= root.settleMs
    }

    // Every built ColumnPane under the view by role: the pane's own column, the parent and the child.
    function columns() {
        var out = {}
        var stack = [root.pane.columnsArea]
        while (stack.length > 0) {
            var o = stack.pop()
            if (o !== null && o.drawsEmpty !== undefined && o.lockedMode !== undefined && typeof o.itemAtIndex === "function")
                out[o.pane !== null ? "active" : o.dim ? "parent" : "child"] = o
            var kids = o !== null && o.children !== undefined ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
        }
        return out
    }
    function isRow(item) { return item.lifted !== undefined && item.dimOpacity !== undefined && item.paintWidth !== undefined }
    // Every ColumnRow a column's list holds, pooled ones included: they stay children of its content item.
    function rowsHeld(col) {
        var kids = col.viewport.contentItem.children, out = []
        for (var i = 0; i < kids.length; i++)
            if (root.isRow(kids[i])) out.push(kids[i])
        return out
    }
    function allRows() {
        var held = [], all = root.columns()
        for (var name in all) held = held.concat(root.rowsHeld(all[name]))
        return held
    }
    // Counts each ColumnRow a hidden column makes as it is parented, so one built and released between two ticks counts too.
    function watchContent(content) {
        var fn = function () {
            var kids = content.children
            for (var i = 0; i < kids.length; i++)
                if (root.isRow(kids[i]) && root.seenRows.indexOf(kids[i]) < 0 && root.made.indexOf(kids[i]) < 0) root.made.push(kids[i])
        }
        content.childrenChanged.connect(fn)
        root.watchers.push({ content: content, fn: fn })
    }
    function unwatch() {
        root.watchers.forEach(function (w) { w.content.childrenChanged.disconnect(w.fn) })
        root.watchers = []
    }
    function offsetOf(col) { return Math.round(col.viewport.contentY - col.viewport.originY) }
    // Model rows, delegates held and delegates not seen at the hide, summed over every column.
    function census() {
        var cols = root.columns(), out = { count: 0, held: 0, created: 0 }
        for (var name in cols) {
            var held = root.rowsHeld(cols[name])
            out.count += cols[name].viewport.count
            out.held += held.length
            for (var i = 0; i < held.length; i++) if (root.seenRows.indexOf(held[i]) < 0) out.created += 1
        }
        return out
    }

    // "" when a shown column draws every row its viewport covers and, for the pane's own, the cursor whole.
    function columnWhole(col, name) {
        if (!col.visible) return ""
        var want = col.pane !== null ? col.pane.shownTotal : col.rows.length
        var v = col.viewport, rowH = Flea.Theme.fileRowHeight
        if (v.count !== want) return name + " holds " + v.count + " of " + want + " rows"
        var top = v.contentY - v.originY
        var last = Math.min(want - 1, Math.floor((top + v.height - 1) / rowH))
        for (var i = Math.max(0, Math.floor(top / rowH)); i <= last; i++) {
            var item = col.itemAtIndex(i)
            var expected = col.pane !== null ? col.pane.rowFor(i) : col.rows[i]
            if (!item || !item.visible || !item.row || !expected || item.row.n !== expected.n)
                return name + " draws no row " + i
        }
        if (col.pane === null || want === 0) return ""
        var cursor = col.itemAtIndex(col.pane.cursorIndex)
        if (!cursor || cursor.cursor !== true || cursor.y < v.contentY || cursor.y + rowH > v.contentY + v.height)
            return name + " draws no whole cursor at " + col.pane.cursorIndex
        return ""
    }
    function columnsWhole() {
        var cols = root.columns(), why = ""
        for (var name in cols) why = why || root.columnWhole(cols[name], name)
        return why
    }

    FloatingWindow {
        id: win
        implicitWidth: 1400
        implicitHeight: 800
        color: Flea.Theme.color.background
        Item { id: frameProbe }
    }
    // Emitted on the GUI thread just before the scene is synced, so what is read here is what that frame draws.
    Connections {
        target: frameProbe.Window.window
        function onAfterAnimating() {
            var l = root.land
            if (l !== null && l.ms < 0 && l.ready()) l.ms = Date.now() - l.at
            var w = root.watch
            if (w === null || root.pane === null || root.pane.viewMode !== "columns") return
            var why = root.columnsWhole()
            w.frames += 1
            if (w.frames === 1) {
                w.firstMs = Date.now() - w.keyAt
                w.firstAt = Date.now()
                w.firstWhy = why
                w.firstY = root.offsetOf(root.columns().active)
                w.parentAnswered = root.pane.columnsArea.answered(root.pane.columnsArea.parentPath)
                w.built = root.census().created
            }
            if (why.length > 0) { w.blank += 1; w.lastWhy = why }
            if (root.columns().active.scrollBar.shown) w.bar += 1
        }
    }
    Flea.Backend { id: realBackend }
    Process { id: touch }

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
            return
        }
        if (Date.now() - root.stamp > root.giveUpMs) {
            root.check("probe completes", "timeout at op " + root.at + " " + JSON.stringify(root.ops[root.at - 1]), "complete")
            root.finish()
            return
        }
        if (root.awaiting !== null && !root.awaiting()) return
        root.awaiting = null
        root.calmFrom = 0
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

    function strike(text) {
        root.key(text)
        root.gen += 1
        var sent = root.gen
        root.awaiting = function () {
            return root.pane.searchGen === sent && !root.pane.searchRunning && root.pane.searchSettledAt >= root.pane.searchKeyAt
        }
    }

    function run(op) {
        if (op.open !== undefined) {
            if (root.pane === null) {
                Flea.ViewState.changeKey("view", "list")
                root.pane = paneComponent.createObject(win.contentItem)
                root.keys = Qt.createQmlObject("import QtTest; TestEvent {}", root.pane.listArea)
            }
            var rows = op.rows !== undefined ? op.rows : op.open === "/sub" ? 10 : op.open === "/empty" ? 0 : root.folderRows
            // A landing behind which the Columns view is kept, timed to the frame that draws it.
            root.land = root.made !== null ? { ready: function () { return root.landed(op.open, rows) }, at: Date.now(), ms: -1 } : null
            root.pane.open(root.fixture + op.open)
            root.awaiting = function () {
                if (!root.calm(root.landed(op.open, rows))) return false
                if (root.land !== null) console.log("COLHID LAND " + root.pane.viewMode + " " + (op.open || "/") + " ms=" + root.land.ms)
                root.land = null
                return true
            }
        } else if (op.view !== undefined) {
            root.viewKey(op.view)
            root.awaiting = function () { return root.calm(root.pane.viewMode === op.view && root.landed("", root.folderRows)) }
        } else if (op.cursorName !== undefined) {
            for (var i = 0; i < root.pane.total && root.pane.rowFor(i) !== null; i++)
                if (root.pane.rowFor(i).n === op.cursorName) root.pane.setCursor(i, 3)
            root.awaiting = function () {
                return root.calm(root.cursorName() === op.cursorName && root.pane.columnsArea.drawnNames("child").split("|").length === 10)
            }
        } else if (op.cursor !== undefined) {
            root.land = root.made !== null ? { ready: function () { return root.drawnAt(op.cursor).length > 0 }, at: Date.now(), ms: -1 } : null
            root.pane.setCursor(op.cursor, 3)
            root.awaiting = function () {
                if (root.drawnAt(op.cursor).length === 0) return root.calm(false)
                // Scrolled by hand so the cursor stands mid-column, the place a plain return must keep.
                var col = root.pane.viewMode === "columns" ? root.columns().active : null
                if (op.scroll === true && col && root.offsetOf(col) !== (op.cursor - 6) * Flea.Theme.fileRowHeight)
                    col.viewport.contentY = col.viewport.originY + (op.cursor - 6) * Flea.Theme.fileRowHeight
                if (!root.calm(true)) return false
                if (root.land !== null) console.log("COLHID STEP " + root.pane.viewMode + " " + op.cursor + " ms=" + root.land.ms)
                root.land = null
                return true
            }
        } else if (op.hide !== undefined) {
            var pressed = false, before = null
            root.awaiting = function () {
                // The bar from the probe's own scroll is down and faded first, so any bar on the return is the return's.
                if (!pressed) {
                    if (!root.calm(!root.columns().active.scrollBar.shown)) return false
                    root.hiddenFrom = { active: root.offsetOf(root.columns().active), cursor: root.pane.cursorIndex, live: root.allRows().filter(function (r) { return r.live }) }
                    root.seenRows = root.allRows()
                    before = root.census()
                    root.viewKey(op.hide)
                    root.calmFrom = 0
                    pressed = true
                }
                if (!root.calm(root.pane.viewMode === op.hide)) return false
                // The pool may drain a released row meanwhile, so the model's count is what a kept column keeps.
                root.hiddenFrom.census = root.census()
                root.check("hide to " + op.hide + " keeps every row and builds none", [root.hiddenFrom.census.count, root.hiddenFrom.census.created], [before.count, 0])
                if (op.pool) {
                    var was = root.hiddenFrom.live, held = root.allRows(), live = held.filter(function (r) { return r.live })
                    root.check("hide to " + op.hide + " drains the " + (root.seenRows.length - was.length) + " rows a shown hop pooled and keeps its live rows",
                        [root.seenRows.length > was.length, live.every(function (r) { return was.indexOf(r) >= 0 }), live.length, held.length - live.length], [true, true, was.length, 0])
                }
                root.made = []
                var cols = root.columns()
                for (var name in cols) root.watchContent(cols[name].viewport.contentItem)
                return true
            }
        } else if (op.back !== undefined) {
            // Read before the return builds anything: only a new count drops a hidden column's rows, and a kept one follows the cursor.
            root.unwatch()
            var now = root.census(), dropped = op.back.indexOf("moved") === 0
            if (op.back !== "cursor") root.check(op.back + " hidden changes built no rows", root.made.length, 0)
            // A new count in the open folder reaches only the pane's own column; a hop reaches every column.
            var active = root.columns().active
            if (op.back === "moved-count")
                root.check(op.back + " the hidden pane column holds no rows", [active.viewport.count, root.rowsHeld(active).length], [0, 0])
            else
                root.check(op.back + (dropped ? " hidden columns hold no rows" : " hidden columns keep their rows"), dropped ? [now.count, now.held] : now.count,
                    dropped ? [0, 0] : root.hiddenFrom.census.count)
            root.made = null
            // From here a row counts as built only if the return builds it.
            root.seenRows = root.allRows()
            root.hiddenFrom.backY = root.offsetOf(root.columns().active)
            root.watch = { label: op.back, keyAt: Date.now(), frames: 0, blank: 0, firstMs: -1, firstAt: 0, firstWhy: "", firstY: -1, lastWhy: "", parentAnswered: false, built: 0, bar: 0 }
            root.viewKey("columns")
            root.awaiting = function () { return root.watch.frames > 0 && Date.now() - root.watch.firstAt >= root.settleMs }
        } else if (op.search) {
            root.pane.listArea.forceActiveFocus()
            root.gen = root.pane.searchGen
            root.startName = root.cursorName()
            root.key("f")
            root.awaiting = function () { return root.pane.searchMode === "typing" }
        } else if (op.type !== undefined) {
            root.queued = op.type.split("")
        } else if (op.touch !== undefined) {
            // A watched re-read that adds a row after the cursor changes the count and leaves the cursor's index as it was.
            touch.command = op.touch ? ["touch", root.fixture + "/zz-added.txt"] : ["rm", "--", root.fixture + "/zz-added.txt"]
            touch.running = true
            var want = root.folderRows + (op.touch ? 1 : 0), index = root.pane.cursorIndex
            root.awaiting = function () { return root.calm(!touch.running && !root.pane.listInFlight && root.pane.total === want && root.pane.cursorIndex === index) }
        } else if (op.exit) {
            root.key("ESC")
            root.awaiting = function () { return root.calm(root.landed("", root.folderRows) && root.cursorName() === root.startName) }
        }
        if (op.back !== undefined) root.awaitReturn(op.back)
    }

    // The first frame showing Columns is whole, no later one is not, and a return over an unchanged count stands where it hid.
    function awaitReturn(label) {
        var wait = root.awaiting
        root.awaiting = function () {
            if (!wait()) return false
            var w = root.watch
            console.log("COLHID SWITCH " + label + " ms=" + w.firstMs + " built=" + w.built + " y=" + w.firstY + " frames=" + w.frames + " parentAnswered=" + w.parentAnswered)
            // The bar shows only on a scroll, and a return is not one.
            root.check(label + " return frames show no scroll bar", w.bar, 0)
            root.check(label + " first frame draws every column whole", w.firstWhy, "")
            root.check(label + " blank frames", [w.blank, w.lastWhy], [0, ""])
            // A column that kept its rows returns with none built, where it hid.
            if (label.indexOf("kept") === 0 || label === "top" || label === "folder")
                root.check(label + " return builds no rows and lands where it hid", [w.built, w.firstY, root.pane.cursorIndex], [0, root.hiddenFrom.active, root.hiddenFrom.cursor])
            else if (label === "cursor")
                root.check(label + " return builds no rows and lands where the hidden column followed the cursor", [w.built, w.firstY], [0, root.hiddenFrom.backY])
            else if (label === "moved-count") {
                // A re-read re-selects the cursor's row, so the dropped column returns with that row inside its first frame.
                var rowH = Flea.Theme.fileRowHeight, top = root.pane.cursorIndex * rowH, h = root.columns().active.viewport.height
                root.check(label + " return shows the cursor row", top >= w.firstY && top + rowH <= w.firstY + h, true)
            }
            root.watch = null
            return true
        }
    }
}
