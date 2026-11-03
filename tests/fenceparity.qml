//@ pragma ShellId flea-fenceparity-test

import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "fenceparity.js" as Probe

// A real WindowBody lists the fixture, then opens Quick Look with Space or Columns with ctrl-2.
ShellRoot {
    id: root

    readonly property string host: Quickshell.env("FENCEPARITY_HOST")
    readonly property string output: Quickshell.env("FENCEPARITY_OUT")
    property int stage: 0
    property int fenceAt: 0
    property int failures: 0
    property double started: Date.now()
    property double quietAt: 0
    property var keys: null
    property var indices: []
    property var record: null
    property var wheelBefore: null
    property bool finished: false
    property bool ticking: false
    // The listing and fences count as settled after this long with no geometry change.
    readonly property int quietMs: 180
    // The whole drive must finish well inside fenceparity.sh's 90 s process timeout.
    readonly property int stallMs: 60000
    // Two wheel notches of 120 down, so the document scrolls and the long fence must move with it.
    readonly property int wheelDelta: -240

    function log(line) { console.log("FENCEPARITY " + line) }
    function check(ok, why) { if (!ok) { root.failures++; root.log("FAIL " + why) } }
    function pane() { return body.item ? body.item.currentPane : null }
    function preview() { var p = root.pane(); return p ? (root.host === "list" ? p.preview : p.previewColumnItem) : null }
    function doc() {
        var p = root.preview()
        return p ? Probe.descendants(p).filter(function (n) { return n.viewport !== undefined && n.blockList !== undefined && typeof n.fenceSlot === "function" })[0] || null : null
    }
    function fence() {
        var d = root.doc()
        var block = d ? d.blockItem(root.indices[root.fenceAt]) : null
        return block ? Probe.descendants(block).filter(function (n) { return n.objectName === "fenceBox" })[0] || null : null
    }
    function calm(ok) {
        if (!ok) { root.quietAt = 0; return false }
        if (root.quietAt === 0) root.quietAt = Date.now()
        return Date.now() - root.quietAt >= root.quietMs
    }
    function finish() {
        if (root.finished) return
        root.finished = true
        root.log("DONE fences=" + root.fenceAt + " failures=" + root.failures)
        quitter.start()
    }
    function ready() {
        var d = root.doc(), p = root.preview()
        if (!d || !p || !d.active || !d.visible || !d.contentReady || !d.firstScreen || d.shownView !== "rendered") return false
        if (root.host === "list") return p.active && p.revealed && p.landed
        return p.visible && p.ready && (!p.swap || (!p.swap.holding && !p.swap.capturing))
    }
    function state() {
        var p = root.pane(), v = root.preview(), d = root.doc()
        return "pane=" + (p ? p.viewMode + "/" + p.cursorIndex + "/" + p.focusView + "/" + p.listArea.activeFocus : "none")
            + " preview=" + (v ? v.path + "/" + v.active + "/" + v.visible + "/" + v.revealed + "/" + v.landed + "/" + v.lookReady : "none")
            + " doc=" + (d ? d.path + "/" + d.active + "/" + d.visible + "/" + d.contentReady + "/" + d.firstScreen + "/" + d.shownView : "none")
    }

    FloatingWindow {
        id: window
        implicitWidth: 1200
        implicitHeight: 760
        Loader {
            id: body
            anchors.fill: parent
            source: "file://" + Quickshell.env("FENCEPARITY_UI") + "/WindowBody.qml"
            onLoaded: item.host = window
            onStatusChanged: if (status === Loader.Error) { root.check(false, "WindowBody failed to load"); root.finish() }
        }
    }
    Image {
        id: shot
        parent: window.contentItem
        width: 1
        height: 1
        opacity: 0
        asynchronous: false
        onStatusChanged: {
            if (status === Image.Ready) pixels.requestPaint()
            else if (status === Image.Error) { root.check(false, "grab could not reload"); root.finish() }
        }
    }
    Canvas {
        id: pixels
        parent: window.contentItem
        opacity: 0
        width: shot.sourceSize.width
        height: shot.sourceSize.height
        onPaint: {
            if (root.stage !== 6 || shot.status !== Image.Ready) return
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.drawImage(shot, 0, 0)
            root.record.pixels = Probe.pixelInks(ctx.getImageData(0, 0, width, height).data, width, height, root.record)
            root.log("RECORD " + JSON.stringify(root.record))
            root.fenceAt++
            root.stage = 3
            root.quietAt = 0
        }
    }
    Timer { id: quitter; interval: 150; onTriggered: Qt.exit(root.failures ? 1 : 0) }
    Timer {
        interval: 25
        repeat: true
        running: !root.finished
        // TestEvent pumps a nested loop, so its key and wheel must not re-enter the current step.
        onTriggered: {
            if (root.ticking) return
            root.ticking = true
            root.tick()
            root.ticking = false
        }
    }

    function tick() {
        if (Date.now() - root.started > root.stallMs) {
            root.check(false, "stage " + root.stage + " fence " + root.fenceAt + " stalled " + root.state())
            root.finish()
            return
        }
        var p = root.pane(), d = root.doc(), f = root.fence()
        if (root.stage === 0) {
            if (!p || p.listInFlight || p.listingState !== "ready" || !p.storageKnown || p.total !== 1) return
            root.check(p.rowFor(0).n === "fences.md", "the real listing did not select the fixture")
            root.check(p.viewMode === "list", "the window did not start in List view")
            root.keys = Qt.createQmlObject("import QtTest; TestEvent {}", p.listArea)
            p.cursorIndex = 0
            p.listArea.forceActiveFocus()
            root.quietAt = 0
            root.stage = 7
            return
        }
        if (root.stage === 7) {
            if (!root.calm(p.cursorIndex === 0 && p.listArea.activeFocus)) return
            if (root.host === "list") root.keys.keyClick(Qt.Key_Space, Qt.NoModifier, -1)
            else root.keys.keyClick(Qt.Key_2, Qt.ControlModifier, -1)
            root.log("OPEN " + root.host + " " + root.state())
            root.stage = 1
            return
        }
        if (root.stage === 1) {
            if (!root.calm(root.ready())) return
            root.check(p.viewMode === (root.host === "list" ? "list" : "columns"), "the requested host is not showing")
            root.check(d.backend === p.backend, "the document does not use the real pane backend")
            root.check(d.path === p.path + "/fences.md", "the host opened another file")
            root.check(d.blockList.length === 5, "the document did not draw its five blocks")
            root.indices = d.blockList.map(function (b, i) { return b.type === "fence" ? i : -1 }).filter(function (i) { return i >= 0 })
            root.check(root.indices.length === 3, "the document did not draw three fences")
            if (root.failures) { root.finish(); return }
            root.stage = 3
        }
        if (root.stage === 3) {
            if (root.fenceAt === root.indices.length) { root.finish(); return }
            d.viewport.positionViewAtIndex(root.indices[root.fenceAt], ListView.Beginning)
            root.quietAt = 0
            root.stage = 4
            return
        }
        if (root.stage === 4) {
            if (!root.calm(f && !f.awaiting && f.width > 0 && f.height > 0 && root.ready())) return
            root.record = Probe.record(d, f, root.host, root.fenceAt, root.indices[root.fenceAt], Flea.Theme)
            if (root.fenceAt === 2) {
                root.check(f.height > d.viewport.height, "the long fence fits inside the viewport")
                root.wheelBefore = { scroll: d.viewport.contentY, y: f.mapToItem(d.viewport, 0, 0).y }
                root.keys.mouseWheel(d.viewport, Math.round(d.viewport.width / 2), Math.round(d.viewport.height / 2), Qt.NoButton, Qt.NoModifier, 0, root.wheelDelta, -1)
                root.quietAt = 0
                root.stage = 5
                return
            }
            root.capture()
            return
        }
        if (root.stage === 5) {
            if (!root.calm(f && !d.viewport.moving)) return
            var scroll = d.viewport.contentY - root.wheelBefore.scroll
            var motion = f.mapToItem(d.viewport, 0, 0).y - root.wheelBefore.y
            root.record.documentScroll = { delta: scroll, fenceDelta: motion, together: scroll > 0 && Math.abs(scroll + motion) < 1 }
            root.record.rect = Probe.rect(f, d.viewport)
            root.capture()
        }
    }
    function capture() {
        var d = root.doc()
        root.stage = 6
        if (root.fenceAt === 0) {
            var whole = body.item.grabToImage(function (result) {
                root.check(result.saveToFile(root.output + "/window.png"), "whole-window grab could not be saved")
            })
            root.check(whole, "whole-window grab was refused")
        }
        var name = root.output + "/fence-" + root.fenceAt + ".png"
        var queued = d.viewport.grabToImage(function (result) {
            root.check(result.saveToFile(name), "grab could not be saved")
            shot.source = "file://" + name
        })
        root.check(queued, "viewport grab was refused")
        if (!queued) root.finish()
    }
}
