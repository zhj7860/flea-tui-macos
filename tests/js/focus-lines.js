.import "../../ui/js/Focus.js" as Focus
.import "../../ui/js/RecentMode.js" as RecentMode
.import "../../ui/js/Search.js" as Search
.import "filterfixture.js" as Fixture

// Issue 12's own suite, split out of tests/js/focus.js at its 300-line cap the way focus-forward.js
// was: what the search's and the filter's query lines do with a key while they hold the caret.

function closed() {
    return { active: false, isMedia: false, isPdf: false }
}

function key(code, text) {
    return { key: code, text: text, modifiers: Qt.NoModifier }
}

// A pane with the whole handleKey route wired, because issue 12's defect is that a query line
// swallowed the key: only the real route can show a key reaching the rows or failing to.
function queryPane() {
    var p = Fixture.pane()
    p.focusView = "list"
    p.viewMode = "list"
    p.searchMode = ""
    p.recentMode = ""
    p.searchQuery = ""
    p.searchFrom = ""
    p.searchHere = false
    p.searchGen = 0
    p.searchRunning = false
    p.searchScanned = 0
    p.searchCancelled = false
    p.home = ""
    p.path = "/d"
    p.showHidden = false
    p.listingState = "ready"
    p.kindNames = []
    p.trashArmedAt = 0
    p.inputAt = 0
    p.rowsAt = 0
    p.cursorStride = 1
    // Half of this is a page key's step, so pageDown and pageUp move a real distance here.
    p.visibleRows = 4
    p.preview = closed()
    p.shareBrowser = { active: false }
    p.said = ""
    p.message = function (text, isError) { p.said = text }
    p.armPrompted = function () {}
    p.clearSelection = function () { p.picked = {} }
    // Mirrors ui/Pane.qml restoreRecentSort, so a walk from Recent restores through it.
    p.restoreRecentSort = function () { RecentMode.restoreSort(p) }
    p.renameEditor = function () { return null }
    p.act = function (action) { Focus.act(action, p) }
    p.cancelledCalls = 0
    p.setCursor = function (index) { p.cursorIndex = Math.max(0, Math.min(p.rows.length - 1, index)) }
    p.openWithoutHistory = function (path) { p.relisted = path }
    p.rowFor = function (index) { return p.rows[index] || null }
    p.join = function (base, name) { return base + "/" + name }
    p.pendingSelect = ""
    p.sentQueries = []
    p.openedScopes = []
    p.closedSessions = 0
    p.backend = { searchOpen: function (scope, folder, hidden) { p.openedScopes.push(scope) },
                  searchQuery: function (query, gen, count) { p.sentQueries.push(gen + ":" + query) },
                  searchClose: function () { p.closedSessions += 1 },
                  searchCancel: function () { p.cancelledCalls += 1 } }
    return p
}

// Focus.handleKey takes the rail only to ask it for a live rename editor.
function noRail() {
    return { renameEditor: function () { return null } }
}

