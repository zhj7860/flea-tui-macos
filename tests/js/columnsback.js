.import "../../ui/js/Columns.js" as Columns
.import "../../ui/js/ColumnsCarry.js" as Carry
.import "sourcefixture.js" as Source

// Back lands parent, active and child whole in its landing turn, asking the parent first and re-arming the child at the flight's end.
function run(check) {
    runReads(check)
    runPlan(check)
    runLanding(check)
    runGuard(check)
    runGlue(check)
}

function listRows(dir, n) {
    var out = []
    for (var i = 0; i < n; i++)
        out.push({ n: dir + i, d: i === 0, s: 13, m: 1, p: i === 0 ? 16877 : 33188, i: i === 0 ? "folder" : "text-x-generic", t: false, k: 0 })
    return out
}

function names(rows) { return rows.map(function (row) { return row.n + (row.d ? "/" : "") + ":" + row.i }).join("|") }
function key(path) { return Columns.peekKey(path, false, false) }

// A columns view as ColumnsCarry reads it: the pane, the peek maps, peekKey and orderOf.
function area(over, pane) {
    var p = { path: "/a/b/c", listingPath: "/a/b", held: 0, rows: listRows("c", 40), total: 300, windowSize: 35, filterQuery: "", searchMode: "",
              backend: { sortBy: "name", sortDesc: false, dirDev: 7, dirWritable: true } }
    for (var k in pane) p[k] = pane[k]
    var a = { pane: p, peeked: {}, denials: {}, peekOrders: {}, peekFacts: {}, peekKey: key, orderOf: function () { return "" } }
    for (var j in over) a[j] = over[j]
    return a
}
var state = { foldersFirst: true, groupByKind: false }

function runReads(check) {
    check("an unanswered column draws no rows", Carry.rowsFor({}, key("/a"), "/a", 0).length, 0)
    var held = {}
    held[key("/a")] = listRows("a", 2)
    check("an answered column draws its rows", Carry.rowsFor(held, key("/a"), "/a", 3).length, 2)
    check("an empty path draws nothing", Carry.rowsFor(held, key(""), "", 3).length, 0)
    var denied = {}
    denied[key("/d")] = 0
    check("a denial whose stat failed keeps mode 0", Carry.deniedMode(denied, key("/d"), 1), 0)
    check("a path never denied reads -1", Carry.deniedMode(denied, key("/e"), 1), -1)
    check("a drag names the peeked device and writability", JSON.stringify(Carry.peekSource(null, "/a", { "/a": { v: 7, w: false } }, 0)),
        JSON.stringify({ pane: null, dir: "/a", v: 7, w: false }))
    check("an unpeeked folder drags as writable on device 0", JSON.stringify(Carry.peekSource(null, "/b", {}, 0)), JSON.stringify({ pane: null, dir: "/b", v: 0, w: true }))
    check("an empty path drags nothing", Carry.peekSource(null, "", {}, 0), null)
    check("a folder with no order of its own asks under none", Carry.orderOf({ folderSorts: {}, rememberSort: true }, "/a", []), "")
}

