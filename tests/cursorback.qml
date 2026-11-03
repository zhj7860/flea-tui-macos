//@ pragma ShellId flea-cursorback-test
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "flea" as Flea

// Back and Forward return the cursor to the row it left in the rows' own turn; tests/cursorback.sh owns the fixture.
ShellRoot {
    id: root
    readonly property string fixture: Quickshell.env("FLEA_PATH")
    readonly property bool dualOnly: Quickshell.env("CURSORBACK_DUAL") === "1"
    readonly property var body: window.body
    property var legPane: null
    property string stage: "ready"
    property string legView: ""
    property string legTarget: ""
    property int legExpected: -1
    property var samples: []
    property int checks: 0
    property int failures: 0
    property bool finished: false
    property bool executing: false
    property double started: Date.now()
    property double stableSince: 0
    property string lastSig: ""
    property int pollMs: 15
    property int stageLimitMs: 12000

    function check(label, actual, expected) {
        checks += 1
        var equal = JSON.stringify(actual) === JSON.stringify(expected)
        if (!equal) failures += 1
        console.log("CURSORBACK " + (equal ? "ok " : "FAIL ") + legView + " " + label + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }
    function pane() { return root.legPane || body.currentPane }
    function cursorName(p) { var r = p.rowFor(p.cursorIndex); return r ? r.n : null }
    // Landed, released, the cursor row drawn, and nothing moving for 400 ms.
    function settled(p, path) {
        if (!p || p.path !== path || p.listInFlight || p.swap.holding) return false
        if (p.listingState !== "ready" && p.listingState !== "empty") return false
        if (p.listingState === "ready" && !p.visibleItemFor(p.cursorIndex)) return false
        return Date.now() - root.stableSince >= 400
    }
    function sig(p) { return p ? [p.path, p.cursorIndex, p.listInFlight, p.listingState, p.total, p.viewMode].join("|") : "" }
    // The drawn proof: the delegate under the cursor is lit as the cursor and sits wholly in the list.
    function drawn(p, name) {
        var item = p.visibleItemFor(p.cursorIndex)
        if (!item || !item.row || item.row.n !== name || item.cursor !== true || !item.visible) return false
        var list = window.itemRect(p.listArea), rect = window.itemRect(item)
        return rect.height > 0 && rect.y >= list.y - 0.5 && rect.y + rect.height <= list.y + list.height + 0.5
    }
    function sample(p) {
        if (p && p.path === root.legTarget) root.samples.push(p.cursorIndex)
    }
    function checkSamples(label, expected) {
        // A same-turn reset through 0 never reaches a 15 ms poll; anything else standing is a frame.
        var bad = root.samples.filter(function (v) { return v !== expected })
        root.check(label + ": the cursor never stood anywhere but the restored row", bad, [])
        root.check(label + ": the restored row is where it settled", root.samples[root.samples.length - 1], expected)
    }
    function restored(label, p, path, name, index) {
        root.check(label + ": the pane is in " + path, p.path, path)
        root.check(label + ": the cursor is on " + name, cursorName(p), name)
        root.check(label + ": at its renumbered index", p.cursorIndex, index)
        root.check(label + ": no restore is left hanging", p.swap.restore, null)
        root.check(label + ": that row draws lit, wholly inside the list", drawn(p, name), true)
        checkSamples(label, index)
    }
    function indexOf(p, name) {
        for (var i = 0; i < p.total; i++) { var r = p.rowFor(i); if (r && r.n === name) return i }
        return -1
    }
    function runShell(args) { shell.command = args; shell.running = true }
    function next(stageName) { stage = stageName; started = Date.now(); stableSince = Date.now(); lastSig = "" }
    function beginLeg(view, target, expected) {
        root.legView = view
        root.legTarget = target
        root.legExpected = expected
        root.samples = []
    }
    function finish() {
        finished = true
        console.log("CURSORBACK DONE checks=" + checks + " failed=" + failures)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
    function advance() {
        if (executing || finished) return
        executing = true
        try { runStage() } catch (error) { check("harness error", String(error), "none"); finish() }
        executing = false
    }
    function track(p, path) {
        var s = sig(p)
        if (s !== lastSig) { lastSig = s; stableSince = Date.now() }
        sample(p)
    }
    function runStage() {
        var timedOut = Date.now() - started > stageLimitMs
        var p = pane()
        if (stage === "ready") {
            if (timedOut) { check("fixture listed", false, true); finish(); return }
            if (root.dualOnly) { next("dualready"); return }
            if (p.listInFlight || p.path !== fixture || p.total < 3 || indexOf(p, "mid") < 0) return
            beginLeg("list", fixture + "/mid", 0)
            p.setCursor(indexOf(p, "mid"))
            p.open(fixture + "/mid")
            next("inmid")
        } else if (stage === "inmid") {
            track(p, p.path)
            if (timedOut) { check("entered mid", false, true); finish(); return }
            if (!settled(p, fixture + "/mid")) return
            // Leave mid from inner.txt, so Forward has a row past the top to come back to.
            p.setCursor(indexOf(p, "inner.txt"))
            runShell(["mkdir", fixture + "/0-newdir"])
            next("inserted")
        } else if (stage === "inserted") {
            if (shell.running && !timedOut) return
            check("the insertion landed", shell.exitCode, 0)
            beginLeg("list", fixture, 2)
            p.goBack()
            next("backlist")
        } else if (stage === "backlist") {
            track(p, p.path)
            if (timedOut) { check("back settled", false, true); finish(); return }
            if (!settled(p, fixture)) return
            restored("back", p, fixture, "mid", 2)
            // 0-sub sorts before aaa.txt, so only a name restore still lands on inner.txt at its renumbered index.
            runShell(["mkdir", fixture + "/mid/0-sub"])
            next("backlistsub")
        } else if (stage === "backlistsub") {
            if (shell.running && !timedOut) return
            if (timedOut) { check("the mid insertion settled", false, true); finish(); return }
            if (!settled(p, fixture)) return
            check("the mid insertion landed", shell.exitCode, 0)
            beginLeg("list", fixture + "/mid", 2)
            p.goForward()
            next("forwardlist")
        } else if (stage === "forwardlist") {
            track(p, p.path)
            if (timedOut) { check("forward settled", false, true); finish(); return }
            if (!settled(p, fixture + "/mid")) return
            restored("forward", p, fixture + "/mid", "inner.txt", 2)
            runShell(["rmdir", fixture + "/mid/0-sub"])
            next("midlistsub")
        } else if (stage === "midlistsub") {
            track(p, p.path)
            if (shell.running && !timedOut) return
            if (timedOut) { check("the mid removal settled", false, true); finish(); return }
            // The watched re-read drops the row; only then is the pane still, so the view switch starts clean.
            if (indexOf(p, "0-sub") >= 0 || !settled(p, fixture + "/mid")) return
            check("the mid removal landed", shell.exitCode, 0)
            runShell(["rmdir", fixture + "/0-newdir"])
            next("viewgrid")
        } else if (stage === "viewgrid") {
            if (shell.running && !timedOut) return
            Flea.ViewState.changeSetting("view", "grid")
            next("gridready")
        } else if (stage === "gridready") {
            track(p, p.path)
            if (timedOut) { check("grid settled", false, true); finish(); return }
            if (!settled(p, fixture + "/mid") || p.viewMode !== "grid") return
            p.open(fixture)
            next("gridbase")
        } else if (stage === "gridbase") {
            track(p, p.path)
            if (timedOut) { check("grid base settled", false, true); finish(); return }
            if (!settled(p, fixture)) return
            beginLeg("grid", fixture + "/mid", 0)
            p.setCursor(indexOf(p, "mid"))
            p.open(fixture + "/mid")
            next("gridinmid")
        } else if (stage === "gridinmid") {
            track(p, p.path)
            if (timedOut) { check("grid entered mid", false, true); finish(); return }
            if (!settled(p, fixture + "/mid")) return
            // Leave mid from inner.txt, so Forward has a row past the top to come back to.
            p.setCursor(indexOf(p, "inner.txt"))
            runShell(["mkdir", fixture + "/0-newdir"])
            next("gridinserted")
        } else if (stage === "gridinserted") {
            if (shell.running && !timedOut) return
            check("the insertion landed", shell.exitCode, 0)
            beginLeg("grid", fixture, 2)
            p.goBack()
            next("backgrid")
        } else if (stage === "backgrid") {
            track(p, p.path)
            if (timedOut) { check("grid back settled", false, true); finish(); return }
            if (!settled(p, fixture)) return
            restored("back", p, fixture, "mid", 2)
            // 0-sub sorts before aaa.txt, so only a name restore still lands on inner.txt at its renumbered index.
            runShell(["mkdir", fixture + "/mid/0-sub"])
            next("backgridsub")
        } else if (stage === "backgridsub") {
            if (shell.running && !timedOut) return
            if (timedOut) { check("the mid insertion settled", false, true); finish(); return }
            if (!settled(p, fixture)) return
            check("the mid insertion landed", shell.exitCode, 0)
            beginLeg("grid", fixture + "/mid", 2)
            p.goForward()
            next("forwardgrid")
        } else if (stage === "forwardgrid") {
            track(p, p.path)
            if (timedOut) { check("grid forward settled", false, true); finish(); return }
            if (!settled(p, fixture + "/mid")) return
            restored("forward", p, fixture + "/mid", "inner.txt", 2)
            runShell(["rmdir", fixture + "/mid/0-sub"])
            next("midgridsub")
        } else if (stage === "midgridsub") {
            track(p, p.path)
            if (shell.running && !timedOut) return
            if (timedOut) { check("the mid removal settled", false, true); finish(); return }
            // The watched re-read drops the row; only then is the pane still, so the view switch starts clean.
            if (indexOf(p, "0-sub") >= 0 || !settled(p, fixture + "/mid")) return
            check("the mid removal landed", shell.exitCode, 0)
            runShell(["rmdir", fixture + "/0-newdir"])
            next("viewcolumns")
        } else if (stage === "viewcolumns") {
            if (shell.running && !timedOut) return
            Flea.ViewState.changeSetting("view", "columns")
            next("columnsready")
        } else if (stage === "columnsready") {
            track(p, p.path)
            if (timedOut) { check("columns settled", false, true); finish(); return }
            if (!settled(p, fixture + "/mid") || p.viewMode !== "columns") return
            p.open(fixture)
            next("columnsbase")
        } else if (stage === "columnsbase") {
            track(p, p.path)
            if (timedOut) { check("columns base settled", false, true); finish(); return }
            if (!settled(p, fixture)) return
            beginLeg("columns", fixture + "/mid", 0)
            p.setCursor(indexOf(p, "mid"))
            p.open(fixture + "/mid")
            next("columnsinmid")
        } else if (stage === "columnsinmid") {
            track(p, p.path)
            if (timedOut) { check("columns entered mid", false, true); finish(); return }
            if (!settled(p, fixture + "/mid")) return
            // Leave mid from inner.txt, so Forward has a row past the top to come back to.
            p.setCursor(indexOf(p, "inner.txt"))
            runShell(["mkdir", fixture + "/0-newdir"])
            next("columnsinserted")
        } else if (stage === "columnsinserted") {
            if (shell.running && !timedOut) return
            check("the insertion landed", shell.exitCode, 0)
            beginLeg("columns", fixture, 2)
            p.goBack()
            next("backcolumns")
        } else if (stage === "backcolumns") {
            track(p, p.path)
            if (timedOut) { check("columns back settled", false, true); finish(); return }
            if (!settled(p, fixture)) return
            restored("back", p, fixture, "mid", 2)
            // 0-sub sorts before aaa.txt, so only a name restore still lands on inner.txt at its renumbered index.
            runShell(["mkdir", fixture + "/mid/0-sub"])
            next("backcolumnssub")
        } else if (stage === "backcolumnssub") {
            if (shell.running && !timedOut) return
            if (timedOut) { check("the mid insertion settled", false, true); finish(); return }
            if (!settled(p, fixture)) return
            check("the mid insertion landed", shell.exitCode, 0)
            beginLeg("columns", fixture + "/mid", 2)
            p.goForward()
            next("forwardcolumns")
        } else if (stage === "forwardcolumns") {
            track(p, p.path)
            if (timedOut) { check("columns forward settled", false, true); finish(); return }
            if (!settled(p, fixture + "/mid")) return
            restored("forward", p, fixture + "/mid", "inner.txt", 2)
            runShell(["rmdir", fixture + "/mid/0-sub"])
            next("midcolumnssub")
        } else if (stage === "midcolumnssub") {
            track(p, p.path)
            if (shell.running && !timedOut) return
            if (timedOut) { check("the mid removal settled", false, true); finish(); return }
            // The watched re-read drops the row; only then is the pane still, so the view switch starts clean.
            if (indexOf(p, "0-sub") >= 0 || !settled(p, fixture + "/mid")) return
            check("the mid removal landed", shell.exitCode, 0)
            runShell(["rmdir", fixture + "/0-newdir"])
            next("wrap")
        } else if (stage === "dualready") {
            if (timedOut) { check("dual settled", false, true); finish(); return }
            // The second pane answers through focus, never by id: no second pane means both focuses answer the primary.
            body.focusPane(0)
            var first = body.currentPane
            body.focusPane(1)
            var second = body.currentPane
            track(second, second.path)
            if (second === first || !settled(second, second.path)) return
            root.legPane = second
            var q = second
            if (q.path !== fixture) { q.open(fixture); return }
            beginLeg("dual", fixture + "/mid", 0)
            q.setCursor(indexOf(q, "mid"))
            q.open(fixture + "/mid")
            next("dualinmid")
        } else if (stage === "dualinmid") {
            var d = pane()
            track(d, d.path)
            if (timedOut) { check("dual entered mid", false, true); finish(); return }
            if (!settled(d, fixture + "/mid")) return
            // Leave mid from inner.txt, so the back leg has a row past the top behind it.
            d.setCursor(indexOf(d, "inner.txt"))
            runShell(["mkdir", fixture + "/0-newdir"])
            next("dualinserted")
        } else if (stage === "dualinserted") {
            if (shell.running && !timedOut) return
            check("the insertion landed", shell.exitCode, 0)
            var e = pane()
            beginLeg("dual", fixture, 2)
            e.goBack()
            next("backdual")
        } else if (stage === "backdual") {
            var f = pane()
            track(f, f.path)
            if (timedOut) { check("dual back settled", false, true); finish(); return }
            if (!settled(f, fixture)) return
            restored("back", f, fixture, "mid", 2)
            runShell(["rmdir", fixture + "/0-newdir"])
            next("wrap")
        } else if (stage === "wrap") {
            if (shell.running && !timedOut) return
            if (failures === 0) console.log("CURSORBACK PASS checks=" + checks)
            else console.log("CURSORBACK FAIL checks=" + checks + " failed=" + failures)
            console.log("CURSORBACK DONE failures=" + failures)
            finish()
        }
    }
    Process {
        id: shell
        property int exitCode: -1
        onExited: function (exitCode) { shell.exitCode = exitCode }
    }
    FloatingWindow {
        id: window
        implicitWidth: 1000
        implicitHeight: 800
        Flea.WindowBody { id: body; host: window }
    }
    Timer { interval: root.pollMs; repeat: true; running: !root.finished; onTriggered: root.advance() }
}
