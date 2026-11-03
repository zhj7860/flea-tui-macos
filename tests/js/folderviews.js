.import "../../ui/js/FolderViews.js" as FolderViews
.import "../../ui/js/Settings.js" as Settings
.import "../../ui/js/Focus.js" as Focus
.import "../../ui/js/Nav.js" as Nav
.import "../../ui/js/Swap.js" as Swap
.import "../../ui/js/Tabs.js" as Tabs
.import "sourcefixture.js" as Source
.import "tabsfixture.js" as Fixture
.import "nav.js" as NavFixture

// A pane drawing folder /a in its own view, with ui/js/Swap.js deciding the hold as ui/PaneSwap.qml does; viewOf is each folder's own view.
function drawing(viewOf) {
    var pane = NavFixture.browsing(["/home/gm"])
    var phase = Swap.idle()
    var rowsView = viewOf["/a"]
    pane.path = "/a"
    pane.viewMode = rowsView
    pane.rows = [{ n: "one" }, { n: "two" }]
    pane.searchMode = ""
    pane.restoreView = function (path) { pane.sent.push("view " + path); if (viewOf[path]) pane.viewMode = viewOf[path] }
    pane.swap = { stopWaiting: function () {}, hold: function (ask) { phase = Swap.begin(phase, pane.listingState, pane.searchMode, ask, 0); return phase.holding } }
    var screen = { pane: pane, frames: [] }
    // One drawn frame: the rows on show and the view they are drawn in. A wrong-view frame draws rows in a view they were not listed in.
    screen.frame = function () {
        screen.frames.push({ rows: pane.rows.length, view: pane.viewMode, wrong: pane.rows.length > 0 && rowsView !== pane.viewMode })
    }
    // The rows land in one turn in the view of the folder they belong to, as ui/PaneSwap.qml land() does.
    screen.land = function (path, rows) {
        if (phase.holding) Nav.forget(pane)
        pane.rows = rows
        rowsView = pane.viewMode
        pane.path = path
        pane.listInFlight = false
        pane.listingState = "ready"
        screen.frame()
    }
    return screen
}

function wrongFrames(screen) { return screen.frames.filter(function (f) { return f.wrong }).length }

function hops(check) {
    var crossing = drawing({ "/a": "grid", "/b": "list" })
    Nav.open(crossing.pane, "/b")
    crossing.frame()
    check("a hop into a folder with another view asks that view, then lists", crossing.pane.sent.join("|"), "view /b|list /b|fsinfo")
    check("and holds none of the left folder's rows while the new view stands", crossing.frames[0].rows + "|" + crossing.frames[0].view, "0|list")
    crossing.land("/b", [{ n: "three" }])
    check("so no frame draws the left folder's rows in the new view", wrongFrames(crossing), 0)
    check("and the rows that land draw in the new folder's view", crossing.frames[1].rows + "|" + crossing.frames[1].view, "1|list")
    var staying = drawing({ "/a": "grid", "/b": "grid" })
    Nav.open(staying.pane, "/b")
    staying.frame()
    check("a hop into a folder in the same view still holds the left folder's rows until the new ones land", staying.frames[0].rows + "|" + staying.frames[0].view, "2|grid")
    staying.land("/b", [{ n: "three" }])
    check("and draws no wrong-view frame either", wrongFrames(staying), 0)
    var blocked = drawing({ "/a": "grid", "/b": "list" })
    blocked.pane.listInFlight = true
    Nav.open(blocked.pane, "/b")
    blocked.frame()
    check("a hop that takes the place of a listing out into another view draws none of the origin folder's rows in it",
          blocked.pane.path + "|" + blocked.pane.viewMode + "|" + blocked.pane.rows.length + "|" + wrongFrames(blocked), "/b|list|0|0")
}

