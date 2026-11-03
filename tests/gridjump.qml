//@ pragma ShellId flea-gridjump-test

import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "flea/js/Filter.js" as Filter
import "flea/js/Marks.js" as Marks
import "flea/js/Selection.js" as Selection

// gridjump: a real ui/GridArea.qml on 10000 rows counts what a far jump and a held j sweep rebind and how many window asks the sweep sends beside a real ui/List.qml; counts only, no time.
ShellRoot {
    id: root

    readonly property int files: 10000
    readonly property int areaWidth: 2368
    readonly property int areaHeight: 1350
    readonly property int sweepSteps: 70
    property var failures: []
    property var script: []
    property var moves: ({})
    property var sweeps: ({})
    property int warmPolls: 0
    property int warmStable: 0
    property int warmLast: -1
    // Every tile the probe has met with the counters its change signals feed; mutated in place, so no binding reads them.
    readonly property var meta: ({ tiles: [], reuse: 0, redundant: 0, blanked: 0 })

    function log(line) { console.log("GRIDJUMP " + line) }
    function check(name, ok, detail) { if (!ok) { root.failures.push(name); root.log("FAIL " + name + " " + detail) } }
    function rowAt(i) {
        var n = String(i)
        while (n.length < 5) n = "0" + n
        return { n: "g_" + n + ".txt", d: false, i: "text-plain", p: 420, s: 0, m: 1758835200, t: false, k: 0, v: 0 }
    }
    function rowsFrom(from, to) { var out = []; for (var i = from; i < to; i++) out.push(root.rowAt(i)); return out }

    Component {
        id: backendStub
        QtObject {
            id: be
            property var pane: null
            property var queue: []
            property int asks: 0
            property int replies: 0
            property real heldListing: 1
            // Window ask outcome: "sync" in the call, "late" on a timer, "fail" an error line, "lost" never, "short" rows that stop before the cursor's row.
            property string mode: "late"
            signal failed(string where, string input, string message, int mode)
            function thumb(rows, cacheOnly) {}
            function thumbcancel(rows) {}
            function dirsize(rows) {}
            function dirsizecancel() {}
            function window(start, count) {
                be.asks += 1
                if (be.mode === "fail") { be.failed("window", "/probe", "/probe is not responding.", 0); return }
                be.queue.push({ start: start, count: count })
                if (be.mode === "sync") be.reply()
                else if (be.mode !== "lost") answer.start()
            }
            // A reply is a parse, every row a new object, and the two writes are PaneSwap's: held first, rows second.
            function reply() {
                var ask = be.queue.shift()
                if (ask === undefined) return
                var from = Math.max(0, Math.min(ask.start, be.pane.total))
                be.pane.held = from
                be.pane.rows = root.rowsFrom(from, Math.min(be.pane.total, from + (be.mode === "short" ? 10 : ask.count)))
                be.replies += 1
            }
            property Timer answer: Timer {
                interval: 1
                onTriggered: { be.reply(); if (be.queue.length > 0) answer.start() }
            }
        }
    }

    Component { id: swapStub; QtObject { property bool searchWarm: false } }

    Component {
        id: paneStub
        QtObject {
            id: p
            property var area: null
            property string viewMode: "grid"
            property string path: "/probe"
            property var rows: []
            property var shown: null
            readonly property int shownTotal: shown === null ? total : shown.length
            property int total: 0
            property int held: 0
            property int cursorIndex: 0
            property int cursorSeq: 0
            property int cursorStride: 1
            property int renamingIndex: -1
            property int renameRequest: 0
            property string renameError: ""
            property bool renamePending: false
            property int selectionVersion: 0
            property int selectionAnchor: 0
            property var selection: Selection.create()
            property bool paneFocused: true
            property bool dualMode: false
            property var clipboard: ({ paths: [], moving: false })
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property var kindNames: []
            property string searchMode: ""
            property string searchQuery: ""
            property string recentMode: ""
            property string filterQuery: ""
            property double inputAt: 0
            property bool filterTyping: false
            property var selectionBand: null
            property int previewIndex: -1
            property bool storageKnown: true
            property string storageClass: ""
            property bool listInFlight: false
            property string listingState: "ready"
            property string focusView: "grid"
            // ui/Pane.qml's own sizing from the area's height, in list rows.
            readonly property int visibleRows: Math.max(1, Math.ceil(root.areaHeight / Flea.Theme.fileRowHeight))
            readonly property int cacheRows: 4
            readonly property int firstSettleMs: 70
            readonly property int settleMs: 120
            readonly property int coalesceMs: 16
            readonly property int refetchMargin: 25
            readonly property int buffer: 150
            readonly property int windowSize: p.visibleRows + 2 * p.buffer
            property var backend: null
            property var sidebar: null
            property var listArea: null
            property var swap: null
            // What the delegates' bindings call, counted in an object no binding reads.
            readonly property var tally: ({ isSelected: 0 })
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) { var o = index - p.held; return (o >= 0 && o < p.rows.length) ? p.rows[o] : null }
            function isSelected(index) { p.tally.isSelected += 1; return p.selectionVersion >= 0 && p.selection.has(index) }
            function selectedIndices() { return [] }
            function selectionCount() { return 0 }
            function thumbFor(index) { return "" }
            function setCursor(index, context) { Filter.setCursor(p, index, context) }
            // ui/Pane.qml showRow: the list and the grid each move through their own showCursor.
            function showRow(view, context) {
                p.area.showCursor(view, context)
                p.area.restartCoalesce()
            }
            function slowClickWasSole(index) { return false }
            function pressSlowClick() {}
            function cancelSlowClick() {}
            function armSlowClick() {}
            function commitRename(newName) {}
            function focusRequested() {}
            function open(path) {}
            function openFile(path) {}
            function renameEditor() { return null }
            // PaneSwap.land: the rows go in before the count, from the top of the listing, cursor and selection on row 0.
            function land() {
                p.listInFlight = true
                p.total = 0
                p.held = 0
                p.rows = []
                p.cursorIndex = 0
                p.selection.only(0, true)
                p.selectionVersion += 1
                p.rows = root.rowsFrom(0, Math.min(root.files, p.windowSize))
                p.total = root.files
                p.listInFlight = false
            }
        }
    }

    Component {
        id: menuStub
        QtObject {
            function close() {}
            function openBackground(point) {}
        }
    }

    property var gridBackend: backendStub.createObject(root)
    property var listBackend: backendStub.createObject(root)
    property var gridPane: paneStub.createObject(root, { backend: root.gridBackend, swap: swapStub.createObject(root), viewMode: "grid" })
    property var listPane: paneStub.createObject(root, { backend: root.listBackend, viewMode: "list", focusView: "list" })
    property var stubMenu: menuStub.createObject(root)

    FloatingWindow {
        implicitWidth: root.areaWidth
        implicitHeight: root.areaHeight
        color: "black"
        TestEvent { id: driver }
        Flea.GridArea { id: grid; width: root.areaWidth; height: root.areaHeight; pane: root.gridPane; menu: root.stubMenu }
    }

    FloatingWindow {
        implicitWidth: root.areaWidth
        implicitHeight: root.areaHeight
        color: "black"
        Flea.List { id: list; width: root.areaWidth; height: root.areaHeight; pane: root.listPane; menu: root.stubMenu }
    }

    // Delegates and parked tiles alive: a tile created in an action moves this up, a reuse does not.
    function tiles() {
        var out = [], kids = grid.contentItem.children
        for (var i = 0; i < kids.length; i++) if (kids[i].listingIndex !== undefined) out.push(kids[i])
        return out
    }
    function adopt() {
        var all = root.tiles()
        for (var i = 0; i < all.length; i++) if (root.meta.tiles.every(function (t) { return t.tile !== all[i] })) root.watch(all[i])
    }
    // One function per tile, so each handler closes over its own tile and counters; the first value a tile is built with is not a change.
    function watch(tile) {
        var m = root.meta, mine = { tile: tile, rows: 0, idx: tile.listingIndex, drawn: tile.row !== null }
        m.tiles.push(mine)
        tile.rowChanged.connect(function () {
            mine.rows += 1
            // The same listing row as at the last change, already drawn: whatever this change was, it drew nothing new.
            if (tile.listingIndex === mine.idx && mine.drawn) m.redundant += 1
            // A live tile that drew a row and now draws none is a blank frame, whatever the window does next.
            if (tile.live && mine.drawn && tile.row === null) m.blanked += 1
            mine.idx = tile.listingIndex
            mine.drawn = tile.row !== null
        })
        tile.pooledChanged.connect(function () { if (!tile.pooled) m.reuse += 1 })
    }
    function snap() {
        root.adopt()
        return { asks: root.gridBackend.asks, replies: root.gridBackend.replies, objects: root.tiles().length + grid.prebuild.parkedCount, reuse: root.meta.reuse,
                 redundant: root.meta.redundant, blanked: root.meta.blanked, isSelected: root.gridPane.tally.isSelected, rows: root.meta.tiles.map(function (t) { return t.rows }) }
    }
    // A tile met only after the first snapshot counts from zero.
    function delta(a, b) {
        var d = { created: b.objects - a.objects, reused: b.reuse - a.reuse, asks: b.asks - a.asks, replies: b.replies - a.replies, twice: 0,
                  unchanged: b.redundant - a.redundant, blanked: b.blanked - a.blanked, isSelected: b.isSelected - a.isSelected, rebound: 0, max: 0, changes: 0 }
        for (var i = 0; i < b.rows.length; i++) {
            var n = b.rows[i] - (i < a.rows.length ? a.rows[i] : 0)
            if (n > 0) d.rebound += 1
            if (n > 1) d.twice += 1
            d.max = Math.max(d.max, n)
            d.changes += n
        }
        return d
    }
    function line(name, d) {
        return name + " created=" + d.created + " reused=" + d.reused + " windows=" + d.asks + " replies=" + d.replies + " tilesRebound=" + d.rebound
            + " maxRebindsPerTile=" + d.max + " tilesRebound2x=" + d.twice + " rowChanges=" + d.changes + " unchangedRowRebinds=" + d.unchanged + " blankedTiles=" + d.blanked + " isSelectedCalls=" + d.isSelected
    }

    // The actions are ui/js/Focus.js act() and ui/js/Grid.js arrow(): one filter move or set, then the selection follows.
    function moveTo(pane, view) { Filter.setCursorView(pane, view); Marks.follow(pane) }
    function moveBy(pane, step) { Filter.moveCursor(pane, step); Marks.follow(pane) }

    Timer { id: tick; onTriggered: root.runNext() }
    function later(ms) { tick.interval = ms; tick.start() }
    function runNext() {
        if (root.script.length === 0) { root.finish(); return }
        root.script.shift().call(root)
    }
    // One measured grid action, then 450 ms for the layout, the replies and the thumb timers.
    function measure(name, action) {
        var a = root.snap()
        action()
        // What the action did before the event loop turned: a late reply has not landed, so a view that moved bound its tiles to no rows.
        var early = root.delta(a, root.snap())
        root.script.unshift(function () {
            var d = root.delta(a, root.snap())
            d.early = early
            root.moves[name] = d
            root.log(root.line("grid " + name, d) + " movedBeforeWindow=" + early.reused + "/" + early.changes)
            root.runNext()
        })
        root.later(450)
    }
    // The pool is warm when the prebuild driver has parked as many tiles as it will and stopped for five polls.
    function warm() {
        root.warmPolls = 0
        root.warmStable = 0
        root.warmLast = -1
        root.script.unshift(root.pollWarm)
        root.later(150)
    }
    function pollWarm() {
        root.warmPolls += 1
        var parked = grid.prebuild.parkedCount
        root.warmStable = parked === root.warmLast ? root.warmStable + 1 : 0
        root.warmLast = parked
        if ((root.warmStable >= 5 && grid.prebuild.want === 0) || root.warmPolls >= 80) { root.runNext(); return }
        root.script.unshift(root.pollWarm)
        root.later(120)
    }
    // A held sweep at the key repeat's rate, then the replies still in flight.
    function sweep(name, pane, step, count, interval) {
        var s = { name: name, pane: pane, step: step, left: count, interval: interval, a: root.snap(), asks: pane.backend.asks }
        root.script.unshift(function () { root.sweepStep(s) })
        root.runNext()
    }
    function sweepStep(s) {
        if (s.left > 0) {
            s.left -= 1
            root.moveBy(s.pane, s.step)
            root.script.unshift(function () { root.sweepStep(s) })
            root.later(s.interval)
            return
        }
        root.script.unshift(function () {
            var out = root.delta(s.a, root.snap())
            out.asks = s.pane.backend.asks - s.asks
            root.sweeps[s.name] = out
            root.log("sweep " + s.name + " windows=" + out.asks + " cursor=" + s.pane.cursorIndex + " held=" + s.pane.held + " rows=" + s.pane.rows.length + (s.pane === root.gridPane ? " " + root.line("", out) : ""))
            root.runNext()
        })
        root.later(500)
    }

    // A tile whose row a window no longer reaches keeps it while the listing is the same, and reads nothing once the listing moved.
    function staleCheck() {
        var tile = root.tiles().filter(function (t) { return t.live && t.listingIndex === 5 })[0], pane = root.gridPane, be = root.gridBackend
        root.check("stale: a tile at index 5 draws its row", tile && tile.row && tile.row.n === "g_00005.txt", "")
        pane.held = 100
        pane.rows = root.rowsFrom(100, 200)
        root.check("stale: the same listing keeps a row the window left", tile.row !== null && tile.row.n === "g_00005.txt", "row=" + JSON.stringify(tile.row))
        be.heldListing = 2
        pane.rows = root.rowsFrom(100, 200)
        root.check("stale: a new listing leaves no row behind", tile.row === null, "row=" + JSON.stringify(tile.row))
        root.runNext()
    }

    function verdict() {
        // A late reply (a piped backend) lands after the key: the view waits for it, so no tile clears and the first G builds one tile; a sync reply lands inside the ask.
        ["G", "g", "End", "Home"].forEach(function (name) {
            [{ key: name, created: name === "G" ? 1 : 0, own: 1 }, { key: name + ".sync", created: 0, own: 0 }].forEach(function (bound) {
                var d = root.moves[bound.key]
                root.check(bound.key + ": a far jump creates at most " + bound.created + " tile once the pool is warm", d.created <= bound.created, "created=" + d.created)
                root.check(bound.key + ": a far jump rebinds a tile twice for at most the cursor's own tile (" + bound.own + ")", d.twice <= bound.own, "twice=" + d.twice)
                root.check(bound.key + ": a far jump blanks no tile but at most the cursor's own (" + bound.own + ")", d.blanked <= bound.own, "blanked=" + d.blanked)
                root.check(bound.key + ": a far jump gives each tile it moves its row once, the cursor's own aside", d.changes <= d.reused + d.created + bound.own, "changes=" + d.changes + " reused=" + d.reused + " created=" + d.created)
                root.check(bound.key + ": a far jump asks one window", d.asks === 1, "windows=" + d.asks)
                if (bound.key === name)
                    root.check(bound.key + ": a far jump moves no tile before its window lands", d.early.reused <= bound.own && d.early.changes <= bound.own, "reused=" + d.early.reused + " changes=" + d.early.changes)
            })
        })
        var g = root.sweeps.grid70, ref = root.sweeps["list" + (root.sweepSteps * grid.columns)]
        root.check("the list reference asks windows", ref.asks > 0, "windows=" + ref.asks)
        root.check("the held sweep asks no more windows than the list over as many rows", g.asks <= ref.asks, "grid=" + g.asks + " list=" + ref.asks)
        root.check("no rows replacement redraws a row a tile already drew", g.unchanged === 0, "unchanged=" + g.unchanged)
        root.check("a held sweep rebinds a tile about once per reuse", g.changes <= g.reused + 2 * grid.columns, "changes=" + g.changes + " reused=" + g.reused)
        root.runNext()
    }

    function scroller() {
        var kids = grid.children
        for (var i = 0; i < kids.length; i++) if (kids[i].objectName === "fleaScroll") return kids[i]
        return null
    }
    // A far jump whose window ask meets the given outcome, then the operator scrolls: the grid must stop waiting and ask a window again.
    function outcome(name, mode) {
        var s = root.script, last = root.files - 1, mine = { asks: 0 }
        s.push(function () { root.gridPane.land(); root.warm() })
        s.push(function () {
            root.gridBackend.mode = mode
            root.gridBackend.queue = []
            mine.asks = root.gridBackend.asks
            root.moveTo(root.gridPane, last)
            root.later(300)
        })
        s.push(function () {
            var parked = mode === "lost"
            // An outcome that frees the wait may be followed by a drift ask for the rows the view now shows, so only a held wait is exactly one.
            root.check(name + ": the jump asked its window", parked ? root.gridBackend.asks - mine.asks === 1 : root.gridBackend.asks - mine.asks >= 1, "windows=" + (root.gridBackend.asks - mine.asks))
            root.check(name + ": the wait " + (parked ? "holds while the reply is out" : "ends on the ask's outcome"), grid.landingWait === parked, "landingWait=" + grid.landingWait)
            var wheel = root.scroller()
            root.check(name + ": the grid has a wheel handler to hear", wheel !== null && wheel.wheeled !== undefined, "")
            if (parked && wheel !== null && wheel.wheeled !== undefined) {
                grid.contentY = 0
                driver.mouseWheel(grid, grid.width / 2, grid.height / 2, Qt.NoButton, Qt.NoModifier, 0, -120, 1)
                root.check(name + ": a wheel ends a wait nothing answers", !grid.landingWait, "landingWait=" + grid.landingWait)
            }
            root.gridBackend.mode = "sync"
            grid.contentY = 0
            root.later(60)
        })
        s.push(function () {
            mine.asks = root.gridBackend.asks
            grid.contentY = Math.max(0, grid.contentHeight - grid.height)
            root.later(150)
        })
        s.push(function () {
            root.check(name + ": a scroll asks a window after it", root.gridBackend.asks > mine.asks, "windows=" + (root.gridBackend.asks - mine.asks))
            root.check(name + ": the scrolled-to rows land", root.gridPane.rowFor(last) !== null, "held=" + root.gridPane.held)
            root.gridBackend.mode = "late"
            root.runNext()
        })
    }

    // A far jump whose window is lost, then the operator takes the view by act(): the wait ends at once, and the late window reveals nothing; a flick may coast on, a reveal lands a half content away.
    function takeover(name, act) {
        var s = root.script, last = root.files - 1, mine = { y: 0 }
        s.push(function () { root.gridPane.land(); root.warm() })
        s.push(function () {
            root.gridBackend.mode = "lost"
            root.gridBackend.queue = []
            root.moveTo(root.gridPane, last)
            root.later(300)
        })
        s.push(function () {
            root.check(name + ": the wait holds while the reply is out", grid.landingWait, "landingWait=" + grid.landingWait)
            grid.contentY = grid.contentHeight / 2
            root.check(name + ": a position write alone keeps the wait", grid.landingWait, "landingWait=" + grid.landingWait)
            act()
            root.check(name + ": the operator's scroll ends the wait", !grid.landingWait, "landingWait=" + grid.landingWait)
            mine.y = grid.contentY
            root.gridBackend.mode = "late"
            root.gridBackend.reply()
            root.later(250)
        })
        s.push(function () {
            root.check(name + ": the late window does not reveal the cursor back", Math.abs(grid.contentY - mine.y) < grid.height && grid.contentY < grid.contentHeight - 2 * grid.height,
                "contentY=" + grid.contentY + " at=" + mine.y)
            root.runNext()
        })
    }
    // A press on a tile, which the band lets through to the view, then moves past the drag threshold, then the release.
    function dragView() {
        var px = -1, py = -1
        for (var y = grid.height / 2; y < grid.height - 10 && px < 0; y += 3)
            for (var x = 10; x < grid.width - 40; x += 3)
                if (grid.tileAt(x + grid.contentX, y + grid.contentY) >= 0) { px = x; py = y; break }
        root.check("a tile exists to drag from", px >= 0, "px=" + px)
        if (px < 0) return
        driver.mousePress(grid, px, py, Qt.LeftButton, Qt.NoModifier, -1)
        for (var i = 1; i <= 12; i++)
            driver.mouseMove(grid, px, py - 12 * i, -1, Qt.LeftButton, Qt.NoModifier)
        driver.mouseRelease(grid, px, py - 144, Qt.LeftButton, Qt.NoModifier, -1)
    }
    function dragBar() {
        var bar = grid.scrollBar, knob = bar.knobItem
        var at = knob.mapToItem(bar, knob.width / 2, knob.height / 2)
        driver.mousePress(bar, at.x, at.y, Qt.LeftButton, Qt.NoModifier, -1)
        driver.mouseMove(bar, at.x, at.y + 30, -1, Qt.LeftButton, Qt.NoModifier)
        driver.mouseRelease(bar, at.x, at.y + 30, Qt.LeftButton, Qt.NoModifier, -1)
    }
    function wheelBar() {
        var bar = grid.scrollBar
        driver.mouseWheel(bar, bar.width / 2, bar.height / 2, Qt.NoButton, Qt.NoModifier, 0, -120, 1)
    }

    function build() {
        var s = root.script, last = root.files - 1
        function step(fn) { s.push(fn) }
        function jump(name, view) { step(function () { root.measure(name, function () { root.moveTo(root.gridPane, view) }) }) }
        function mode(name) { step(function () { root.gridBackend.mode = name; root.runNext() }) }
        step(function () {
            root.gridPane.area = grid
            root.gridPane.listArea = grid
            root.gridPane.cursorStride = Qt.binding(function () { return grid.columns })
            root.gridBackend.pane = root.gridPane
            root.listPane.area = list
            root.listPane.listArea = list
            root.listBackend.pane = root.listPane
            root.gridPane.land()
            root.listPane.land()
            root.warm()
        })
        step(function () {
            root.log("geometry columns=" + grid.columns + " cellHeight=" + grid.cellHeight + " visibleTileRows=" + grid.visibleTileRows + " landingTiles=" + grid.landingTiles
                + " held=" + root.gridPane.held + " rows=" + root.gridPane.rows.length + " plan=" + JSON.stringify(grid.windowPlan) + " listRows=" + root.gridPane.windowSize)
            root.check("the grid lays out 18 columns", grid.columns === 18, "columns=" + grid.columns)
            grid.forceActiveFocus()
            root.runNext()
        })
        // One round trip to each end warms the pool; the measured set then runs with the backend late and again with it quick.
        jump("warm.G", last)
        jump("warm.g", 0)
        mode("late")
        jump("G", last)
        jump("g", 0)
        jump("End", last)
        jump("Home", 0)
        mode("sync")
        jump("G.sync", last)
        jump("g.sync", 0)
        jump("End.sync", last)
        jump("Home.sync", 0)
        mode("late")
        // The held sweep on a fresh landing, then the same keys in the list, and the list over as many rows as the grid crossed.
        step(function () { root.gridPane.land(); root.warm() })
        step(function () { root.sweep("grid70", root.gridPane, grid.columns, root.sweepSteps, 34) })
        step(function () { root.listPane.land(); root.later(800) })
        step(function () { root.sweep("list70", root.listPane, 1, root.sweepSteps, 34) })
        step(function () { root.listPane.land(); root.later(800) })
        step(function () { root.sweep("list" + (root.sweepSteps * grid.columns), root.listPane, 1, root.sweepSteps * grid.columns, 20) })
        step(function () { root.gridPane.land(); root.warm() })
        step(root.staleCheck)
        step(root.verdict)
        root.outcome("failed window", "fail")
        root.outcome("short window", "short")
        root.outcome("lost window", "lost")
        root.takeover("lost window, view drag", root.dragView)
        root.takeover("lost window, bar drag", root.dragBar)
        root.takeover("lost window, bar wheel", root.wheelBar)
    }

    function finish() {
        root.log("DONE failures=" + root.failures.length)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    Timer { interval: 120000; running: true; onTriggered: { root.check("timeout", false, ""); root.finish() } }

    Component.onCompleted: {
        // Stock Omarchy's size: 125 px minimum cells, so a 2368 px grid lays out 18 columns.
        Flea.ViewState.setTextSize({ mode: 12 })
        root.build()
        root.later(700)
    }
}
