.import "../../ui/js/BackReturn.js" as BackReturn
.import "../../ui/js/Nav.js" as Nav
.import "../../ui/js/Tabs.js" as Tabs
.import "nav.js" as NavSuite

// Back and Forward land by name, then saved index, then the top; these copy ui/PaneSwap.qml's rows turn, tests/cursor-swap.qml drives it.

function rowsOf(names) { return names.map(function (name) { return { n: name } }) }
function fifty(prefix, start, count) {
    var out = []
    for (var i = 0; i < count; i++) out.push(prefix + (start + i))
    return out
}

// A pane standing in /home/gm/Work with its cursor on index, through the real Nav verbs.
function standing(names, index, history) {
    var p = NavSuite.browsing(history || [])
    p.searchMode = ""
    p.searchFrom = ""
    p.recentMode = ""
    p.recentFrom = ""
    p.viewMode = "list"
    p.showHidden = false
    p.selectionVersion = 0
    p.held = 0
    p.rows = rowsOf(names)
    p.total = names.length
    p.cursorIndex = index
    p.listingPath = "/home/gm/Work"
    // ui/PaneSwap.qml hold(): every listing arms the travel's restore, any other listing clears it.
    p.swap = { restore: null, stopWaiting: function () {},
        hold: function (ask) { p.swap.restore = ask.restore || null; return false } }
    p.rowFor = function (i) { return p.rows[i - p.held] || null }
    p.join = function (base, name) { return base + "/" + name }
    p.selectedIndices = function () { return [] }
    p.selection = { follows: function () { return false }, toggle: function () {} }
    p.clearSelection = function () { p.selectionVersion++ }
    p.backend.sortBy = "name"
    p.backend.sortDesc = false
    p.backend.listRequests = 1
    p.backend.dirDev = 7
    // The shipped backend closes a live search on leave, which leaving a walk calls.
    p.backend.searchClose = function () {}
    p.setCursor = function (i) { p.cursorIndex = Math.max(0, Math.min(p.total - 1, i)) }
    return p
}

// A pane on a small directory with a Back owed to a big one; the first window is modelled per turn.
function windowed(history) {
    var p = NavSuite.browsing(history || [])
    p.searchMode = ""
    p.searchFrom = ""
    p.recentMode = ""
    p.recentFrom = ""
    p.viewMode = "list"
    p.path = "/mid"
    p.listingPath = "/mid"
    p.held = 0
    p.rows = rowsOf(["m1"])
    p.total = 1
    p.cursorIndex = 0
    p.windowSize = 64
    p.selectionVersion = 0
    p.sentLocate = []
    p.sentWindow = []
    p.swap = { restore: null, phase: { listed: null }, stopWaiting: function () {},
        hold: function (ask) { p.swap.restore = ask.restore || null; return false } }
    p.rowFor = function (i) { var o = i - p.held; return o >= 0 && o < p.rows.length ? p.rows[o] : null }
    p.join = function (base, name) { return base === "/" ? "/" + name : base + "/" + name }
    p.selectedIndices = function () { return [] }
    p.selection = { follows: function () { return false }, toggle: function () {} }
    p.clearSelection = function () { p.selectionVersion++ }
    p.backend.send = function (m) { p.sentLocate.push(m) }
    p.backend.window = function (start, count) { p.sentWindow.push([start, count]) }
    p.setCursor = function (i) { p.cursorIndex = Math.max(0, Math.min(p.total - 1, i)) }
    return p
}

// The listing's first rows in ui/PaneSwap.qml rowsLanded order; returns the cursor that turn took.
function land(p, names, total) {
    Nav.forget(p)
    p.held = 0
    p.rows = rowsOf(names)
    p.total = total === undefined ? names.length : total
    BackReturn.landRestore(p, p.swap.restore)
    p.swap.restore = null
    p.listInFlight = false
    return p.cursorIndex
}

// A rows turn through the real defer decision: waiting leaves the pane untouched, landing assigns.
function deferTurn(p, start, names, total) {
    if (typeof BackReturn.deferForLocate === "function") {
        p.swap.phase = { listed: { total: total, path: p.listingPath } }
        if (BackReturn.deferForLocate(p, p.swap.restore, rowsOf(names), p.swap.phase.listed))
            return "deferred"
    }
    Nav.forget(p)
    p.held = start
    p.rows = rowsOf(names)
    p.total = total
    BackReturn.landRestore(p, p.swap.restore)
    p.swap.restore = null
    p.listInFlight = false
    return p.cursorIndex
}

