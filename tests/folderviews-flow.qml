//@ pragma ShellId flea-folderviews-flow-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/FolderViews.js" as FolderViews
import "flea/js/RecentMode.js" as RecentMode
import "flea/js/Search.js" as Search
import "flea/js/Tabs.js" as Tabs

// A real Pane over the real backend: which view each folder draws as the window navigates, switches tabs and enters or leaves Dual, with Remember each folder's view on and off.
ShellRoot {
    id: root

    readonly property string fixture: Quickshell.env("FOLDERVIEWS_DIR")
    readonly property int tickMs: 20
    readonly property int giveUpMs: 10000
    readonly property string a: root.fixture + "/a"
    readonly property string b: root.fixture + "/b"
    readonly property string c: root.fixture + "/c"
    readonly property string gone: root.fixture + "/gone"
    property var steps: []
    property int at: 0
    property var awaiting: null
    property int settle: 0
    property double stamp: Date.now()
    property int checks: 0
    property int failures: 0
    property string phase: ""
    property var pane: null
    property var secondHost: null
    property bool ticking: false
    property string held: ""
    property string heldB: ""
    property var sampled: null

    function check(label, actual, expected) {
        root.checks += 1
        var ok = JSON.stringify(actual) === JSON.stringify(expected)
        if (!ok) root.failures += 1
        console.log("FOLDERVIEWS " + (ok ? "PASS " : "FAIL ") + root.phase + ": " + label + " got=" + JSON.stringify(actual) + " expected=" + JSON.stringify(expected))
    }
    function finish() {
        console.log("FOLDERVIEWS DONE checks=" + root.checks + " failed=" + root.failures)
        Qt.exit(root.failures > 0 ? 1 : 0)
    }

    FloatingWindow {
        id: win
        implicitWidth: 1000
        implicitHeight: 700
        color: Flea.Theme.color.background
    }
    Flea.Backend { id: realBackend }
    Component {
        id: paneComponent
        Flea.Pane {
            width: 1000
            height: 700
            backend: realBackend
            // ui/WindowBody.qml binds the primary pane to the window's layout the same way.
            dualMode: Flea.ViewState.state.view === "dual"
        }
    }

    Component {
        id: secondComponent
        Item {
            width: 1000
            height: 700
            readonly property alias pane: other
            Flea.Backend { id: otherBackend; preserveSort: true }
            // ui/WindowBody.qml builds the secondary pane list-only and in Dual for good.
            Flea.Pane { id: other; anchors.fill: parent; backend: otherBackend; dualMode: true; listOnly: true }
            // The window's route for a view the secondary pane is asked for: ChromeBar.viewChosen, which lands on the primary pane (folderviews-flow.sh pins both lines).
            Connections { target: other; function onViewRequested(mode) { root.pane.chooseView(mode) } }
        }
    }

    function landed(path) { return !root.pane.listInFlight && root.pane.path === path && root.pane.total > 0 && root.pane.searchMode.length === 0 }
    function stored() { return Flea.ViewState.folderViews }
    function standing() { return Flea.ViewState.state.view }
    function unchanged() { return JSON.stringify(root.stored()) === root.held }

    // One step: run, wait for its landing, let the zero-interval timers fire, then read.
    function step(run, until) { root.steps.push({ run: run, until: until || null }) }
    function see(label, read, expected) { root.step(function () { root.check(label, read(), expected) }) }
    function seeView(label, expected) { root.see(label, function () { return root.pane.viewMode }, expected) }
    function goTo(path) { root.step(function () { root.pane.open(path) }, function () { return root.landed(path) }) }
    // The pane as the request leaves it, before the listing answers: the view it draws and whether rows are still held.
    function sample() { root.sampled = { view: root.pane.viewMode, held: root.pane.rows.length > 0 } }
    function hop(path) { root.step(function () { root.pane.open(path); root.sample() }, function () { return root.landed(path) }) }
    function choose(mode) { root.step(function () { root.pane.chooseView(mode) }) }
    function key(action) { root.step(function () { root.pane.act(action) }) }

    // The same walk under both settings: the standing view is columns, so a folder with no view of its own is told from one holding List.
    function plan(remember) {
        var on = remember
        root.step(function () {
            root.phase = on ? "remember on" : "remember off"
            Flea.ViewState.changeKey("view", "columns")
            Flea.ViewState.changeKey("rememberViewPerFolder", on)
            root.held = JSON.stringify(root.stored())
            root.pane = paneComponent.createObject(win.contentItem)
        })
        root.goTo(root.a)
        root.seeView("a folder with no view of its own opens in the standing view", "columns")
        root.choose("grid")
        root.seeView("Grid chosen in A draws at once", "grid")
        root.see(on ? "A's choice is stored" : "off, A's choice is not stored", function () { return on ? root.stored()[root.a] : root.unchanged() }, on ? "grid" : true)
        root.goTo(root.b)
        root.seeView(on ? "B has no view of its own and takes the standing one" : "off, the Grid chosen in A is the standing view", on ? "columns" : "grid")
        root.choose("list")
        root.seeView("List chosen in B draws at once", "list")
        root.hop(root.a)
        root.seeView(on ? "A reopens in Grid" : "off, A draws the standing List", on ? "grid" : "list")
        root.see(on ? "a hop from B's List into A's Grid holds none of B's rows in Grid" : "off, a hop between folders in one view holds the left folder's rows",
                 function () { return root.sampled }, on ? { view: "grid", held: false } : { view: "list", held: true })
        root.goTo(root.b)
        root.seeView(on ? "B reopens in List" : "off, B draws the standing List", "list")
        root.step(function () { root.pane.goBack() }, function () { return root.landed(root.a) })
        root.seeView(on ? "Back restores A's Grid" : "off, Back draws the standing List", on ? "grid" : "list")
        root.step(function () { root.pane.goForward() }, function () { return root.landed(root.b) })
        root.seeView(on ? "Forward restores B's List" : "off, Forward draws the standing List", "list")
        root.goTo(root.c)
        root.seeView(on ? "C has no view of its own, so the standing Columns" : "off, C draws the standing List", on ? "columns" : "list")
        root.step(function () { root.pane.openParent(); root.sample() }, function () { return root.landed(root.fixture) })
        root.seeView(on ? "the parent has no view of its own, so the standing Columns" : "off, the parent draws the standing List", on ? "columns" : "list")
        root.see("a hop between two folders in one view holds the left folder's rows", function () { return root.sampled }, { view: on ? "columns" : "list", held: true })
        // Two tabs: one on A holding Grid, one on B holding List.
        root.goTo(root.a)
        root.choose("grid")
        root.step(function () { Tabs.openNew(root.pane, root.b) }, function () { return root.landed(root.b) })
        root.seeView(on ? "a new tab opened on B draws B's List" : "off, a new tab draws the standing Grid", on ? "list" : "grid")
        root.choose("list")
        root.step(function () { Tabs.selectAt(root.pane, 0) }, function () { return root.landed(root.a) })
        root.seeView("switching back to the tab on A draws its Grid", "grid")
        root.see(on ? "a tab switch leaves the standing view alone" : "off, a tab switch makes its view the standing one", root.standing, on ? "columns" : "grid")
        root.step(function () { Tabs.selectAt(root.pane, 1) }, function () { return root.landed(root.b) })
        root.seeView("switching to the tab on B draws its List", "list")
        root.see(on ? "and still leaves the standing view alone" : "off, the standing view follows the tab", root.standing, on ? "columns" : "list")
        root.step(function () { Tabs.selectAt(root.pane, 0) }, function () { return root.landed(root.a) })
        // Two tabs on one folder: the second changes its view, and the first brings back the folder's view as it stands now.
        root.step(function () { Tabs.selectAt(root.pane, 1) }, function () { return root.landed(root.b) })
        root.goTo(root.a)
        root.choose("list")
        root.step(function () { Tabs.selectAt(root.pane, 0) })
        root.seeView(on ? "the first tab on A draws A's view as the second tab left it" : "off, the first tab on A draws the view it held", on ? "list" : "grid")
        root.choose("grid")
        // The keys and the chrome's buttons both land in chooseView, so a key is the same choice.
        root.key("viewColumns")
        root.seeView("the Columns key draws Columns", "columns")
        root.key("viewGrid")
        root.seeView("the Grid key draws Grid", "grid")
        root.see(on ? "the keys stored A's view" : "off, the keys wrote nothing to folderViews", function () { return on ? root.stored()[root.a] : root.unchanged() }, on ? "grid" : true)
        // Dual is a window layout: both panes draw the list, and a view choice leaves it and shows on the primary pane.
        root.step(function () { Flea.ViewState.changeKey("view", "dual") })
        root.seeView("Dual draws the list in the primary pane", "list")
        root.see("Dual is on for the pane", function () { return root.pane.dualMode }, true)
        root.key("viewList")
        root.see("a view key in Dual leaves Dual", function () { return root.pane.dualMode }, false)
        root.seeView("and the primary pane draws the chosen List", "list")
        root.see("and it is the standing view", root.standing, "list")
        root.see(on ? "and A remembers it" : "off, nothing is written to folderViews", function () { return on ? root.stored()[root.a] : root.unchanged() }, on ? "list" : true)
        root.step(function () { Flea.ViewState.changeKey("view", "dual") })
        root.choose("columns")
        root.see("a view button in Dual leaves Dual as the key does", function () { return root.pane.dualMode }, false)
        root.see("and the button's view is the standing one", root.standing, "columns")
        root.seeView("and the primary pane draws it", "columns")
        root.see(on ? "and A remembers it" : "off, nothing is written to folderViews", function () { return on ? root.stored()[root.a] : root.unchanged() }, on ? "columns" : true)
        // A view key on the secondary pane's focus takes the window's route: Dual ends and the primary pane draws it.
        root.choose("columns")
        root.see(on ? "A starts remembered as Columns" : "off, the standing view starts as Columns", function () { return on ? root.stored()[root.a] : root.standing() }, "columns")
        root.step(function () {
            Flea.ViewState.changeKey("view", "dual")
            root.secondHost = secondComponent.createObject(win.contentItem)
            root.secondHost.pane.open(root.b)
        }, function () { return !root.secondHost.pane.listInFlight && root.secondHost.pane.path === root.b && root.secondHost.pane.total > 0 })
        root.step(function () { root.heldB = JSON.stringify(root.stored()[root.b]) })
        root.step(function () { root.secondHost.pane.act("viewGrid") })
        root.see("the Grid key on the secondary pane leaves Dual", function () { return root.pane.dualMode }, false)
        root.seeView("and the primary pane draws Grid", "grid")
        root.see("and it is the standing view", root.standing, "grid")
        root.see(on ? "and A remembers Grid" : "off, nothing is written to folderViews", function () { return on ? root.stored()[root.a] : root.unchanged() }, on ? "grid" : true)
        root.see(on ? "and the secondary pane's folder is unchanged" : "off, the secondary pane's folder stores nothing", function () { return on ? JSON.stringify(root.stored()[root.b]) === root.heldB : root.unchanged() }, true)
        // Entering Dual again, the Columns key on the secondary pane does the same.
        root.step(function () { Flea.ViewState.changeKey("view", "dual") })
        root.step(function () { root.secondHost.pane.act("viewColumns") })
        root.see("the Columns key on the secondary pane leaves Dual", function () { return root.pane.dualMode }, false)
        root.seeView("and the primary pane draws Columns", "columns")
        root.see(on ? "and A remembers Columns, B stays as it was" : "off, nothing is written to folderViews",
                 function () { return on ? [root.stored()[root.a], JSON.stringify(root.stored()[root.b]) === root.heldB] : root.unchanged() }, on ? ["columns", true] : true)
        root.step(function () { Flea.ViewState.changeKey("view", "columns") })
        root.choose("columns")
        root.see("the standing view is Columns again", root.standing, "columns")
        // A search stands over its folder, and a history over the root: neither is a folder to remember a view for.
        root.step(function () { root.pane.forceActiveFocus(); Search.start(root.pane) }, function () { return root.pane.searchMode === "typing" })
        root.seeView("a search draws the standing view", "columns")
        root.choose("list")
        root.see("a view chosen in a search stores no view for its folder", function () { return on ? root.stored()[root.a] : root.unchanged() }, on ? "columns" : true)
        root.seeView("and it draws", "list")
        root.see("and it is the standing view", root.standing, "list")
        root.step(function () { Search.abort(root.pane) }, function () { return root.pane.searchMode.length === 0 && root.landed(root.a) })
        root.seeView(on ? "leaving the search draws the folder's own view" : "off, leaving the search draws the standing List", on ? "columns" : "list")
        root.step(function () { RecentMode.run(root.pane, [root.a, root.b], {}) }, function () { return root.pane.recentMode.length > 0 && !root.pane.listInFlight })
        root.choose("columns")
        root.see("a view chosen in Recent stores no view for the root", function () { return root.stored()["/"] === undefined }, true)
        root.seeView("and it draws", "columns")
        root.step(function () { RecentMode.close(root.pane) }, function () { return root.pane.recentMode.length === 0 && root.landed(root.a) })
        root.seeView(on ? "leaving Recent draws the folder's own view" : "off, leaving Recent draws the standing Columns", "columns")
        root.see(on ? "the map holds only the folders chosen in" : "off, nothing is written to folderViews",
                 function () { return on ? Object.keys(root.stored()).sort() : JSON.stringify(root.stored()) === root.held }, on ? [root.a, root.b] : true)
        // The setting is read live: the open folder takes the view the new setting gives it, as the sort setting re-applies the open folder's sort.
        if (on) {
            root.step(function () { Flea.ViewState.changeKey("view", "grid") })
            root.seeView("the standing view changing leaves the open folder's own Columns", "columns")
            root.step(function () { Flea.ViewState.changeKey("rememberViewPerFolder", false) })
            root.seeView("switching the setting off draws the open folder in the standing Grid", "grid")
            root.step(function () { Flea.ViewState.changeKey("rememberViewPerFolder", true) })
            root.seeView("and switching it on again draws the open folder's own Columns", "columns")
            root.step(function () { Flea.ViewState.changeKey("view", "columns") })
        }
        // A listing that fails leaves the pane on its folder and in that folder's own view, whatever view the folder asked for held.
        root.step(function () {
            var leaf = {}
            leaf[root.gone] = "grid"
            Flea.ViewState.changeMapEntries("folderViews", leaf, FolderViews.set(root.stored(), root.gone, "grid"))
            root.pane.open(root.gone)
            root.sample()
        }, function () { return !root.pane.listInFlight })
        root.see(on ? "the hop itself drew the refused folder's Grid and none of A's rows" : "off, the hop drew the standing Columns over A's held rows",
                 function () { return root.sampled }, on ? { view: "grid", held: false } : { view: "columns", held: true })
        root.seeView("a refused hop leaves the origin folder's view", "columns")
        root.see("and the pane on the origin folder", function () { return root.pane.path }, root.a)
        root.step(function () { root.secondHost.destroy(); root.secondHost = null; root.pane.destroy(); root.pane = null })
    }

    Timer {
        interval: root.tickMs
        running: true
        repeat: true
        onTriggered: {
            if (root.ticking) return
            root.ticking = true
            try { root.tick() } finally { root.ticking = false }
        }
    }

    function tick() {
        if (Date.now() - root.stamp > root.giveUpMs) {
            root.check("probe completes", "timeout at step " + root.at, "complete")
            root.finish()
            return
        }
        if (root.awaiting !== null && !root.awaiting()) return
        root.awaiting = null
        if (root.settle > 0) {
            root.settle -= 1
            return
        }
        if (root.at >= root.steps.length) {
            root.finish()
            return
        }
        root.stamp = Date.now()
        var s = root.steps[root.at]
        root.at += 1
        s.run()
        root.awaiting = s.until
        root.settle = 3
    }

    Component.onCompleted: {
        root.plan(true)
        root.plan(false)
    }
}
