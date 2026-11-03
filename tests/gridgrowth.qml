//@ pragma ShellId flea-gridgrowth-test

import QtQuick
import Quickshell
import "flea" as Flea

// A Down during cache regrowth carries no growth step on its frame: steps advance only on quiet frames.
ShellRoot {
    id: root

    property var failures: []
    property int stage: 0
    property int cols: 0
    property int s0: -1
    property int c0: 0
    property int frames: 0
    property bool framed: false
    property int polls: 0
    property int minSteps: 0
    readonly property int doneStage: 6

    function pad(i) { var n = String(i); while (n.length < 4) n = "0" + n; return n }
    function bigRows() {
        var out = []
        for (var i = 0; i < 343; i++)
            out.push({ n: "g_" + root.pad(i) + ".txt", d: false, i: "text-plain", p: 420, s: 0, m: 1758835200, t: false, k: 0, v: 0 })
        return out
    }
    property var parentRows: [{ n: "big", d: true, i: "folder", p: 493, s: 0, m: 1758835200, t: false, k: 0, v: 0 }]

    Component {
        id: backendStub
        QtObject {
            function peek(path, size, hidden) {}
            function thumb(rows, cacheOnly) {}
            function thumbcancel(rows) {}
            function dirsize(rows) {}
            function dirsizecancel() {}
            function window(start, count) {}
            function askMeta(index, text, media, archive) { return 0 }
        }
    }

    Component {
        id: paneStub
        QtObject {
            property string path: "/probe"
            property var rows: []
            property var shown: null
            readonly property int shownTotal: shown === null ? total : shown.length
            property int total: 0
            property int held: 0
            property int cursorIndex: 0
            property int renamingIndex: -1
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property var clipboard: ({ paths: [], moving: false })
            property var selectionBand: null
            property int previewIndex: -1
            property bool listInFlight: false
            property int settleMs: 120
            property int coalesceMs: 16
            property int refetchMargin: 25
            property int buffer: 150
            property int windowSize: 35
            property var backend: null
            property var sidebar: null
            function rowFor(index) { var o = index - held; return (o >= 0 && o < rows.length) ? rows[o] : null }
            function isSelected(index) { return false }
        }
    }
    Component { id: menuStub; QtObject { function close() {} } }
    property var stubPane: null

    FloatingWindow {
        implicitWidth: 2344
        implicitHeight: 1340
        color: "black"
        Loader {
            id: viewLoader
            active: false
            width: 2344
            height: 1332
            sourceComponent: Flea.GridArea { pane: root.stubPane; menu: menuStub.createObject(root) }
        }
    }

    Connections {
        target: viewLoader.Window.window
        function onFrameSwapped() { root.frames += 1; root.onFrame() }
    }

    function view() { return viewLoader.item }
    function delegateCount() {
        var v = root.view()
        if (!v || !v.contentItem) return -1
        var n = 0, kids = v.contentItem.children
        for (var i = 0; i < kids.length; i++) if (kids[i].listingIndex !== undefined) n++
        return n
    }
    // A wall-clock growth driver can fire between the key and its frame, so one running across a Down fails.
    function wallDriver(v) {
        var res = v.resources || []
        for (var i = 0; i < res.length; i++) {
            var r = res[i]
            if (r && r.interval !== undefined && r.repeat && r.running) return true
        }
        return false
    }
    function land(path, total, rows) {
        var p = root.stubPane
        p.listInFlight = true
        p.total = 0
        p.held = 0
        p.rows = []
        p.cursorIndex = 0
        p.rows = rows
        p.total = total
        p.path = path
        p.listInFlight = false
    }

    Timer { id: step; interval: 5; repeat: false; onTriggered: root.advance() }
    Timer { id: watch; interval: 120; repeat: false; onTriggered: root.finish() }
    Timer { id: frameGuard; interval: 800; repeat: false; onTriggered: { root.onFrame() } }
    Timer { id: watchdog; interval: 20000; repeat: false; onTriggered: function() { root.failures.push("timed out"); root.report() } }

    function advance() {
        var v = root.view()
        if (root.stage === 0) {
            root.stubPane = paneStub.createObject(root, { backend: backendStub.createObject(root) })
            root.land("/fx/enter", 1, root.parentRows)
            viewLoader.active = true
            root.stage = 1
            step.restart()
            return
        }
        if (root.stage === 1) {
            if (!v) { step.restart(); return }
            root.land("/fx/enter/big", 1000, root.bigRows())
            root.stage = 2
            step.restart()
            return
        }
        if (root.stage === 2) {
            if (v.cacheSteps < 1) { root.polls += 1; if (root.polls > 400) { root.failures.push("growth never started"); root.report(); return } step.restart(); return }
            if (v.cacheSteps > v.cacheStepsMargin) { root.failures.push("growth finished before a down"); root.report(); return }
            root.down()
            return
        }
        if (root.stage === 4) {
            // Growth runs to its end on its own frames, then a second landing must empty the cache and grow it back again.
            if (v.cacheSteps <= v.cacheStepsMargin) { root.polls += 1; if (root.polls > 800) { root.failures.push("growth never finished"); root.report() } else step.restart(); return }
            root.minSteps = v.cacheSteps
            root.polls = 0
            root.stage = 5
            root.land("/fx/enter/big2", 1000, root.bigRows())
            step.restart()
            return
        }
        if (root.stage === 5) {
            if (v.cacheSteps < 1) { root.polls += 1; if (root.polls > 800) { root.failures.push("the second landing never regrew"); root.report() } else step.restart(); return }
            if (root.minSteps !== 0) root.failures.push("the second landing kept the grown cache, steps never fell below " + root.minSteps)
            root.report()
        }
    }
    Connections {
        target: viewLoader.item
        function onCacheStepsChanged() { if (root.stage === 5) root.minSteps = Math.min(root.minSteps, viewLoader.item.cacheSteps) }
    }
    function down() {
        var v = root.view()
        root.stage = 3
        root.cols = v.columns
        root.s0 = v.cacheSteps
        root.c0 = root.delegateCount()
        root.frames = 0
        root.framed = false
        root.stubPane.cursorIndex = root.stubPane.cursorIndex + (v.columns || 1)
        if (!(v.cacheQuiet > 0))
            root.failures.push("down left no quiet hold on growth")
        if (root.wallDriver(v))
            root.failures.push("down kept a wall-clock growth driver running")
        frameGuard.restart()
        watch.restart()
    }
    function onFrame() {
        if (root.stage !== 3 || root.framed) return
        root.framed = true
        frameGuard.stop()
        var step = Math.max(1, Math.ceil(root.cols / 2))
        if (root.delegateCount() - root.c0 > step)
            root.failures.push("down built over one step of " + step + " on its frame")
    }
    function finish() {
        if (root.stage !== 3) return
        root.stage = 4
        root.polls = 0
        step.restart()
    }
    function report() {
        // Past every live stage, with every timer stopped, so nothing polls or reports again before the kill lands.
        root.stage = root.doneStage
        step.stop(); watch.stop(); frameGuard.stop(); watchdog.stop()
        if (root.failures.length === 0)
            console.log("GRIDGROWTH PASS steps=" + root.s0 + " frames=" + root.frames)
        for (var f = 0; f < root.failures.length; f++)
            console.log("GRIDGROWTH FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
    Component.onCompleted: { watchdog.start(); step.start() }
}
