//@ pragma ShellId flea-opener-ask-test
import QtQuick
import Quickshell
import Quickshell.Io
import "flea" as Flea

// tests/opener-ask.sh's harness: the real ui/Opener.qml against a stub flea, offscreen.
ShellRoot {
    id: shell

    property int checks: 0
    property var failures: []
    property int ticks: 0
    property int scene: -1
    property bool done: false
    readonly property int settleTicks: 3
    readonly property int sceneTickBound: 100

    property var asked: []
    property var gotWith: []
    property var failed: []
    property var busy: []
    property var dirs: []
    property bool permDone: false

    function log(line) { console.log("OPENER " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(name, actual, expected) {
        shell.checks++
        if (JSON.stringify(actual) === JSON.stringify(expected)) return
        shell.failures.push(name)
        shell.log("FAIL " + name + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }

    Flea.Opener {
        id: opener
        onAskRunRaw: function (path, text) { shell.asked.push([path, text]) }
        onAskOpenWith: function (path) { shell.gotWith.push(path) }
        onFailed: function (path) { shell.failed.push(path) }
        onBusy: function (path) { shell.busy.push(path) }
        onIsDirectory: function (path) { shell.dirs.push(path) }
    }

    function askScene() { opener.open("/ask/tool.sh") }
    function runAsk() {
        shell.check("ask:one-ask", shell.asked.length, 1)
        var line = shell.asked.length === 1 ? JSON.parse(shell.asked[0][1]) : null
        shell.check("ask:path-and-kind", [shell.asked[0][0], line && line.kind, line && line.target],
            ["/ask/tool.sh", "script", "/real/tool.sh"])
        shell.check("ask:nothing-else", [shell.gotWith.length, shell.failed.length, shell.dirs.length], [0, 0, 0])
    }
    function withScene() { opener.open("/with/data.bin") }
    function runWith() {
        shell.check("openwith:routed", shell.gotWith, ["/with/data.bin"])
        shell.check("openwith:nothing-else", [shell.asked.length, shell.failed.length], [1, 0])
    }
    function refusedScene() { opener.open("/missing/tool.sh") }
    function runRefused() {
        shell.check("refused:failed", shell.failed, ["/missing/tool.sh"])
    }
    function okScene() { opener.open("/ok/tool.sh") }
    function runOk() {
        shell.check("ok:silent", [shell.asked.length, shell.gotWith.length, shell.failed.length, shell.dirs.length], [1, 1, 1, 0])
    }
    // flea --open with its ask status but no line on stdout.
    function noLineScene() { opener.open("/noline/tool.sh") }
    function runNoLine() {
        shell.check("noline:refused", [shell.asked.length, shell.failed], [1, ["/missing/tool.sh", "/noline/tool.sh"]])
    }
    // The stub loses its run bit, so the next open never starts and reports no exit.
    function setRunBit(on) {
        shell.permDone = false
        perm.command = ["chmod", on ? "+x" : "-x", Quickshell.env("FLEA_BIN")]
        perm.running = true
    }
    function noStartScene() { shell.setRunBit(false) }
    function runNoStart() { opener.open("/ask/never.sh") }
    function noStartRefusedScene() {}
    function runNoStartRefused() {
        shell.check("nostart:refused", [shell.asked.length, shell.failed.slice(2)], [1, ["/ask/never.sh"]])
        shell.check("nostart:released", opener.pending, false)
        shell.setRunBit(true)
    }
    function busyScene() { opener.open("/slow/first.sh") }
    function runBusy() {
        opener.open("/slow/second.sh")
        shell.check("busy:second-dropped", shell.busy, ["/slow/second.sh"])
        Quickshell.execDetached(["touch", Quickshell.env("FLEA_TEST_RELEASE")])
    }
    function dirsScene() { opener.open("/dir/sub") }
    function runDirs() {
        shell.check("dirs:navigates", [shell.dirs, shell.busy], [["/dir/sub"], []])
    }

    readonly property var scenes: [
        { setup: shell.askScene, ready: function () { return shell.asked.length >= 1 }, run: shell.runAsk },
        { setup: shell.withScene, ready: function () { return shell.gotWith.length >= 1 }, run: shell.runWith },
        { setup: shell.refusedScene, ready: function () { return shell.failed.length >= 1 }, run: shell.runRefused },
        // No scene waits on the clock: ok is ready once its launch has answered, and the slow stub holds the first launch open until runBusy releases it, so the second open meets a live one.
        { setup: shell.okScene, ready: function () { return !opener.pending }, run: shell.runOk },
        { setup: shell.noLineScene, ready: function () { return shell.failed.length >= 2 }, run: shell.runNoLine },
        { setup: shell.noStartScene, ready: function () { return shell.permDone }, run: shell.runNoStart },
        { setup: shell.noStartRefusedScene, ready: function () { return shell.failed.length >= 3 }, run: shell.runNoStartRefused },
        // The open after a launch that never started goes through, so the opener did not wedge busy.
        { setup: function () {}, ready: function () { return shell.permDone }, run: function () { shell.dirsScene() } },
        { setup: function () {}, ready: function () { return shell.dirs.length >= 1 }, run: shell.runDirs },
        { setup: shell.busyScene, ready: function () { return opener.pending }, run: shell.runBusy }
    ]

    Process {
        id: perm
        onExited: shell.permDone = true
    }

    Timer {
        id: ticker
        interval: 100
        repeat: true
        running: true
        onTriggered: shell.advance()
    }

    function advance() {
        if (shell.done) return
        shell.ticks++
        if (shell.scene < 0) {
            if (shell.ticks < shell.settleTicks) return
            shell.scene = 0
            shell.scenes[0].setup()
            shell.ticks = 0
            return
        }
        var current = shell.scenes[shell.scene]
        if (!shell.ready(current.ready()) && shell.ticks <= shell.sceneTickBound) return
        current.run()
        shell.scene++
        shell.ticks = 0
        if (shell.scene >= shell.scenes.length) {
            shell.report()
            return
        }
        shell.scenes[shell.scene].setup()
    }
    function ready(item) { return item !== null && item !== undefined && item !== false }

    function report() {
        ticker.running = false
        shell.done = true
        if (shell.failures.length === 0)
            shell.log("PASS " + shell.checks + " checks")
        shell.log("DONE failures=" + shell.failures.length)
        shell.quit()
    }
}
