//@ pragma ShellId flea-preview-earlyask-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Thumbs.js" as Thumbs

// Pre-capture thumb ask over the real ColumnsArea and SelectionPreview: idle press asks once before capture, walk none early.
ShellRoot {
    id: root

    property string fixtureDir: Quickshell.env("PREVIEW_EARLYASK_FIXTURE")
    property var failures: []
    // One entry per backend thumb call: the rows, and whether a picture was up when it was sent.
    property var thumbLog: []
    property int holdsAtPress: 0
    property string wantRow: "b.jpg"
    // Walk and column-off press timing: a stalled attempt is retried, three stalls fail.
    readonly property int stallTries: 3
    // Past offStallMs the listing's 70 ms first settle may have run, so the sample no longer isolates the press.
    readonly property int offStallMs: 60
    // Under the 120 ms settle, so every walk step still trails the press before it.
    readonly property int walkStallMs: 100
    property var walkStamps: []
    property var walkStalls: []
    property real pressAt: 0
    property var pressStalls: []

    function fail(text) { root.failures.push(text) }
    function preview() { return area.previewColumn }
    function swap() { return area.swapState() }
    function maxOf(list) { var m = 0; for (var i = 0; i < list.length; i++) m = Math.max(m, list[i]); return m }
    function gapsOf(stamps) {
        var out = []
        for (var i = 1; i < stamps.length; i++) out.push(stamps[i] - stamps[i - 1])
        return out
    }

    function noteThumb(ask) {
        var s = root.swap()
        root.thumbLog.push({ rows: ask.slice(), holding: s.holding, capturing: s.capturing, holds: s.holds })
    }

    Component {
        id: backendStub
        QtObject {
            signal peeked(string path, bool hidden, int total, var rows, bool readFailed, int mode, bool hiddenLast, int first)
            signal metaResult(var message)
            property int metaSeq: 0
            function peek(path, size, hidden) {}
            function askMeta(index, wantLines, wantMedia, wantArchive) {
                metaSeq += 1
                var token = metaSeq
                answerMetaTimer.token = token
                answerMetaTimer.restart()
                return token
            }
            // Production answers asynchronously, so the stub lands the file a turn later.
            function thumb(ask, cacheOnly) {
                if (ask.length === 0) return
                root.noteThumb(ask)
                for (var i = 0; i < ask.length; i++) answerThumbTimer.queue.push(ask[i])
                answerThumbTimer.restart()
            }
            function thumbcancel(rows) {}
            function dirsize(rows) {}
            function dirsizecancel() {}
            function window(start, count) {}
        }
    }

    Timer {
        id: answerThumbTimer
        interval: 20
        repeat: false
        property var queue: []
        onTriggered: {
            var state = root.stubPane.thumbState
            for (var i = 0; i < queue.length; i++)
                state = Thumbs.remember(state, queue[i], root.fixtureDir + "/c" + (queue[i] % 6) + ".png", 240)
            root.stubPane.thumbState = state
            queue = []
        }
    }

    Timer {
        id: answerMetaTimer
        interval: 20
        repeat: false
        property int token: 0
        onTriggered: root.stubBackend.metaResult({ token: token, w: 8, h: 8, ms: 1, rate: 0,
            entries: 0, unpacked: 0, afailed: false, names: [], lines: 3, partial: false,
            lfailed: false, target: "", targetdir: "", owner: "", orient: 1 })
    }

    Component {
        id: paneStub
        QtObject {
            property string path: "/probe/studio"
            property var rows: []
            property int cursorIndex: 0
            property bool showHidden: false
            property int windowSize: 35
            property bool listInFlight: false
            property string listingState: "ready"
            property string searchMode: ""
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property var kindNames: ["text-x-generic", "image-x-generic"]
            property bool storageKnown: true
            property string storageClass: "local"
            property int total: 0
            property int held: 0
            property var shown: null
            property int shownTotal: 0
            property int previewIndex: -1
            property int renamingIndex: -1
            property var clipboard: null
            property var trash: ({ opened: false })
            property int selectionVersion: 0
            property int firstSettleMs: 70
            property int settleMs: 120
            property int coalesceMs: 16
            property int refetchMargin: 25
            property int buffer: 150
            property var backend: null
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) { return (index >= 0 && index < rows.length) ? rows[index] : null }
            function isSelected(index) { return false }
            function selectedIndices() { return [] }
            function selectionCount() { return 0 }
            function open(path) {}
            function openFile(path) {}
            function focusRequested() {}
            function pressSlowClick() {}
        }
    }

    Component {
        id: menuStub
        QtObject {
            function close() {}
            function openBackground(point) {}
        }
    }

    property var stubBackend: backendStub.createObject(root)
    property var stubPane: paneStub.createObject(root, { backend: root.stubBackend })

    FloatingWindow {
        implicitWidth: 1200
        implicitHeight: 600
        color: Flea.Theme.color.background

        Flea.ColumnsArea {
            id: area
            anchors.fill: parent
            pane: root.stubPane
            menu: menuStub.createObject(root)
            onThumbsApplied: function (work) { root.stubPane.thumbState = Thumbs.applied(root.stubPane.thumbState, work) }
        }
    }

    property var folderSub: ({ n: "sub", d: true, k: 0, p: 493, s: 0, m: 9, t: false, i: "folder" })
    property var fileA: ({ n: "a.jpg", d: false, k: 1, p: 420, s: 15, m: 8, t: true, i: "image-x-generic" })
    property var fileB: ({ n: "b.jpg", d: false, k: 1, p: 420, s: 16, m: 10, t: true, i: "image-x-generic" })
    property var fileC: ({ n: "c.jpg", d: false, k: 1, p: 420, s: 17, m: 11, t: true, i: "image-x-generic" })
    property var fileD: ({ n: "d.jpg", d: false, k: 1, p: 420, s: 18, m: 12, t: true, i: "image-x-generic" })
    property var fileE: ({ n: "e.jpg", d: false, k: 1, p: 420, s: 19, m: 13, t: true, i: "image-x-generic" })

    function rowName() { var row = root.preview().row; return row ? String(row.n) : "" }

    Timer { id: kickoff; interval: 600; repeat: false; onTriggered: root.phaseStart() }
    Timer { id: offSample; interval: 40; repeat: false; onTriggered: root.phaseOffSample() }
    Timer { id: poll; interval: 20; repeat: true; property int polls: 0; onTriggered: root.pollSettled() }
    Timer { id: quiet; interval: 600; repeat: false; onTriggered: root.phaseQuiet() }
    Timer { id: quiet2; interval: 500; repeat: false; onTriggered: root.phaseWalkPrimer() }
    Timer { id: walkPrimer; interval: 30; repeat: false; onTriggered: root.phaseWalk() }
    Timer { id: stepper; interval: 30; repeat: true; property int step: 0; onTriggered: root.walkStep() }
    Timer { id: donePoll; interval: 20; repeat: true; property int polls: 0; onTriggered: root.pollDone() }
    Timer { id: doneQuiet; interval: 400; repeat: false; onTriggered: root.phaseDone() }
    Timer { id: stallQuiet; interval: 400; repeat: false; onTriggered: root.retryWalkOrFail() }

    function phaseStart() {
        if (!Flea.ViewState.previewAutomatic || !Flea.ViewState.previewColumn) {
            root.fail("start needs automatic preview with its column, else no load follows a press")
            root.report()
            return
        }
        root.stubPane.rows = [root.folderSub, root.fileA, root.fileB, root.fileC, root.fileD, root.fileE]
        // Column-off leg first, through the production toggle, sampled before the listing's own settle.
        Flea.ViewState.changeLeaf("preview", { column: false })
        root.pressColumnOff()
    }

    function pressColumnOff() {
        root.stubPane.cursorIndex = 0
        root.stubPane.cursorIndex = 5
        root.pressAt = Date.now()
        offSample.start()
    }

    function phaseOffSample() {
        var lag = Date.now() - root.pressAt
        if (lag >= root.offStallMs) {
            console.log("EARLYASK RETRY offSample gap=" + lag)
            root.pressStalls = root.pressStalls.concat([lag])
            if (root.pressStalls.length < root.stallTries) {
                root.thumbLog = []
                root.pressColumnOff()
                return
            }
            root.fail("the box stalled every column-off press (gaps " + root.pressStalls.join(",") + ")")
            root.report()
            return
        }
        if (root.preview().visible)
            root.fail("the preview column did not hide for the column-off leg")
        if (root.thumbLog.length !== 0)
            root.fail("a press with the preview column off asks row "
                + root.thumbLog[0].rows.join(",") + ", want no early ask")
        if (root.failures.length > 0) { root.report(); return }
        root.stubPane.cursorIndex = 0
        Flea.ViewState.changeLeaf("preview", { column: true })
        poll.polls = 0
        poll.start()
    }

    // The folder waits by data with no picture and no ask; the primer press then settles on A.
    function pollSettled() {
        poll.polls += 1
        if (root.rowName() === "a.jpg" && root.thumbLog.length === 1) { poll.stop(); quiet.start(); return }
        if (root.stubPane.cursorIndex === 0 && poll.polls === 1) root.stubPane.cursorIndex = 1
        if (poll.polls > 250) { poll.stop(); root.fail("primer never settled on A"); root.report() }
    }

    function phaseQuiet() {
        if (root.thumbLog.length !== 1 || root.thumbLog[0].rows.join(",") !== "1")
            root.fail("primer asks " + root.thumbLog.length + " time(s), want the one load ask for row 1")
        // Folder-to-file primer must ask before the capture too, or a childPath-first handler wins.
        if (root.thumbLog.length === 1 && (root.thumbLog[0].holding || root.thumbLog[0].capturing))
            root.fail("primer asks under a picture, want the folder-to-file press to ask before the capture")
        if (root.failures.length > 0) { root.report(); return }
        var pv = root.preview()
        var cur = root.stubPane.rowFor(root.stubPane.cursorIndex)
        console.log("PREVIEWEARLYASK DIAG canRead=" + pv.canRead + " visible=" + pv.visible
            + " known=" + root.stubPane.storageKnown + " sel=" + root.stubPane.selectionCount()
            + " idx=" + root.stubPane.cursorIndex + " t=" + (cur ? cur.t : "norow")
            + " askedKeys=" + Object.keys(root.stubPane.thumbState.file).join(",")
            + " class=" + root.stubPane.storageClass + " lastMoveAt=" + pv.lastMoveAt
            + " lastMoveKey=" + pv.lastMoveKey + " auto=" + Flea.ViewState.previewAutomatic)
        root.thumbLog = []
        root.holdsAtPress = root.swap().holds
        root.stubPane.cursorIndex = 2
        donePoll.polls = 0
        donePoll.start()
    }

    // An isolated press asks before the capture: no picture up, no new hold started.
    function pollDone() {
        donePoll.polls += 1
        if (root.rowName() === root.wantRow && root.thumbLog.length === 1) {
            donePoll.stop()
            if (root.wantRow === "b.jpg") root.phaseIsolated()
            else doneQuiet.start()
            return
        }
        if (donePoll.polls > 250) {
            donePoll.stop()
            root.fail(root.wantRow === "b.jpg" ? "isolated press never loaded B" : "a walk never settled on D")
            root.report()
        }
    }

    function phaseIsolated() {
        var entry = root.thumbLog[0]
        if (entry.rows.join(",") !== "2")
            root.fail("isolated press asks row " + entry.rows.join(",") + ", want row 2")
        if (entry.holding || entry.capturing)
            root.fail("isolated press asks under a picture, want it before the capture")
        if (entry.holds !== root.holdsAtPress)
            root.fail("isolated press asks after a new hold, want it before the capture starts")
        if (root.failures.length > 0) { root.report(); return }
        quiet2.start()
    }

    // Exactly one ask per press: the quiet after the load sends nothing twice.
    function phaseWalkPrimer() {
        if (root.thumbLog.length !== 1)
            root.fail("isolated press asks " + root.thumbLog.length + " time(s), want exactly one")
        if (root.failures.length > 0) { root.report(); return }
        root.walkPress()
    }

    // The primer press is the first stamp, so a stall before the first step counts as one.
    function walkPress() {
        root.walkStamps = [Date.now()]
        root.stubPane.cursorIndex = 3
        walkPrimer.start()
    }

    // The walk primer is idle and asks early; the five walk steps are its own window.
    function phaseWalk() {
        root.thumbLog = []
        stepper.step = 0
        stepper.start()
    }

    function walkStep() {
        var targets = [4, 5, 4, 5, 4]
        root.walkStamps = root.walkStamps.concat([Date.now()])
        root.stubPane.cursorIndex = targets[stepper.step]
        stepper.step += 1
        if (stepper.step < targets.length) return
        stepper.stop()
        var gaps = root.gapsOf(root.walkStamps)
        var worst = root.maxOf(gaps)
        if (worst < root.walkStallMs) { root.pollWalkDone(); return }
        // A stalled walk asks per step, so its settle never matches: retry it before polling.
        console.log("EARLYASK RETRY walk gap=" + worst)
        root.walkStalls = root.walkStalls.concat([gaps])
        stallQuiet.start()
    }

    // Lets the stalled walk's last load settle, then forgets its asks, so the retry asks rows 3 to 5 again.
    function retryWalkOrFail() {
        if (root.walkStalls.length < root.stallTries) {
            root.stubPane.thumbState = ({ file: {}, order: [] })
            root.walkPress()
            return
        }
        root.fail("the box stalled every walk (gaps "
            + root.walkStalls.map(function (g) { return g.join(",") }).join(" | ") + ")")
        root.report()
    }

    function pollWalkDone() { root.wantRow = "d.jpg"; donePoll.polls = 0; donePoll.start() }

    // Five presses 30 ms apart send no early ask and one ask lands after the settle.
    function phaseDone() {
        if (root.thumbLog.length !== 1)
            root.fail("a walk asks " + root.thumbLog.length + " time(s), want no early ask and one after the settle")
        else if (root.thumbLog[0].rows.join(",") !== "4")
            root.fail("a walk asks row " + root.thumbLog[0].rows.join(",") + ", want the settled row 4")
        else if (root.thumbLog[0].holding !== true)
            root.fail("a walk lands its ask outside the settled load, want the load's own ask")
        if (root.rowName() !== "d.jpg")
            root.fail("a walk shows " + root.rowName() + ", want d.jpg")
        if (root.failures.length === 0)
            console.log("PREVIEWEARLYASK PASS isolated=precapture once=1 walk=silent-then-one columnoff=silent")
        root.report()
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("PREVIEWEARLYASK FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    Component.onCompleted: kickoff.start()
}
