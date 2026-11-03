//@ pragma ShellId flea-pdf-idle-test

import Quickshell
import QtQuick

// r35-pdfidle: the real PreviewPdf and PdfViewer open an idle press early, hold walks and busy renders for the settle.
ShellRoot {
    id: shell

    readonly property string uiDir: Quickshell.env("PDF_IDLE_UI")
    readonly property string pdfA: Quickshell.env("PDF_IDLE_A")
    readonly property string pdfB: Quickshell.env("PDF_IDLE_B")
    readonly property string pdfHeavy: Quickshell.env("PDF_IDLE_HEAVY")
    readonly property string pdfC: Quickshell.env("PDF_IDLE_C")

    // Fails a stage past its press, so a press never waits unseen on a loading page.
    readonly property int openTimeoutMs: 5000
    // The heavy document trails its press past the plain timeout, so it waits longer.
    readonly property int heavyOpenTimeoutMs: 10000
    // The heavy render is only known loading once seen, so its wait is the longest.
    readonly property int heavyRenderTimeoutMs: 15000
    // Idle again before the heavy document, past the settle, so only the render can hold it.
    readonly property int reidleMs: 300

    property var failures: []
    property int stage: 0
    property double mark: 0
    property double pressedAt: 0
    property double secondPressedAt: 0
    // When the column's open last landed, stamped on the change, so the check measures the landing, not the tick.
    property double landedAt: 0
    // The surface's fastOpens before a press, so each open is read as fast path or settle by count.
    property int fastBase: 0
    property bool armedAfterFirst: false
    property string armedFor: ""
    // Presented frames, counted on the window's frameSwapped; the probe connects before any arm.
    property int frameCount: 0
    property int pressFrame: -1
    property int openFrame: -1
    property var openedLog: []
    property bool pulse: false

    function log(line) { console.log("PDFIDLE " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(name, cond) {
        log((cond ? "PASS " : "FAIL ") + name)
        if (!cond)
            failures.push(name)
    }
    function done() {
        log("DONE failures=" + failures.length)
        quit()
    }
    // The PreviewPdf under a surface: the column Loader item itself, or PdfViewer's inner page.
    function innerPdf(item) {
        if (!item)
            return null
        if (item.opened !== undefined && typeof item.fastOpens === "number"
                && item.pageItem !== undefined)
            return item
        var kids = item.children || []
        for (var i = 0; i < kids.length; i++) {
            var found = shell.innerPdf(kids[i])
            if (found)
                return found
        }
        return null
    }
    function colPdf() { return columnLoader.item }
    function colPage() { return columnLoader.item ? columnLoader.item.pageItem : null }
    // True while a render is in flight; fails the stage past the open timeout, so a press never lands on a loading page.
    function renderHeld(since, name, view) {
        var page = view || shell.colPage()
        if (!page || page.status !== Image.Loading)
            return false
        if (Date.now() - since > shell.openTimeoutMs)
            shell.check(name, false), shell.done()
        return true
    }

    FloatingWindow {
        id: win
        implicitWidth: 800
        implicitHeight: 560
        color: "#303030"

        // Counts presented frames for the open ordering, see shell.frameCount.
        Item {
            id: frameProbe
            Connections {
                target: frameProbe.Window.window
                function onFrameSwapped() { shell.frameCount += 1 }
            }
        }

        Loader {
            id: columnLoader
            x: 20; y: 20; width: 360; height: 470
            source: "file://" + shell.uiDir + "/PreviewPdf.qml"
            onLoaded: { item.active = true }
            onStatusChanged: if (status === Loader.Error) { shell.check("the column surface loads", false); shell.done() }
        }

        Loader {
            id: quickLoader
            x: 400; y: 20; width: 360; height: 470
            source: "file://" + shell.uiDir + "/PdfViewer.qml"
            onLoaded: { item.active = true }
            onStatusChanged: if (status === Loader.Error) { shell.check("the Quick Look surface loads", false); shell.done() }
        }
    }

    // Every opened value the column takes, so a cancelled open is seen even if it never settles.
    Connections {
        target: columnLoader.item
        function onOpenedChanged() {
            // Stamped on the landing, so the settle check measures the open, not the tick.
            shell.landedAt = Date.now()
            if (shell.pressFrame >= 0 && shell.openFrame < 0 && columnLoader.item.opened === shell.armedFor)
                shell.openFrame = shell.frameCount
            shell.openedLog.push(columnLoader.item.opened)
        }
    }

    Timer {
        id: tick
        interval: 5
        running: true
        repeat: true
        onTriggered: shell.step()
    }

    function step() {
        var now = Date.now()
        if (shell.stage === 0) {
            if (!columnLoader.item)
                return
            shell.armedFor = shell.pdfA
            shell.pressFrame = shell.frameCount
            shell.openFrame = -1
            shell.openedLog = []
            // A pulse schedules a frame after the press, so the open has a frame to wait for.
            shell.pulse = !shell.pulse
            win.color = shell.pulse ? "#313131" : "#303030"
            shell.fastBase = columnLoader.item.fastOpens
            columnLoader.item.path = shell.pdfA
            shell.pressedAt = now
            shell.stage = 1
        } else if (shell.stage === 1) {
            if (columnLoader.item.opened !== shell.pdfA) {
                if (now - shell.pressedAt > shell.openTimeoutMs)
                    shell.check("the isolated document opens at all", false), shell.done()
                return
            }
            shell.check("an isolated press opens on the fast path", columnLoader.item.fastOpens === shell.fastBase + 1)
            shell.check("the open waits for the first frame after the press", shell.openFrame > shell.pressFrame)
            shell.mark = now
            shell.stage = 2
        } else if (shell.stage === 2) {
            // The walk starts idle, page rendered and settle passed, so only the walk itself can hold a step.
            var shown = shell.colPage()
            if (!shown || shown.status !== Image.Ready || now - columnLoader.item.lastRequestAt <= columnLoader.item.settleMs) {
                if (now - shell.mark > shell.openTimeoutMs)
                    shell.check("the first page renders before the walk", false), shell.done()
                return
            }
            // Two walk steps in one turn: the first arms the idle path, the second lands inside the settle.
            shell.openedLog = []
            shell.fastBase = columnLoader.item.fastOpens
            columnLoader.item.path = shell.pdfC
            shell.armedAfterFirst = columnLoader.item.fastArmed
            columnLoader.item.path = shell.pdfB
            shell.check("the first walk step arms the idle path", shell.armedAfterFirst === true)
            shell.check("the next step inside the settle drops it", columnLoader.item.fastArmed === false)
            shell.pressedAt = now
            shell.stage = 3
        } else if (shell.stage === 3) {
            if (columnLoader.item.opened !== shell.pdfB) {
                if (now - shell.pressedAt > shell.openTimeoutMs)
                    shell.check("the walk lands on the second document", false), shell.done()
                return
            }
            // landedAt is stamped on the open, so the landing proves the settle wait with no bare constant.
            shell.check("a walk press waits for the settle", shell.landedAt - columnLoader.item.lastRequestAt >= columnLoader.item.settleMs)
            shell.stage = 4
        } else if (shell.stage === 4) {
            if (columnLoader.item.opened !== shell.pdfB) {
                if (now - shell.pressedAt > shell.openTimeoutMs)
                    shell.check("the walk lands on the second document", false), shell.done()
                return
            }
            shell.check("the walk lands on the second document", true)
            shell.check("the walk opens at the settle, never the fast path", columnLoader.item.fastOpens === shell.fastBase)
            shell.check("the passed-over step never opens", shell.openedLog.indexOf(shell.pdfC) < 0)
            shell.mark = now
            shell.stage = 5
        } else if (shell.stage === 5) {
            // Idle again before the heavy document, so only the render can still hold it.
            if (now - shell.mark < shell.reidleMs)
                return
            columnLoader.item.path = shell.pdfHeavy
            shell.pressedAt = now
            shell.stage = 6
        } else if (shell.stage === 6) {
            if (columnLoader.item.opened !== shell.pdfHeavy) {
                if (now - shell.pressedAt > shell.heavyOpenTimeoutMs)
                    shell.check("the heavy document opens at all", false), shell.done()
                return
            }
            shell.log("heavy opened after " + Math.round(now - shell.pressedAt) + " ms")
            shell.pressedAt = now
            shell.stage = 7
        } else if (shell.stage === 7) {
            var page = shell.colPage()
            if (!page || page.status !== Image.Loading) {
                if (now - shell.pressedAt > shell.heavyRenderTimeoutMs)
                    shell.check("the heavy render is seen loading", false), shell.done()
                return
            }
            // A switch while the first render is in flight takes the settle, never the fast path.
            shell.fastBase = columnLoader.item.fastOpens
            columnLoader.item.path = shell.pdfB
            shell.pressedAt = now
            shell.stage = 8
        } else if (shell.stage === 8) {
            if (columnLoader.item.opened !== shell.pdfB) {
                if (now - shell.pressedAt > shell.openTimeoutMs)
                    shell.check("the held switch lands at the settle", false), shell.done()
                return
            }
            // As in stage 3, the landing proves the settle wait with no bare constant.
            shell.check("a switch with a live render waits for the settle", shell.landedAt - columnLoader.item.lastRequestAt >= columnLoader.item.settleMs)
            // Fresh mark, so the settle wait below fails only on a render held past it.
            shell.mark = now
            shell.stage = 9
        } else if (shell.stage === 9) {
            if (columnLoader.item.opened !== shell.pdfB) {
                if (now - shell.pressedAt > shell.openTimeoutMs)
                    shell.check("the held switch lands at the settle", false), shell.done()
                return
            }
            // The column page lands first, so the Quick Look press below is isolated from its render.
            var live = shell.colPage()
            if (!live || live.status === Image.Loading || columnLoader.item.shownPage < 0) {
                if (now - shell.mark > shell.openTimeoutMs)
                    shell.check("the column render settles before the Quick Look press", false), shell.done()
                return
            }
            shell.check("the held switch lands at the settle", columnLoader.item.fastOpens === shell.fastBase)
            var quick = shell.innerPdf(quickLoader.item)
            if (quick) {
                // A pulse schedules a frame after the press, so the open has a frame to wait for.
                shell.pulse = !shell.pulse
                win.color = shell.pulse ? "#313131" : "#303030"
                shell.fastBase = quick.fastOpens
                quick.path = shell.pdfA
                shell.pressedAt = now
                // Fresh mark, so the cancel guard below fails only on a render held past it.
                shell.mark = now
                shell.stage = 10
            } else {
                shell.check("Quick Look reaches the shared rule", false)
                shell.done()
            }
        } else if (shell.stage === 10) {
            // The guard reads Quick Look's own page, not the column's, so it waits until Quick Look holds one.
            var target = shell.innerPdf(quickLoader.item)
            if (!target || target.opened !== shell.pdfA || !target.pageItem) {
                if (now - shell.pressedAt > shell.openTimeoutMs)
                    shell.check("Quick Look opens an isolated press on the fast path", false), shell.done()
                return
            }
            if (shell.renderHeld(shell.mark, "the page render settles before the cancel press", target.pageItem))
                return
            shell.check("Quick Look opens an isolated press on the fast path", target.fastOpens === shell.fastBase + 1)
            // A second request in the same turn cancels the first open: both sets run before any frame.
            shell.armedFor = shell.pdfA
            shell.pressFrame = shell.frameCount
            shell.openFrame = -1
            shell.openedLog = []
            shell.fastBase = columnLoader.item.fastOpens
            columnLoader.item.path = shell.pdfC
            // The first step arms the frame path; a press taken by the render gate would stay disarmed.
            shell.check("the cancel press arms the frame path", columnLoader.item.fastArmed === true)
            columnLoader.item.path = shell.pdfA
            // A frame presents while disarmed, so the cancel holds against a real frame.
            shell.pulse = !shell.pulse
            win.color = shell.pulse ? "#313131" : "#303030"
            shell.secondPressedAt = now
            shell.stage = 11
        } else if (shell.stage === 11) {
            if (columnLoader.item.opened !== shell.pdfA) {
                if (now - shell.secondPressedAt > shell.openTimeoutMs)
                    shell.check("the second request opens at the settle", false), shell.done()
                return
            }
            shell.check("the second request opens at the settle", true)
            var sawC = false
            for (var i = 0; i < shell.openedLog.length; i++)
                if (shell.openedLog[i] === shell.pdfC)
                    sawC = true
            shell.check("the cancelled first open never lands", !sawC)
            shell.check("the cancelled open waits for the settle, never the fast path",
                columnLoader.item.fastOpens === shell.fastBase)
            shell.mark = now
            shell.stage = 12
        } else if (shell.stage === 12) {
            // A render of the first page still in flight would take the render gate, not the idle arm.
            if (shell.renderHeld(shell.mark, "the page render settles before the hidden press"))
                return
            // A window that never swaps still opens at the settle: hidden, no frame presents.
            shell.armedFor = shell.pdfC
            shell.pressFrame = shell.frameCount
            shell.openFrame = -1
            shell.openedLog = []
            win.visible = false
            shell.fastBase = columnLoader.item.fastOpens
            columnLoader.item.path = shell.pdfC
            shell.check("the hidden press takes the idle arm", columnLoader.item.fastArmed === true)
            shell.pressedAt = now
            shell.stage = 13
        } else if (shell.stage === 13) {
            if (columnLoader.item.opened !== shell.pdfC) {
                if (now - shell.pressedAt > shell.openTimeoutMs)
                    shell.check("a hidden window still opens at the settle", false), shell.done()
                return
            }
            shell.check("a hidden window still opens at the settle", true)
            shell.check("that open waits for the settle, never a frame", columnLoader.item.fastOpens === shell.fastBase)
            shell.check("no frame presents before that open", shell.openFrame === shell.pressFrame)
            shell.done()
        }
    }
}
