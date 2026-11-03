//@ pragma ShellId flea-navframe-test
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "flea" as Flea
import "flea/js/Swap.js" as Swap

// Enter and Back draw no frame before the landing, and the listing gate still refuses input.
ShellRoot {
    id: root
    readonly property string fixture: Quickshell.env("FLEA_NAVFRAME_DIR") || ""
    readonly property string pidFile: Quickshell.env("FLEA_NAVFRAME_PID") || ""
    readonly property string viewName: Quickshell.env("FLEA_NAVFRAME_VIEW") || "list"
    readonly property int entries: Number(Quickshell.env("FLEA_NAVFRAME_ENTRIES") || "0")
    // The paused backend gives a frame the key asked for heldMs to draw, three 120 Hz frames inside Swap.CAP_MS.
    readonly property int heldMs: Swap.CAP_MS - 25
    property int checks: 0
    property int failures: 0
    property int frames: 0
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
    property double railBy: 0
    // Slack past the rail's reveal timer: past it the rail is not coming, and the run fails by name.
    readonly property int railSlackMs: 2000
    property int railWait: 0
    property int keyFrames: 0
    property real wheelFrom: 0

    function fail(text) {
        failures += 1
        console.log("NAVFRAME FAIL " + viewName + " " + text)
    }
    function check(name, actual, expected) {
        checks += 1
        if (actual !== expected) fail(name + " got=" + actual + " expected=" + expected)
        else console.log("NAVFRAME ok " + viewName + " " + name)
    }
    function finish() {
        ticker.stop()
        console.log("NAVFRAME DONE " + viewName + " " + checks + " checks, " + failures + " failed")
        Qt.quit()
    }
    function view() { return root.viewName === "columns" ? pane.columnsArea.activeColumn().viewport : pane.listArea }
    // The centre of a visible entry, in the pane's own coordinates.
    function entryPoint(index) {
        var item = root.view().itemAtIndex(index)
        return item ? item.mapToItem(pane, item.width / 2, item.height / 2) : Qt.point(-1, -1)
    }
    function landed(path) {
        return function () {
            return !pane.listInFlight && !pane.swap.holding && pane.path === path
                && (path === fixture + "/e" ? pane.listingState === "empty" : pane.total > 0)
        }
    }
    function signalBackend(name) {
        signaller.command = ["/bin/sh", "-c", "kill -" + name + " \"$(cat \"$0\")\"", root.pidFile]
        signaller.done = false
        signaller.running = true
        root.waitFor = function () { return signaller.done }
    }
    function quiet() { root.quietNeeded = true; root.quietMark = -1; root.railWait = root.railWaitMs(); root.railBy = Date.now() + root.railWait }
    // ui/Sidebar.qml reveals the rail's groups once, railSettleMs after it is built; that frame and the one after it belong to no key.
    function railSettled() { return pane !== null && pane.sidebar !== null && pane.sidebar.railDeadlineElapsed }
    // The reveal timer plus the slack, fixed once per quiet step so the failure names the budget it used.
    function railWaitMs() { return (pane !== null && pane.sidebar !== null ? pane.sidebar.railSettleMs : 0) + root.railSlackMs }
    // One measured navigation: pause the backend, press the key, let heldMs pass, read the frames, resume, land.
    function measured(name, key, path) {
        return [
            quiet,
            function () { signalBackend("STOP") },
            function () {
                root.keyFrames = root.frames
                console.log("NAVFRAME KEY " + viewName + " " + name)
                keys.keyClick(key, Qt.NoModifier, -1)
                check(name + ": the listing is out after the key", pane.listInFlight, true)
                root.waitUntil = Date.now() + root.heldMs
            },
            function () {
                console.log("NAVFRAME HELD " + viewName + " " + name)
                check(name + ": the reply is still out after " + root.heldMs + " ms", pane.listInFlight, true)
                check(name + ": frames drawn between the key and the landing", root.frames - root.keyFrames, 0)
                signalBackend("CONT")
            },
            function () { root.waitFor = landed(path) },
            // The landing changes the rows, so a counter that saw no frame here would pass the zero above unseen.
            function () { root.waitUntil = Date.now() + 1000; root.waitFor = function () { return root.frames > root.keyFrames } },
            function () { check(name + ": the landing draws a frame", root.frames > root.keyFrames, true) }
        ]
    }
    // While a listing is out: a press, a band drag and a wheel notch over the rows land on nothing, hover still reaches a row.
    function refusedWhileOut() {
        var flick = root.view()
        var row = entryPoint(3), below = entryPoint(5)
        var cursor = pane.cursorIndex, contentY = flick.contentY, notes = root.loadingNotes, selected = pane.selectionCount()
        keys.mouseClick(pane, row.x, row.y, Qt.LeftButton, Qt.NoModifier, -1)
        check("out: a press over a row shows the loading note", root.loadingNotes, notes + 1)
        check("out: a press over a row moves no cursor", pane.cursorIndex, cursor)
        check("out: a press over a row changes no selection", pane.selectionCount(), selected)
        keys.mousePress(pane, below.x, below.y, Qt.LeftButton, Qt.NoModifier, -1)
        keys.mouseMove(pane, below.x + 40, row.y, -1, Qt.LeftButton, Qt.NoModifier)
        check("out: a drag over the rows starts no band", pane.selectionBand, null)
        keys.mouseRelease(pane, below.x + 40, row.y, Qt.LeftButton, Qt.NoModifier, -1)
        check("out: a band drag changes no selection", pane.selectionCount(), selected)
        keys.mouseWheel(pane, row.x, row.y, Qt.NoButton, Qt.NoModifier, 0, -120, -1)
        check("out: a wheel notch scrolls nothing", flick.contentY, contentY)
        keys.mouseMove(pane, row.x, row.y + 2, -1, Qt.NoButton, Qt.NoModifier)
        check("out: hover still reaches the row", flick.itemAtIndex(3).hovered, true)
    }
    function groundInA() { var last = entryPoint(2); return Qt.point(last.x, last.y + 3 * root.view().itemAtIndex(2).height) }
    // Once landed the same inputs reach the rows: a band from empty ground, a press on a row.
    function passedInA() {
        var row = entryPoint(1), ground = groundInA()
        keys.mousePress(pane, ground.x, ground.y, Qt.LeftButton, Qt.NoModifier, -1)
        keys.mouseMove(pane, ground.x + 30, row.y, -1, Qt.LeftButton, Qt.NoModifier)
        check("landed: a drag from empty ground starts a band", pane.selectionBand !== null, true)
        keys.mouseRelease(pane, ground.x + 30, row.y, Qt.LeftButton, Qt.NoModifier, -1)
        check("landed: the band ends on release", pane.selectionBand, null)
        keys.mouseClick(pane, row.x, row.y, Qt.LeftButton, Qt.NoModifier, -1)
        check("landed: a press on a row moves the cursor there", pane.cursorIndex, 1)
    }
    // The guard in ui/PaneStates.qml: the one MouseArea beside the pane's empty state, laid from the header down.
    function paneGuard() {
        var kids = pane.emptyState.parent.children, found = []
        for (var i = 0; i < kids.length; i++) if (kids[i].pressAndHoldInterval !== undefined) found.push(kids[i])
        return found.length === 1 && found[0].x === pane.listSlot.x && found[0].y === pane.header.y ? found[0] : null
    }
    // With the guard off, the band's own gate is all that refuses a drag from empty ground while a listing is out.
    function bandRefusedWhileOut(ground, row) {
        var guard = paneGuard()
        if (!guard) { fail("out: the PaneStates guard was not the one MouseArea at the header"); return }
        check("out: the held listing still reads ready, so only listInFlight closes the band", pane.listingState, "ready")
        guard.enabled = false
        keys.mousePress(pane, ground.x, ground.y, Qt.LeftButton, Qt.NoModifier, -1)
        keys.mouseMove(pane, ground.x + 30, row.y, -1, Qt.LeftButton, Qt.NoModifier)
        check("out: with the guard off a drag from empty ground starts no band", pane.selectionBand, null)
        keys.mouseRelease(pane, ground.x + 30, row.y, Qt.LeftButton, Qt.NoModifier, -1)
        guard.enabled = true
    }
    function wheelPasses() {
        var flick = root.view(), row = entryPoint(3)
        root.wheelFrom = flick.contentY
        keys.mouseWheel(pane, row.x, row.y, Qt.NoButton, Qt.NoModifier, 0, -120, -1)
        root.waitUntil = Date.now() + 400
        root.waitFor = function () { return flick.contentY > root.wheelFrom }
    }
    function bandRefusedOnEmpty() {
        var flick = root.view(), ground = flick.mapToItem(pane, flick.width / 2, flick.height / 2)
        keys.mousePress(pane, ground.x, ground.y, Qt.LeftButton, Qt.NoModifier, -1)
        keys.mouseMove(pane, ground.x + 60, ground.y + 60, -1, Qt.LeftButton, Qt.NoModifier)
        check("empty: a drag on an empty listing starts no band", pane.selectionBand, null)
        keys.mouseRelease(pane, ground.x + 60, ground.y + 60, Qt.LeftButton, Qt.NoModifier, -1)
        check("empty: and shows no loading note", root.loadingNotes, 0)
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
                function onFrameSwapped() { root.frames += 1 }
            }
        }
    }
    Process {
        id: signaller
        property bool done: false
        onExited: done = true
    }

    Component.onCompleted: {
        var a = fixture + "/a"
        steps = [
            function () { pane = paneComponent.createObject(win.contentItem); pane.open(fixture); root.waitFor = landed(fixture) },
            function () {
                check("the fixture is listed whole", pane.total, entries)
                check("the view is " + viewName, pane.viewMode, viewName)
                pane.listArea.forceActiveFocus()
            }
        ].concat(measured("enter", Qt.Key_Return, a), measured("back", Qt.Key_Backspace, fixture), [
            quiet,
            function () { signalBackend("STOP") },
            function () {
                keys.keyClick(Qt.Key_Return, Qt.NoModifier, -1)
                refusedWhileOut()
                signalBackend("CONT")
            },
            function () { root.waitFor = landed(a) },
            function () { check("out: the notes came only from the refused presses", root.loadingNotes, 2); passedInA(); signalBackend("STOP") },
            function () {
                var ground = groundInA(), row = entryPoint(1)
                keys.keyClick(Qt.Key_Backspace, Qt.NoModifier, -1)
                check("out: the listing is out after Back", pane.listInFlight, true)
                bandRefusedWhileOut(ground, row)
                signalBackend("CONT")
            },
            function () { root.loadingNotes = 0; root.waitFor = landed(fixture) },
            wheelPasses,
            function () { check("landed: a wheel notch scrolls the rows", view().contentY > root.wheelFrom, true) },
            function () { pane.open(fixture + "/e"); root.waitFor = landed(fixture + "/e") },
            function () { check("empty: the listing is empty", pane.listingState, "empty"); bandRefusedOnEmpty(); finish() }
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
            // Quiet: the rail settled, then 300 ms with no presented frame, so a measured key starts from rest.
            if (root.quietNeeded) {
                if (!root.railSettled()) {
                    root.quietMark = -1
                    if (Date.now() > root.railBy) {
                        root.fail("navframe: the rail never revealed its groups (railDeadlineElapsed still false after " + root.railWait + " ms)")
                        root.finish()
                    }
                    return
                }
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