// takeLocated is the fix under test; without it the reply resolves to a marker the checks refuse.
function resolve(p, message) {
    if (typeof BackReturn.takeLocated !== "function") return "missing"
    BackReturn.takeLocated(p, message)
    return p.cursorIndex
}

function run(check) {
    // Travel keeps the departed directory for forward, a refresh keeps the branch, a new open drops it.
    var travel = standing(["a"], 0, [BackReturn.makeEntry("/home/gm", "", 0)])
    Nav.back(travel)
    check("back preserves the departed directory for forward",
        travel.forwardHistory.map(BackReturn.pathOf).join("|"), "/home/gm/Work")
    Nav.forward(travel)
    check("forward while loading is taken from the place asked for", travel.forwardHistory.length + "|" + travel.history.map(BackReturn.pathOf).join("|"), "0|/home/gm")
    travel.listInFlight = false
    Nav.forward(travel)
    check("forward returns to the departed directory", travel.path, "/home/gm/Work")
    check("forward restores back history",
        travel.history.map(BackReturn.pathOf).join("|"), "/home/gm")
    travel.listInFlight = false
    Nav.back(travel)
    travel.listInFlight = false
    Nav.open(travel, travel.path)
    check("refresh preserves forward history", travel.forwardHistory.length, 1)
    travel.listInFlight = false
    Nav.open(travel, "/tmp")
    check("new navigation discards the old forward branch", travel.forwardHistory.length, 0)

    // Entering a folder records the row; Back finds it by name after an insertion renumbered it.
    var into = standing(["a", "b", "c", "d", "Music", "z"], 4)
    Nav.open(into, "/home/gm/Work/Music")
    check("entering a folder records the row the cursor left",
        BackReturn.pathOf(into.history[0]) + "|" + into.history[0].name + "|" + into.history[0].index,
        "/home/gm/Work|Music|4")
    land(into, ["x", "y"])
    into.setCursor(1)
    Nav.back(into)
    check("back records the folder it leaves for forward",
        BackReturn.pathOf(into.forwardHistory[0]) + "|" + into.forwardHistory[0].name,
        "/home/gm/Work/Music|y")
    check("back lands on the folder it left, by name, after an insertion renumbered it",
        land(into, ["a", "b", "new", "c", "d", "Music", "z"]), 5)
    Nav.forward(into)
    check("forward lands on the row it left there, by name with the saved index elsewhere",
        land(into, ["x", "z", "y"]), 2)
    into.setCursor(1)
    Nav.back(into)
    check("a second back keeps finding the name wherever the sort put it",
        land(into, ["a", "Music", "b"]), 1)

    // Gone since: the saved index, clamped to the listing; an empty listing keeps the top.
    var gone = standing(["a"], 0)
    gone.history = [BackReturn.makeEntry("/home/gm", "deleted", 7)]
    Nav.back(gone)
    check("a name missing from the listing falls back to the saved index, clamped",
        land(gone, ["a", "b", "c"]), 2)
    var empty = standing(["a"], 0)
    empty.history = [BackReturn.makeEntry("/home/gm", "deleted", 7)]
    Nav.back(empty)
    check("an empty directory settles at the top with nothing armed",
        land(empty, [], 0) + "|" + empty.swap.restore, "0|null")

    // A newer listing replaces the armed entry, so the next rows land at the top and another directory's landing is dropped.
    var replaced = standing(["a"], 0)
    replaced.history = [BackReturn.makeEntry("/home/gm", "far", 3)]
    Nav.back(replaced)
    replaced.listInFlight = false
    replaced.swap.restore = null
    check("with the entry dropped the next rows stay at the top, though the name sits at 2 (the drop runs in cursor-swap)",
        land(replaced, ["b", "x", "far"]), 0)
    BackReturn.landRestore(replaced, BackReturn.makeEntry("/elsewhere", "far", 3))
    check("a landing for another directory moves nothing, though the name sits at 2", replaced.cursorIndex, 0)

    // A walk's rows name matches under their scope, so leaving one records no row to come back to.
    var search = standing(["sub/found.txt"], 0, [])
    search.searchMode = "results"
    Nav.open(search, "/tmp")
    check("leaving a search records its scope at the top, naming no row",
        BackReturn.pathOf(search.history[0]) + "|" + search.history[0].name + "|" + search.history[0].index,
        "/home/gm/Work||0")

    // A re-sorted folder still answers by name through a real Back: the order left behind is not the order returned to.
    var resorted = standing(["b", "a", "Music"], 2)
    Nav.open(resorted, "/home/gm/Work/Music")
    land(resorted, ["m1", "m2"])
    resorted.setCursor(1)
    Nav.back(resorted)
    check("back finds the name in the new order, not the index it stood on",
        land(resorted, ["a", "Music", "b"]), 1)

    // Each tab keeps its own stacks, so a tab switch keeps what every Back still owes its folder.
    var tabbed = standing(["a", "b", "Music"], 2)
    tabbed.history = [BackReturn.makeEntry("/home/gm", "Music", 2)]
    tabbed.tabs = Tabs.pack([Tabs.snapshot(tabbed), Tabs.snapshot(tabbed)], 0)
    Tabs.selectAt(tabbed, 1)
    Tabs.selectAt(tabbed, 0)
    Nav.back(tabbed)
    check("a tab switch keeps the stacks the back travels",
        land(tabbed, ["a", "b", "Music"]), 2)

    // A Back into a windowed listing whose saved name sits outside the first window waits for the window its locate names.
    var big = windowed([BackReturn.makeEntry("/big", "report", 800)])
    Nav.back(big)
    var names750 = fifty("w", 750, 50)
    check("a windowed back asks locate before anything lands",
        deferTurn(big, 750, names750, 2000)
            + "|" + big.sentLocate.length + ":" + (big.sentLocate[0] || {}).path,
        "deferred|1:/big/report")
    check("the waiting turn moves nothing: no cursor, still armed (the stub forgets at request; the probe holds)",
        big.rows.map(function (row) { return row.n }).join(",") + "|" + big.cursorIndex
            + "|" + (big.swap.restore && big.swap.restore.pendingPath), "|0|/big/report")
    var at801 = fifty("w", 801, 50)
    at801[0] = "report"
    check("the located reply fetches the window and still moves nothing",
        resolve(big, { directory: "/big", path: "/big/report", index: 801 })
            + "|" + JSON.stringify(big.sentWindow) + "|" + big.cursorIndex
            + "|" + (big.swap.restore && big.swap.restore.pendingPath),
        "0|[[801,64]]|0|/big/report")
    check("a second located reply fetches nothing more",
        BackReturn.takeLocated(big, { directory: "/big", path: "/big/report", index: 801 }) + "|" + big.sentWindow.length, "false|1")
    check("the located window lands the cursor on the named row, once",
        deferTurn(big, 801, at801, 2000) + "|" + big.swap.restore, "801|null")
    var inside = windowed([BackReturn.makeEntry("/big", "report", 10)])
    Nav.back(inside)
    check("a saved index inside the first window still waits when the name moved out, since that row is another file",
        deferTurn(inside, 0, fifty("w", 0, 64), 2000) + "|" + (inside.sentLocate[0] || {}).path, "deferred|/big/report")
    var bigGone = windowed([BackReturn.makeEntry("/big", "report", 800)])
    Nav.back(bigGone)
    deferTurn(bigGone, 750, fifty("w", 750, 50), 2000)
    check("a located miss asks for the fallback window and still moves nothing",
        resolve(bigGone, { directory: "/big", path: "/big/report", index: -1 })
            + "|" + JSON.stringify(bigGone.sentWindow) + "|" + bigGone.cursorIndex, "0|[[800,64]]|0")
    check("the fallback window lands the clamped index and drops the restore",
        deferTurn(bigGone, 800, fifty("w", 800, 50), 2000) + "|" + bigGone.swap.restore, "800|null")
    var bigStale = windowed([BackReturn.makeEntry("/big", "report", 800)])
    Nav.back(bigStale)
    deferTurn(bigStale, 750, fifty("w", 750, 50), 2000)
    check("a reply for another path is refused",
        typeof BackReturn.takeLocated === "function"
            ? BackReturn.takeLocated(bigStale, { directory: "/big", path: "/big/other", index: 3 }) : "missing", false)
    check("a refused reply leaves the armed restore alone",
        bigStale.swap.restore && bigStale.swap.restore.pendingPath, "/big/report")
}
