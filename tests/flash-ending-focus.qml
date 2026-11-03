//@ pragma ShellId flea-flash-ending-focus-test

import QtQuick
import Quickshell
import qs.Commons
import "flea" as Flea

// tests/flash-ending-focus.sh's harness: a failed flash with a Flash again ending parks the keyboard frame on the drawn end button.
ShellRoot {
    id: shell

    property var failures: []
    property int ticks: 0
    property int phase: 0
    property int flashId: 0

    function log(line) { console.log("FLASHFOCUS " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(name, cond, detail) {
        if (cond) shell.log("PASS " + name)
        else shell.failures.push(name + " got " + detail)
    }

    Item {
        Item {
            id: stubBackend
            signal flashImageResult(var message)
            signal flashTargetsResult(var message)
            signal flashStartedLine(var id, var total, var known)
            signal flashProgressLine(var id, var phase, var bytes, var total, var permille)
            signal flashDoneLine(var message)
            signal flashEjectLine(var message)
            signal failed(string where, string input, string message, int mode)
            property var flashed: []
            function flashImage(path) {}
            function flashTargets(path) {}
            function flash(id, path, dev, seq, serial, bytes) { flashed.push({id: id, path: path}) }
            function flashCancel(id) {}
            function flashEject(dev, seq) {}
        }

        Item {
            id: stubPane
            property var backend: stubBackend
            property var transfer: null
            function sticky(text) {}
            function message(text, isError) {}
            function join(folder, name) { return folder + "/" + name }
        }
    }

    FloatingWindow {
        implicitWidth: 640
        implicitHeight: 480
        color: "#303030"

        Flea.FlashView {
            id: view
            pane: stubPane
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: shell.advance()
    }

    // The right-aligned Size Texts the flasher's rows draw, found by their column width.
    function sizeCells(root) {
        var out = [], queue = [root]
        while (queue.length > 0) {
            var o = queue.shift()
            if (o.visible && o.horizontalAlignment === Text.AlignRight && o.width === Flea.Theme.column.size && o.parent && o.parent.parent) out.push(o)
            var kids = o.children !== undefined ? o.children : []
            for (var i = 0; i < kids.length; i++) queue.push(kids[i])
        }
        return out
    }

    function drive() {
        return { dev: "sdb", seq: 7, serial: "S1", bytes: 8000000000,
            label: "Stick", model: "Ultra", refused: "" }
    }

    function advance() {
        shell.ticks += 1
        if (shell.ticks < 2) return
        if (shell.phase === 0) {
            view.openWithImage("/scope/iso/x.img")
            stubBackend.flashImageResult({path: "/scope/iso/x.img", kind: "raw",
                bytes: 1000, unpacked: 1000, known: true, member: ""})
            stubBackend.flashTargetsResult({drives: [shell.drive()]})
            shell.check("flash-flow-live", view.live === true && view.chosenDrive !== null,
                "live=" + view.live + " chosen=" + JSON.stringify(view.chosenDrive))
            shell.phase = 1
        } else if (shell.phase === 1) {
            // The image row and the drive row each end their Size cell one rowPaddingX inside the row, the flasher board's rule.
            var cells = shell.sizeCells(view)
            var gaps = cells.map(function (c) { return Math.round(c.parent.parent.width - c.mapToItem(c.parent.parent, c.width, 0).x) })
            shell.check("flash-size-cells-end-one-padding-in", cells.length === 2 && gaps.every(function (g) { return g === Flea.Theme.spacing.rowPaddingX }),
                "cells=" + cells.length + " gaps=" + JSON.stringify(gaps) + " want=" + Flea.Theme.spacing.rowPaddingX)
            view.pressFlash()
            shell.flashId = stubBackend.flashed.length === 1 ? stubBackend.flashed[0].id : 0
            if (shell.flashId > 0)
                stubBackend.flashStartedLine(shell.flashId, 1000, true)
            shell.check("flash-press-sent", shell.flashId > 0 && view.running === true,
                "flashed=" + JSON.stringify(stubBackend.flashed) + " running=" + view.running)
            shell.phase = 2
        } else if (shell.phase === 2) {
            stubBackend.flashDoneLine({id: shell.flashId, ok: false, err: "busy"})
            var back = view.ending !== null && view.ending.flashBack === true
            shell.check("flash-failure-ending-offers-flash-again", back,
                "ending=" + JSON.stringify(view.ending))
            shell.check("a Flash again ending frames the drawn button",
                view.endItem.activeFocus === true && view.endItem.focusShown === true,
                "activeFocus=" + view.endItem.activeFocus + " focusShown=" + view.endItem.focusShown)
            for (var i = 0; i < shell.failures.length; i++)
                shell.log("FAIL " + shell.failures[i])
            shell.log("DONE failures=" + shell.failures.length)
            shell.phase = 3
            shell.quit()
        }
    }
}
