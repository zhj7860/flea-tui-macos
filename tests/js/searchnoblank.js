.import "../../ui/js/Swap.js" as Swap
.import "../../ui/js/Search.js" as Search
.import "../../ui/js/Filter.js" as Filter
.import "../../ui/js/Nav.js" as Nav
.import "filterfixture.js" as Fixture

// Search and "/" draw no blank or partial frame: the counter shapes ui/PaneSwap.qml reads per frame.

function run(check) {
    // The navigation arm is unchanged: a listing out drawn loading is blank, past the cap it is loading.
    check("a listing out drawn in the loading state before the cap is the blank frame",
        Swap.frameKind(true, "loading", false, 0, 0, false), "blank")
    check("after the cap it is the loading state a slow folder always showed",
        Swap.frameKind(true, "loading", true, 0, 0, false), "loading")
    check("held rows are no blank frame, and neither is a pane at rest",
        Swap.frameKind(true, "ready", false, 5, 40, false) + "|" + Swap.frameKind(false, "ready", false, 5, 40, false), "|")
    // A live answer holds old rows until its own rows land, so drawn never reaches zero beside a live count.
    check("search live with its rows drawn is no blank frame",
        Swap.frameKind(false, "ready", false, 3, 3, true), "")
    check("search live with rows cleared beside a count naming them is the blank frame",
        Swap.frameKind(false, "ready", false, 0, 3, true), "blank")
    check("an honest search zero carries its own zero, so it is no blank frame",
        Swap.frameKind(false, "empty", false, 0, 0, true), "")
    // "/" narrows in JS and never touches rows, so drawn stays the held window whatever matches.
    check("a filter with matches and its rows drawn is no blank frame",
        Swap.frameKind(false, "ready", false, 40, 40, true), "")
    var missed = Fixture.pane(undefined, 33)
    Fixture.typeInto(missed, "zzz")
    check("a filter with no match keeps the held window drawn, so it is no blank frame either",
        missed.rows.length + "/" + missed.shownTotal + "|"
            + Swap.frameKind(false, "ready", false, missed.rows.length, missed.total, missed.filterQuery.length > 0), "7/0|")
    check("a filter with its rows cleared beside the directory count is the blank frame",
        Swap.frameKind(false, "ready", false, 0, 40, true), "blank")
    // Without a live session or a standing query the new arm stays silent, whatever rows say.
    check("no session and no query counts nothing even with no row drawn",
        Swap.frameKind(false, "ready", false, 0, 40, false), "")
    // Columns "/" narrows through shown with the held rows standing: the active column models shownTotal over pane.rows.
    var narrowed = Fixture.pane()
    Fixture.typeInto(narrowed, "screen")
    check("a Columns '/' narrowing never touches rows or total",
        narrowed.rows.length + "/" + narrowed.total + "/" + narrowed.shownTotal, "7/7/3")
    check("its frame is no blank: rows stand beside the directory count under the standing query",
        Swap.frameKind(false, "ready", false, narrowed.rows.length, narrowed.total, narrowed.filterQuery.length > 0), "")
    check("every drawn view position resolves to a held row",
        [0, 1, 2].map(function (v) { return narrowed.rowFor(Filter.at(narrowed.shown, v)) !== null }).join(","), "true,true,true")
    var nomatch = Fixture.pane()
    Fixture.typeInto(nomatch, "zzz")
    check("a Columns '/' no-match keeps the held window too, so the message draws over standing rows",
        nomatch.rows.length + "/" + nomatch.total + "/" + nomatch.shownTotal, "7/7/0")
    check("and the counter stays silent there as well",
        Swap.frameKind(false, "ready", false, nomatch.rows.length, nomatch.total, nomatch.filterQuery.length > 0), "")
    check("a Columns frame emptied for one turn under the standing query is the blank frame",
        Swap.frameKind(false, "ready", false, 0, nomatch.total, nomatch.filterQuery.length > 0), "blank")
    // The exit is atomic: held walk rows keep the session open until the folder lands.
    var walked = Swap.heard(Swap.idle(), true)
    check("the search exit holds the walk state until the folder lands",
        Swap.begin(walked, "ready", "typing", { holdWalk: true }, 0).holding, true)
    check("any other listing after a walk still forgets at once",
        Swap.begin(walked, "ready", "", {}, 0).holding, false)
    check("an exit with the folder rows standing holds them too",
        Swap.begin(walked, "ready", "", { holdWalk: true }, 0).holding, true)
    check("a late session line never lands once the exit is out",
        Swap.dropSessionLine("typing", 9, 9, true), true)
    check("while the exit's own directory lines still land",
        Swap.dropSessionLine("typing", 0, 9, true), false)
    // The forgot exit holds nothing, so it goes out loading with the walk's count of 12 still named beside it.
    var forgot = Swap.begin(walked, "ready", "", {}, 0)
    check("the forgot exit counts its blank frame on the listing arm, never the live one",
        forgot.holding + "|" + Swap.frameKind(true, "loading", forgot.fellBack, 0, 12, false), "false|blank")
    check("the held exit counts nothing: ready rows beside their own count with the strip up",
        Swap.frameKind(true, "ready", false, 3, 12, true), "")
    // The abort wires the exit: the backend closes at the request and the drawn state waits.
    var closed = 0
    var asked = null
    var exiting = { searchMode: "typing", searchQuery: "nor", searchRunning: false,
        searchCancelled: false, searchGen: 9, searchFrom: "/d", searchBase: "/scope",
        path: "/d", total: 12, backend: { searchClose: function () { closed++ } },
        openWithoutHistory: function (path, options) { asked = { path: path, options: options } } }
    Search.abort(exiting)
    check("the abort re-lists the folder it came from", asked.path, "/d")
    check("and the relist holds the walk state", asked.options && asked.options.holdWalk, true)
    check("the abort closes the backend through the walk it leaves", closed, 1)
    check("and the drawn session waits for the landing", exiting.searchMode + "|" + (exiting.searchLeaving === true), "typing|true")
    // The same exit through ui/js/Nav.js lands the relist mark on the swap phase the listing failure reads.
    var routed = { searchMode: "typing", searchQuery: "nor", searchRunning: false, searchCancelled: false,
        searchGen: 9, searchOpenedGen: 0, searchFrom: "/d", searchBase: "/scope", path: "/d", total: 12,
        listInFlight: false, listingState: "ready", listingPath: "", pendingBackground: "", linkTargetPendingId: 0,
        storageClass: "", storageKnown: true, windowSize: 10, showHidden: false, filterTyping: false,
        listingPreferences: "", appliedListingPreferences: "", sent: [],
        backend: { searchClose: function () {}, list: function (path) { routed.sent.push(path) }, askFsInfo: function () {} } }
    routed.swap = { phase: Swap.idle(), hold: function (ask) {
        routed.swap.phase = Swap.begin(routed.swap.phase, routed.listingState, routed.searchMode, ask, 0)
        return routed.swap.phase.holding } }
    routed.openWithoutHistory = function (path, options) { Nav.openWithoutHistory(routed, path, options) }
    Search.abort(routed)
    check("an abort routed through the navigation asks its folder with the relist mark held",
        routed.sent.join("|") + "|" + routed.swap.phase.holding + "|" + routed.swap.phase.relist, "/d|true|true")
    // Leaving a walk defers the drawn close while results stand, and closes at once otherwise.
    var liveClosed = 0
    var living = { searchMode: "results", searchQuery: "n", searchRunning: false,
        searchGen: 4, total: 3, backend: { searchClose: function () { liveClosed++ } } }
    Search.leaveWalk(living)
    check("a live walk keeps its strip with the backend closed", living.searchMode + "|" + liveClosed, "results|1")
    check("and owes its landing", living.searchLeaving, true)
    // Tabs close the walk before the navigation closes it again: one backend close per exit.
    var reClosed = 0
    var reliving = { searchMode: "results", searchQuery: "n", searchRunning: false,
        searchGen: 4, total: 3, searchLeaving: true, backend: { searchClose: function () { reClosed++ } } }
    Search.leaveWalk(reliving)
    check("a second close of the same exit closes nothing again", reClosed, 0)
    var emptyClosed = 0
    var emptied = { searchMode: "typing", searchQuery: "", searchRunning: false,
        searchGen: 2, total: 7, searchFrom: "/d", searchBase: "", path: "/d",
        backend: { searchClose: function () { emptyClosed++ } } }
    Search.leaveWalk(emptied)
    check("an emptied query closes at once with nothing to hold", emptied.searchMode + "|" + emptyClosed, "|1")
    // The Esc relist carries its mark on the phase, so only its own failure clears the cursor file.
    var relisting = { listInFlight: true, listedSeen: false, searchGen: 3, pendingSelect: "/d/b.txt",
        swap: { phase: Swap.begin(Swap.idle(), "ready", "", { holdWalk: true, relist: true }, 0), drop: function () {} } }
    Swap.failListing(relisting, "scan")
    check("an Esc relist that died leaves no cursor file armed", relisting.pendingSelect, "")
    var later = { listInFlight: true, listedSeen: false, searchGen: 3, pendingSelect: "/d/b.txt",
        swap: { phase: Swap.begin(Swap.idle(), "ready", "", {}, 0), drop: function () {} } }
    Swap.failListing(later, "scan")
    check("but a later listing failing after a search keeps its own", later.pendingSelect, "/d/b.txt")
    check("and the relist mark ends with the listing", Swap.dropped(relisting.swap.phase).relist, false)
}
