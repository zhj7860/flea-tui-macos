//@ pragma ShellId flea-slowsource-nas-test

import QtQuick
import QtTest
import Quickshell
import "flea/js/ExtThumbs.js" as ExtThumbs
import "flea/js/MarkdownPrepared.js" as Prepared

// The real WindowBody under a network storage class, behind the request-holding proxy tests/slowsource-nas.sh writes: leg "enter" presses Return on a folder whose listing is held, a "look-*" leg Space on a file.
// Sample output: "NASPROBE ENTER cap=1 capFrame=4 markFrame=5 markDelta=1 timer=swap-cap keyToCapMs=70 keyToMarkMs=82 landMs=401 shownMs=332" is one held listing judged.
ShellRoot {
    id: root

    readonly property string uiDir: Quickshell.env("NAS_UI") || ""
    readonly property string leg: Quickshell.env("NAS_LEG") || "enter"
    readonly property bool looks: root.leg.indexOf("look") === 0
    // The launch folder's row count, the folder Return opens, the file Space opens, and what the held reply is.
    readonly property int total: Number(Quickshell.env("NAS_TOTAL") || "0")
    readonly property string target: Quickshell.env("NAS_TARGET") || ""
    readonly property int holdMs: Number(Quickshell.env("NAS_HOLD_MS") || "0")
    // The class the proxy reports: "network" for the NAS, "" for the local control.
    readonly property string wantClass: Quickshell.env("NAS_CLASS") === undefined ? "network" : (Quickshell.env("NAS_CLASS") || "")
    readonly property int pollMs: 10
    readonly property int quietPolls: 12
    // A rest that outlasts Quick Look's unit timer and the compile it starts, so the Space compiles nothing.
    readonly property int restPolls: 200
    readonly property int watchdogMs: 30000
    // A held reply that never comes: the leg ends this long after the card revealed.
    readonly property int neverMs: 600
    // The cap is 66 ms; a software frame or two and a loaded lane add to it, a held GUI thread adds the whole hold.
    readonly property int capSlackMs: 130

    property int stage: 0
    property int quiet: 0
    property int failures: 0
    property int frames: 0
    property double stageAt: Date.now()
    property var keys: null
    property double keyAt: 0

    // The frame counts the judgement reads: -1 until it happens.
    property int capFrame: -1
    property double capAt: 0
    property string timer: ""
    property int markFrame: -1
    property double markAt: 0
    property string markFlags: ""
    property int landFrame: -1
    property double landAt: 0
    property int landedFrame: -1
    property var capWatchSwap: null
    property var capWatchPv: null
    property var armWatch: []
    // One entry per frame drawn after the key: "ms since the key:listingState letter, H holding, F fell back, I in flight, rows".
    property var frameTrace: []
    // The swap's counters are the window's since launch, whose first two frames are blank before any listing lands; the leg judges what the key added.
    property int blankBase: 0

    function log(line) { console.log("NASPROBE " + line) }
    function fail(why) { root.failures++; root.log("FAIL " + root.leg + ": " + why) }
    function pane() { return body.item ? body.item.currentPane : null }
    function pv() { return root.pane() ? root.pane().preview : null }
    function finish() {
        root.log("DONE leg=" + root.leg + " failures=" + root.failures)
        Qt.exit(root.failures ? 1 : 0)
    }
    function findAll(item, type, out) {
        if (!item) return out
        if (String(item).indexOf(type) === 0) out.push(item)
        var kids = item.children || []
        for (var i = 0; i < kids.length; i++) root.findAll(kids[i], type, out)
        return out
    }
    function indexOf(name) {
        var p = root.pane()
        for (var i = 0; i < p.total; i++) {
            var row = p.rowFor(i)
            if (row && row.n === name) return i
        }
        return -1
    }
    function press(key, count) {
        root.pane().listArea.forceActiveFocus()
        for (var i = 0; i < count; i++) root.keys.keyClick(key, Qt.NoModifier, -1)
    }
    // The pane's listing mark, as a frame would draw it, and the Timer that put it there.
    function paneMarks() {
        return root.findAll(root.pane(), "LoadingState", []).filter(function (s) { return s.visible && (s.armed || s.heldOff) })
    }
    function cardMarks() {
        var p = root.pv()
        return p ? root.findAll(p, "LoadingState", []).filter(function (s) { return s.visible && (s.armed || s.heldOff) }) : []
    }

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

    // afterAnimating runs just before each frame is synchronised, so it sees what that frame draws.
    Connections {
        target: window.contentItem.Window.window
        function onAfterAnimating() {
            root.frames++
            if (root.stage !== 3 && root.stage !== 4) return
            var pane = root.pane()
            if (!root.looks && root.frameTrace.length < 14)
                root.frameTrace.push((Date.now() - root.keyAt) + ":" + pane.listingState.charAt(0) + (pane.swap.holding ? "H" : "") + (pane.swap.fellBack ? "F" : "") + (pane.listInFlight ? "I" : "") + pane.rows.length)
            if (!root.looks) {
                if (root.markFrame < 0) {
                    var marks = root.paneMarks()
                    if (marks.length > 0) {
                        root.markFrame = root.frames
                        root.markAt = Date.now()
                        root.markFlags = "armed=" + marks[0].armed + " heldOff=" + marks[0].heldOff + " fellBack=" + pane.swap.fellBack
                    }
                }
                if (root.landFrame < 0 && !pane.listInFlight && pane.listingState === "ready" && pane.path === root.target) {
                    root.landFrame = root.frames
                    root.landAt = Date.now()
                }
                return
            }
            var p = root.pv()
            if (!p) return
            if (root.markFrame < 0 && p.revealed && !p.landed && root.cardMarks().length > 0) {
                root.markFrame = root.frames
                root.markAt = Date.now()
                root.markFlags = "loadingEarly=" + p.loadingEarly
            }
            if (root.landedFrame < 0 && p.landed) {
                root.landedFrame = root.frames
                root.landAt = Date.now()
            }
        }
    }

    // The swap's cap Timer ends in a fallback, counted in the turn it fires; the reveal cap ends in revealCaps.
    Connections {
        target: root.capWatchSwap
        function onFallbacksChanged() {
            if (root.capFrame < 0) {
                root.capFrame = root.frames
                root.capAt = Date.now()
                root.timer = "swap-cap"
            }
        }
    }
    Connections {
        target: root.capWatchPv
        function onRevealCapsChanged() {
            if (root.capFrame < 0) {
                root.capFrame = root.frames
                root.capAt = Date.now()
                root.timer = "reveal-cap"
            }
        }
    }
    // The pane mark's own hold-off Timer, for a hold that is not the swap's.
    Repeater {
        model: root.armWatch
        delegate: Item {
            required property var modelData
            Connections {
                target: modelData
                function onArmedChanged() {
                    if (modelData.armed && root.capFrame < 0) {
                        root.capFrame = root.frames
                        root.capAt = Date.now()
                        root.timer = "loading-holdoff"
                    }
                }
            }
        }
    }

    function judgeEnter() {
        var pane = root.pane()
        var s = pane.swap.describe()
        var delta = root.markFrame >= 0 && root.capFrame >= 0 ? root.markFrame - root.capFrame : -99
        root.log("ENTER hold=" + root.holdMs + " cap=" + s.fallbacks + " capFrame=" + root.capFrame + " markFrame=" + root.markFrame + " markDelta=" + delta + " timer=" + root.timer
            + " keyToCapMs=" + (root.capAt ? root.capAt - root.keyAt : -1) + " keyToMarkMs=" + (root.markAt ? root.markAt - root.keyAt : -1)
            + " landMs=" + (root.landAt - root.keyAt) + " landFrame=" + root.landFrame + " shownMs=" + s.shownMs + " holds=" + s.holds + " blank=" + (s.blankFrames - root.blankBase) + " loading=" + s.loadingFrames + " " + root.markFlags + " trace=" + root.frameTrace.join(","))
        root.log("WINDOW " + root.leg + " from=" + root.keyAt + " to=" + (root.landAt || Date.now()))
        // The mark follows the Timer: a listing that lands before the cap Timer fires draws its rows and no mark, one that lands after it draws the mark on the first frame after that Timer.
        if (root.capFrame < 0) {
            if (root.markFrame >= 0) root.fail("the loading mark drew with no Timer fired")
            else if (root.holdMs >= 60) root.fail("no Timer fired before the held listing landed, so the mark had nothing to draw on")
        }
        else if (root.markFrame < 0) root.fail("the held listing never drew the loading mark")
        else if (delta < 0 || delta > 1) root.fail("the loading mark drew " + delta + " frame(s) after the " + root.timer + " Timer fired, want the first")
        else if (root.capAt - root.keyAt > root.capSlackMs) root.fail("the cap Timer fired " + (root.capAt - root.keyAt) + " ms after Return, want about 66: the GUI thread was held")
        if (s.blankFrames - root.blankBase !== 0) root.fail((s.blankFrames - root.blankBase) + " blank frame(s) drew while the listing was held, want 0")
        if (root.markFrame >= 0 && s.shownMs < 100) root.fail("the loading mark stood " + s.shownMs + " ms, under 100")
    }

    function judgeLook() {
        var p = root.pv()
        var st = p.openState()
        var s = p.swap ? p.swap.describe() : null
        var delta = root.markFrame >= 0 && root.capFrame >= 0 ? root.markFrame - root.capFrame : -99
        root.log("LOOK " + root.leg + " file=" + root.target + " hold=" + root.holdMs + " revealCaps=" + st.revealCaps + " lookEmptyFrames=" + st.lookEmptyFrames + " revealedEarly=" + st.revealedEarly + " landed=" + st.landed
            + " capFrame=" + root.capFrame + " markFrame=" + root.markFrame + " markDelta=" + delta + " landedFrame=" + root.landedFrame
            + " keyToCapMs=" + (root.capAt ? root.capAt - root.keyAt : -1) + " keyToLandMs=" + (root.landedFrame >= 0 ? root.landAt - root.keyAt : -1)
            + " swap=" + (s ? JSON.stringify(s) : "none") + " " + root.markFlags)
        root.log("WINDOW " + root.leg + " from=" + root.keyAt + " to=" + (root.landAt || Date.now()))
        if (st.lookEmptyFrames !== 0) root.fail(st.lookEmptyFrames + " frame(s) drew the card or dim with neither content nor the loading state, want 0")
        if (st.revealCaps > 0) {
            if (root.markFrame < 0) root.fail("the reveal cap fired and the card never drew the loading state")
            else if (delta < 0 || delta > 1) root.fail("the card drew its loading state " + delta + " frame(s) after the reveal cap fired, want the first")
            else if (root.capAt - root.keyAt > root.capSlackMs) root.fail("the reveal cap fired " + (root.capAt - root.keyAt) + " ms after Space, want about 66: the GUI thread was held")
        } else if (root.holdMs > 0 && (!root.landAt || root.landAt - root.keyAt > root.capSlackMs)) {
            // A read the rest already took in (a prefetch that outran the hold) lands inside the cap and needs no loading state; any later landing must have been capped.
            root.fail("a read held " + root.holdMs + " ms landed " + (root.landAt ? root.landAt - root.keyAt : -1) + " ms after the key without the reveal cap firing")
        }
    }

    // A key can spin the event loop, which fires the poll inside its own handler; the nested turn waits for the outer one.
    property bool busy: false
    function step() {
        var pane = root.pane()
        if (Date.now() - root.stageAt > root.watchdogMs) {
            root.fail("stage " + root.stage + " stalled" + (pane ? " state=" + pane.listingState + " path=" + pane.path + " total=" + pane.total : ""))
            root.finish()
            return
        }
        if (root.stage === 0) {
            if (!pane || pane.listInFlight || pane.listingState !== "ready" || pane.total !== root.total || !pane.storageKnown) return
            var row = pane.rowFor(pane.cursorIndex)
            root.keys = Qt.createQmlObject("import QtTest; TestEvent {}", pane.listArea)
            var asks = row ? Prepared.readsInline({ n: "a.md", d: false, p: 33188, s: 10 }, pane.storageClass, pane.storageKnown) : null
            root.log("STORAGE leg=" + root.leg + " class=" + pane.storageClass + " known=" + pane.storageKnown + " thumbsPresent=" + ExtThumbs.present(pane.storageClass)
                + " readsInline=" + asks + " cacheOnly=" + ExtThumbs.cacheOnly(pane.storageClass, {}))
            if (pane.storageClass !== root.wantClass) { root.fail("the proxy's class did not reach the pane: " + pane.storageClass + ", want " + root.wantClass); root.finish(); return }
            root.stage = 1
            root.quiet = 0
            root.stageAt = Date.now()
            return
        }
        // A quiet launch first: the first frames after a launch are not the ones under test.
        if (root.stage === 1) {
            if (++root.quiet < 60) return
            if (root.looks) {
                var at = root.indexOf(root.target)
                if (at < 0) { root.fail("no row named " + root.target); root.finish(); return }
                // A key always moves the cursor, so the window holds Quick Look's units as a user's window does before Space.
                if (at === pane.cursorIndex) { root.press(Qt.Key_Down, 1); root.press(Qt.Key_Up, 1) }
                else root.press(Qt.Key_Down, at - pane.cursorIndex)
            } else if (root.indexOf(root.target.split("/").pop()) < 0) {
                root.fail("no row named " + root.target); root.finish(); return
            }
            root.stage = 2
            root.quiet = 0
            root.stageAt = Date.now()
            return
        }
        // The cursor rests, then the key.
        if (root.stage === 2) {
            if (++root.quiet < (root.looks ? root.restPolls : root.quietPolls)) return
            root.frames = 0
            root.keyAt = Date.now()
            if (root.looks) {
                root.press(Qt.Key_Space, 1)
                var p = root.pv()
                if (!p || !p.active) { root.fail("Space did not open Quick Look"); root.finish(); return }
                root.capWatchPv = p
                root.capWatchSwap = null
            } else {
                root.capWatchSwap = pane.swap
                root.blankBase = pane.swap.blankFrames
                root.armWatch = root.findAll(pane, "LoadingState", [])
                root.keyAt = Date.now()
                root.press(Qt.Key_Return, 1)
            }
            root.quiet = 0
            root.stage = 3
            root.stageAt = Date.now()
            return
        }
        if (root.stage === 3) {
            if (!root.looks) {
                if (root.landFrame < 0 || pane.swap.holding) return
                if (++root.quiet < root.quietPolls) return
                root.judgeEnter()
                root.finish()
                return
            }
            var look = root.pv()
            // A held read that never lands ends a little after the card revealed.
            var never = root.holdMs >= 60000
            if (!look.revealed) return
            if (!look.landed && !never) return
            if (never && Date.now() - root.stageAt < root.neverMs + 400) return
            if (++root.quiet < root.quietPolls) return
            root.judgeLook()
            root.finish()
        }
    }

    Timer {
        id: poll
        interval: root.pollMs
        repeat: true
        running: true
        onTriggered: {
            if (root.busy) return
            root.busy = true
            try { root.step() } finally { root.busy = false }
        }
    }
}