function runPlan(check) {
    check("a Back names the parent of the shown path", Carry.isBack("/a/b/c", "/a/b"), true)
    check("a Back from a trailing slash names it too", Carry.isBack("/a/b/c/", "/a/b"), true)
    check("an Enter names no Back", Carry.isBack("/a/b", "/a/b/c"), false)
    check("a rail hop two up names no Back", Carry.isBack("/a/b/c", "/a"), false)
    check("staying at the root names no Back", Carry.isBack("/", "/"), false)
    check("an Enter carries the listing into its new ancestor slot", Carry.plan(area({}, { listingPath: "/a/b/c/c0" }), ["/a/b"], state).seed, "/a/b/c")
    var plan = Carry.plan(area({}, {}), ["/a"], state)
    check("a Back asks the incoming parent alone", plan.pre.join("|"), "/a")
    check("and carries the folder left as the seed", plan.seed + ">" + plan.target, "/a/b/c>/a/b")
    check("the seed is the first window, cut to the peek's own count", plan.rows.length, 35)
    check("in the peek's own shape, n, d and i alone", JSON.stringify(plan.rows[0]), JSON.stringify({ n: "c0", d: true, i: "folder" }))
    check("with the folder's device and writability", JSON.stringify(plan.facts), JSON.stringify({ v: 7, w: true }))
    check("a listing shorter than a peek's count carries all of it", Carry.plan(area({}, { rows: listRows("c", 3), total: 3 }), ["/a"], state).rows.length, 3)
    check("a 4-column Back asks the two ancestors not yet shown", Carry.plan(area({}, {}), ["/", "/a"], state).pre.join("|"), "/|/a")
    check("a scrolled window seeds nothing", Carry.plan(area({}, { held: 40 }), ["/a"], state).rows, null)
    check("a filtered window seeds nothing", Carry.plan(area({}, { filterQuery: "c1" }), ["/a"], state).rows, null)
    check("a searched window seeds nothing", Carry.plan(area({}, { searchMode: "results" }), ["/a"], state).rows, null)
    check("a window short of the peek's count seeds nothing", Carry.plan(area({}, { rows: listRows("c", 20) }), ["/a"], state).rows, null)
    check("a date order seeds nothing", Carry.plan(area({}, { backend: { sortBy: "mtime", sortDesc: true } }), ["/a"], state).rows, null)
    check("folders mixed in seed nothing", Carry.plan(area({}, {}), ["/a"], { foldersFirst: false }).rows, null)
    check("a kind grouping seeds nothing", Carry.plan(area({}, {}), ["/a"], { foldersFirst: true, groupByKind: true }).rows, null)
    check("a folder that remembers its own order seeds nothing", Carry.plan(area({ orderOf: function () { return "size1" } }, {}), ["/a"], state).rows, null)
    check("a remembered name order still seeds", Carry.plan(area({ orderOf: function () { return "name0" } }, {}), ["/a"], state).rows.length, 35)
    var linkTarget = listRows("c", 40)
    linkTarget[3] = { n: "ln", d: false, p: 33188, i: "text-x-generic", l: "../x" }
    check("a window holding a target link seeds nothing", Carry.plan(area({}, { rows: linkTarget }), ["/a"], state).rows, null)
    var linkMode = listRows("c", 40)
    linkMode[5] = { n: "ln", d: false, p: 41471, i: "text-x-generic" }
    check("a window holding a symlink mode seeds nothing", Carry.plan(area({}, { rows: linkMode }), ["/a"], state).rows, null)
    var exe = listRows("c", 40)
    exe[4] = { n: "run", d: false, p: 33261, i: "application-x-executable" }
    check("a window holding an executable seeds nothing", Carry.plan(area({}, { rows: exe }), ["/a"], state).rows, null)
}

