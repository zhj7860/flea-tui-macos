.import "../../ui/js/Nav.js" as Nav
.import "../../ui/js/BackReturn.js" as BackReturn
.import "../../ui/js/Anchor.js" as Anchor
.import "../../ui/js/Swap.js" as Swap
.import "../../ui/js/Tabs.js" as Tabs
.import "sourcefixture.js" as Source

// The newest navigation takes the place of a listing still out: while one is out, the folder it asked for is the pane's current place.

var LOADING = "A directory is already loading."

// A pane showing /home/gm with a settled listing; a request is out until land() answers it.
function pane(history) {
    var p = {
        listInFlight: false, listedSeen: true, path: "/home/gm", listingPath: "", total: 40, held: 10, rows: [{ n: "a.txt" }],
        shown: null, kindNames: [], thumbState: "", dirSizeState: "", cursorIndex: 3, pendingSelect: "", renamingIndex: -1,
        trashArmedAt: 0, listingState: "ready", stateMessage: "", lockedMode: 0, filterQuery: "", filterTyping: false,
        collide: { opened: false }, menuVisible: false, history: history || [], forwardHistory: [], said: [], sent: [], stopped: 0, cleared: 0
    }
    p.clearSelection = function () { p.cleared += 1 }
    p.message = function (text, isError) { p.said.push(text) }
    p.listArea = { primeSettle: function () {} }
    p.rowFor = function (index) { return index === 3 ? { n: "a.txt", d: false } : null }
    p.join = function (base, name) { return base + "/" + name }
    // ui/PaneSwap.qml holding the settled rows, with the Back or Forward entry it keeps for the landing.
    p.swap = { restore: null, stopWaiting: function () { p.stopped += 1 },
               hold: function (ask) { p.swap.restore = ask.restore ? Object.assign({}, ask.restore) : null; return true } }
    p.backend = { list: function (path) { p.sent.push("list " + path) }, askFsInfo: function () { p.sent.push("fsinfo") } }
    p.open = function (target) { Nav.open(p, target) }
    p.openWithoutHistory = function (target, options) { Nav.openWithoutHistory(p, target, options) }
    return p
}

// The answer for the newest request: the pane moves onto it and nothing is out.
function land(p) {
    p.path = p.listingPath
    p.listInFlight = false
    p.swap.restore = null
}

function paths(stack) { return stack.map(BackReturn.pathOf).join("|") }
function marked(stack) { return stack.map(function (e) { return BackReturn.pathOf(e) + ":" + (e.name || "") + ":" + (e.index || 0) }).join("|") }

