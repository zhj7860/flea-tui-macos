//@ pragma ShellId flea-quicklook-hold-test

import QtQuick
import QtTest
import Quickshell
import "flea/js/PreviewKeys.js" as PreviewKeys
import "flea/js/Swap.js" as Swap

// Sample output: "QLHOLD STEP move frames=31 frozen=0 bare=0 loading=9 holds=0 empty=0 caps=1" is one step, judged once it settles.
// The hold is the window between Space and the card's first frame; no frame in it may draw the card without its content.
ShellRoot {
    id: root

    readonly property string uiDir: Quickshell.env("QLHOLD_UI")
    readonly property string fixture: Quickshell.env("QLHOLD_DIR")
    // Each step opens Quick Look on its file, acts during the hold, and is judged once the content lands.
    readonly property var steps: [
        { name: "press", file: "d-large.png", act: "press" },
        { name: "wheel", file: "d-large.png", act: "wheel" },
        { name: "move", file: "d-large.png", to: "e-large.png" },
        { name: "reopen", file: "d-large.png" },
        { name: "minshow", file: "b-mid.jpg", act: "press" },
        { name: "stall", file: "b-mid.jpg" },
        { name: "text", file: "f-notes.txt", act: "press" },
        { name: "pdf", file: "h-page.pdf", act: "press" }
    ]
    // Past the cap, so a cap counted from before show() is overdue by the time it returns.
    readonly property int stallMs: 400
    readonly property int pollMs: 20
    readonly property int quietPolls: 8
    readonly property int settlePolls: 10
    readonly property int watchdogMs: 20000

    property int stage: 0
    property int step: 0
    property int quiet: 0
    property int failures: 0
    property double stageAt: Date.now()
    property var keys: null
    property bool reopened: false
    property bool moved: false
    property bool stallArmed: false
    property var capInShow: null
    property var capAfterShow: null
    // The cap Timer while a move runs, and how often its running flag changed meanwhile.
    property var capWatch: null
    property int capFlips: 0
    // Per step: frames drawn with the card revealed, revealed over a held picture, revealed with neither content nor the loading state, and revealed over the loading state.
    property int frames: 0
    property int frozen: 0
    property int bare: 0
    property int loading: 0
    property var before: ({ empty: 0, caps: 0, holds: 0 })
    property double openedAt: 0
    property int landedMs: 0
    // The early loading state's own clock: when it drew (Preview.loadingSince), when content became ready after it, and when the card landed.
    property double earlySince: 0
    property double readyAt: 0
    property double landedAt: 0

    function log(line) { console.log("QLHOLD " + line) }
    function fail(why) { root.failures++; root.log("FAIL " + root.cur().name + ": " + why) }
    function finish() {
        root.log("DONE steps=" + root.step + " failures=" + root.failures)
        Qt.exit(root.failures ? 1 : 0)
    }
    function cur() { return root.steps[Math.min(root.step, root.steps.length - 1)] }
    function pane() { return body.item ? body.item.currentPane : null }
    function pv() { return root.pane() ? root.pane().preview : null }
    function indexOf(name) {
        for (var i = 0; i < root.pane().total; i++) {
            var row = root.pane().rowFor(i)
            if (row && row.n === name) return i
        }
        return -1
    }
    function findAll(item, type, out) {
        if (String(item).indexOf(type) === 0) out.push(item)
        var kids = item.children || []
        for (var i = 0; i < kids.length; i++) root.findAll(kids[i], type, out)
        return out
    }
    // The crawl on screen: a LoadingState that is visible and past its hold-off, or told to skip it.
    function loadingShown() {
        return root.findAll(root.pv(), "LoadingState", []).some(function (s) { return s.visible && (s.armed || s.heldOff) })
    }
    function swapCount(key) { var s = root.pv().swap; return s ? s[key] : 0 }
    function early() { return root.pv().revealedEarly === true }
    function caps() { return root.pv().revealCaps - root.before.caps }

    FloatingWindow {
        id: window
        implicitWidth: 1000
        implicitHeight: 700
        Loader {
            id: body
            anchors.fill: parent
            source: "file://" + root.uiDir + "/WindowBody.qml"
            onLoaded: item.host = window
            onStatusChanged: if (status === Loader.Error) { root.fail("WindowBody failed to load"); root.finish() }
        }
    }

    // The same moment Preview's own counter reads: just before each frame is synchronised.
    Connections {
        target: root.stage === 2 ? window.contentItem.Window.window : null
        function onAfterAnimating() {
            var p = root.pv()
            if (!p || !p.active || !p.revealed) return
            root.frames++
            if (p.landed) return
            var s = p.swap
            if (s && (s.holding || s.capturing)) root.frozen++
            else if (!root.loadingShown()) root.bare++
            else root.loading++
        }
    }

    // The three moments the minimum show is judged from, read at the instant each property flips.
    Connections {
        target: root.stage === 2 ? root.pv() : null
        function onRevealedEarlyChanged() { if (root.pv().revealedEarly) root.earlySince = root.pv().loadingSince }
        function onLookReadyChanged() { if (root.pv().lookReady && root.earlySince > 0 && root.readyAt === 0) root.readyAt = Date.now() }
        function onLandedChanged() { if (root.pv().landed) root.landedAt = Date.now() }
    }

    // The stall step opens a kind already built, so its cap counts from the key and is running inside show(); a kind's first build arms it after show() (tests/quicklook-firstkind.sh).
    Connections {
        target: root.stallArmed ? root.pv() : null
        function onActiveChanged() {
            if (!root.pv().active) return
            root.stallArmed = false
            var cap = root.capTimer()
            root.capInShow = cap ? cap.running : null
            var until = Date.now() + root.stallMs
            while (Date.now() < until) {}
        }
    }
    // Preview's reveal cap, found by its objectName among the Timers.
    function capTimer() {
        var r = root.pv().resources
        for (var i = 0; i < r.length; i++)
            if (String(r[i]).indexOf("QQmlTimer") === 0 && r[i].objectName === "revealCap") return r[i]
        return null
    }

    Connections {
        target: root.capWatch
        function onRunningChanged() { root.capFlips++ }
    }

    // The move waits for the cap to count, not a sleep, since show() defers past a running capture.
    function moveNow() {
        var cap = root.capTimer()
        if (!cap || !cap.running) return false
        if (root.pv().revealed) root.fail("the card revealed before the move, so the move was not inside the cap")
        if (cap.interval !== Swap.CAP_MS) root.fail("the reveal cap is " + cap.interval + " ms, want Swap.CAP_MS " + Swap.CAP_MS)
        root.capFlips = 0
        root.capWatch = cap
        PreviewKeys.act("cursorDown", root.pane())
        root.capWatch = null
        if (root.capFlips !== 0) root.fail("a move during the hold restarted the reveal cap, want the open's deadline kept")
        return true
    }

    function clock() {
        root.earlySince = 0
        root.readyAt = 0
        root.landedAt = 0
    }

    function open() {
        var p = root.pv()
        var s = root.cur()
        root.frames = 0
        root.frozen = 0
        root.bare = 0
        root.loading = 0
        root.quiet = 0
        root.reopened = false
        root.moved = false
        root.clock()
        root.before = p ? { empty: p.lookEmptyFrames, caps: p.revealCaps, holds: root.swapCount("holds") } : { empty: 0, caps: 0, holds: 0 }
        root.pane().listArea.forceActiveFocus()
        root.stallArmed = s.name === "stall"
        root.stage = 2
        root.stageAt = Date.now()
        root.openedAt = Date.now()
        PreviewKeys.open(root.pane())
        p = root.pv()
        if (!p || !p.active) { root.fail("Space did not open Quick Look"); root.stage = 3; return }
        if (p.revealed) root.fail("the card revealed inside Space's own turn")
        if (s.name === "stall") { var cap = root.capTimer(); root.capAfterShow = cap ? cap.running : null }
        if (s.act) {
            var x = 4, y = 4
            if (s.act === "press") root.keys.mouseClick(p, x, y, Qt.LeftButton, Qt.NoModifier, -1)
            else root.keys.mouseWheel(p, x, y, Qt.NoButton, Qt.NoModifier, 0, -120, -1)
            // A closed card never lands, so the step ends here and the next one runs.
            if (!p.active) { root.fail("a " + s.act + " during the hold closed Quick Look before its card drew"); root.stage = 3; return }
            else if (!p.revealed || !root.early()) root.fail("a " + s.act + " during the hold did not reveal the card at once")
            else if (p.landed) root.fail("the content landed inside the " + s.act + "'s own turn, so the loading state went untested")
            else if (!root.loadingShown()) root.fail("a " + s.act + " revealed the card without its content or the loading state")
        }
    }

    function judge() {
        var p = root.pv()
        var s = root.cur()
        var empty = p.lookEmptyFrames - root.before.empty
        var holds = root.swapCount("holds") - root.before.holds
        root.log("STEP " + s.name + " frames=" + root.frames + " frozen=" + root.frozen + " bare=" + root.bare + " loading=" + root.loading
            + " holds=" + holds + " empty=" + empty + " caps=" + root.caps() + " early=" + root.early() + " landedMs=" + root.landedMs + " stoodMs=" + (root.earlySince > 0 ? root.landedAt - root.earlySince : 0) + " readyMs=" + (root.earlySince > 0 ? root.readyAt - root.earlySince : 0) + (s.name === "stall" ? " capInShow=" + root.capInShow + " capAfterShow=" + root.capAfterShow : ""))
        if (empty !== 0) root.fail(empty + " frame(s) drew the card or dim during the hold, want 0")
        if (root.frozen !== 0) root.fail(root.frozen + " frame(s) revealed a held picture before the content landed, want 0")
        if (root.bare !== 0) root.fail(root.bare + " frame(s) revealed the card with neither content nor the loading state, want 0")
        if (s.name === "move" && holds !== 0) root.fail("a move during the hold took " + holds + " picture(s), want 0")
        if (root.earlySince > 0 && root.landedAt - root.earlySince < Swap.MIN_SHOW_MS)
            root.fail("the loading state stood " + (root.landedAt - root.earlySince) + " ms before the content landed, want at least Swap.MIN_SHOW_MS " + Swap.MIN_SHOW_MS)
        if (s.name === "minshow" && !(root.readyAt > 0 && root.readyAt - root.earlySince < Swap.MIN_SHOW_MS))
            root.fail(root.earlySince <= 0 ? "the early loading state never drew, so the wait went untested" : root.readyAt <= 0 ? "the content never reported ready, so the wait went untested" : "the content was ready " + (root.readyAt - root.earlySince) + " ms after the reveal, so it did not land inside the minimum and the wait went untested")
        if (s.name === "stall" && root.capAfterShow !== true) root.fail(root.capAfterShow === null ? "found no reveal cap Timer" : "the reveal cap was not counting once show() returned")
        if (s.name === "stall" && root.capInShow !== true) root.fail(root.capInShow === null ? "found no reveal cap Timer" : "the reveal cap was not counting inside show() for a kind already built, so the key's turn was outside it")
        if (s.name !== "move" && p.path !== root.fixture + "/" + s.file) root.fail("landed on " + p.path)
    }

    Timer {
        id: poll
        interval: root.pollMs
        repeat: true
        running: true
        onTriggered: {
            var pane = root.pane()
            if (Date.now() - root.stageAt > root.watchdogMs) {
                root.fail("stage " + root.stage + " stalled" + (root.pv() ? " active=" + root.pv().active + " revealed=" + root.pv().revealed + " landed=" + root.pv().landed + " path=" + root.pv().path : "") + (root.stage === 2 && root.cur().name === "move" && !root.moved ? ", waiting for the reveal cap to count before the move" : ""))
                root.finish()
                return
            }
            if (root.stage === 0) {
                if (!pane || pane.listInFlight || pane.listingState !== "ready" || pane.total < 3) return
                root.keys = Qt.createQmlObject("import QtTest; TestEvent {}", pane.listArea)
                root.stage = 1
                root.stageAt = Date.now()
                return
            }
            var p = root.pv()
            if (root.stage === 1) {
                var row = pane.rowFor(pane.cursorIndex)
                if (p && p.visible) { root.quiet = 0; return }
                if (!row || row.n !== root.cur().file) { pane.cursorIndex = root.indexOf(root.cur().file); root.quiet = 0; return }
                if (++root.quiet < root.quietPolls) return
                root.open()
                return
            }
            if (root.stage === 2) {
                var want = root.fixture + "/" + (root.cur().to || root.cur().file)
                if (root.cur().name === "move" && !root.moved) {
                    if (p.landed) {
                        root.fail("the picture landed before the reveal cap counted, so the move was not inside the hold")
                        root.finish()
                        return
                    }
                    root.moved = root.moveNow()
                    root.quiet = 0
                    return
                }
                if (!p.landed || p.path !== want) { root.quiet = 0; return }
                // Space, Escape, Space: the reopen lands inside the close fade of a card that drew.
                if (root.cur().name === "reopen" && !root.reopened) {
                    root.reopened = true
                    root.clock()
                    root.openedAt = Date.now()
                    PreviewKeys.act("escape", pane)
                    PreviewKeys.open(pane)
                    if (!p.active || p.revealed) root.fail("Escape then Space did not reopen into the hold")
                    return
                }
                if (root.quiet === 0) root.landedMs = Date.now() - root.openedAt
                if (++root.quiet < root.settlePolls) return
                root.judge()
                root.stage = 3
                root.stageAt = Date.now()
                PreviewKeys.act("escape", pane)
                return
            }
            if (root.stage === 3) {
                if (p.visible) return
                root.step++
                root.stage = 1
                root.quiet = 0
                root.stageAt = Date.now()
                if (root.step >= root.steps.length) root.finish()
            }
        }
    }
}
