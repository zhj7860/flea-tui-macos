//@ pragma ShellId flea-pv-gif-test

import QtQuick
import Quickshell
import "flea" as Flea

// An animated GIF in the Columns preview frame and in Quick Look's image pane: the still draws first, the moving layer exists only for an animated GIF after that, plays only while shown and uncovered, and goes with the file.
ShellRoot {
    id: root

    readonly property string dir: Quickshell.env("PVGIF_DIR")
    property var failures: []
    property int checks: 0
    property int step: 0
    property int waited: 0
    // The frame number the pause and resume steps compare against.
    property int held: -1
    property double heldAt: 0
    property bool finished: false
    // Frames seen by the per-frame guard with a moving layer present.
    property int framesWithAnimation: 0

    function log(line) { console.log("PVGIF " + line) }
    function check(cond, what) {
        root.checks++
        if (!cond) { root.failures.push(what); root.log("FAIL " + what) }
        return cond
    }
    function row(name, icon) { return { n: name, d: false, s: 1200000, m: 1, p: 33188, i: icon, t: true, k: 0 } }

    FloatingWindow {
        id: win
        implicitWidth: 1000
        implicitHeight: 700
        color: "black"

        Flea.PreviewColumn {
            id: column
            width: 400
            height: 500
        }

        Flea.PreviewImage {
            id: look
            x: 400
            width: 600
            height: 400
            visible: false
        }
    }

    // The frame's still picture: the first QQuickImage child of the frame.
    function still() {
        var kids = column.frameItem.children
        for (var i = 0; i < kids.length; i++)
            if (String(kids[i]).indexOf("QQuickImage") === 0) return kids[i]
        return null
    }
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
    function mine() { return root.mover(column.frameItem) }

    function show(name, icon, kind, thumb, meta) {
        column.thumb = thumb
        column.row = root.row(name, icon)
        column.kindName = kind
        column.meta = meta
        column.path = root.dir + "/" + name
    }

    // Every frame: the moving layer never exists before the still is drawn, the still stays until the moving one has its first frame, and the moving one is gone with its file.
    Connections {
        target: column.Window.window
        function onAfterAnimating() {
            var gif = root.mine()
            var thumb = root.still()
            if (gif === null || thumb === null) {
                if (root.step >= 1 && thumb !== null && column.thumbShown) root.check(thumb.visible, "a frame drew no picture at all")
                return
            }
            root.framesWithAnimation++
            root.check(column.frameStatus === Image.Ready, "a frame held the moving layer before the still frame was drawn")
            root.check(/\.gif$/.test(column.path), "a frame held a moving layer for " + column.path)
            if (gif.opacity === 0) root.check(thumb.visible, "a frame drew neither the still nor the moving layer")
            else root.check(!thumb.visible, "a frame drew the still under the moving layer")
        }
    }

    function waitFor(ok) {
        if (ok()) { root.waited = 0; return true }
        if (++root.waited > 1000) { root.check(false, "step " + root.step + " timed out"); root.finish() }
        return false
    }
    function advance(to) { root.step = to; root.waited = 0 }

    Timer {
        id: tick
        interval: 5
        repeat: true
        onTriggered: {
            var gif = root.mine()
            if (root.step === 1) {
                // The animated clip: the still draws, then the moving layer replaces it.
                if (!root.waitFor(function () { return gif !== null && gif.ready && column.frameStatus === Image.Ready })) return
                root.check(column.previewState === "image", "the gif row read as " + column.previewState)
                root.check(gif.playing, "the moving layer is not playing while shown")
                root.held = gif.currentFrame
                root.advance(2)
            } else if (root.step === 2) {
                if (!root.waitFor(function () { return gif.currentFrame !== root.held })) return
                root.check(true, "advanced")
                column.overlayOpen = true
                root.check(!gif.playing, "the moving layer plays under Quick Look")
                root.held = gif.currentFrame
                root.heldAt = Date.now()
                root.advance(3)
            } else if (root.step === 3) {
                if (Date.now() - root.heldAt < 700) return
                root.check(gif.currentFrame === root.held, "the moving layer advanced from " + root.held + " to " + gif.currentFrame + " under Quick Look")
                column.overlayOpen = false
                root.advance(4)
            } else if (root.step === 4) {
                if (!root.waitFor(function () { return gif.currentFrame !== root.held })) return
                win.visible = false
                root.check(!gif.playing, "the moving layer plays in a hidden window")
                root.held = gif.currentFrame
                root.heldAt = Date.now()
                root.advance(5)
            } else if (root.step === 5) {
                if (Date.now() - root.heldAt < 700) return
                root.check(gif.currentFrame === root.held, "the moving layer advanced from " + root.held + " to " + gif.currentFrame + " in a hidden window")
                win.visible = true
                root.advance(6)
            } else if (root.step === 6) {
                if (!root.waitFor(function () { return gif.playing && gif.currentFrame !== root.held })) return
                root.advance(7)
                // The facts stay at 24 frames while the path moves: only the path can take the moving layer, as when a move lands before its meta.
                column.path = root.dir + "/shot.png"
                root.check(root.mine() === null, "the moving layer outlived a path change with its frames still above one")
            } else if (root.step === 7) {
                if (!root.waitFor(function () { return column.frameStatus === Image.Ready })) return
                root.check(column.meta.frames > 1, "the meta did not keep its frames across the path change")
                root.check(root.mine() === null, "a PNG path got a moving layer")
                // Another GIF with the frames still above one: only the new file's layer is built.
                column.path = root.dir + "/clip2.gif"
                root.advance(71)
            } else if (root.step === 71) {
                var next = root.mine()
                if (!root.waitFor(function () { next = root.mine(); return next !== null && next.ready })) return
                root.check(/clip2\.gif$/.test(String(next.path)), "the moving layer plays " + next.path + ", want clip2.gif")
                root.show("shot.png", "image-x-generic", "PNG image", root.dir + "/shot.png", { w: 160, h: 90, frames: 0 })
                root.check(root.mine() === null, "the moving layer outlived a move to a PNG")
                root.advance(72)
            } else if (root.step === 72) {
                if (!root.waitFor(function () { return column.frameStatus === Image.Ready })) return
                root.check(root.mine() === null, "a PNG got a moving layer")
                root.advance(8)
                root.show("still.gif", "image-x-generic", "GIF image", root.dir + "/still.png", { w: 160, h: 90, frames: 1 })
                root.heldAt = Date.now()
            } else if (root.step === 8) {
                if (!root.waitFor(function () { return column.frameStatus === Image.Ready && column.path.indexOf("still.gif") > 0 })) return
                if (Date.now() - root.heldAt < 600) return
                root.check(root.mine() === null, "a one-frame gif got a moving layer")
                root.advance(9)
                look.path = root.dir + "/clip.gif"
                look.frames = 24
                look.visible = true
            } else if (root.step === 9) {
                // Quick Look: the same layer over its picture, in the picture's rect.
                var mv = root.mover(look)
                if (!root.waitFor(function () { mv = root.mover(look); return mv !== null && mv.ready })) return
                root.check(look.pictureItem.status === Image.Ready, "Quick Look built the moving layer before its picture")
                root.check(mv.width === look.pictureItem.width && mv.height === look.pictureItem.height, "the moving layer left the picture's rect " + mv.width + "x" + mv.height + " vs " + look.pictureItem.width + "x" + look.pictureItem.height)
                root.check(mv.playing, "Quick Look's moving layer is not playing")
                root.held = mv.currentFrame
                root.advance(10)
            } else if (root.step === 10) {
                var m2 = root.mover(look)
                if (!root.waitFor(function () { return m2.currentFrame !== root.held })) return
                look.frames = 1
                root.check(root.mover(look) === null, "Quick Look kept a moving layer for a one-frame gif")
                root.finish()
            }
        }
    }

    function finish() {
        if (root.finished) return
        root.finished = true
        tick.stop()
        root.check(root.framesWithAnimation > 0, "the per-frame guard never saw a moving layer")
        if (root.failures.length === 0)
            root.log("PASS checks=" + root.checks + " still-first moving-after pause-covered pause-hidden gone-with-file")
        root.log("DONE failures=" + root.failures.length)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    Timer {
        interval: 100
        running: true
        onTriggered: {
            root.step = 1
            root.show("clip.gif", "image-x-generic", "GIF image", root.dir + "/clip.png", { w: 160, h: 90, frames: 24 })
            tick.start()
        }
    }
}