function runLanding(check) {
    var plan = Carry.plan(area({}, {}), ["/a"], state)
    var a = area({}, { path: "/a/b" })
    a.peeked[key("/a")] = listRows("a", 2)
    a.peekOrders[key("/a")] = ""
    a.peekFacts["/a"] = { v: 1, w: true }
    a.peeked[key("/a/b")] = listRows("b", 2)
    a.peeked[key("/a/b/c/c0")] = listRows("x", 2)
    var next = Carry.landing(plan, a, ["/a"])
    check("the landing keeps the shown ancestor", next.peeked[key("/a")] === a.peeked[key("/a")], true)
    check("with its order and facts", next.orders[key("/a")] + ":" + next.facts["/a"].v, ":1")
    check("drops the columns no longer shown", next.peeked[key("/a/b")] === undefined && next.peeked[key("/a/b/c/c0")] === undefined, true)
    check("seeds the folder left as the child", next.peeked[key("/a/b/c")] === plan.rows, true)
    check("under its present order, with its facts", next.orders[key("/a/b/c")] + ":" + next.facts["/a/b/c"].v, ":7")
    check("with no outstanding ask when all peeks already answered", Object.keys(next.pending).length, 0)
    check("leaves the maps it was handed alone", a.peeked[key("/a/b")] !== undefined, true)
    check("no carry clears everything", JSON.stringify(Carry.landing(null, a, ["/a"])), JSON.stringify({ peeked: {}, denials: {}, orders: {}, facts: {}, pending: {} }))
    check("a carry for another target clears everything", Object.keys(Carry.landing(plan, area({}, { path: "/x" }), ["/a"]).peeked).length, 0)
    check("an ancestor whose reply is still out is not kept", Carry.landing(plan, area({}, { path: "/a/b" }), ["/a"]).peeked[key("/a")], undefined)
    a.orderOf = function () { return "size1" }
    check("an ancestor kept under another order is not reused", Carry.landing(plan, a, ["/a"]).peeked[key("/a")], undefined)
    check("a folder re-sorted since the request is not seeded", Carry.landing(plan, a, ["/a"]).peeked[key("/a/b/c")], undefined)
    var asked = area({}, { path: "/a/b" })
    asked.peeked[key("/a/b/c")] = listRows("z", 1)
    asked.peekOrders[key("/a/b/c")] = ""
    check("a seed never replaces rows a peek already answered", Carry.landing(plan, asked, ["/a/b/c"]).peeked[key("/a/b/c")][0].n, "z0")
    var lateralPlan = Carry.plan(area({}, { listingPath: "/a/b/d" }), ["/a/b"], state)
    var lateral = area({ shownChildPath: "/a/b/c/kid" }, { path: "/a/b/d" })
    lateral.peeked[key("/a/b")] = listRows("parent", 2)
    lateral.peekOrders[key("/a/b")] = ""
    lateral.denials[key("/a/b")] = 0
    lateral.peekFacts["/a/b"] = { v: 8, w: false }
    lateral.peeked[key(lateral.shownChildPath)] = listRows("child", 2)
    lateral.peekOrders[key(lateral.shownChildPath)] = ""
    var kept = Carry.landing(lateralPlan, lateral, ["/a/b"])
    check("a lateral landing keeps the identical parent rows", kept.peeked[key("/a/b")] === lateral.peeked[key("/a/b")], true)
    check("with the parent's denial and drag facts", kept.denials[key("/a/b")] + ":" + kept.facts["/a/b"].v + ":" + kept.facts["/a/b"].w, "0:8:false")
    check("and the old third folder while its replacement waits", kept.peeked[key(lateral.shownChildPath)] === lateral.peeked[key(lateral.shownChildPath)], true)
    var parentAsk = Columns.sentKey(key("/a/b"), lateral.pane.windowSize, "")
    var goneAsk = Columns.sentKey(key("/gone"), lateral.pane.windowSize, "")
    lateral.pending = {}; lateral.pending[parentAsk] = 2; lateral.pending[goneAsk] = 1
    var outstanding = Carry.landing(lateralPlan, lateral, ["/a/b"]).pending
    check("outstanding watching refreshes of a kept parent still land", outstanding[parentAsk], 2)
    check("an outstanding peek of a folder no longer drawn is dropped", outstanding[goneAsk], undefined)
    lateral.peekKey = function (path) { return Columns.peekKey(path, true, false) }
    check("another hidden-files key carries none of the old peeks", Object.keys(Carry.landing(lateralPlan, lateral, ["/a/b"]).peeked).length, 0)
}

