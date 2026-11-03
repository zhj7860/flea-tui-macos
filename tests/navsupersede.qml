//@ pragma ShellId flea-navsupersede-test
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "flea" as Flea
import "flea/js/Swap.js" as Swap

// A folder asked for while another listing is out is taken: the pane keeps the rows it drew and lands on it alone, heldMs inside Swap.CAP_MS.
ShellRoot {
    id: root
    readonly property string fixture: Quickshell.env("FLEA_NAVSUPERSEDE_DIR") || ""
    readonly property string pidFile: Quickshell.env("FLEA_NAVSUPERSEDE_PID") || ""
    readonly property int entries: Number(Quickshell.env("FLEA_NAVSUPERSEDE_ENTRIES") || "0")
    readonly property int heldMs: Swap.CAP_MS - 25
    property int checks: 0
    property int failures: 0
    property int frames: 0
    property int framesOfA: 0
    property int loadingNotes: 0
    property var pane: null
    // The steps left, and what the current one waits on: a condition, a time, or frames to stop.
    property var steps: []
    property var waitFor: null
    property double waitUntil: 0
    property double deadline: 0
    property bool quietNeeded: false
    property int quietMark: -1
    property double quietSince: 0
    property int askFrames: 0
    property double askedAt: 0

    function fail(text) {
        failures += 1
        console.log("NAVSUPERSEDE FAIL " + text)
    }
    function check(name, actual, expected) {
        checks += 1
        if (actual !== expected) fail(name + " got=" + actual + " expected=" + expected)
        else console.log("NAVSUPERSEDE ok " + name)
    }
    function finish() {
        ticker.stop()
        console.log("NAVSUPERSEDE DONE " + checks + " checks, " + failures + " failed")
        Qt.quit()
    }
    // True while the rows the pane holds are the folder a's.
    function showsA() {
        var rows = pane ? pane.rows : []
        for (var i = 0; i < rows.length; i++) if (String(rows[i].n).indexOf("inner-a-") === 0) return true
        return false
    }
    function names() { return pane.rows.map(function (row) { return row.n }).join(",") }
    function landed(path) {
        return function () { return !pane.listInFlight && !pane.swap.holding && pane.path === path && pane.total > 0 }
    }
    function signalBackend(name) {
        signaller.command = ["/bin/sh", "-c", "kill -" + name + " \"$(cat \"$0\")\"", root.pidFile]
        signaller.done = false
        signaller.running = true
        root.waitFor = function () { return signaller.done }
    }
    function quiet() { root.quietNeeded = true; root.quietMark = -1 }
    // One step back through the history, the way the mouse button and the key both take it, then the landing on the folder it names.
    function backTo(name, path) {
        return [
            function () { pane.goBack(); check(name + ": the listing asked for is " + path, pane.listingPath, path); root.waitFor = landed(path) },
            function () { check(name + ": the pane stands on " + path, pane.path, path) }
        ]
    }

    FloatingWindow {
        id: win
        implicitWidth: 1200
        implicitHeight: 800
        Flea.Backend { id: probeBackend }
        Component {
            id: paneComponent
            Flea.Pane {
                width: 1200
                height: 800
                backend: probeBackend
                onMessage: function (text) { if (text === Swap.LOADING) root.loadingNotes += 1 }
            }
        }
        TestEvent { id: keys }
        Item {
            id: frameProbe
            Connections {
                target: frameProbe.Window.window
                function onFrameSwapped() { root.frames += 1; if (root.showsA()) root.framesOfA += 1 }
            }
        }
    }
    Process {
        id: signaller
        property bool done: false
        onExited: done = true
    }

    Component.onCompleted: {
        var a = fixture + "/a", b = fixture + "/b"
        steps = [
            function () { pane = paneComponent.createObject(win.contentItem); pane.open(fixture); root.waitFor = landed(fixture) },
            function () {
                check("the fixture is listed whole", pane.total, entries)
                pane.listArea.forceActiveFocus()
            },
            quiet,
            function () { signalBackend("STOP") },
            function () {
                root.askFrames = root.frames
                root.askedAt = Date.now()
                pane.open(a)
                check("the first folder is asked for", pane.listingPath + "|" + pane.listInFlight, a + "|true")
                root.waitUntil = Date.now() + 10
            },
            function () {
                pane.open(b)
                check("a second folder asked for while the first is out is not refused", root.loadingNotes, 0)
                check("the listing asked for moves to the second folder", pane.listingPath + "|" + pane.listInFlight, b + "|true")
                root.waitUntil = root.askedAt + root.heldMs
            },
            function () {
                check("the reply is still out after " + root.heldMs + " ms", pane.listInFlight, true)
                check("the pane still stands on the folder it drew", pane.path, fixture)
                check("and still holds that folder's rows whole", pane.total + "|" + root.showsA(), entries + "|false")
                check("no frame is drawn between the first ask and the landing", root.frames - root.askFrames, 0)
                // A row acts on the listing it was drawn for, so it keeps refusing while one is out.
                var row = pane.listArea.itemAtIndex(3).mapToItem(pane, 40, 10)
                keys.mouseClick(pane, row.x, row.y, Qt.LeftButton, Qt.NoModifier, -1)
                check("a press on a row is still refused with the loading note", root.loadingNotes, 1)
                check("and the listing asked for stays the second folder", pane.listingPath, b)
                signalBackend("CONT")
            },
            function () { root.waitFor = landed(b) },
            function () {
                check("the pane lands on the second folder", pane.path + "|" + pane.total, b + "|3")
                check("with its own rows", names(), "inner-b-1.txt,inner-b-2.txt,inner-b-3.txt")
                check("the first folder's rows never drew a frame", root.framesOfA, 0)
                check("and the landing added no refusal", root.loadingNotes, 1)
                pane.listArea.forceActiveFocus()
            }
        ].concat(backTo("back from the second folder skips the first, which never landed", fixture), [
            function () { check("and the start folder is whole", pane.total, entries); finish() }
        ])
        deadline = Date.now() + 25000
    }

    Timer {
        id: ticker
        interval: 10
        running: true
        repeat: true
        onTriggered: {
            if (Date.now() > root.deadline) {
                root.fail("stalled with " + root.steps.length + " steps left")
                root.finish()
                return
            }
            // Quiet: 300 ms with no presented frame, so a measured ask starts from rest.
            if (root.quietNeeded) {
                if (root.quietMark !== root.frames) { root.quietMark = root.frames; root.quietSince = Date.now(); return }
                if (Date.now() - root.quietSince < 300) return
                root.quietNeeded = false
            }
            // A condition waits until it holds or its optional time runs out; a bare time is a delay.
            if (root.waitFor ? !root.waitFor() && (root.waitUntil === 0 || Date.now() < root.waitUntil)
                             : Date.now() < root.waitUntil) return
            root.waitFor = null
            root.waitUntil = 0
            if (root.steps.length === 0) return
            var step = root.steps[0]
            root.steps = root.steps.slice(1)
            try {
                step()
            } catch (error) {
                root.fail("a step threw: " + error)
                root.finish()
            }
        }
    }
}