function run(check) {
    // Issue 12: both query lines owned every key while they had the caret, so an arrow never reached
    // the rows and a listing with more than one match could not be walked from the keyboard.
    var narrowing = queryPane()
    narrowing.filterTyping = true
    narrowing.filterQuery = "scr"
    narrowing.refresh()
    Focus.handleKey(key(Qt.Key_Down, ""), narrowing, noRail())
    check("an arrow on the filter's query line hands the caret back to the rows",
          narrowing.filterTyping, false)
    check("and leaves the filter standing, so the narrowed rows are what is moved through",
          narrowing.filterQuery, "scr")
    check("and moves the cursor on that same press, to the second row the filter kept",
          narrowing.cursorIndex, 1)
    // The line is still a line: every printable character narrows it rather than reaching the rows.
    var typingOn = queryPane()
    typingOn.filterTyping = true
    typingOn.filterQuery = "scr"
    typingOn.refresh()
    Focus.handleKey(key(Qt.Key_J, "j"), typingOn, noRail())
    check("and j is still typed into the query rather than moving the cursor",
          typingOn.filterQuery + "|" + typingOn.filterTyping, "scrj|true")

    // The search's line moves the result cursor the way fzf does, so one press walks no walk: a walk per keystroke is the sweep the design refused.
    var walking = queryPane()
    walking.searchMode = "typing"
    walking.searchQuery = "scr"
    walking.cursorIndex = 5
    Focus.handleKey(key(Qt.Key_Down, ""), walking, noRail())
    check("an arrow on the search's query line moves the cursor and keeps the line",
          walking.searchMode + "|" + walking.searchQuery + "|" + walking.cursorIndex, "typing|scr|6")
    check("and asks for nothing", walking.sentQueries.length + walking.openedScopes.length, 0)
    var stillTyping = queryPane()
    stillTyping.searchMode = "typing"
    stillTyping.searchQuery = "scr"
    Focus.handleKey(key(Qt.Key_E, "e"), stillTyping, noRail())
    check("and a printable key still extends the query without walking anything",
          stillTyping.searchQuery + "|" + stillTyping.sentQueries.join(","), "scre|1:scre")
    // While the folder's listing is out, an arrow on the query line moves no held row, as it moves none off the line.
    var loading = queryPane()
    loading.searchMode = "typing"
    loading.searchQuery = "scr"
    loading.cursorIndex = 5
    loading.listInFlight = true
    Focus.handleKey(key(Qt.Key_Down, ""), loading, noRail())
    check("an arrow on the query line while a listing is out keeps the cursor and says why",
          loading.cursorIndex + "|" + loading.said, "5|A directory is already loading.")
    var leaving = queryPane()
    leaving.searchMode = "typing"
    leaving.searchQuery = "scr"
    leaving.cursorIndex = 5
    leaving.searchLeaving = true
    Focus.handleKey(key(Qt.Key_Down, ""), leaving, noRail())
    check("and while the search's exit is out the arrow moves nothing either", leaving.cursorIndex, 5)
    // Quick Look drawn over a search still typing owns its keys, as it does over any listing.
    var looked = queryPane()
    looked.searchMode = "typing"
    looked.searchQuery = "scr"
    looked.preview = { active: true, isMedia: false, isPdf: false, revealStrip: function () {},
                       close: function () { looked.preview.active = false } }
    Focus.handleKey(key(Qt.Key_E, "e"), looked, noRail())
    check("a letter over Quick Look types nothing into the hidden query",
          looked.searchQuery + "|" + looked.sentQueries.length, "scr|0")
    Focus.handleKey(key(Qt.Key_Escape, ""), looked, noRail())
    check("and Escape closes Quick Look, leaving the search standing",
          looked.preview.active + "|" + looked.searchMode + "|" + looked.searchQuery, "false|typing|scr")
    // The share listing drawn over a search still typing owns its keys the same way.
    var shared = queryPane()
    shared.searchMode = "typing"
    shared.searchQuery = "scr"
    shared.cursorIndex = 5
    shared.shareBrowser = { active: true, owner: shared, moved: 0, moveCursor: function (step) { shared.shareBrowser.moved += step },
                            activateCursor: function () {}, close: function () { shared.shareBrowser.active = false } }
    Focus.handleKey(key(Qt.Key_E, "e"), shared, noRail())
    Focus.handleKey(key(Qt.Key_Down, ""), shared, noRail())
    check("a letter and an arrow over the share listing type nothing and walk only the listing",
          shared.searchQuery + "|" + shared.sentQueries.length + "|" + shared.cursorIndex + "|" + shared.shareBrowser.moved, "scr|0|5|1")
    Focus.handleKey(key(Qt.Key_Escape, ""), shared, noRail())
    check("and Escape closes the share listing, leaving the search standing",
          shared.shareBrowser.active + "|" + shared.searchMode + "|" + shared.searchQuery, "false|typing|scr")
    // The rail draws no caret, so the query line keeps its arrows while the rail holds the view.
    var railed = queryPane()
    railed.searchMode = "typing"
    railed.searchQuery = "scr"
    railed.cursorIndex = 5
    railed.focusView = "rail"
    var rail = { cursorIndex: 2, entries: [1, 2, 3, 4], renameEditor: function () { return null } }
    Focus.handleKey(key(Qt.Key_Down, ""), railed, rail)
    check("an arrow on the query line walks the results even while the rail holds the view",
          railed.cursorIndex + "|" + rail.cursorIndex, "6|2")

    // Issue 287: Ctrl+V reaches each query line's paste, and with no line up it stays the file paste.
    function pasteChord() { return { key: Qt.Key_V, text: "\u0016", modifiers: Qt.ControlModifier } }
    function clipPane(clip, log) {
        var p = queryPane()
        p.clipboardText = function () { log.push("read"); return clip }
        p.act = function (action) { log.push(action) }
        return p
    }
    var filterLog = []
    var filtering = clipPane("repo", filterLog)
    filtering.filterTyping = true
    filtering.filterQuery = ""
    Focus.handleKey(pasteChord(), filtering, noRail())
    check("ctrl+v on the filter's line types the clipboard into its query and runs no action",
          filtering.filterQuery + "|" + filterLog.join(","), "repo|read")
    var searchLog = []
    var searching = clipPane("repo", searchLog)
    searching.searchMode = "typing"
    Focus.handleKey(pasteChord(), searching, noRail())
    check("ctrl+v on the search's line extends its query and runs no action",
          searching.searchQuery + "|" + searching.sentQueries.join(",") + "|" + searchLog.join(","), "repo|1:repo|read")
    var listLog = []
    Focus.handleKey(pasteChord(), clipPane("repo", listLog), noRail())
    check("with no query line up ctrl+v is the file paste and never reads the clipboard text", listLog.join(","), "paste")

    // Issue 28's four keys leaving the line was claimed in prose and in a comment and driven by
    // nothing, and the up arrow was untested too. ui/SearchStrip.qml draws the query as a Text with
    // the caret pinned after it, so Home, End, PageUp and PageDown have no caret to move on the line
    // and the listing's own meaning is the only one they can carry: ui/js/Focus.js LEAVES_LINE.
    // "scr" keeps rows 0, 1, 5 and 6, so the cursor starts on the third of the four and every one
    // of these five has somewhere different to take it: leaving the line is half the behaviour and
    // the key still reaching the listing is the other half, which nothing here used to assert.
    var others = [Qt.Key_Up, Qt.Key_Home, Qt.Key_End, Qt.Key_PageUp, Qt.Key_PageDown]
    var handed = []
    var landed = []
    var committed = []
    for (var i = 0; i < others.length; i++) {
        var narrowed = queryPane()
        narrowed.filterTyping = true
        narrowed.filterQuery = "scr"
        narrowed.refresh()
        narrowed.cursorIndex = 5
        Focus.handleKey(key(others[i], ""), narrowed, noRail())
        handed.push(narrowed.filterTyping + ":" + narrowed.filterQuery)
        landed.push(narrowed.cursorIndex)
        var walks = queryPane()
        walks.searchMode = "typing"
        walks.searchQuery = "scr"
        walks.cursorIndex = 5
        Focus.handleKey(key(others[i], ""), walks, noRail())
        committed.push(walks.searchMode + ":" + walks.sentQueries.length)
    }
    check("every other cursor key hands the filter's caret back, with its query left standing",
          handed.join("|"), "false:scr|false:scr|false:scr|false:scr|false:scr")
    check("and each one then means what it means in the listing, off the row it started on",
          landed.join("|"), "1|0|6|0|6")
    check("and on the search's line each one moves the cursor and commits nothing",
          committed.join("|"), "typing:0|typing:0|typing:0|typing:0|typing:0")

    // Two-step Escape through the real act route: the first press stops a running walk and keeps the results, the next closes the session and re-lists its folder.
    var walking = queryPane()
    walking.searchMode = "results"
    walking.searchRunning = true
    walking.searchGen = 2
    walking.searchQuery = "sc"
    Focus.act("escape", walking)
    check("the first escape stops the walk and keeps the results",
          walking.cancelledCalls + "|" + walking.searchMode, "1|results")
    walking.searchRunning = false
    Focus.act("escape", walking)
    check("and the next escape closes it and re-lists its folder",
          walking.cancelledCalls + "|" + walking.searchMode + "|" + walking.relisted + "|" + walking.closedSessions, "1|results|/d|1")

    // Issue 30's only control is tab on the search's query line, and it was driven straight into
    // Search.typeKey. Nothing said Focus.handleKey routes Qt.Key_Tab there rather than resolving it
    // through Keymap to focusNext, which is what the very same key means one state away.
    var scoping = queryPane()
    scoping.searchMode = "typing"
    scoping.searchQuery = "scr"
    Focus.handleKey(key(Qt.Key_Tab, "\t"), scoping, noRail())
    check("tab on the search's query line reaches the scope and not the focus switch",
          scoping.searchHere + "|" + scoping.focusView, "true|list")
    var switching = queryPane()
    Focus.handleKey(key(Qt.Key_Tab, "\t"), switching, noRail())
    check("and with no query line up the same key is the focus switch the sheet draws",
          switching.searchHere + "|" + switching.focusView, "false|rail")

    // ui/js/Search.js says the scope is a property of the window: close() and reveal() leave
    // searchHere standing on purpose, so it holds until it is pressed again. That is a claim about
    // state outliving the search that set it, and it was written in a comment and driven by nothing.
    var sticky = queryPane()
    sticky.home = "/d"
    sticky.path = "/d/sub"
    sticky.searchMode = "typing"
    sticky.searchQuery = "scr"
    Focus.handleKey(key(Qt.Key_Tab, "\t"), sticky, noRail())
    check("tab re-opens the new scope and re-sends the standing query",
          sticky.openedScopes.join(",") + "|" + sticky.sentQueries.join(","), "/d/sub|1:scr")
    Focus.handleKey(key(Qt.Key_Escape, ""), sticky, noRail())
    check("escape off the query line closes the backend and leaves the scope where tab put it",
          sticky.searchMode + "|" + sticky.searchHere + "|" + sticky.closedSessions, "typing|true|1")
    Search.start(sticky)
    check("so the next search opens the pane's own directory with no second press",
          sticky.openedScopes.pop(), "/d/sub")
    // The denominator: without that flip the same fixture opens home, so the check above is not
    // reading a scope the pane would have chosen anyway.
    var wide = queryPane()
    wide.home = "/d"
    wide.path = "/d/sub"
    Search.start(wide)
    check("and a window that never pressed tab still opens the whole home directory",
          wide.openedScopes.join(","), "/d")
}