function run(check) {
    var p = pane(["/"])
    Nav.open(p, "/mnt/a")
    check("the first open is out, the pane still draws the folder it left", p.listInFlight + "|" + p.path + "|" + p.listingPath, "true|/home/gm|/mnt/a")
    Nav.open(p, "/mnt/b")
    check("a second open while it is out is taken, not refused", p.said.join(""), "")
    check("and asks for the second folder behind the first", p.sent.join(","), "list /mnt/a,fsinfo,list /mnt/b,fsinfo")
    check("and the folder asked for moves to the second", p.listingPath + "|" + p.listInFlight, "/mnt/b|true")
    check("and the drawn folder stays until an answer lands", p.path, "/home/gm")
    check("and the listing let go is told, once", p.stopped, 1)
    check("and a place that never landed is not pushed", paths(p.history), "/|/home/gm")
    check("and the forward branch stays cleared", p.forwardHistory.length, 0)
    land(p)
    check("the pane lands on the newest folder", p.path, "/mnt/b")
    var behind = pane(["/"])
    Nav.open(behind, "/mnt/a")
    Nav.open(behind, "/mnt/b")
    land(behind)
    Nav.back(behind)
    check("Back from the newest folder lands on the place before the one that never landed", behind.listingPath + " " + paths(behind.history), "/home/gm /")
    Nav.open(p, "/mnt/c")
    check("a first request out of a settled pane lets nothing go", p.stopped, 1)

    var kept = pane(["/", "/home"])
    kept.path = "/home/gm"
    Nav.open(kept, "/mnt/a")
    Nav.back(kept)
    check("a Back taken while a listing is out puts the pending place on the other stack", paths(kept.forwardHistory), "/mnt/a")
    Nav.open(kept, "/mnt/b")
    check("a Back that returns to the drawn place makes it a place to push again, and the open clears the forward branch", paths(kept.history) + "|" + kept.forwardHistory.length, "/|/home|/home/gm|0")
    var far = pane(["/", "/home"])
    far.path = "/home/gm"
    Nav.open(far, "/mnt/a")
    Nav.back(far)
    Nav.back(far)
    Nav.open(far, "/mnt/b")
    check("an open over a Back that stepped to another place keeps the drawn place in history and clears the forward branch", paths(far.history) + "|" + far.forwardHistory.length, "/|/home/gm|0")

    // A Back out puts the drawn place on the forward branch an open clears, so the open must keep it in history.
    var away = pane(["/home/x", "/home/y"])
    away.path = "/home/z"
    Nav.back(away)
    Nav.open(away, "/mnt/w")
    land(away)
    check("an open over a Back out keeps the drawn place, not the one never reached, behind the new folder", paths(away.history) + "|" + away.forwardHistory.length, "/home/x|/home/z|0")
    Nav.back(away)
    check("and Back from the new folder lands on the drawn place", away.listingPath, "/home/z")
    var ahead = pane(["/home/x"])
    ahead.path = "/home/z"
    ahead.forwardHistory = ["/home/y"]
    Nav.forward(ahead)
    Nav.open(ahead, "/mnt/w")
    check("an open over a Forward out leaves the drawn place pushed once, by the Forward", paths(ahead.history) + "|" + ahead.forwardHistory.length, "/home/x|/home/z|0")

    // A Forward stacked on a Back out re-reads the drawn folder, so the open pushes the drawn place from the pane itself.
    var stacked = pane(["/home/x", "/home/y"])
    stacked.path = "/home/z"
    Nav.back(stacked)
    Nav.forward(stacked)
    Nav.open(stacked, "/mnt/w")
    check("an open over a Forward stacked on a Back out keeps the drawn place in history once", paths(stacked.history) + "|" + stacked.forwardHistory.length, "/home/x|/home/y|/home/z|0")

    var same = pane(["/"])
    Nav.open(same, "/mnt/a")
    Nav.open(same, "/mnt/a")
    check("asking for the folder already asked for pushes no second entry", paths(same.history), "/|/home/gm")

    var reread = pane(["/"])
    reread.listInFlight = true
    reread.listingPath = "/home/gm"
    Nav.open(reread, "/mnt/a")
    check("a navigation over a re-read of the drawn folder remembers the cursor row it left", marked(reread.history), "/::0|/home/gm:a.txt:3")

    // Back and Forward step from the place asked for, so two quick Backs step back twice.
    var quick = pane(["/", "/home", { path: "/home/gm", name: "b.txt", index: 5 }])
    quick.path = "/home/gm/Work"
    Nav.back(quick)
    check("a first Back lists the entry it pops", quick.listingPath + " " + paths(quick.history), "/home/gm /|/home")
    Nav.back(quick)
    check("a second Back before it lands steps back again", quick.listingPath + " " + paths(quick.history), "/home /")
    check("and says nothing", quick.said.join(""), "")
    check("and Forward keeps the places left in order, the pending one with the cursor it owed",
          marked(quick.forwardHistory), "/home/gm/Work:a.txt:3|/home/gm:b.txt:5")
    Nav.forward(quick)
    check("a Forward while loading takes the newest forward entry from the place asked for", quick.listingPath + " " + paths(quick.history), "/home/gm /|/home")

    // Up climbs from the folder asked for, as it already does past the wait.
    var up = pane(["/"])
    Nav.open(up, "/mnt/share/deep")
    Nav.parent(up)
    check("Up while loading climbs from the folder asked for", up.listingPath + "|" + up.pendingSelect, "/mnt/share|/mnt/share/deep")
    check("and the climb is taken, the folder that never landed is not pushed", paths(up.history) + "|" + up.said.join(""), "/|/home/gm|")
    check("canGoUp reads the same rule while a listing is out", Nav.climbsFromListing(up), true)
    check("and a re-read of the drawn folder climbs from the drawn one", Nav.climbsFromListing({ listInFlight: true, listingPath: "/home/gm", path: "/home/gm" }), false)

    // Row actions keep their refusal, and a re-list in place never takes a navigation's place.
    var row = pane()
    row.listInFlight = true
    row.listingPath = "/mnt/a"
    row.rowFor = function () { return { n: "docs", d: true, i: 0 } }
    Nav.openCursor(row, { open: function () {} })
    check("Enter on a row while loading still refuses and asks for nothing", row.said.join("") + "|" + row.sent.length, LOADING + "|0")
    var inPlace = pane()
    inPlace.listInFlight = true
    inPlace.listingPath = "/mnt/a"
    Nav.openWithoutHistory(inPlace, "/home/gm", { inPlace: true })
    check("a re-list in place of the drawn folder still refuses while a navigation is out", inPlace.said.join("") + "|" + inPlace.listingPath + "|" + inPlace.sent.length, LOADING + "|/mnt/a|0")
    var plain = pane()
    plain.listInFlight = true
    Nav.openWithoutHistory(plain, "/etc")
    check("and a caller that names no supersede refuses too", plain.said.join("") + "|" + plain.sent.length, LOADING + "|0")

    // A listing that already fell back to the loading mark keeps it through the newest request.
    var fell = pane(["/"])
    fell.listingState = "loading"
    fell.listInFlight = true
    fell.listingPath = "/mnt/a"
    fell.swap.phase = Swap.expired(Swap.idle())
    fell.swap.fellBack = true
    fell.swap.hold = function (ask) { fell.swap.phase = Swap.begin(fell.swap.phase, fell.listingState, "", ask, 1); fell.swap.fellBack = fell.swap.phase.fellBack; return fell.swap.phase.holding }
    Nav.open(fell, "/mnt/b")
    check("the loading mark is not dropped by the newest request", fell.swap.phase.fellBack + "|" + fell.swap.phase.holding, "true|false")

    // The failure of a folder no longer asked for ends nothing.
    var dropped = false
    var late = { listInFlight: true, listedSeen: false, listingPath: "/mnt/b", swap: { phase: { relist: false }, drop: function () { dropped = true } } }
    check("a failure naming an earlier folder ends nothing", Swap.failListing(late, "scan", "/mnt/a") + "|" + dropped + "|" + late.listInFlight, "false|false|true")
    check("a failure naming the folder asked for ends the listing", Swap.failListing(late, "scan", "/mnt/b") + "|" + dropped + "|" + late.listInFlight, "true|true|false")
    var dead = { listInFlight: true, listedSeen: false, listingPath: "/mnt/b", swap: { phase: { relist: false }, drop: function () {} } }
    check("a dead backend names no folder and still ends it", Swap.failListing(dead, "backend", "") + "|" + dead.listInFlight, "true|false")
    var other = { listInFlight: true, listedSeen: false, listingPath: "/mnt/b", swap: { phase: { relist: false }, drop: function () {} } }
    check("a failure that is not a scan ends it whatever path it names", Swap.failListing(other, "rename-stranded", "/mnt/a/old.txt") + "|" + other.listInFlight, "true|false")

    // ui/Pane.qml openWithoutHistory as written: a navigation passes a listing out and restarts the wait, a re-list does neither.
    var paneOpen = eval("(function (root, Anchor, Nav, trashHost, RecentMode, ViewState, listingWait, newPath, options) {"
        + Source.block(Source.source("ui/Pane.qml"), "function openWithoutHistory(newPath, options)", "ui/Pane.qml") + "})")
    function viaPane(options) {
        var q = pane(), hops = [], waits = 0
        q.listInFlight = true
        q.flashActive = false
        paneOpen(q, Anchor, { openWithoutHistory: function (on, path) { hops.push(path) } }, { close: function () {} },
                 { leave: function () {} }, { state: {} }, { restart: function () { waits += 1 } }, "/mnt/b", options)
        return hops.join(",") + "|" + waits + "|" + q.said.join("")
    }
    check("a navigation reaches the listing and gives it a fresh wait", viaPane({ supersede: true }), "/mnt/b|1|")
    check("anything else is refused before the wait is touched", viaPane({ inPlace: true }) + "," + viaPane(), "|0|" + LOADING + ",|0|" + LOADING)

    // A tab switch leaves its cursor, order and located row to the landing; a navigation that lets that listing go takes them with it.
    function tabbed() {
        var q = pane(["/"])
        q.viewMode = "list"
        q.showHidden = false
        q.tabs = { items: [], index: 0, pendingCursor: -1, pendingCursorName: null, pendingLocatePath: "", pendingSortBy: "", pendingSortDesc: false }
        return q
    }
    function owed(q) { var t = q.tabs; return [t.pendingCursor, t.pendingCursorName, t.pendingLocatePath, t.pendingSortBy, t.pendingSortDesc].join("|") }
    function item(path, cursor, by) { return { path: path, showHidden: false, viewMode: "list", history: [], forwardHistory: [], cursorIndex: cursor, sortBy: by, sortDesc: true } }
    var tab = tabbed()
    Tabs.apply(tab, item("/mnt/t2", 7, "size"))
    check("a tab switch leaves its cursor and order for the landing", owed(tab), "7|||size|true")
    Nav.open(tab, "/mnt/c")
    check("a navigation that lets the switch's listing go clears what the switch owed", owed(tab), "-1||||false")
    var again = tabbed()
    Tabs.apply(again, item("/mnt/t2", 7, "size"))
    Tabs.apply(again, item("/mnt/t3", 2, "date"))
    check("a second switch while the first is out owes its own cursor and order, not the first's", owed(again), "2|||date|true")
    var kept = tabbed()
    kept.listInFlight = true
    kept.listingPath = "/home/gm"
    kept.tabs.pendingCursor = 5
    Nav.openWithoutHistory(kept, "/mnt/c", { inPlace: true })
    check("a refused re-list leaves what the landing owes alone", owed(kept), "5||||false")
}
