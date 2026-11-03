//@ pragma ShellId flea-shelf-mark-test

import QtQuick
import QtQuick.Shapes
import Quickshell
import "shelf" as Shelf

// The shelf mark's measured bounds, transformed bounds and painted ink at two sizes.
ShellRoot {
    id: shell

    property int checks: 0
    property int failures: 0
    property int sample: 0
    property bool done: false
    property var captureResult: null
    readonly property var captures: [smallCapture, largeCapture]
    readonly property var marks: [smallMark, largeMark]

    function log(line) { console.log("SHELFMARK " + line) }
    function check(name, ok, detail) {
        shell.checks++
        if (!ok) shell.failures++
        shell.log((ok ? "PASS " : "FAIL ") + name + (ok ? "" : ": " + detail))
    }
    function finish() {
        if (shell.done) return
        shell.done = true
        shell.log("DONE " + shell.checks + " checks, " + shell.failures + " failed")
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
    function rectText(rect) { return [rect.x, rect.y, rect.width, rect.height].join(",") }
    function near(a, b) { return Math.abs(a - b) <= 0.01 }

    FloatingWindow {
        implicitWidth: 80
        implicitHeight: 48
        color: "transparent"

        Item {
            id: smallCapture
            width: 20
            height: 20
            Shelf.FleaShelfMark { id: smallMark; x: 4; y: 4; width: 12; height: 12 }
        }
        Item {
            id: largeCapture
            x: 32
            width: 32
            height: 32
            Shelf.FleaShelfMark { id: largeMark; x: 4; y: 4; width: 24; height: 24 }
        }
        Image {
            id: shot
            opacity: 0
            onStatusChanged: {
                if (status === Image.Ready) probe.requestPaint()
                else if (status === Image.Error) {
                    shell.check("grab reloads", false, source)
                    shell.finish()
                }
            }
        }
        Canvas {
            id: probe
            width: 32
            height: 32
            opacity: 0
            onPaint: if (shot.status === Image.Ready && !shell.done) shell.painted(getContext("2d"))
        }
    }

    Timer { interval: 300; running: true; onTriggered: shell.measure() }
    Timer {
        interval: 10000
        running: !shell.done
        onTriggered: {
            shell.check("probe completes", false, "timed out")
            shell.finish()
        }
    }

    function measure() {
        var mark = shell.marks[shell.sample]
        var shape = null
        for (var i = 0; i < mark.children.length; i++)
            if (mark.children[i] instanceof Shape) shape = mark.children[i]
        var bounds = shape ? shape.boundingRect : Qt.rect(0, 0, 0, 0)
        var name = mark.width + "px "
        shell.check(name + "bounds equal ink", bounds.x === 2 && bounds.y === 2
            && bounds.width === 20 && bounds.height === 20, shell.rectText(bounds))
        var mapped = shape ? shape.mapToItem(mark, bounds.x, bounds.y, bounds.width, bounds.height)
            : Qt.rect(0, 0, 0, 0)
        shell.check(name + "mapped bounds equal box", shell.near(mapped.x, 0) && shell.near(mapped.y, 0)
            && shell.near(mapped.width, mark.width) && shell.near(mapped.height, mark.height), shell.rectText(mapped))
        if (!shell.captures[shell.sample].grabToImage(function(result) {
            shell.captureResult = result
            if (!result.saveToFile(Quickshell.env("FLEA_SHELF_MARK_DIR") + "/mark-" + mark.width + ".png")) {
                shell.check(name + "grab saves", false, "saveToFile refused")
                shell.finish()
                return
            }
            shot.source = result.url
        })) {
            shell.check(name + "grab starts", false, "grabToImage refused")
            shell.finish()
        }
    }

    // The padded grab exposes overflow beyond the mark rather than clipping it to its box.
    function painted(ctx) {
        var capture = shell.captures[shell.sample]
        var mark = shell.marks[shell.sample]
        ctx.clearRect(0, 0, probe.width, probe.height)
        ctx.drawImage(shot, 0, 0)
        var pixels = ctx.getImageData(0, 0, capture.width, capture.height).data
        var left = capture.width, top = capture.height, right = -1, bottom = -1
        for (var y = 0; y < capture.height; y++) {
            for (var x = 0; x < capture.width; x++) {
                if (pixels[(y * capture.width + x) * 4 + 3] === 0) continue
                left = Math.min(left, x)
                top = Math.min(top, y)
                right = Math.max(right, x)
                bottom = Math.max(bottom, y)
            }
        }
        shell.check(mark.width + "px painted bounds equal box", right >= left && bottom >= top
            && Math.abs(left - mark.x) <= 1 && Math.abs(top - mark.y) <= 1
            && Math.abs(right + 1 - mark.x - mark.width) <= 1
            && Math.abs(bottom + 1 - mark.y - mark.height) <= 1,
            [left, top, right + 1, bottom + 1].join(","))
        shell.sample++
        if (shell.sample === shell.marks.length) shell.finish()
        else Qt.callLater(shell.measure)
    }
}