// The landing gap holds the third column through the shipped moveThird guard, and only the gap does.
function runGuard(check) {
    var src = Source.source("ui/ColumnsArea.qml")
    var make = new Function("root", "Columns", "Filter", "ExtThumbs", "ViewState", "Qt", "thirdSwap", "preview", "folderFallback",
        "return (" + Source.slice(src, "function moveThird(settled)", "function settleThird()") + ")")
    function moves(carry, inFlight, cursorRow) {
        var shown = 0, stopped = 0
        var guardRoot = {
            cursorIsDir: false, shownIsDir: true, childPath: "/a/b/c", shownChildPath: "/a/b/c0",
            cursorRow: cursorRow === undefined ? null : cursorRow, shownHasRow: true, carry: carry, answered: function () { return false },
            pane: { listInFlight: inFlight, storageClass: "local", shown: null },
            showCursorRow: function () { shown += 1 },
            swapKey: function () { return "k" }
        }
        var stubs = { Filter: { cursorShown: function () { return true } }, ExtThumbs: { manualHold: function () { return false } },
            ViewState: { preview: false, previewColumn: false, previewAutomatic: false }, thirdSwap: { capturing: false, holding: false },
            preview: { followSelection: function () {}, armSettle: function () {} }, folderFallback: { stop: function () { stopped += 1 }, restart: function () {} } }
        make(guardRoot, Columns, stubs.Filter, stubs.ExtThumbs, stubs.ViewState, Qt, stubs.thirdSwap, stubs.preview, stubs.folderFallback)(true)
        return shown + " shown, " + stopped + " stopped"
    }
    check("the landing gap keeps the third column without moving it", moves({}, true), "0 shown, 0 stopped")
    check("the same move with the flight over lands the third column", moves({}, false), "1 shown, 1 stopped")
    check("the same move with no carry lands the third column", moves(null, true), "1 shown, 1 stopped")
    check("the same move with a cursor row already landed lands the third column", moves({}, true, { d: false }), "1 shown, 1 stopped")
}

