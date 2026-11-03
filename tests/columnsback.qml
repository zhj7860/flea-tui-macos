//@ pragma ShellId flea-columnsback-test

import QtQuick
import Quickshell
import "flea" as Flea

// 31 Columns Back landings over a real ColumnsArea with a stub pane and serial stub backend, each whole in its first frame.
ShellRoot {
    id: root
    readonly property int rowsPer: 300
    readonly property int launches: 16
    property var failures: []
    property var lands: []
    property var downFrameCounts: []
    property int launch: 0
    property var area: null
    property var pane: null
    property var backend: null
    // The step list of the current launch, and what the running step waits on.
    property var steps: []
    property var waitFor: null
    property double waitUntil: 0
    property var m: null

    function fail(text) { root.failures.push(text); console.log("CB FAILNOTE " + text) }
    function dirRows(prefix, dir, file) {
        var out = [], first = dir ? 1 : 0
        if (dir) out.push({ n: dir, d: true, s: 4096, m: 1, p: 16877, i: "folder", t: false, k: 1 })
        for (var i = first; i < root.rowsPer; i++)
            out.push({ n: prefix + "-f" + (i < 10 ? "00" : i < 100 ? "0" : "") + i, d: false, s: 13, m: 1, p: 33188, i: "text-x-generic", t: false, k: 0 })
        return out
    }
    readonly property var dirs: ({ "/a": root.dirRows("a", "b"), "/a/b": root.dirRows("b", "c"), "/a/b/c": root.dirRows("c", "c-dir"),
                                   "/a/b/c/c-dir": root.dirRows("e", ""), "/": root.dirRows("r", "a") })
    function peekShape(rows) { return rows.map(function (r) { return { n: r.n, d: r.d, i: r.i } }) }

    FloatingWindow {
        id: win
        implicitWidth: 1300
        implicitHeight: 600
        Item {
            id: host
            anchors.fill: parent
            Connections {
                target: host.Window.window
                function onAfterAnimating() { root.frame() }
            }
        }
    }

    Component {
        id: backendStub
        QtObject {
            signal peeked(string path, bool hidden, int total, var rows, bool readFailed, int mode, bool hiddenLast, int first, var dev, var writable, string by, bool desc)
            signal changed(string path)
            property int dirDev: 2049
            property bool dirWritable: true
            property string sortBy: "name"
            property bool sortDesc: false
            property double freeAt: 0
            property var queue: []
            function enqueue(one) {
                var now = Date.now()
                freeAt = Math.max(freeAt, now) + 6
                one.due = freeAt
                queue = queue.concat([one])
                pump.start()
            }
            function peek(path, first, hidden, hiddenLast, keep) { root.note("peek", path); enqueue({ kind: "peek", path: path, first: first }) }
            function list(path, first) { root.note("list", path); enqueue({ kind: "list", path: path, first: first }) }
            function askFsInfo() {}
            function askMeta(row, text, media, archive) { return 0 }
            function thumb(rows, cacheOnly) {}
            function thumbcancel(rows) {}
            function dirsize(rows) {}
            function dirsizecancel() {}
            function window(start, count) {}
        }
    }
    Timer {
        id: pump
        interval: 1
        repeat: true
        onTriggered: {
            var b = root.backend, now = Date.now()
            while (b && b.queue.length > 0 && b.queue[0].due <= now) {
                var one = b.queue[0]
                b.queue = b.queue.slice(1)
                var rows = root.dirs[one.path] || []
                if (one.kind === "peek")
                    b.peeked(one.path, false, rows.length, root.peekShape(rows.slice(0, one.first)), false, 0, false, one.first, 2049, true, "", false)
                else
                    root.land(one.path, rows)
            }
            if (!b || b.queue.length === 0) pump.stop()
        }
    }
    Component {
        id: paneStub
        QtObject {
            property string path: "/a/b/c"
            property string listingPath: "/a/b/c"
            property var rows: []
            property var shown: null
            property int shownTotal: 0
            property int total: 0
            property int held: 0
            property int cursorIndex: 0
            property int renamingIndex: -1
            property bool showHidden: false
            property int windowSize: 35
            property bool listInFlight: false
            property string listingState: "ready"
            property string searchMode: ""
            property string searchBase: ""
            property string filterQuery: ""
            property string pendingSelect: ""
            property bool pendingMenu: false
            property var trash: ({ opened: false })
            property var clipboard: ({ paths: [], moving: false })
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property var kindNames: []
            property bool storageKnown: true
            property string storageClass: "local"
            property int previewIndex: -1
            property int selectionVersion: 0
            property var selectionBand: null
            property int firstSettleMs: 70
            property int settleMs: 120
            property int coalesceMs: 16
            property int refetchMargin: 25
            property int buffer: 150
            property var backend: null
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) { var i = index - held; return (i >= 0 && i < rows.length) ? rows[i] : null }
            function isSelected(index) { return false }
            function selectedIndices() { return [] }
            function selectionCount() { return 0 }
            function thumbFor(index) { return "" }
            function open(path) {}
            function openFile(path) {}
            function pressSlowClick() {}
        }
    }
    Component {
        id: areaComponent
        Flea.ColumnsArea {
            anchors.fill: parent
            menu: QtObject { function close() {} function openBackground(point) {} }
        }
    }

    // One request the way Nav.openWithoutHistory sends it: listInFlight, then listingPath, then the list.
    function request(target, select) {
        root.pane.pendingSelect = select
        root.pane.listInFlight = true
        root.pane.listingPath = target
        if (root.m) root.m.ask = Date.now()
        root.backend.list(target, root.pane.windowSize)
    }
    // ui/PaneSwap.qml land: Nav.forget, the rows, applyListed's total and path, then rowsLanded's cursor and the flight's end.
    function land(path, all) {
        var t0 = Date.now(), before = root.m ? root.census() : null
        if (root.m) root.m.landAt = t0
        var p = root.pane
        p.total = 0; p.shownTotal = 0; p.held = 0; p.rows = []; p.kindNames = []; p.cursorIndex = 0; p.listingState = "loading"
        p.rows = all.slice(0, p.windowSize)
        p.kindNames = ["Plain text document", "Folder"]
        p.total = all.length
        p.shownTotal = all.length
        p.path = path
        p.listingState = all.length === 0 ? "empty" : "ready"
        var select = p.pendingSelect, at = 0
        p.pendingSelect = ""
        for (var i = 0; i < p.rows.length; i++) if (select.length > 0 && p.join(path, p.rows[i].n) === select) at = i
        p.cursorIndex = at
        p.listInFlight = false
        if (root.downAfterLand) { root.downAfterLand = false; root.downArm.start() }
        if (!root.m) return
        root.m.landEnd = Date.now()
        root.m.landTurn = root.m.landEnd - t0
        root.m.turn = root.delta(before, root.census())
        root.m.lastFp = ""
    }

    function note(kind, path) {
        if (!root.m || kind !== "peek") return
        var now = Date.now(), phase = root.m.landAt === 0 ? "pre" : root.m.landEnd === 0 ? "land" : "post"
        root.m.peeks.push(path + "@" + (now - root.m.key) + ":" + phase)
    }
    function columns() {
        var out = {}, stack = [root.area]
        while (stack.length > 0) {
            var o = stack.pop()
            if (o && o.drawsEmpty !== undefined && o.lockedMode !== undefined && typeof o.itemAtIndex === "function")
                out[o.pane !== null ? "active" : o.dim ? "parent" : "child"] = o
            var kids = o && o.children !== undefined ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
        }
        return out
    }
    function rowItems(col) {
        var kids = col.viewport.contentItem.children, out = []
        for (var i = 0; i < kids.length; i++)
            if (kids[i].lifted !== undefined && kids[i].paintWidth !== undefined) out.push(kids[i])
        return out
    }
    // Per column: every delegate item it holds, and the live ones in view, top to bottom.
    function census() {
        var cols = root.columns(), out = {}
        for (var name in cols) {
            var col = cols[name], items = root.rowItems(col), live = []
            for (var i = 0; i < items.length; i++)
                if (items[i].live && items[i].visible && items[i].y + items[i].height > col.viewport.contentY && items[i].y < col.viewport.contentY + col.viewport.height)
                    live.push(items[i])
            live.sort(function (a, b) { return a.y - b.y })
            out[name] = { items: items, live: live, shown: col.visible && col.width > 0 && (name !== "child" || root.area.shownIsDir) }
        }
        return out
    }
    function delta(a, b) {
        var out = {}, names = ["parent", "active", "child"]
        for (var n = 0; n < names.length; n++) {
            var name = names[n], was = a[name] ? a[name].items : [], now = b[name] ? b[name].items : [], built = 0, gone = 0
            for (var i = 0; i < now.length; i++) if (was.indexOf(now[i]) < 0) built += 1
            for (var j = 0; j < was.length; j++) if (now.indexOf(was[j]) < 0) gone += 1
            out[name] = { built: built, gone: gone }
        }
        return out
    }
    function deltaText(d) { return "p+" + d.parent.built + "-" + d.parent.gone + " a+" + d.active.built + "-" + d.active.gone + " c+" + d.child.built + "-" + d.child.gone }
    // What a frame draws, item by item: each column's live rows by name and place, its lift, and the cursor.
    function fp(c) {
        var parts = [], names = ["parent", "active", "child"]
        for (var n = 0; n < names.length; n++) {
            var col = c[names[n]]
            if (!col || !col.shown) { parts.push(names[n] + ":-"); continue }
            parts.push(names[n] + ":" + col.live.map(function (it) { return (it.row ? it.row.n : "?") + "@" + Math.round(it.y) + (it.lifted ? "^" : "") }).join(","))
        }
        return parts.join("#") + "#cur=" + root.pane.cursorIndex
    }
    function want(path, c, name) {
        var col = c[name], rows = root.dirs[path] || []
        if (!col || !col.shown || col.live.length === 0) return false
        var full = Math.min(rows.length, root.pane.windowSize, Math.floor(root.columns()[name].viewport.height / col.live[0].height))
        if (col.live.length < full) return false
        for (var i = 0; i < col.live.length; i++) if (!col.live[i].row || col.live[i].row.n !== rows[i].n) return false
        return true
    }
    function whole(c) {
        return root.pane.path === root.m.target && root.pane.cursorIndex === 0 && root.want("/a", c, "parent")
            && root.want("/a/b", c, "active") && root.want("/a/b/c", c, "child")
    }
    function frame() {
        var mm = root.m
        if (mm && mm.landAt === 0) { mm.preFrames += 1; if (root.fp(root.census()) !== mm.restFp) mm.preChanges += 1 }
        if (!mm || mm.landEnd === 0) {
            if (root.down !== null) root.downFrame(false)
            return
        }
        var now = Date.now(), c = root.census(), f = root.fp(c)
        mm.frames += 1
        if (mm.firstFrame === 0) { mm.firstFrame = now; mm.firstCensus = c }
        if (mm.lastFp !== "" && f !== mm.lastFp) mm.late.push((now - mm.key) + "ms " + f.slice(0, 160))
        mm.lastFp = f
        if (mm.wholeAt === 0 && root.whole(c)) mm.wholeAt = now
        if (root.down !== null) root.downFrame(false)
    }

    // A Down is counted in frames and delegates, never in wall clock: drawn by the first frame after its key, then every frame of its 200 ms settle adds the delegates built and the delegates dropped outside the child column (a file row empties it by design), both summing to 0; down is non-null while it waits.
    property var down: null
    function downFrame(settled) {
        var dn = root.down, c = root.census(), d = root.delta(dn.before, c), active = root.columns().active
        if (!settled) { dn.frames += 1; if (dn.drawn === 0 && active && active.selectedIndex === 1) dn.drawn = dn.frames }
        dn.before = c; dn.built += d.parent.built + d.active.built + d.child.built; dn.gone += d.parent.gone + d.active.gone; dn.left += d.child.gone
        if (!settled) return
        root.down = null; root.downFrameCounts.push(dn.drawn)
        console.log("CB DOWN launch=" + root.launch + " frames=" + dn.frames + " drawn=" + dn.drawn + " built=" + dn.built + " gone=" + dn.gone + " childLeft=" + dn.left)
        if (dn.drawn === 0) root.fail("Down after landing " + root.launch + " was not drawn in " + dn.frames + " frames")
        else if (dn.drawn > 1) root.fail("Down after landing " + root.launch + " was drawn in frame " + dn.drawn + ", want the first after its key")
        if (dn.built !== 0 || dn.gone !== 0) root.fail("Down after landing " + root.launch + " built " + dn.built + " and dropped " + dn.gone + " delegates, want 0 and 0")
    }

    function measure(shape) {
        root.m = { shape: shape, target: "/a/b", key: Date.now(), ask: 0, landAt: 0, landEnd: 0, landTurn: 0, peeks: [], frames: 0, firstFrame: 0, preFrames: 0, preChanges: 0, restFp: root.fp(root.census()),
                   firstCensus: null, wholeAt: 0, late: [], lastFp: "", turn: null }
        root.request("/a/b", "/a/b/c")
    }
    function finish() {
        var mm = root.m, after = root.delta(mm.firstCensus || root.census(), root.census())
        var pre = mm.peeks.filter(function (p) { return /:pre$/.test(p) }), post = mm.peeks.filter(function (p) { return !/:pre$/.test(p) })
        var line = "CB LAND launch=" + root.launch + " shape=" + mm.shape + " key2ask=" + (mm.ask - mm.key) + " ask2land=" + (mm.landAt - mm.ask)
            + " landTurn=" + mm.landTurn + " firstFrame=" + (mm.firstFrame > 0 ? mm.firstFrame - mm.key : -1)
            + " whole=" + (mm.wholeAt > 0 ? mm.wholeAt - mm.key : -1) + " late=" + mm.late.length + " frames=" + mm.frames + " preFrames=" + mm.preFrames + " preChanges=" + mm.preChanges
            + " peeksPre=" + pre.length + " peeksAfter=" + post.length + " parentAtRequest=" + pre.filter(function (p) { return p.indexOf("/a@") === 0 }).length
            + " childPeeksPre=" + pre.filter(function (p) { return p.indexOf("/a/b/c@") === 0 }).length
            + " childPeeks=" + mm.peeks.filter(function (p) { return p.indexOf("/a/b/c@") === 0 }).length
            + " turn=" + root.deltaText(mm.turn) + " after300=" + root.deltaText(after) + " peeks=" + mm.peeks.join(",")
        console.log(line)
        for (var i = 0; i < mm.late.length; i++) console.log("CB LATE launch=" + root.launch + " " + mm.shape + " " + mm.late[i])
        root.lands.push({ shape: mm.shape, line: line, first: mm.firstFrame - mm.key, whole: mm.wholeAt > 0 ? mm.wholeAt - mm.key : -1,
                          late: mm.late.length, preChanges: mm.preChanges, pre: pre.length, parentAtRequest: pre.filter(function (p) { return p.indexOf("/a@") === 0 }).length,
                          childPre: Number(line.match(/childPeeksPre=(\d+)/)[1]), childPeeks: Number(line.match(/childPeeks=(\d+)/)[1]), childGone: mm.turn.child.gone + after.child.gone,
                          builtAfter: after.parent.built + after.active.built + after.child.built })
        root.m = null
    }

    // One launch: a fresh area at /a/b/c, cursor on a file, so its child column has never built a row.
    function launchSteps(measured) {
        return [
            function () {
                if (root.area) root.area.destroy()
                root.backend = backendStub.createObject(root)
                root.pane = paneStub.createObject(root, { backend: root.backend })
                var all = root.dirs["/a/b/c"]
                root.pane.rows = all.slice(0, 35); root.pane.total = 300; root.pane.shownTotal = 300; root.pane.cursorIndex = 1
                root.area = areaComponent.createObject(host, { pane: root.pane })
                root.waitUntil = Date.now() + 200
            },
            function () { if (measured) root.measure("back1"); else root.request("/a/b", "/a/b/c"); root.waitUntil = Date.now() + 320 },
            function () { if (measured) root.finish(); root.request("/a/b/c", ""); root.waitUntil = Date.now() + 200 },
            function () { root.measure("back2"); root.waitUntil = Date.now() + 320 },
            function () { root.finish(); root.request("/a/b/c", ""); root.waitUntil = Date.now() + 200 },
            function () { root.downAfterLand = true; root.request("/a/b", "/a/b/c"); root.waitUntil = Date.now() + 320 }
        ]
    }
    // A Down 16 ms after the landing, as a key held through Back would send it.
    property bool downAfterLand: false
    property Timer downArm: Timer {
        interval: 16
        onTriggered: { root.down = { frames: 0, drawn: 0, built: 0, gone: 0, left: 0, before: root.census() }; root.pane.cursorIndex = 1; root.waitUntil = Date.now() + 200 }
    }

    Timer {
        id: ticker
        interval: 2
        running: false
        repeat: true
        onTriggered: {
            if (root.waitFor !== null) {
                if (!root.waitFor() && Date.now() < root.waitUntil) return
                root.waitFor = null
            }
            if (Date.now() < root.waitUntil || root.downArm.running) return
            if (root.down !== null) root.downFrame(true)
            if (root.steps.length === 0) {
                root.launch += 1
                if (root.launch >= root.launches) { ticker.stop(); root.report(); return }
                root.steps = root.launchSteps(true)
            }
            var next = root.steps[0]
            root.steps = root.steps.slice(1)
            next()
        }
    }

    function stats(vals) {
        if (vals.length === 0) return "med=- min=- max=-"
        var s = vals.slice().sort(function (a, b) { return a - b })
        return "med=" + s[Math.floor(s.length / 2)] + " min=" + s[0] + " max=" + s[s.length - 1]
    }
    function report() {
        var shapes = ["back1", "back2"]
        if (root.lands.length !== 31) root.fail("ran " + root.lands.length + " Back landings, want 31")
        if (root.downFrameCounts.length !== root.launches) root.fail("ran " + root.downFrameCounts.length + " Downs, want " + root.launches)
        for (var s = 0; s < shapes.length; s++) {
            var g = root.lands.filter(function (l) { return l.shape === shapes[s] })
            var pick = function (k) { return g.map(function (l) { return l[k] }) }
            console.log("CB BENCH " + shapes[s] + " n=" + g.length + " first " + root.stats(pick("first")) + " whole " + root.stats(pick("whole"))
                + " late " + root.stats(pick("late")) + " peeksPre " + root.stats(pick("pre")) + " childGone " + root.stats(pick("childGone"))
                + " builtAfter " + root.stats(pick("builtAfter")) + " childPeeks " + root.stats(pick("childPeeks")) + " preChanges " + root.stats(pick("preChanges")))
        }
        console.log("CB BENCH down frames " + root.stats(root.downFrameCounts))
        for (var i = 0; i < root.lands.length; i++) {
            var l = root.lands[i]
            // Every landing asked the parent once at its request, dropped nothing, and settled in its first frame.
            if (l.parentAtRequest !== 1) root.fail(l.shape + " " + i + " asked the parent " + l.parentAtRequest + " times at the request, want 1")
            if (l.childPre !== 0) root.fail(l.shape + " " + i + " asked the folder left " + l.childPre + " times before its landing")
            if (l.childPeeks > 1) root.fail(l.shape + " " + i + " asked the folder left " + l.childPeeks + " times, want at most its one watch")
            if (l.childGone !== 0) root.fail(l.shape + " " + i + " dropped " + l.childGone + " child delegates")
            if (l.preChanges !== 0) root.fail(l.shape + " " + i + " changed items in " + l.preChanges + " frames before its landing")
            if (l.late !== 0) root.fail(l.shape + " " + i + " changed items in " + l.late + " frames after its first")
            if (l.builtAfter !== 0) root.fail(l.shape + " " + i + " built " + l.builtAfter + " delegates after its first frame")
            if (l.whole < 0 || l.whole !== l.first) root.fail(l.shape + " " + i + " first frame " + l.first + " is not its whole frame " + l.whole)
        }
        for (var f = 0; f < root.failures.length; f++) console.log("COLUMNSBACK FAIL " + root.failures[f])
        if (root.failures.length === 0) console.log("COLUMNSBACK PASS backs=" + root.lands.length + " downs=" + root.downFrameCounts.length)
        Qt.quit()
    }

    Component.onCompleted: {
        Flea.ViewState.state = { previewColumn: false, previewAutomatic: false }
        root.launch = 0
        root.steps = root.launchSteps(false)
        root.waitUntil = Date.now() + 600
        ticker.start()
    }
}
