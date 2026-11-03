//@ pragma ShellId flea-quicklook-rect-test

import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "flea/js/PreviewKeys.js" as PreviewKeys

// Sample output: "QLRECT CASE pdf 485x712 frames=14 reveal=41ms" is one Quick Look open at 1200 x 760 whose every revealed frame drew that surface.
// The real window, listing and backend: code, a PDF and a portrait picture open at their tall rect on the first revealed frame, and no shown surface resizes until close.
ShellRoot {
    id: root

    readonly property string uiDir: Quickshell.env("QLRECT_UI")
    readonly property string fixture: Quickshell.env("QLRECT_DIR")
    readonly property int pollMs: 20
    readonly property int watchdogMs: 30000
    // Polls of a quiet window before a case starts, so the previous close and the listing are done.
    readonly property int quietPolls: 10
    // Time after the reveal a case keeps watching frames, so a late resize is seen.
    readonly property int tailMs: 400
    readonly property int revealRuns: 5

    property int checks: 0
    property int failures: 0
    property int quiet: 0
    property double stageAt: Date.now()
    property double keyAt: 0
    property double revealMs: 0
    property double tailAt: 0
    property string stage: "boot"
    property var queue: []
    property var current: null
    property var frames: []
    property bool finished: false
    // The state the multi-step cases carry between polls.
    property int swapHolds: 0
    property int swapMid: 0
    property string swapTarget: ""
    property string wantBefore: ""
    property string wantAfter: ""
    property int shownRow: -1
    property var probes: []

    function log(line) { console.log("QLRECT " + line) }
    function check(cond, what) {
        root.checks++
        if (!cond) { root.failures++; root.log("FAIL " + what) }
        return cond
    }
    function pane() { return body.item ? body.item.currentPane : null }
    function pv() { return root.pane() ? root.pane().preview : null }
    function surface() { return root.pv() ? root.pv().panesItem.parent : null }
    function indexOf(name) {
        var pane = root.pane()
        for (var i = 0; i < pane.total; i++) {
            var row = pane.rowFor(i)
            if (row && row.n === name) return i
        }
        return -1
    }
    function size(f) { return Math.round(f.w) + "x" + Math.round(f.h) }
    function sizes(list) { return list.map(root.size).join(" ") }
    function goto(stage) { root.stage = stage; root.stageAt = Date.now() }

    FloatingWindow {
        id: window
        implicitWidth: 1200
        implicitHeight: 760
        Loader {
            id: body
            anchors.fill: parent
            source: "file://" + root.uiDir + "/WindowBody.qml"
            onLoaded: item.host = window
            onStatusChanged: if (status === Loader.Error) { root.check(false, "WindowBody failed to load"); root.finish() }
        }
    }

    // Every frame drawn with the card on screen: its size, whether a swap holds a picture, and the pane container's size.
    Connections {
        target: window.contentItem.Window.window
        function onAfterAnimating() {
            var p = root.pv()
            var s = root.surface()
            if (!p || !s || !p.active || s.opacity <= 0) return
            if (root.frames.length === 0 && root.stage === "open") root.revealMs = Date.now() - root.keyAt
            root.frames.push({ w: s.width, h: s.height, held: p.held, paneW: p.panesItem.width, paneH: p.panesItem.height })
        }
    }

    function finish() {
        if (root.finished) return
        root.finished = true
        poll.stop()
        root.log((root.failures === 0 ? "PASS" : "DONE-FAIL") + " checks=" + root.checks + " failures=" + root.failures)
        root.log("DONE")
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    function next() {
        if (root.queue.length === 0) { root.finish(); return }
        root.current = root.queue.shift()
        var pane = root.pane()
        pane.listArea.forceActiveFocus()
        pane.cursorIndex = root.indexOf(root.current.name)
        root.quiet = 0
        root.goto("rest")
    }

    function open() {
        root.frames = []
        root.keyAt = Date.now()
        root.goto("open")
        if (root.current.noThumb) {
            // No cached thumbnail: the picture's size is known only from the backend's metadata reply.
            var pane = root.pane()
            var row = pane.rowFor(pane.cursorIndex)
            pane.quickLook().open(root.fixture + "/" + row.n, row.i, row.s, pane.kindNames[row.k] || "", "")
        } else {
            PreviewKeys.open(root.pane())
        }
        root.shownRow = root.pane().cursorIndex
        if (root.current.afterOpen) root.current.afterOpen(root.pv())
    }

    // The first revealed frame is the case's rect, no later frame differs, and the pane container is the card's size.
    function judge() {
        var c = root.current
        var f = root.frames
        if (!root.check(f.length > 0, c.label + " drew no revealed frame")) return
        root.check(root.size(f[0]) === c.want, c.label + " first revealed frame is " + root.size(f[0]) + ", want " + c.want)
        var moved = f.filter(function (x) { return x.w !== f[0].w || x.h !== f[0].h })
        root.check(moved.length === 0, c.label + " resized after reveal: " + root.sizes(moved.slice(0, 3)) + " after " + root.size(f[0]))
        var loose = f.filter(function (x) { return x.paneW !== x.w || x.paneH !== x.h })
        root.check(loose.length === 0, c.label + " drew " + loose.length + " frame(s) whose panes differ from the card")
        root.log("CASE " + c.label + " " + root.size(f[0]) + " frames=" + f.length + " reveal=" + Math.round(root.revealMs) + "ms")
    }

    function close() {
        root.pv().close()
        root.goto("closing")
    }

    // The zoomed portrait keeps the surface: two + presses and the card never moves.
    function zoomed(p) {
        root.wantBefore = root.size(root.frames[0])
        PreviewKeys.act("zoomIn", { preview: p })
        PreviewKeys.act("zoomIn", { preview: p })
        root.frames = []
        root.goto("zoom")
    }

    // The metadata reply is dropped (the row it answers is another), so the reveal waits out the cap and takes today's rect; a genuine reply after that changes nothing.
    function late(p) {
        root.wantBefore = root.size(root.frames[0])
        root.frames = []
        p.imageRow = root.shownRow
        p.pane.backend.askMeta(root.shownRow, false, false, false)
        root.goto("late")
    }

    // j or k to a file of another rect: the card keeps the old rect while the swap holds its picture, and has the new one from the frame the swap lets go.
    function swap(p) {
        root.frames = []
        root.swapHolds = p.swapState().holds
        root.swapMid = p.swapState().midFrames
        root.probes = []
        root.swapTarget = root.current.to
        root.wantBefore = root.current.want
        root.wantAfter = root.current.toWant
        PreviewKeys.act(root.current.move, root.pane())
        root.goto("swap")
    }

    Connections {
        target: root.pv()
        function onShapeNextChanged() { Qt.callLater(root.probe) }
    }
    function probe() {
        var p = root.pv()
        var s = root.surface()
        if (root.stage !== "swap" || !p || !s) return
        root.probes.push({ held: p.held, w: s.width, h: s.height, paneW: p.panesItem.width, paneH: p.panesItem.height })
    }

    function judgeSwap(p) {
        var f = root.frames
        var held = f.filter(function (x) { return x.held })
        var live = f.filter(function (x) { return !x.held })
        var label = root.current.label
        root.check(held.length > 0, label + " held no picture, so the swap did not run")
        root.check(held.every(function (x) { return root.size(x) === root.wantBefore }), label + " resized the card under the held picture: " + root.sizes(held))
        // Probes are taken a turn after each change of the next shape; a PDF target lands inside its own show(), where no probe stands under a hold.
        var under = root.probes.filter(function (x) { return x.held })
        if (root.current.observed) {
            root.check(under.length > 0, label + " probed no state under the hold: " + JSON.stringify(root.probes))
            root.check(under.every(function (x) { return root.size(x) === root.wantBefore }), label + " drew the card at " + root.sizes(under) + " under the hold, want " + root.wantBefore)
            root.check(under.some(function (x) { return Math.round(x.paneW) + "x" + Math.round(x.paneH) === root.wantAfter }), label + " laid no panes out at the next card's " + root.wantAfter + " under the hold: " + root.sizes(under.map(function (x) { return { w: x.paneW, h: x.paneH } })))
        }
        root.check(live.length > 0 && root.size(live[0]) === root.wantAfter, label + " first frame after the swap is " + (live.length ? root.size(live[0]) : "none") + ", want " + root.wantAfter)
        root.check(live.every(function (x) { return root.size(x) === root.wantAfter }), label + " resized after the swap: " + root.sizes(live))
        root.check(p.shape.kind === root.current.toKind && p.shape.known === true, label + " drew the unknown shape: " + JSON.stringify(p.shape))
        root.check(p.swapState().midFrames === root.swapMid, label + " drew " + (p.swapState().midFrames - root.swapMid) + " half-built frame(s)")
        root.log("SWAP " + label + " end=" + p.swapState().last.end + " ms=" + p.swapState().last.ms + " held=" + held.length + " live=" + live.length + " " + root.wantBefore + " to " + root.wantAfter)
    }

    Timer {
        id: poll
        interval: root.pollMs
        repeat: true
        running: true
        onTriggered: {
            var pane = root.pane()
            var p = root.pv()
            if (Date.now() - root.stageAt > root.watchdogMs) {
                root.check(false, "stage " + root.stage + " stalled in " + (root.current ? root.current.label : "boot"))
                root.finish()
                return
            }
            if (root.stage === "boot") {
                if (!pane || pane.listInFlight || pane.listingState !== "ready" || pane.total < 5 || !pane.storageKnown) return
                root.log("LISTED " + pane.total)
                root.queue = root.build()
                root.next()
                return
            }
            if (root.stage === "rest") {
                var row = pane.rowFor(pane.cursorIndex)
                if ((p !== null && p.active) || !row || row.n !== root.current.name) {
                    root.quiet = 0
                    if (!(p !== null && p.active)) pane.cursorIndex = root.indexOf(root.current.name)
                    return
                }
                if (++root.quiet >= root.quietPolls) root.open()
                return
            }
            if (root.stage === "open") {
                if (!p.revealedOpen || root.frames.length === 0 || Date.now() - root.keyAt < root.revealMs + root.tailMs) return
                root.judge()
                if (root.current.after) root.current.after(p)
                else root.close()
                return
            }
            if (root.stage === "zoom" || root.stage === "late") {
                if (Date.now() - root.stageAt < root.tailMs) return
                var f = root.frames
                root.check(f.length > 0 && f.every(function (x) { return root.size(x) === root.wantBefore }), root.current.label + " changed the card from " + root.wantBefore + " to " + (f.length ? root.sizes(f.slice(-1)) : "none"))
                if (root.stage === "zoom") root.check(p.surfaceItem().zoom > 1, "the portrait did not zoom")
                else root.check(p.imageW > 0, "the genuine metadata reply never landed")
                root.log("HELD " + root.current.label + " " + root.wantBefore + " frames=" + f.length)
                root.close()
                return
            }
            if (root.stage === "swap") {
                var s = p.swapState()
                if (s.holds <= root.swapHolds || s.holding || s.capturing || p.path.indexOf(root.swapTarget) < 0 || !p.lookReady) return
                root.tailAt = Date.now()
                root.goto("swaptail")
                return
            }
            if (root.stage === "swaptail") {
                if (Date.now() - root.tailAt < root.tailMs) return
                root.judgeSwap(p)
                root.close()
                return
            }
            if (root.stage === "closing") {
                if (p.visible) return
                root.next()
            }
        }
    }

    function build() {
        var list = []
        list.push({ label: "code", name: "a-main.rs", want: "984x712" })
        // The board's 485 is the A4 page over the window's height less the edges and the top bar, 27 px at base 14; this box's bar is Theme.chromeHeight.
        var pdfW = Math.ceil((760 - 2 * Flea.Theme.preview.edge - Flea.Theme.chromeHeight) * 595 / 842)
        root.log("BAR chromeHeight=" + Flea.Theme.chromeHeight + " baseSize=" + Flea.Theme.baseSize)
        list.push({ label: "pdf", name: "b-doc.pdf", want: pdfW + "x712" })
        list.push({ label: "portrait", name: "d-portrait.png", want: "330x712" })
        for (var i = 0; i < root.revealRuns; i++)
            list.push({ label: "portrait-nothumb-" + (i + 1), name: "d-portrait.png", want: "330x712", noThumb: true })
        list.push({ label: "landscape", name: "c-land.jpg", want: "984x624" })
        list.push({ label: "small-portrait", name: "e-small.png", want: "984x624" })
        list.push({ label: "zoomed-portrait", name: "d-portrait.png", want: "330x712", after: root.zoomed })
        list.push({ label: "cap", name: "d-portrait.png", want: "984x624", noThumb: true, afterOpen: function (p) { p.imageRow = 9999 }, after: root.late })
        list.push({ label: "pdf-to-landscape", name: "b-docs.pdf", want: pdfW + "x712", to: "c-land.jpg", toKind: "image", toWant: "984x624", move: "cursorDown", observed: true, after: root.swap })
        list.push({ label: "landscape-to-pdf", name: "c-land.jpg", want: "984x624", to: "b-docs.pdf", toKind: "pdf", toWant: pdfW + "x712", move: "cursorUp", after: root.swap })
        // The next file shares the page aspect, then is a portrait whose own size reply must land over the PDF that is going away.
        list.push({ label: "pdf-to-pdf", name: "b-doc.pdf", want: pdfW + "x712", to: "b-docs.pdf", toKind: "pdf", toWant: pdfW + "x712", move: "cursorDown", after: root.swap })
        list.push({ label: "pdf-to-portrait", name: "c-tall.pdf", want: pdfW + "x712", to: "d-portrait.png", toKind: "image", toWant: "330x712", move: "cursorDown", after: root.swap })
        list.push({ label: "small-to-portrait", name: "e-small.png", want: "984x624", to: "d-portrait.png", toKind: "image", toWant: "330x712", move: "cursorUp", after: root.swap })
        return list
    }
}
