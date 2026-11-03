//@ pragma ShellId flea-markdown-rebind-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/CodeRuns.js" as CodeRuns

// A same-file pane handoff over two real backends, with A's reply held until its connection has moved to B.
ShellRoot {
    id: shell

    property int stage: 0
    property int ticks: 0
    property int failures: 0
    property bool done: false
    property var originalFence: null
    property string originalPath: ""
    property int originalToken: 0
    property int sourceToken: 0
    property int sourceAsks: 0
    property var sourceReply: null

    function log(text) { console.log("MARKDOWN_REBIND " + text) }
    function check(ok, text) {
        if (!ok) shell.failures += 1
        shell.log((ok ? "PASS " : "FAIL ") + text)
    }
    function finish() {
        shell.done = true
        shell.log("DONE " + shell.failures + " failed")
        quitter.start()
    }
    function fences(item) {
        var stack = [item], out = []
        while (stack.length > 0) {
            var current = stack.pop()
            if (current.objectName === "fenceBox") out.push(current)
            var kids = current.children || []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
        }
        return out
    }

    component DelayedBackend: Item {
        property bool hold: false
        property var replies: []
        property var asks: ({})
        signal codeResult(var message)
        Flea.Backend { id: inner }
        function askCode(slot, source, first, count) {
            asks[slot] = (asks[slot] || 0) + 1
            return inner.askCode(slot, source, first, count)
        }
        function release() {
            var ready = replies
            replies = []
            for (var i = 0; i < ready.length; i++) codeResult(ready[i])
        }
        Connections {
            target: inner
            function onCodeResult(message) {
                if (hold) replies = replies.concat([message])
                else codeResult(message)
            }
        }
    }
    DelayedBackend { id: backendA; hold: true }
    DelayedBackend { id: backendB }

    FloatingWindow {
        implicitWidth: 560
        implicitHeight: 600
        color: "#101315"
        Flea.PreviewMarkdown {
            id: pane
            width: parent.width
            height: 300
            active: true
            path: Quickshell.env("MDCODE_DIR") + "/rebind.md"
            size: 1
            backend: backendA
        }
        Flea.CodeLines {
            id: source
            y: 300
            width: parent.width
            height: 300
            backend: backendA
            slot: "rebind-source"
            path: "rebind.rs"
            fromText: true
            text: "fn source() {}\n"
            active: shell.stage >= 2
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: !shell.done
        onTriggered: {
            shell.ticks += 1
            if (shell.ticks > 100) {
                shell.check(false, "handoff probe timed out in stage " + shell.stage)
                shell.finish()
                return
            }
            if (shell.stage === 0) {
                var found = shell.fences(pane)
                if (found.length !== 1 || found[0].token === 0 || backendA.replies.length === 0) return
                shell.originalFence = found[0]
                shell.originalPath = pane.path
                shell.originalToken = found[0].token
                shell.log("REPRO A token=" + found[0].token + " waits=" + pane.fenceWaits + " firstScreen=" + pane.firstScreen)
                pane.backend = backendB
                backendA.release()
                shell.stage = 1
                shell.ticks = 0
                return
            }
            if (shell.stage === 1) {
                var fence = shell.originalFence
                if (!pane.firstScreen && shell.ticks < 20) return
                var asked = backendB.asks[fence.slot] || 0
                shell.log("REPRO B asks=" + asked + " token=" + fence.token + " waits=" + pane.fenceWaits + " firstScreen=" + pane.firstScreen)
                shell.check(pane.path === shell.originalPath && shell.fences(pane)[0] === fence, "handoff keeps the same file and live fence")
                shell.check(asked > 0 && fence.token === 0 && pane.firstScreen && pane.fenceWaits === 0, "backend handoff asks again and releases its first-screen hold")
                var coloured = fence.held[1] && fence.held[1].some(function (run, at) { return at % 2 === 0 && run > 0 })
                shell.check(coloured && fence.children[0].text === fence.markup, "B's engine colours reach the live fence")
                shell.stage = 2
                shell.ticks = 0
                return
            }
            if (shell.stage === 2) {
                if (source.token === 0 || backendA.replies.length === 0) return
                shell.sourceToken = source.token
                shell.sourceAsks = backendB.asks[source.slot] || 0
                backendB.hold = true
                source.backend = backendB
                shell.stage = 3
                shell.ticks = 0
                return
            }
            if (shell.stage === 3) {
                var sourceAsked = (backendB.asks[source.slot] || 0) - shell.sourceAsks
                if (backendB.replies.length === 0 && shell.ticks < 20) return
                shell.log("CODELINES_HELD oldToken=" + shell.sourceToken + " token=" + source.token
                    + " B_asks=" + sourceAsked + " firstScreen=" + source.firstScreen)
                shell.check(sourceAsked === 1, "CodeLines backend handoff asks B exactly once")
                if (backendB.replies.length === 0) {
                    shell.check(false, "CodeLines receives B's own held engine reply")
                    shell.finish()
                    return
                }
                shell.sourceReply = backendB.replies[0]
                shell.check(shell.sourceReply.token === source.token && source.token === shell.sourceToken,
                    "CodeLines handoff exercises colliding real backend tokens")
                backendA.release()
                shell.stage = 4
                shell.ticks = 0
                return
            }
            if (shell.stage === 4) {
                var dropped = source.token === shell.sourceReply.token && source.answer === "" && source.total === 0
                    && source.asking !== null && Object.keys(source.held).length === 0 && !source.firstScreen
                shell.log("CODELINES_LATE_A dropped=" + dropped + " held=" + Object.keys(source.held).length
                    + " answer=" + JSON.stringify(source.answer) + " firstScreen=" + source.firstScreen)
                shell.check(dropped, "CodeLines drops A's late reply while B's reply is held")
                backendB.release()
                shell.stage = 5
                shell.ticks = 0
                return
            }
            if (shell.stage === 5) {
                var list = source.children.filter(function (child) { return typeof child.itemAtIndex === "function" })[0]
                var row = list ? list.itemAtIndex(0) : null
                if ((!source.firstScreen || !row) && shell.ticks < 20) return
                var finalAsks = (backendB.asks[source.slot] || 0) - shell.sourceAsks
                shell.log("CODELINES_DONE oldToken=" + shell.sourceToken + " token=" + source.token
                    + " B_asks=" + finalAsks + " firstScreen=" + source.firstScreen)
                shell.check(finalAsks === 1 && source.token === 0 && source.firstScreen,
                    "CodeLines B reply releases the first screen without another ask")
                var engineRuns = shell.sourceReply.lines[0]
                var coloured = engineRuns && engineRuns.some(function (run, at) { return at % 2 === 0 && run > 0 })
                var body = row ? row.children[1] : null
                shell.check(coloured && source.answer === "styled" && JSON.stringify(source.rowAt(1)) === JSON.stringify(engineRuns)
                    && body !== null && body.textFormat === Text.StyledText && body.text === CodeRuns.styled(engineRuns, source.inks),
                    "B's engine colours reach the live CodeLines text")
                shell.finish()
            }
        }
    }
    Timer {
        id: quitter
        interval: 200
        onTriggered: Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
