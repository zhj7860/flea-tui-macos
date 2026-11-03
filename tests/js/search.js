.import "../../ui/js/Search.js" as Search
.import "../../ui/js/Drag.js" as Drag
.import "../../ui/js/RecentMode.js" as RecentMode
.import "sourcefixture.js" as Source

function run(check) {
    // The strip's right edge while a session walks: the count alone, then the count with its time.
    // Only these shapes reach the strip; an empty query shows no count over the folder rows.
    check("a walking session pairs the count with its crawl", Search.note(9, true, false), "9 found \u00b7 still scanning")
    check("and a landed one is the count alone", Search.note(9, false, false), "9 found")
    check("and a four-figure find groups", Search.note(1204, true, false), "1,204 found \u00b7 still scanning")
    check("the empty caption keeps a query's own $ signs as typed",
        Search.nothingMatches("a$&b$$c$'"), "Nothing matches a$&b$$c$'")
    check("and before any answer names a query it draws no caption", Search.nothingMatches(""), "")
    check("and nothing found still says so", Search.note(0, false, false), "0 found")
    check("and an empty query shows no count at all", Search.note(12, true, true), "")
    check("even once its folder rows land", Search.note(12, false, true), "")

    // V7: the SearchFilter board's own status cell, the count beside the state that changes it.
    check("a running walk pairs what it found with what it scanned",
          Search.statusLine(true, 12, 4120, 300), "12 found · Searching, 4,120 scanned")
    check("a finished walk reports what it found and how long it took",
          Search.statusLine(false, 1, 18204, 412), "1 found in 0.4 s")
    check("and nothing found still says so", Search.statusLine(false, 0, 18204, 412), "0 found in 0.4 s")


    check("the home prefix reads as a tilde", Search.scope("/home/gm/Work/claude/flea", "/home/gm"), "~/Work/claude/flea")
    check("home itself is the bare tilde", Search.scope("/home/gm", "/home/gm"), "~")
    check("a path outside home keeps its own form", Search.scope("/usr/share", "/home/gm"), "/usr/share")

    // The scope rule: the backend walks whatever path this picks, so this is the whole of
    // "universal search across the home folder" and the only place the policy lives.
    check("a search anywhere under home walks the whole home directory",
          Search.scopeRoot("/home/u/Downloads/deep", "/home/u"), "/home/u")
    check("home itself is already the scope", Search.scopeRoot("/home/u", "/home/u"), "/home/u")
    check("a mount outside home searches the mount, never home instead",
          Search.scopeRoot("/run/media/u/NAS/photos", "/home/u"), "/run/media/u/NAS/photos")
    check("a sibling whose name merely starts with home's is outside it",
          Search.scopeRoot("/home/under", "/home/u"), "/home/under")
    check("with no home in the environment the pane searches where it stands",
          Search.scopeRoot("/d", ""), "/d")

    // The strip's own right edge, which the board draws as the pair esc really is from here.
    check("the strip says esc stops the walk and keeps the results", Search.wayOut(true, false), "esc cancels, then returns")
    check("and landed, empty or stopped it only leaves", Search.wayOut(false, false) + "|" + Search.wayOut(true, true) + "|" + Search.wayOut(false, true), "esc returns|esc returns|esc returns")


    // The pointer's own contract: a double click on a result reveals it, and opens a row anywhere
    // else. ui/js/Tap.js asks this rather than deciding it, so the rule lives beside the reveal.
    check("a double click on a search result takes the operator to the file",
          Search.activateAction({ searchMode: "results", searchQuery: "no" }), "reveal")
    check("a double click on an ordinary row still opens it",
          Search.activateAction({ searchMode: "" }), "open")
    check("a double click while the query line is still up opens the row under it",
          Search.activateAction({ searchMode: "typing" }), "open")
    check("unless the line already stands on a query",
          Search.activateAction({ searchMode: "typing", searchQuery: "no" }), "reveal")

    // A walk with no matches yet is still working, so the area keeps the crawl rather than flashing empty.
    check("matches make the listing ready", Search.listingState({ searchRunning: true }, 3), "ready")
    check("a running walk with nothing yet is still loading", Search.listingState({ searchRunning: true }, 0), "loading")
    check("a stopped walk with nothing is empty", Search.listingState({ searchRunning: false }, 0), "empty")

    // The live session: opening starts the scope's walk at once, every keystroke sends its
    // query with a rising generation, and answers for an older generation are ignored.
    // Only the members start, typed and backspace touch are stubbed; sent records the wire.
    function typing(query) {
        var sent = []
        var p = {
            searchMode: "typing", searchQuery: query, searchRunning: false, searchScanned: 0,
            searchCancelled: false, searchMs: 0, searchGen: 0, path: "/d",
            recentMode: "", recentFrom: "", recentPaths: [],
            showHidden: false, total: 2, held: 0, kindNames: [], cursorIndex: 1,
            rows: [{ n: "b.txt" }, { n: "todo.txt" }],
            listingState: "ready", opened: 0, sent: sent, windowSize: 200, shownTotal: 9,
            home: "", searchFrom: "", searchBase: "", relisted: "", searchHere: false,
            clearSelection: function () {},
            setCursor: function (index) { p.cursorIndex = Math.max(0, Math.min(p.shownTotal - 1, index)) },
            rowFor: function (index) { return p.rows[index - p.held] || null },
            join: function (base, name) { return base === "/" ? "/" + name : base + "/" + name },
            pendingSelect: "",
            listArea: { restartSettle: function () {} },
            open: function (path) { p.opened += 1 },
            openWithoutHistory: function (path) { p.relisted = path },
            // Mirrors ui/Pane.qml restoreRecentSort, so a walk from Recent restores through it.
            restoreRecentSort: function () { RecentMode.restoreSort(p) },
            backend: { searchOpen: function (scope, folder, hidden) { sent.push("open " + scope + "|" + folder) },
                        searchQuery: function (query, gen, count) { sent.push("query " + gen + ":" + query + "/" + count) },
                        searchClose: function () { sent.push("close") } }
        }
        return p
    }
    function press(code, text) { return { key: code, text: text, modifiers: Qt.NoModifier } }
    var opener = typing("")
    opener.searchMode = ""
    Search.start(opener)
    check("opening the strip starts the scope walk at once, with no rows touched",
          opener.searchMode + "|" + opener.sent.join(","), "typing|open /d|/d")
    check("and remembers the folder and arms the cursor file for the way back",
          opener.searchFrom + "|" + opener.pendingSelect, "/d|/d/todo.txt")
    var again = typing("")
    again.searchMode = "typing"
    Search.start(again)
    check("opening twice starts one session", again.sent.length, 0)
    var fromRecent = typing("")
    fromRecent.searchMode = ""
    fromRecent.recentMode = "results"
    fromRecent.recentFrom = "/d/sub"
    fromRecent.path = "/"
    Search.start(fromRecent)
    check("f from Recent leaves first, so the scope is the real folder, and asks that folder's rows at once",
          fromRecent.recentMode + "|" + fromRecent.path + "|" + fromRecent.sent.join(","),
          "|/d/sub|open /d/sub|/d/sub,query 1:/200")
    check("and the cursor file is named from Recent's own base", fromRecent.pendingSelect, "/todo.txt")
    check("and the history rows still drawn keep their own base until the folder's answer replaces them",
          Search.baseOf(fromRecent), "/")
    Search.typeKey(press(Qt.Key_Escape, ""), fromRecent)
    check("so Esc with nothing typed re-lists the folder over Recent's rows",
          fromRecent.searchMode + "|" + fromRecent.relisted, "|/d/sub")
    var delLine = typing("")
    Search.typeKey({ key: Qt.Key_Delete, text: "\u007f", modifiers: Qt.NoModifier }, delLine)
    check("DEL types nothing into search", delLine.searchQuery + "|" + delLine.sent.length, "|0")
    Search.typeKey(press(Qt.Key_E, "e"), delLine)
    check("a letter sends its query with the first generation",
          delLine.searchQuery + "|" + delLine.sent.join(","), "e|query 1:e/200")
    var line = typing("scr")
    Search.typeKey(press(Qt.Key_E, "e"), line)
    check("a printable key extends the query and sends the next generation",
          line.searchQuery + "|" + line.sent.join(","), "scre|query 1:scre/200")
    Search.typeKey(press(Qt.Key_E, "e"), line)
    check("and generations rise one per keystroke", line.sent.join(","), "query 1:scre/200,query 2:scree/200")
    check("and each send leaves the cursor standing for the landing to keep", line.cursorIndex, 1)
    Search.typeKey(press(Qt.Key_Backspace, ""), line)
    check("backspace shrinks the query and re-sends it",
          line.searchQuery + "|" + line.sent.pop(), "scre|query 3:scre/200")
    Search.typeKey(press(Qt.Key_Backspace, ""), line)
    Search.typeKey(press(Qt.Key_Backspace, ""), line)
    Search.typeKey(press(Qt.Key_Backspace, ""), line)
    Search.typeKey(press(Qt.Key_Backspace, ""), line)
    check("backspace to empty sends the empty query and the folder rows come back, strip open",
          line.searchQuery + "|" + line.sent.pop() + "|" + line.searchMode, "|query 7:/200|typing")
    Search.typeKey(press(Qt.Key_Backspace, ""), line)
    check("backspace past empty sends nothing more", line.searchQuery + "|" + line.sent.length, "|5")
    var keyed = typing("scr")
    keyed.searchGen = 2
    keyed.total = 11
    Search.searched(keyed, 7, 400, 33.1, false, 1, true)
    check("an answer for an older generation is ignored", keyed.total + "|" + keyed.searchRunning, "11|false")
    Search.searched(keyed, 4, 400, 33.1, false, 2, true)
    check("and one for the newest sent generation replaces the counts while walking",
          keyed.total + "|" + keyed.searchRunning, "4|true")
    Search.searched(keyed, 4, 400, 33.1, false, 2, false)
    check("and its landing ends the walk", keyed.searchRunning, false)
    var reopened = typing("scr")
    reopened.searchGen = 1
    reopened.total = 11
    Search.closeSession(reopened)
    Search.start(reopened)
    Search.searched(reopened, 7, 400, 33.1, false, 1, true)
    check("a late answer at the closed session's newest gen drops before the next session sends",
          reopened.total + "|" + reopened.searchRunning, "11|true")
    Search.typeKey(press(Qt.Key_S, "s"), reopened)
    Search.searched(reopened, 7, 400, 33.1, false, 1, true)
    check("a late answer from a closed session never lands on the next session's first query",
          reopened.total + "|" + reopened.sent.pop(), "11|query 2:s/200")
    var idle = typing("scr")
    idle.searchGen = 3
    Search.closeSession(idle)
    Search.start(idle)
    Search.typeKey(press(Qt.Key_Escape, ""), idle)
    check("escape before the next session sends anything closes it with no re-list",
          idle.searchMode + "|" + idle.relisted, "|")
    var kept = typing("scr")
    kept.searchGen = 1
    Search.typeKey(press(Qt.Key_Return, ""), kept)
    check("enter keeps the results and moves the keys to them, sending nothing",
          kept.searchMode + "|" + kept.sent.length, "results|0")
    var abandoned = typing("scr")
    abandoned.searchGen = 3
    Search.typeKey(press(Qt.Key_Escape, ""), abandoned)
    check("escape closes the backend and re-lists the folder it came from",
          abandoned.searchMode + "|" + abandoned.sent.join(",") + "|" + abandoned.relisted, "typing|close|/d")
    var untouched = typing("")
    untouched.searchMode = ""
    untouched.total = 0
    Search.start(untouched)
    Search.typeKey(press(Qt.Key_Escape, ""), untouched)
    check("leaving recomputes the listing state with nothing to wait on",
          untouched.listingState, "empty")
    check("escape with nothing sent closes the session and lists nothing again",
          untouched.sent.join(",") + "|" + untouched.relisted, "open /d|/d,close|")
    var underHome = typing("scr")
    underHome.home = "/home/u"
    underHome.path = "/home/u/Downloads"
    underHome.searchMode = ""
    Search.start(underHome)
    check("the session opens on the home scope and remembers the folder, never taking it as base",
          underHome.sent.join(",") + "|" + underHome.path + "|" + underHome.searchFrom,
          "open /home/u|/home/u/Downloads|/home/u/Downloads|/home/u/Downloads")

    // Issue 30: the scope is chosen on the query line itself rather than in the settings, because it
    // belongs to this search and not to the application; the strip's own "in <scope>" is the readout,
    // and nothing is persisted, which is the whole reason this needs no settings row.
    check("with the scope set to here the walk stays in the pane's own directory",
          Search.scopeRoot("/home/u/Downloads/deep", "/home/u", true), "/home/u/Downloads/deep")
    check("and with it off the walk is still the whole home directory",
          Search.scopeRoot("/home/u/Downloads/deep", "/home/u", false), "/home/u")
    var here = typing("scr")
    here.home = "/home/u"
    here.path = "/home/u/Downloads"
    here.searchGen = 1
    Search.typeKey(press(Qt.Key_Tab, "\t"), here)
    check("tab on the query line points the walk at the directory the pane is in", here.searchHere, true)
    check("re-opens the new scope and re-sends the standing query",
          here.sent.join(","), "open /home/u/Downloads|/home/u/Downloads,query 2:scr/200")
    Search.typeKey(press(Qt.Key_Backtab, "\t"), here)
    check("and the key flips back, so home is one press away again", here.searchHere, false)
    var emptyTab = typing("")
    emptyTab.searchGen = 0
    Search.typeKey(press(Qt.Key_Tab, "\t"), emptyTab)
    check("tab with an empty query only re-opens the scope, sending nothing",
          emptyTab.sent.join(",") + "|" + emptyTab.searchQuery, "open /d|/d|")
    var done = typing("kept")
    done.searchMode = "results"
    done.searchGen = 4
    Search.start(done)
    check("f in results reopens the query line with the query kept and no session",
          done.searchMode + "|" + done.searchQuery + "|" + done.sent.length, "typing|kept|0")
    check("each flip re-opens and re-sends", here.sent.pop(), "query 3:scr/200")

    var blank = typing("")
    Search.typeKey(press(Qt.Key_Return, ""), blank)
    check("enter on an empty line closes it and sends nothing",
          blank.searchMode + "|" + blank.sent.join(","), "|close")

    check("a re-answer keeps the cursor's file when the window still names it",
          Search.keptIndex("todo.txt", [{ n: "b.txt" }, { n: "todo.txt" }], 0), 1)
    check("and falls back to row 0 with the window offset", Search.keptIndex("gone.txt", [{ n: "b.txt" }], 5), 5)
    check("and no name keeps the window start", Search.keptIndex(null, [{ n: "b.txt" }], 5), 5)
    var stamped = typing("")
    Search.typeKey(press(Qt.Key_E, "e"), stamped)
    check("a send stamps keyAt and clears the landing stamps",
          stamped.searchKeyAt > 0 && stamped.searchFirstRowsAt === 0 && stamped.searchSettledAt === 0, true)
    Search.searched(stamped, 1, 10, 5.5, false, 1, false)
    check("a landed searched stamps settled", stamped.searchSettledAt >= stamped.searchKeyAt && stamped.searchSettledAt > 0, true)
    var settled = stamped.searchSettledAt
    Search.searched(stamped, 9, 10, 5.5, false, 0, false)
    check("a gen-less line never lands or stamps", stamped.total + "|" + stamped.searchSettledAt, "1|" + settled)
    var armed = typing("")
    armed.searchMode = ""
    Search.start(armed)
    check("opening arms the cursor file for the way back",
          armed.pendingSelect + "|" + armed.searchFrom, "/d/todo.txt|/d")

    // A new session restarts the landed generation with its numbering, so its first answer parks
    // on its best match; re-entering the query line from results keeps the standing one.
    var fresh = typing("")
    fresh.searchMode = ""
    fresh.swap = { landedGen: 7 }
    Search.start(fresh)
    check("a new session restarts the landed generation with its numbering", fresh.swap.landedGen, 0)
    var kept = typing("")
    kept.searchMode = "results"
    kept.swap = { landedGen: 7 }
    Search.start(kept)
    check("re-entering the query line from results keeps the landed generation", kept.swap.landedGen, 7)

    // Session rows join against the listing's base: a home-wide search started in a subfolder names
    // the scope's path for Copy path and the send rows when the menu carries no selection.
    var actionsSrc = Source.source("ui/PaneMenuActions.qml")
    var targetsFn = new Function("root", "Search", "paths",
        Source.block(actionsSrc, "function targets(", "ui/PaneMenuActions.qml"))
    var scopedPane = { path: "/home/u/Downloads/deep", searchBase: "/home/u",
        cursorRow: { n: "docs/notes-old.md" },
        join: function (base, name) { return base + "/" + name } }
    check("a cursor row with no selection joins against the search scope",
          targetsFn({ pane: scopedPane }, Search, null).join(","), "/home/u/docs/notes-old.md")
    var performFn = new Function("root", "Flea", "LocalSendJs", "CopyAs", "Menu", "Ops", "ViewState", "Search",
        "action", "menuId", "paths",
        Source.block(actionsSrc, "function perform(", "ui/PaneMenuActions.qml"))
    var copied = []
    var menuRoot = { pane: { path: "/home/u/Downloads/deep", searchBase: "/home/u",
        cursorRow: { n: "docs/notes-old.md" },
        join: function (base, name) { return base + "/" + name },
        opener: { copyText: function (text) { copied.push(text) } } } }
    menuRoot.targets = function (paths) { return targetsFn(menuRoot, Search, paths) }
    performFn(menuRoot, {}, {}, {}, {}, {}, {}, Search, "copypath", 0, null)
    check("Copy path with no selection copies the scope-joined row",
          copied.join(","), "/home/u/docs/notes-old.md")

    // A session row's drag names the scope its rows join against, so the folder the search began in still takes it.
    var lifted = { path: "/home/u/Downloads", searchBase: "/home/u", backend: { dirDev: 0 },
        rowFor: function (i) { return { n: "Docs/y.txt" } },
        join: function (base, name) { return base + "/" + name } }
    var wire = Drag.mimeFor(lifted, [0], false, false)
    check("a session row's drag names the search scope as its source",
          Drag.markerSource(wire[Drag.ROWS_MIME]), "/home/u")
    check("so dropping it on the folder the search began in is taken",
          Drag.canDropInto(wire[Drag.ROWS_MIME], ["file:///home/u/Docs/y.txt"], "/home/u/Downloads"), true)
    check("and so is a drop on the scope itself, since the row lives one folder down",
          Drag.canDropInto(wire[Drag.ROWS_MIME], ["file:///home/u/Docs/y.txt"], "/home/u"), true)
    check("while the row's own folder still refuses it",
          Drag.canDropInto(wire[Drag.ROWS_MIME], ["file:///home/u/Docs/y.txt"], "/home/u/Docs"), false)
    var history = { path: "/", searchBase: "", backend: { dirDev: 0 },
        rowFor: function (i) { return { n: "home/u/a.txt" } },
        join: function (base, name) { return base === "/" ? "/" + name : base + "/" + name } }
    check("a Recent row dropped on the root, which is not its folder, is taken too",
          Drag.canDropInto(Drag.mimeFor(history, [0], false, false)[Drag.ROWS_MIME], ["file:///home/u/a.txt"], "/"), true)

    // Issue 287: Ctrl+V and Shift+Insert paste the clipboard's first line, one query generation per paste.
    function pastePress(code, mods) { return { key: code, text: "", modifiers: mods } }
    function clipTyping(clip) {
        var r = typing("")
        r.clipboardText = function () { return clip }
        return r
    }
    var clipLine = clipTyping("repo\nsecond line")
    Search.typeKey(pastePress(Qt.Key_V, Qt.ControlModifier), clipLine)
    check("ctrl+v pastes the clipboard's first line into the search", clipLine.searchQuery, "repo")
    check("and the whole paste sends one generation",
          clipLine.sent.join(","), "query 1:repo/200")
    var clipShift = clipTyping("repo\nsecond line")
    Search.typeKey(pastePress(Qt.Key_Insert, Qt.ShiftModifier), clipShift)
    check("shift+insert pastes the same way", clipShift.searchQuery, "repo")
    var clipDirty = clipTyping("a\tb\u0001c")
    Search.typeKey(pastePress(Qt.Key_V, Qt.ControlModifier), clipDirty)
    check("a tab or control character in the clipboard types nothing", clipDirty.searchQuery, "abc")
    var clipBlank = clipTyping("")
    Search.typeKey(pastePress(Qt.Key_V, Qt.ControlModifier), clipBlank)
    check("an empty clipboard sends nothing and leaves the query as it was",
          clipBlank.searchQuery + "|" + clipBlank.sent.length, "|0")
    var clipMissing = clipTyping(undefined)
    Search.typeKey(pastePress(Qt.Key_V, Qt.ControlModifier), clipMissing)
    check("and a clipboard holding no text does too",
          clipMissing.searchQuery + "|" + clipMissing.sent.length, "|0")
}