function run(check) {
    hops(check)
    check("the browser modes are List, Columns and Grid", FolderViews.MODES.join(","), "list,columns,grid")
    check("a missing map has no folder view", FolderViews.get(null, "/a"), "")
    var one = FolderViews.set({}, "/home/gm", "grid")
    check("a folder records its Grid choice", FolderViews.get(one, "/home/gm"), "grid")
    check("and another folder remains unset", FolderViews.has(one, "/home/gm/Downloads"), false)
    var both = FolderViews.set(one, "/home/gm/Downloads", "list")
    check("two folders retain independent choices", FolderViews.get(both, "/home/gm"), "grid")
    check("and Downloads has its own List choice", FolderViews.get(both, "/home/gm/Downloads"), "list")
    check("a saved folder wins only while the setting is on", FolderViews.viewFor(both, "/home/gm", "columns", true), "grid")
    check("otherwise the global fallback stays in effect", FolderViews.viewFor(both, "/home/gm", "columns", false), "columns")
    check("an unvisited folder uses the global fallback", FolderViews.viewFor(both, "/home/gm/Pictures", "columns", true), "columns")
    check("a malformed mode falls back safely", FolderViews.viewFor({"/a": "dual"}, "/a", "list", true), "list")
    check("the dual-pane window layout is never a folder view", FolderViews.MODES.indexOf("dual"), -1)
    check("remembering needs both the setting and a path", FolderViews.shouldRemember(true, "/a"), true)
    check("and an empty path cannot create an entry", FolderViews.shouldRemember(true, ""), false)
    check("and disabling the setting prevents a write", FolderViews.shouldRemember(false, "/a"), false)
    var full = {}
    for (var i = 0; i < FolderViews.MAX; i++)
        full = FolderViews.set(full, "/d" + i, "list")
    var over = FolderViews.set(full, "/new", "columns")
    check("the map is capped", Object.keys(over).length, FolderViews.MAX)
    check("and evicts its oldest entry", FolderViews.has(over, "/d0"), false)
    check("while retaining its newest entry", FolderViews.get(over, "/new"), "columns")
    var rows = Settings.rows("view", { data: {} })
    var ids = rows.map(function (row) { return row.id })
    var remember = rows[ids.indexOf("rememberViewPerFolder")] || {}
    var sorted = rows[ids.indexOf("rememberSort")] || {}
    check("Settings exposes the per-folder view switch", remember.label, "Remember each folder's view")
    check("and it ships off for backwards compatibility", remember.on, false)
    check("and it sits right after the last-used view", ids.indexOf("rememberViewPerFolder") - ids.indexOf("view"), 1)
    check("and it is the sort switch's shape: a check, one glyph, no caption",
          [remember.kind, typeof remember.glyph, remember.caption].join("|"), [sorted.kind, typeof sorted.glyph, sorted.caption].join("|"))
    // The Pane's own functions are QML, so tests/folderviews-flow.qml drives them on a real Pane; these are the routes into it that plain JS can drive.
    var tabbed = Fixture.pane("/home/gm")
    var adopted = []
    tabbed.adoptView = function (path, mode) { adopted.push(path + "|" + mode); tabbed.viewMode = "columns" }
    Tabs.openNew(tabbed)
    tabbed.viewMode = "grid"
    tabbed.path = "/home/gm/Work"
    Tabs.selectAt(tabbed, 0)
    check("a tab restore hands its folder and view to the pane to decide", adopted.join(","), "/home/gm|list")
    check("and clears at once when the view the pane decided is not the one on screen", tabbed.clearedAtOnce, true)
    var kept = Fixture.pane("/home/gm")
    kept.adoptView = function (path, mode) { kept.viewMode = mode }
    Tabs.openNew(kept)
    kept.path = "/home/gm/Work"
    Tabs.selectAt(kept, 0)
    check("and holds the rows on screen when it is", kept.clearedAtOnce, false)
    var keyed = { calls: [], chooseView: function (mode) { keyed.calls.push(mode) } }
    var keys = ["viewList", "viewColumns", "viewGrid"]
    keys.forEach(function (action) { Focus.act(action, keyed) })
    check("the three view keys choose through the pane's one route", keyed.calls.join(","), "list,columns,grid")
    // The rest read source text: no suite builds the Trash host, the window or the picker outside the app, so no behaviour can be driven.
    var folder = Source.slice(Source.source("ui/Pane.qml"), "readonly property string viewFolder", "// Dual draws lists")
    check("a folder's view is kept for no Trash standing over it", folder.indexOf("!trashHost.opened") >= 0, true)
    var winbody = Source.source("ui/WindowBody.qml")
    var chrome = Source.slice(winbody, "onViewChosen:", "// The path bar's four.")
    check("the chrome's view buttons send every choice to the primary pane, which the keys reach too", chrome.indexOf("primaryPane.chooseView(mode)") >= 0 && chrome.indexOf("changeKey") < 0, true)
    check("and the secondary pane's view choice takes the chrome's own route", winbody.indexOf("onViewRequested: function (mode) { chrome.viewChosen(mode) }") >= 0, true)
    var picker = ["ui/PickerWindow.qml", "ui/PickerChrome.qml", "ui/PickerList.qml", "ui/PickerGrid.qml"].map(Source.source).join("")
    check("the picker keeps its own view and never touches the folder map or its switch",
          picker.indexOf("folderViews") < 0 && picker.indexOf("rememberViewPerFolder") < 0 && picker.indexOf("FolderViews") < 0, true)
}
