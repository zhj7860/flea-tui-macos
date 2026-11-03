//@ pragma ShellId flea-flingframe-test

import QtQuick
import Quickshell
import "flea" as Flea

// flingframe: a fling scrolls List, Grid and Columns by a few rows a frame, and each frame is counted (delegates built, rebound, texts changed, row reads, backend asks), never timed.
ShellRoot {
    id: root

    property var failures: []
    property bool finished: false
    property var kinds: ["list", "grid", "columns"]
    property int kindAt: -1
    property string phase: "idle"
    property double phaseAt: 0
    property double deadline: 0
    // Rows a frame (tile rows in Grid) the fling moves by, and the frames it runs.
    property var speeds: [1, 3, 6]
    property int speedAt: 0
    property var starts: ["top", "mid"]
    property int startAt: 0
    property var costs: []
    property int trial: 0
    property var wheelBefore: null
    property int frameAt: 0
    readonly property int frames: 20
    // Waits and limits, in ms unless named otherwise.
    readonly property int tickMs: 16
    readonly property int timeoutMs: 110000
    readonly property int mountWaitMs: 300
    readonly property int fillDeadlineMs: 8000
    // After the driver's own hold, so the first landing's hold has ended.
    readonly property int fillGraceMs: 300
    readonly property int rewindWaitMs: 400
    readonly property int wheelRewindWaitMs: 200
    readonly property int wheelTrials: 20
    // One wheel update moves this many px and a stroke is two of them after its Begin.
    readonly property int wheelUpdatePx: 20
    readonly property int wheelUpdates: 2
    // Rows (tile rows in Grid) below the top a mid start sits at.
    readonly property int midRowsList: 400
    readonly property int midRowsGrid: 40
    // The share of the planned travel a fling must cover for its counts to mean anything.
    readonly property real travelShare: 0.9
    // The kinds whose viewport declares cursorClamped (List only; Grid and ColumnPane's ListView declare none).
    readonly property var clampKinds: ["list"]
    property double travel: 0
    property double planned: 0
    property var before: null
    property var samples: []
    property var tallyBefore: null
    property var summary: ({})
    property string kind: "list"

    FlingMeasure { id: measure }
    function fail(reason) { if (root.failures.indexOf(reason) < 0) root.failures.push(reason) }
    property var bigRows: measure.rowsFor(3000)

    Component {
        id: backendStub
        QtObject {
            id: stub
            signal peeked(string path, bool hidden, int total, var rows, bool readFailed, int mode, bool hiddenLast, int first, int dev, bool writable, string by, bool desc)
            property int dirDev: 0
            property string sortBy: "name"
            property bool sortDesc: false
            function peek(path, size, hidden) {
                var p = String(path)
                Qt.callLater(function () { var rows = measure.rowsFor(6); stub.peeked(p, false, rows.length, rows, false, 0, false, 35, 0, true, "", false) })
            }
            function thumb(rows, cacheOnly) { root.tally.thumb += 1 }
            function thumbcancel(rows) { root.tally.thumbcancel += 1 }
            function dirsize(rows) { root.tally.dirsize += 1 }
            function dirsizecancel() { root.tally.dirsizecancel += 1 }
            function window(start, count) { root.tally.window += 1 }
            function askMeta(index, text, media, archive) { root.tally.askMeta += 1; return 0 }
        }
    }

    Component { id: swapStub; QtObject { property bool searchWarm: false } }

    Component {
        id: paneStub
        QtObject {
            id: pane
            property string path: "/probe"
            property var rows: []
            property var shown: null
            readonly property int shownTotal: shown === null ? total : shown.length
            property int total: 0
            property int held: 0
            property int cursorIndex: 0
            property int renamingIndex: -1
            property int renameRequest: 0
            property string renameError: ""
            property bool renamePending: false
            property int selectionVersion: 0
            property bool paneFocused: true
            property bool dualMode: false
            property bool showHidden: false
            property var trash: ({ opened: false })
            property var clipboard: ({ paths: [], moving: false })
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property var kindNames: []
            property string searchMode: ""
            property string searchQuery: ""
            property string recentMode: ""
            property string filterQuery: ""
            property bool filterTyping: false
            property var selectionBand: null
            property int previewIndex: -1
            property bool storageKnown: true
            property string storageClass: ""
            property bool listInFlight: false
            property string listingState: "ready"
            property string pendingSelect: ""
            property bool pendingMenu: false
            property string focusView: "list"
            property string viewMode: "list"
            property int cursorStride: 17
            property double inputAt: 0
            property int rowsAt: 0
            property string keySequence: ""
            property string keySequenceIdentity: ""
            property int trashArmedAt: 0
            property int visibleRows: 43
            property int cacheRows: 4
            property int firstSettleMs: 70
            property int settleMs: 120
            property int coalesceMs: 16
            property int refetchMargin: 25
            property int buffer: 150
            property int windowSize: 35
            property var backend: null
            property var sidebar: null
            property var listArea: null
            property var swap: null
            onCursorIndexChanged: { root.tally.cursor += 1; root.tally.clampWrites += root.inClamp ? 1 : 0 }
            function renameEditor() { return null }
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) { root.tally.rowFor += 1; var o = index - held; return (o >= 0 && o < rows.length) ? rows[o] : null }
            function isSelected(index) { root.tally.isSelected += 1; return false }
            function selectedIndices() { return [] }
            function selectionCount() { return 0 }
            function thumbFor(index) { return "" }
            function setCursor(index, mode) { cursorIndex = index }
            function slowClickWasSole(index) { return false }
            function pressSlowClick() {}
            function cancelSlowClick() {}
            function armSlowClick() {}
            function commitRename(newName) {}
            function open(path) {}
            function openFile(path) {}
            function focusRequested() {}
        }
    }
    Component { id: menuStub; QtObject { function close() {} function openBackground(point) {} } }

    // True only while the clamp hook writes the cursor, so a write is credited to the clamp by where it ran.
    property bool inClamp: false
    property var tally: ({ rowFor: 0, isSelected: 0, thumb: 0, thumbcancel: 0, dirsize: 0, dirsizecancel: 0, window: 0, askMeta: 0, cursor: 0, clamped: 0, clampWrites: 0 })
    property var stubBackend: backendStub.createObject(root)
    property var stubPane: paneStub.createObject(root, { backend: root.stubBackend, swap: swapStub.createObject(root) })

    FloatingWindow {
        implicitWidth: 2536
        implicitHeight: 1389
        color: "black"
        Loader { id: viewLoader; width: 2536; height: 1381 }
    }
    Component { id: listView; Flea.List { width: 2536; height: 1381; pane: root.stubPane; menu: menuStub.createObject(root) } }
    Component { id: gridView; Flea.GridArea { width: 2536; height: 1381; pane: root.stubPane; menu: menuStub.createObject(root) } }
    Component { id: columnsView; Flea.ColumnsArea { width: 2536; height: 1381; pane: root.stubPane; menu: menuStub.createObject(root) } }

    // The flickable that scrolls and the object that owns its prebuild driver.
    function view() {
        var top = viewLoader.item
        if (!top) return null
        return root.kind === "columns" ? top.activeColumn().viewport : top
    }
    function driver() {
        var top = viewLoader.item
        if (!top) return null
        return root.kind === "columns" ? top.activeColumn().prebuild : top.prebuild
    }
    function delegates() {
        var out = [], v = root.view()
        if (!v || !v.contentItem) return out
        var kids = v.contentItem.children
        for (var i = 0; i < kids.length; i++)
            if (kids[i].listingIndex !== undefined) out.push(kids[i])
        return out
    }
    function snap() {
        var d = root.driver(), all = root.delegates(), at = new Map()
        for (var i = 0; i < all.length; i++)
            at.set(all[i], { index: all[i].listingIndex, live: all[i].live === true, texts: measure.textsOf(all[i], []).join("|") })
        return { created: d.createdCount, destroyed: d.destroyedCount, delegates: all.length, at: at, tally: Object.assign({}, root.tally) }
    }
    function land(path, total, rows) {
        var p = root.stubPane
        p.listInFlight = true
        p.total = 0
        p.held = 0
        p.rows = []
        p.cursorIndex = 0
        p.listingState = "loading"
        p.rows = rows
        p.total = total
        p.path = path
        p.listingState = "ready"
        p.listInFlight = false
    }

    function go(next) { root.phase = next; root.phaseAt = Date.now() }
    function elapsed() { return Date.now() - root.phaseAt }
    function rowH() { return root.kind === "grid" ? root.view().cellHeight : Flea.Theme.fileRowHeight }
    function columnsOf() { return root.kind === "grid" ? root.view().columns : 1 }
    function stepPx() { return root.speeds[root.speedAt] * root.rowH() }
    function midY(v) { return v.originY - v.topMargin + (root.kind === "grid" ? root.midRowsGrid : root.midRowsList) * root.rowH() }

    // The view must have moved by the stroke before any count of the stroke means anything.
    function report() {
        var s = root.samples, n = s.length, rows = root.speeds[root.speedAt], start = root.starts[root.startAt]
        var m = measure.means(s)
        var cs = root.costs.slice().sort(function (a, b) { return a - b; }), csum = 0
        for (var c = 0; c < cs.length; c++) csum += cs[c]
        var line = "FLINGFRAME " + root.kind + " " + start + " rows=" + rows + " frames=" + n + " travel=" + root.travel.toFixed(0) + "/" + root.planned.toFixed(0) + "px"
        for (var name in m) line += " " + name + "=" + m[name].toFixed(2)
        console.log(line + " writeMs=" + (csum / cs.length).toFixed(2) + "/" + cs[cs.length - 1])
        var tag = root.kind + " " + start + " rows=" + rows + ": "
        if (root.travel < root.travelShare * root.planned) { root.fail(tag + "the view moved " + root.travel.toFixed(0) + " of " + root.planned.toFixed(0) + " px, so the stroke did not scroll"); return }
        measure.judge(tag, m, rows * root.columnsOf(), start === "mid", 1).forEach(root.fail)
    }

    function finish() {
        if (root.finished) return
        root.finished = true
        if (root.failures.length > 0) console.log("FLINGFRAME FAIL " + root.failures.slice(0, 8).join("; "))
        else console.log("FLINGFRAME DONE")
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    function nextKind() {
        root.kindAt += 1
        if (root.kindAt >= root.kinds.length) { root.finish(); return }
        root.kind = root.kinds[root.kindAt]
        root.stubPane.focusView = root.kind
        root.stubPane.viewMode = root.kind
        root.speedAt = 0
        root.startAt = 0
        viewLoader.sourceComponent = root.kind === "list" ? listView : root.kind === "grid" ? gridView : columnsView
        root.go("mount")
    }

    // A check the probe cannot make is a failure, never a skipped check: the counts and the clamp hook must exist on the view the kind builds.
    function hookable(v, d) {
        if (typeof d.createdCount !== "number" || typeof d.destroyedCount !== "number") {
            root.fail(root.kind + ": the prebuild driver has no createdCount or destroyedCount, so builds cannot be counted")
            return false
        }
        var has = v.cursorClamped !== undefined, want = root.clampKinds.indexOf(root.kind) >= 0
        if (has !== want) {
            root.fail(root.kind + ": cursorClamped is " + (has ? "declared" : "missing") + " on the viewport, the probe expects it " + (want ? "declared" : "missing") + ", so the clamp count cannot be trusted")
            return false
        }
        if (has) v.cursorClamped.connect(function (first, last) {
            root.tally.clamped += 1
            var p = root.stubPane
            var to = Math.max(first, Math.min(last, p.cursorIndex))
            root.inClamp = true
            if (to !== p.cursorIndex) p.cursorIndex = to
            root.inClamp = false
        })
        return true
    }

    function cursorOutside() { return root.clampKinds.indexOf(root.kind) >= 0 && root.trial % 2 === 0 }

    function wheelStroke(v) {
        var hand = null, kids = v.children
        for (var w = 0; w < kids.length; w++) if (kids[w].objectName === "fleaScroll") hand = kids[w]
        if (!hand) { root.fail("wheel: no handler in " + root.kind); return false }
        var update = { phase: Qt.ScrollUpdate, pixelDelta: Qt.point(0, -root.wheelUpdatePx), angleDelta: Qt.point(0, 0), modifiers: 0, accepted: false }
        var y0 = v.contentY, t1 = Date.now()
        hand.handleWheel({ phase: Qt.ScrollBegin, pixelDelta: Qt.point(0, 0), angleDelta: Qt.point(0, 0), modifiers: 0, accepted: false })
        var took = hand.handleWheel(update)
        hand.handleWheel(update)
        v.forceLayout()
        root.costs.push(Date.now() - t1)
        var moved = measure.diff(root.wheelBefore, root.snap())
        var tag = "wheel " + root.kind + ": "
        if (root.trial === 0) console.log("FLINGFRAME " + root.kind + " wheel first stroke accepted=" + took + " moved=" + (v.contentY - y0) + "px rebound=" + moved.rebound + " created=" + moved.created + " cursor=" + moved.tally.cursor + " asks=" + (moved.tally.thumb + moved.tally.thumbcancel + moved.tally.window))
        if (took !== true) root.fail(tag + "the handler did not accept the stroke")
        if (v.contentY === y0) { root.fail(tag + "the handler moved the view by 0 px"); return true }
        // The stroke is the frame: a mid start has a full pool, and the rows it may reveal are those the pixels it moved cross.
        var per = (Math.ceil(Math.abs(v.contentY - y0) / root.rowH()) + 1) * root.columnsOf()
        measure.judge(tag, measure.flat(moved), per, true, root.wheelUpdates).forEach(root.fail)
        if (root.cursorOutside() && moved.tally.clampWrites < 1) root.fail(tag + "the cursor started above the view and no clamp hook wrote it, so the clamp write is not exercised")
        if (moved.tally.cursor !== moved.tally.clampWrites) root.fail(tag + "the cursor moved " + moved.tally.cursor + " times in the stroke but the clamp hook wrote it " + moved.tally.clampWrites + ", so another writer moved it")
        return true
    }

    Timer {
        interval: root.tickMs
        running: true
        repeat: true
        onTriggered: {
            if (root.finished) return
            var v = root.view(), d = root.driver()
            if (root.phase === "idle") {
                root.nextKind()
            } else if (root.phase === "mount") {
                if (!v || !d) return
                if (root.elapsed() < root.mountWaitMs) return
                root.land("/probe", 3000, root.bigRows)
                if (!root.hookable(v, d)) { root.go("done"); return }
                root.deadline = Date.now() + root.fillDeadlineMs
                root.go("fill")
            } else if (root.phase === "fill") {
                // The pool is full once the driver wants nothing, and the first landing's hold has ended.
                if (root.elapsed() < d.holdMs + root.fillGraceMs) return
                if (d.want > 0 && Date.now() < root.deadline) return
                console.log("FLINGFRAME " + root.kind + " pool delegates=" + root.delegates().length + " parked=" + d.parkedCount + " want=" + d.want + " created=" + d.createdCount + " cols=" + root.columnsOf())
                if (d.want > 0) {
                    root.fail(root.kind + ": the pool never filled, the driver still wants " + d.want + " after " + root.fillDeadlineMs + " ms")
                    root.go("done")
                    return
                }
                root.go("rewind")
            } else if (root.phase === "rewind") {
                v.contentY = root.starts[root.startAt] === "mid" ? root.midY(v) : v.originY - v.topMargin
                root.samples = []
                root.costs = []
                root.frameAt = 0
                root.travel = 0
                root.planned = 0
                if (root.elapsed() < root.rewindWaitMs) return
                root.before = root.snap()
                root.go("fling")
            } else if (root.phase === "fling") {
                // One frame: read what the last write cost, then write the next step.
                var now = root.snap()
                if (root.frameAt > 0) root.samples.push(measure.diff(root.before, now))
                root.before = now
                if (root.frameAt >= root.frames) {
                    root.report()
                    root.speedAt += 1
                    if (root.speedAt >= root.speeds.length) {
                        root.speedAt = 0
                        root.startAt += 1
                        if (root.startAt >= root.starts.length) { root.trial = 0; root.costs = []; root.go("wheelrewind"); return }
                    }
                    root.go("rewind")
                    return
                }
                root.frameAt += 1
                var t0 = Date.now(), y0 = v.contentY, step = root.stepPx()
                v.contentY = y0 + step
                v.forceLayout()
                root.costs.push(Date.now() - t0)
                root.travel += v.contentY - y0
                root.planned += step
            } else if (root.phase === "wheelrewind") {
                // A fresh stroke from rest in the middle: its Begin and first two updates through the real wheel handler, then the layout.
                v.contentY = root.midY(v)
                // Even trials leave the cursor above the view, so the stroke's clamps each pull it down.
                if (root.cursorOutside()) root.stubPane.cursorIndex = 0
                if (root.elapsed() < root.wheelRewindWaitMs) return
                root.wheelBefore = root.snap()
                if (!root.wheelStroke(v)) { root.go("done"); return }
                root.trial += 1
                if (root.trial >= root.wheelTrials) {
                    var wc = root.costs.slice(), ws = 0, wm = 0
                    for (var x = 0; x < wc.length; x++) { ws += wc[x]; wm = Math.max(wm, wc[x]) }
                    console.log("FLINGFRAME " + root.kind + " wheel trials=" + wc.length + " beginPlusTwoUpdatesMs=" + (ws / wc.length).toFixed(2) + "/" + wm)
                    root.go("done")
                    return
                }
                root.go("wheelrewind")
            } else if (root.phase === "done") {
                viewLoader.sourceComponent = undefined
                root.nextKind()
            }
        }
    }

    Timer {
        interval: root.timeoutMs
        running: true
        onTriggered: { root.fail("timeout in " + root.kind + " phase " + root.phase); root.finish() }
    }
    Component.onCompleted: Flea.ViewState.setTextSize({ mode: 14 })
}
