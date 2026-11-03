//@ pragma ShellId flea-menu-open-cost-test
import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "flea/js/MenuFit.js" as MenuFit

// tests/menu-settle.sh's open-cost leg: the real pane opens its row menu by the m key and by a click point, and every open reads its rows' widths a few times, never once per row.
ShellRoot {
    id: root
    readonly property var pane: body.currentPane
    readonly property var menu: pane ? pane.contextMenu() : null
    readonly property string fixture: Quickshell.env("FLEA_PATH")
    readonly property string firstPath: Quickshell.env("FLEA_COST_FIRST") === "click" ? "click" : "key"
    readonly property int fixtureRows: 8
    // One early open precedes four alternating opens with the retained ready menu.
    readonly property int opens: 4
    readonly property int pollMs: 20
    readonly property int stageLimitMs: 8000
    // Ticks an open rests so its provider answers land and no frame is pending when the next one starts.
    readonly property int restTicks: 10
    readonly property int keyRow: 0
    readonly property int clickRow: 1
    readonly property real clickInset: 40
    // One read per build, when its rows stand; a read per row built would be about twenty a build.
    readonly property int readsPerBuild: 1
    // Cold construction sizes the empty card and flyout before any rows stand.
    readonly property int initialFitReads: 2
    readonly property string longLabel: "A label long enough that its row wants more than the card's base width, " + "so the fit has to widen the card to hold it whole"

    property string stage: "ready"
    property int sample: 0
    property bool early: true
    property int rest: 0
    property bool finished: false
    property bool executing: false
    property double started: Date.now()
    property string path: "key"
    property bool measuring: false
    property int readsBefore: 0
    property int constructionReads: 0
    property int builds: 0
    property double tPlace: 0
    property double tFrame: 0
    property int checks: 0
    property int failures: 0

    function log(line) { console.log("MENUOPEN " + line) }
    function check(name, ok) {
        checks += 1
        if (ok) return
        failures += 1
        log("FAIL " + name)
    }
    function next(stageName) { stage = stageName; started = Date.now() }
    function finish() {
        finished = true
        log((failures === 0 ? "PASS " : "FAIL ") + checks + " checks")
        log("DONE failures=" + failures)
        body.quitBackends()
    }
    function advance() {
        if (executing || finished) return
        executing = true
        try { runStage() }
        catch (error) { check("harness error " + String(error), false); finish() }
        executing = false
    }
    function runStage() {
        // Hold the normal idle gate while the fixture becomes ready for the early input.
        if (root.early && root.pane) root.pane.inputAt = Date.now()
        var label = (root.early ? "early " : "open " + sample + " ") + path
        var timedOut = Date.now() - started > stageLimitMs
        if (stage === "ready") {
            if (timedOut) { check("fixture listed", false); finish(); return }
            if (pane.listInFlight || pane.path !== fixture || pane.total < fixtureRows || !pane.visibleItemFor(clickRow + 1)) return
            next("rest")
        } else if (stage === "rest") {
            if (!root.early && !pane.menuHost.ready) {
                if (timedOut) { check("menu warmed before first open", false); finish() }
                return
            }
            if (rest++ < restTicks) return
            rest = 0
            path = root.early ? firstPath : (sample % 2 === 0) === (firstPath === "key") ? "key" : "click"
            pane.setCursor(keyRow)
            pane.listArea.forceActiveFocus()
            readsBefore = MenuFit.reads
            builds = 0
            constructionReads = 0
            tFrame = 0
            measuring = true
            if (root.early) {
                check("early " + path + " starts with an untouched Loader", pane.menuHost.status === Loader.Null && pane.menuHost.item === null && !pane.menuHost.ready)
            } else if (sample === 0) {
                check("first " + path + " menu is compiled before input", pane.menuHost.status === Loader.Ready)
                log("PREWARM ready=" + pane.menuHost.status)
            }
            tPlace = Date.now()
            if (path === "key") {
                driver.keyClickChar("m", Qt.NoModifier, -1)
            } else {
                // The pane's own right-click handler, the one a mouse reaches.
                var row = pane.visibleItemFor(clickRow)
                driver.mouseClick(row, clickInset, row.height / 2, Qt.RightButton, Qt.NoModifier, -1)
            }
            next("shown")
        } else if (stage === "shown") {
            if (timedOut) { check(label + " reached a frame", false); finish(); return }
            if (tFrame === 0 || rest++ < restTicks) return
            rest = 0
            measuring = false
            if (root.early) {
                check(label + " reached a frame", tFrame > 0)
                check(label + " sized its initial card and flyout once", constructionReads === initialFitReads)
            }
            var reads = MenuFit.reads - readsBefore
            check(label + " opened", menu.opened)
            // Equal is the target: fewer would mean the fit was not read, or this is not the library the menu imports.
            check(label + " read " + reads + " times for " + builds + " builds", builds >= 1 && reads === readsPerBuild * builds)
            // A flyout reads its rows once when they stand: opened by its row, rebuilt with the card, and moved with its row.
            var flyoutRow = menu.entries.findIndex(function(e) { return e.action === "tags" && e.submenu && e.submenu.length > 1 })
            check(label + " offers a flyout", flyoutRow >= 0)
            if (flyoutRow < 0) { finish(); return }
            var before = MenuFit.reads
            menu.openSubmenu(flyoutRow)
            check(label + " flyout opened by its row read once", menu.submenuOpen && MenuFit.reads - before === readsPerBuild)
            // The refresh path a provider answer takes: the Dropbox row above Tags comes or goes, so the open flyout's row moves.
            before = MenuFit.reads
            menu.dropboxInstalled = !menu.dropboxInstalled
            menu.refreshProviderRows()
            var movedRow = menu.entries.findIndex(function(e) { return e.action === "tags" })
            check(label + " moved flyout and card read once each", movedRow !== flyoutRow && menu.openSubmenuRow === movedRow && MenuFit.reads - before === 2 * readsPerBuild)
            menu.openSubmenuRow = -1
            // A long label widens the card past its base width and past the list it replaces, so a held or stale fit fails here.
            var widthBefore = menu.frameItem.width
            menu.setEntries([{ label: longLabel, action: "open" }, { label: "Short", action: "copy" }])
            check(label + " card widens for a long label", menu.frameItem.width > Math.max(Flea.Theme.menuWidth, widthBefore))
            // Copy as has no row in that list, so c opens it as the lone flyout, which reads its rows once too.
            before = MenuFit.reads
            menu.openSubmenuFor("copyAs")
            check(label + " lone flyout read once", menu.loneFlyoutAction === "copyAs" && MenuFit.reads - before === readsPerBuild)
            log(label + " reads=" + reads + " builds=" + builds + (root.early ? " init_reads=" + constructionReads : "") + " frame_ms=" + (tFrame - tPlace))
            menu.close()
            if (root.early) root.early = false
            else sample += 1
            if (sample >= opens) finish()
            else next("rest")
        }
    }

    Connections {
        target: root.pane ? root.pane.menuHost : null
        function onReadyChanged() {
            if (root.early && root.measuring && root.pane.menuHost.ready) {
                root.constructionReads = MenuFit.reads - root.readsBefore
                root.readsBefore = MenuFit.reads
            }
        }
    }
    Connections {
        target: root.pane ? root.pane.menuHost.item : null
        function onEntriesChanged() { if (root.measuring) root.builds += 1 }
    }
    Connections {
        target: root.menu ? root.menu.Window.window : null
        function onFrameSwapped() { if (root.measuring && root.menu.opened && root.tFrame === 0) root.tFrame = Date.now() }
    }

    FloatingWindow {
        id: window
        implicitWidth: 1000
        implicitHeight: 800
        Flea.WindowBody { id: body; host: window }
        Item { anchors.fill: parent; TestEvent { id: driver } }
    }
    Timer { interval: root.pollMs; repeat: true; running: !root.finished; onTriggered: root.advance() }
}
