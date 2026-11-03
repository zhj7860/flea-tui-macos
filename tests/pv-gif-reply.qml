//@ pragma ShellId flea-pv-gif-reply-test

import QtQuick
import Quickshell
import "flea" as Flea

// A backend meta reply carrying a GIF's frames reaches Quick Look's PreviewImage, the Columns frame's meta, and builds the moving layer.
ShellRoot {
    id: root

    readonly property string dir: Quickshell.env("PVGIF_DIR")
    property var failures: []
    property int checks: 0
    property int step: 0
    property int waited: 0
    property bool finished: false

    function log(line) { console.log("PVGIF " + line) }
    function check(cond, what) {
        root.checks++
        if (!cond) { root.failures.push(what); root.log("FAIL " + what) }
        return cond
    }
    function row(name, icon) { return { n: name, d: false, s: 1200000, m: 1, p: 33188, i: icon, t: true, k: 0 } }
    function waitFor(ok) {
        if (ok()) { root.waited = 0; return true }
        if (++root.waited > 1000) { root.check(false, "step " + root.step + " timed out"); root.finish() }
        return false
    }
    function advance(to) { root.step = to; root.waited = 0 }
    // The moving layer under a node, whichever host built it.
    function mover(node) {
        var kids = node.children || []
        for (var i = 0; i < kids.length; i++) {
            if (String(kids[i]).indexOf("QQuickAnimatedImage") === 0 || String(kids[i]).indexOf("PreviewAnimation") === 0) return kids[i]
            var inner = root.mover(kids[i])
            if (inner !== null) return inner
        }
        return null
    }

    // A stub backend answers the real Preview and SelectionPreview, which read the pane the way the product does.
    QtObject {
        id: backend
        property var asks: []
        property int token: 0
        signal metaResult(var message)
        function askMeta(index, wantText, wantMedia, wantArchive) { backend.asks.push(index); backend.token += 1; return backend.token }
        function thumb(ask, cacheOnly) {}
        function thumbcancel(rows) {}
    }

    QtObject {
        id: pane
        property string path: root.dir
        property int cursorIndex: 0
        property int selectionVersion: 0
        property var rows: [root.row("clip.gif", "image-x-generic")]
        property var kindNames: ({ 0: "GIF image" })
        property int settleMs: 120
        property bool storageKnown: true
        property string storageClass: "local"
        property bool listInFlight: false
        property var thumbState: ({ file: {}, order: [] })
        property var backend: backend
        property var listArea: ({ forceActiveFocus: function () {} })
        function rowFor(index) { return (index >= 0 && index < rows.length) ? rows[index] : null }
        function join(base, name) { return String(base) + "/" + String(name) }
        function selectionCount() { return 1 }
        function selectedIndices() { return [cursorIndex] }
    }

    Window {
        visible: true
        width: 600
        height: 400

        Flea.SelectionPreview {
            id: selection
            width: 300
            height: 400
            pane: pane
            swap: null
        }

        Flea.Preview {
            id: quick
            x: 300
            width: 300
            height: 400
            pane: pane
        }
    }

    function reply(frames, token) {
        backend.metaResult({ token: token, row: 0, w: 160, h: 90, ms: 0, rate: 0, entries: 0, unpacked: 0, afailed: false,
            names: [], lines: 0, partial: false, lfailed: false, target: "", targetdir: false, owner: "", orient: 1, frames: frames })
    }

    Timer {
        id: tick
        interval: 5
        repeat: true
        onTriggered: {
            if (root.step === 1) {
                quick.open(root.dir + "/clip.gif", "image-x-generic", 1200000, "GIF image", root.dir + "/clip.png")
                selection.followSelection()
                root.advance(2)
            } else if (root.step === 2) {
                // The still is drawn first, so a layer built before the reply would already stand here.
                if (!root.waitFor(function () { var si = quick.surfaceItem(); return backend.asks.length >= 2 && selection.pendingToken !== 0 && si !== null && si.pictureItem.status === Image.Ready })) return
                root.check(quick.imageFrames === 0 && selection.meta === null, "frames were known before any reply")
                root.check(root.mover(quick) === null, "Quick Look built the moving layer before any reply")
                root.reply(24, selection.pendingToken)
                root.check(quick.imageFrames === 24, "Preview.imageFrames read " + quick.imageFrames + " after a reply of 24")
                root.check(selection.meta !== null && selection.meta.frames === 24, "SelectionPreview's column meta lost the reply's frames")
                var qi = quick.surfaceItem()
                root.check(qi !== null && qi.frames === 24, "PreviewImage.frames read " + (qi ? qi.frames : "no item") + " after a reply of 24")
                root.advance(3)
            } else if (root.step === 3) {
                var qm = root.mover(quick)
                if (!root.waitFor(function () { qm = root.mover(quick); return qm !== null })) return
                root.check(true, "Quick Look built the moving layer from the reply")
                root.finish()
            }
        }
    }

    function finish() {
        if (root.finished) return
        root.finished = true
        tick.stop()
        if (root.failures.length === 0)
            root.log("PASS checks=" + root.checks + " reply-reaches-quicklook reply-reaches-column")
        root.log("DONE failures=" + root.failures.length)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    Timer {
        interval: 100
        running: true
        onTriggered: { root.step = 1; tick.start() }
    }
}