// The shipped ColumnsArea request, landing, flight-end and reply bodies over a stub backend, as one Back sequence.
function runGlue(check) {
    var src = Source.source("ui/ColumnsArea.qml")
    var glue = src.indexOf("function onListingPathChanged()") >= 0 && src.indexOf("Carry.landing(") >= 0 && src.indexOf("function onListInFlightChanged()") >= 0
    check("the request plans through Carry.plan, the landing through Carry.landing, the flight's end refreshes once", glue, true)
    if (!glue)
        return
    var load = function (from, to) { return new Function("root", "Columns", "Carry", "ViewState", "return (" + Source.slice(src, from, to) + ")") }
    var sent = []
    var watched = []
    var thirdMoves = 0
    var cRows = listRows("c", 35)
    var inert = { cancel: function () {}, stop: function () {} }
    var childColumn = { emptyItem: { animateEntrance: true, markItem: { settle: function () {} } } }
    var root = {
        landing: { begin: function () {}, landed: function () {}, answered: function () {} },
        visible: true, width: 1300, columnsLimit: undefined, carry: null, peekVersion: 0, keep: { drawn: ["/a/b", "/a/b/c/c0"] },
        peeked: {}, pending: {}, denials: {}, peekOrders: {}, peekFacts: {}, childPath: "/a/b/c/c0", shownChildPath: "/a/b/c/c0", cursorIsDir: true,
        pane: { path: "/a/b/c", listingPath: "/a/b/c", listInFlight: false, rows: cRows, held: 0, total: 300, windowSize: 35, showHidden: false,
                filterQuery: "", searchMode: "", backend: { sortBy: "name", sortDesc: false, dirDev: 7, dirWritable: true,
                peek: function (path, first, hidden, last, keep) {
                    sent.push(path)
                    watched = watched.filter(function (one) { return keep.indexOf(one) >= 0 })
                    if (keep.indexOf(path) >= 0 && watched.indexOf(path) < 0) watched.push(path)
                } } },
        askMeta: function () {}, askThumb: function () {}, showCursorRow: function () {}, moveThird: function () { thirdMoves += 1 },
        peekKey: function (path) { return key(path) },
        orderOf: function (path) { return "" }
    }
    var vs = { state: { foldersFirst: true, groupByKind: false } }
    root.peeked[key("/a/b")] = listRows("b", 35)
    root.peekOrders[key("/a/b")] = ""
    root.ask = load("function ask(path, again, rearm)", "\n    // Hidden view asks nothing")(root, Columns, Carry, vs)
    root.answered = load("function answered(path)", "\n    // again re-asks")(root, Columns, Carry, vs)
    root.refreshNeighbours = load("function refreshNeighbours()", "\n\n    // One row, only when")(root, Columns, Carry, vs)
    var onRequest = load("function onListingPathChanged()", "\n        function onPathChanged()")(root, Columns, Carry, vs)
    var onPath = load("function onPathChanged()", "\n        // The flight's end")(root, Columns, Carry, vs)
    var onFlight = load("function onListInFlightChanged()", "\n    }\n\n    Row {")(root, Columns, Carry, vs)
    var onPeeked = new Function("root", "Columns", "childColumn", "thirdSwap", "folderFallback", "return (" + Source.slice(src,
        "function onPeeked(path, hidden, total, rows, readFailed, mode, hiddenLast, first, dev, writable, by, desc)", "\n    }\n\n    // A new listing") + ")")(root, Columns, childColumn, inert, inert)
    var answer = function (path, rows) { onPeeked(path, false, rows.length, rows, false, 0, false, 35, 7, true, undefined, false) }
    watched = ["/a/b", "/a/b/c/c0"]

    // The request: Nav.openWithoutHistory sets listInFlight, then listingPath, then sends the list.
    root.pane.listInFlight = true
    root.pane.listingPath = "/a/b"
    onRequest()
    check("the request asks the parent alone, before the list", sent.join("|"), "/a")
    check("every drawn column stays watched, and the parent is armed", watched.join("|"), "/a/b|/a/b/c/c0|/a")
    answer("/a", listRows("a", 35))
    check("its reply lands before the list's", Carry.rowsFor(root.peeked, key("/a"), "/a", root.peekVersion).length === 35 && Object.keys(root.pending).length === 0, true)

    // The landing turn: Nav.forget empties the rows, then rows, path and the restored cursor land, then the flight ends.
    sent = []
    root.pane.rows = []
    root.childPath = ""
    root.refreshNeighbours()
    root.pane.rows = listRows("b", 35)
    root.pane.path = "/a/b"
    root.childPath = "/a/b/b0"
    onPath()
    check("the landing turn asks nothing while its cursor is still out", sent.length, 0)
    check("the landing draws the parent", Carry.rowsFor(root.peeked, key("/a"), "/a", root.peekVersion).length, 35)
    var seeded = Carry.rowsFor(root.peeked, key("/a/b/c"), "/a/b/c", root.peekVersion)
    check("and the folder left as the child, in a peek's shape", names(seeded), names(cRows.map(function (row) { return { n: row.n, d: row.d, i: row.i } })))
    check("with no ask still out", Object.keys(root.pending).length, 0)
    root.childPath = "/a/b/c"
    root.pane.listInFlight = false
    onFlight()
    check("the carry is spent", root.carry, null)
    check("the third column, held through the gap, takes the landed cursor once", thirdMoves, 1)
    check("the flight's end asks the child once, to re-arm its watch", sent.join("|"), "/a/b/c")
    check("never the parent the request answered", sent.indexOf("/a"), -1)
    check("the backend then watches exactly the drawn columns", watched.slice().sort().join("|"), "/a|/a/b/c")
    var before = root.peekVersion
    answer("/a/b/c", JSON.parse(JSON.stringify(seeded)))
    check("its reply carries the seeded rows", names(Carry.rowsFor(root.peeked, key("/a/b/c"), "/a/b/c", root.peekVersion)), names(seeded))
    check("and lands as one peek", root.peekVersion, before + 1)

    // An Enter seeds the listing left into its incoming parent and arms its watch at the flight's end.
    sent = []
    root.pane.listInFlight = true
    root.pane.listingPath = "/a/b/c"
    onRequest()
    check("an Enter carries its listing and asks nothing redundant at its request", root.carry !== null && sent.length === 0, true)
    root.pane.path = "/a/b/c"
    root.childPath = ""
    onPath()
    check("its parent is seeded in the landing", root.answered("/a/b"), true)
    check("its landing waits for the final cursor before asking", sent.length, 0)
    root.pane.listInFlight = false
    onFlight()
    check("then refreshes and watches its new parent", sent.join("|"), "/a/b")
}
