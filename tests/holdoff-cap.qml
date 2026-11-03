//@ pragma ShellId flea-holdoff-cap-test

import Quickshell
import QtQuick
import "flea" as Flea
import "flea/js/Swap.js" as Swap

// The real ui/PreviewPdf.qml: its render cap reads Swap.CAP_MS, a loading state drawn stands Swap.MIN_SHOW_MS before the page that landed shows, and a page landing before the cap draws no loading state.
ShellRoot {
    id: shell

    readonly property string lightPdf: Quickshell.env("HOLDOFF_LIGHT")
    readonly property string heavyPdf: Quickshell.env("HOLDOFF_HEAVY")
    property var failures: []
    property var passes: []
    // Frames swapped with a loading state up, and polls that saw a page shown over it or a minimum timer that had let go early.
    property int loadingFrames: 0
    property int pageOverLoading: 0
    property int releasedEarly: 0
    // Samples of a turn made under a standing minimum: renders in flight, and how many of those still had the old minimum timer running.
    property bool reTurning: false
    property int pendingSamples: 0
    property int minimumDuringRender: 0
    property var watched: null
    // The step in flight: a condition polled every few milliseconds, what to run when it holds, and the polls left.
    property var waiting: null

    function log(line) { console.log("HOLDOFF " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(name, ok, detail) {
        if (ok) { shell.passes.push(name); shell.log("ok " + name) }
        else { shell.failures.push(name); shell.log("FAIL " + name + (detail ? ": " + detail : "")) }
    }
    function finish() {
        shell.log(shell.failures.length === 0 ? "DONE checks=" + shell.passes.length : "FAIL " + shell.failures.length + " check(s)")
        shell.quit()
    }

    // The timer a surface names by objectName, found among its declared children.
    function timerOf(item, name) {
        for (var i = 0; i < item.data.length; i++)
            if (item.data[i].objectName === name) return item.data[i]
        return null
    }
    function loadingUp(item) {
        var kids = item.children
        for (var i = 0; i < kids.length; i++)
            if (String(kids[i]).indexOf("LoadingState") === 0 && kids[i].visible && (kids[i].armed || kids[i].heldOff)) return true
        return false
    }

    // A box too slow to land a one-rectangle page inside the limit proves nothing about the content that does; the first field counts the checks left out.
    function slowBox(ms, skipped, limit) {
        if (ms < limit)
            return false
        shell.log("SKIP " + skipped + " a light page took " + ms + " ms, past " + limit + " ms, so it says nothing about landing before it")
        return true
    }
    // A render in flight for a page no earlier render cached: the old minimum timer must already be stopped when its status changes to Loading.
    function sampleReTurn(item) {
        if (!shell.reTurning || item.pageItem.status !== Image.Loading || item.pageItem.currentFrame === item.shownPage)
            return
        shell.pendingSamples += 1
        if (shell.timerOf(item, "renderMin").running) shell.minimumDuringRender += 1
    }

    // One step waits for its condition, polled every 4 ms; the poll counters feed the checks above and only a swapped frame counts as a frame.
    function until(label, cond, then, polls) {
        shell.waiting = { label: label, cond: cond, then: then, left: polls || 1500 }
    }
    function poll() {
        var item = shell.watched
        if (item !== null) {
            var minimum = shell.timerOf(item, "renderMin")
            if (item.fellBack && item.pageItem.visible) shell.pageOverLoading += 1
            if (minimum !== null && minimum.running && !item.fellBack) shell.releasedEarly += 1
        }
        var step = shell.waiting
        if (step === null) return
        if (step.cond()) { shell.waiting = null; step.then(); return }
        step.left -= 1
        if (step.left <= 0) { shell.waiting = null; shell.check(step.label, false, "never held"); shell.finish() }
    }
    Timer { interval: 4; running: true; repeat: true; onTriggered: shell.poll() }

    // Sampled at the page's own status change, after the surface's handler, so no poll can miss a render that lands in a few milliseconds.
    Connections {
        target: shell.reTurning ? light.pageItem : null
        function onStatusChanged() { shell.sampleReTurn(light) }
    }

    Connections {
        target: host.Window.window
        function onFrameSwapped() {
            var item = shell.watched
            if (item !== null && shell.loadingUp(item)) shell.loadingFrames += 1
        }
    }

    FloatingWindow {
        implicitWidth: 1560
        implicitHeight: 560
        color: "#303030"

        Rectangle {
            id: host
            color: "#101315"
            x: 20
            y: 20
            width: 1520
            height: 470

            Flea.PreviewPdf {
                id: light
                x: 0
                width: 740
                height: 470
                path: shell.lightPdf
                active: true
            }

            Flea.PreviewPdf {
                id: heavy
                x: 760
                width: 740
                height: 470
                path: shell.heavyPdf
                active: false
            }
        }
    }

    Component.onCompleted: shell.until("the light document shows its first page", function () { return light.shownPage === 0 && light.pageCount === 4 }, shell.stepCap, 2500)

    // The cap's Timer reads the listing swap's cap, and a surface with a page up has no loading state.
    function stepCap() {
        var cap = shell.timerOf(light, "renderCap")
        shell.check("the render cap Timer reads Swap.CAP_MS", cap !== null && cap.interval === Swap.CAP_MS, cap ? "interval " + cap.interval : "no Timer named renderCap")
        shell.check("a page shown draws no loading state", light.fellBack === false && shell.loadingUp(light) === false)
        shell.watched = light
        shell.loadingFrames = 0
        shell.pageOverLoading = 0
        shell.releasedEarly = 0
        shell.turnBefore()
    }

    // A light page lands before the cap: no frame draws the loading state, and the cap has stopped.
    property double turnedAt: 0
    function turnBefore() {
        shell.turnedAt = Date.now()
        light.turn(1)
        shell.until("a light page lands", function () { return light.shownPage === 1 }, function () {
            var cap = shell.timerOf(light, "renderCap")
            if (!shell.slowBox(Date.now() - shell.turnedAt, 1, Swap.CAP_MS)) {
                shell.check("a page landing before the cap draws no loading state", shell.loadingFrames === 0 && light.fellBack === false && cap.running === false,
                            "loading frames " + shell.loadingFrames + " fellBack " + light.fellBack + " cap running " + cap.running)
            }
            shell.afterBefore()
        })
    }

    // Loading is up and the page lands a frame later: it stands, renderMin owes the rest, and a turn to an unrendered page stops renderMin.
    property double stamp: 0
    function afterBefore() {
        shell.stamp = Date.now()
        light.fellBackAt = shell.stamp
        light.fellBack = true
        shell.loadingFrames = 0
        shell.pageOverLoading = 0
        shell.releasedEarly = 0
        light.turn(1)
        shell.until("the next light page lands", function () { return light.shownPage === 2 }, function () {
            var minimum = shell.timerOf(light, "renderMin")
            var owed = Swap.showLeft(shell.stamp, Date.now())
            // Past Swap.MIN_SHOW_MS by the landing, the loading state has already gone and there is no minimum left to owe.
            var slow = shell.slowBox(Date.now() - shell.stamp, 3, Swap.MIN_SHOW_MS)
            if (!slow) {
                shell.check("a page landing under a drawn loading state leaves it up", light.fellBack === true && light.pageItem.visible === false && shell.loadingUp(light) === true,
                            "fellBack " + light.fellBack + " page visible " + light.pageItem.visible)
                shell.check("and its minimum timer owes the rest of Swap.MIN_SHOW_MS", minimum.running === true && minimum.interval >= owed && minimum.interval <= Swap.MIN_SHOW_MS,
                            "running " + minimum.running + " interval " + minimum.interval + " owed " + owed)
            }
            shell.pendingSamples = 0
            shell.minimumDuringRender = 0
            shell.reTurning = true
            light.turn(1)
            shell.until("the re-turned light page lands", function () { return light.shownPage === 3 }, function () {
                shell.reTurning = false
                if (!slow) {
                    shell.check("a turn made under the minimum stops that timer for its own render", shell.pendingSamples > 0 && shell.minimumDuringRender === 0,
                                "renders sampled " + shell.pendingSamples + " with the old minimum running " + shell.minimumDuringRender)
                }
                shell.until("the minimum ends", function () { return light.fellBack === false }, shell.afterMinimum, 400)
            })
        })
    }

    function afterMinimum() {
        shell.check("the page shows once the minimum timer lets go, never before", light.pageItem.visible === true && shell.pageOverLoading === 0 && shell.releasedEarly === 0 && shell.timerOf(light, "renderMin").running === false,
                    "page over loading " + shell.pageOverLoading + " released early " + shell.releasedEarly)
        shell.check("and the loading state stood in frames until then", shell.loadingFrames > 0, "loading frames " + shell.loadingFrames)
        // A loading state that already stood its minimum goes at the landing.
        light.fellBackAt = Date.now() - Swap.MIN_SHOW_MS - 5
        light.fellBack = true
        shell.loadingFrames = 0
        light.turn(-1)
        shell.until("the earlier light page lands again", function () { return light.shownPage === 2 }, function () {
            shell.check("a loading state that stood its minimum goes at the landing", light.fellBack === false && light.pageItem.visible === true && shell.timerOf(light, "renderMin").running === false,
                        "fellBack " + light.fellBack + " minimum running " + shell.timerOf(light, "renderMin").running)
            shell.stepHeavy()
        })
    }

    // A page that renders past the cap: the cap runs at Swap.CAP_MS, the loading state goes up with the page down, and its stamp is set.
    function stepHeavy() {
        shell.watched = heavy
        shell.loadingFrames = 0
        shell.pageOverLoading = 0
        shell.releasedEarly = 0
        heavy.active = true
        shell.until("the heavy document shows its first page", function () { return heavy.shownPage === 0 && heavy.pageCount === 2 }, function () {
            var cap = shell.timerOf(heavy, "renderCap")
            heavy.turn(1)
            shell.until("the cap starts for the heavy page", function () { return cap.running === true || heavy.fellBack === true }, function () {
                shell.check("a render past the cap runs the cap at Swap.CAP_MS", cap.interval === Swap.CAP_MS, "interval " + cap.interval)
                shell.until("the heavy page falls back", function () { return heavy.fellBack === true }, function () {
                    shell.check("a page not rendered by the cap draws the loading state in its place", heavy.pageItem.visible === false && heavy.fellBackAt > 0 && shell.loadingUp(heavy) === true,
                                "page visible " + heavy.pageItem.visible + " stamp " + heavy.fellBackAt)
                    shell.until("a frame draws it", function () { return shell.loadingFrames > 0 }, function () {
                        shell.check("and a frame draws it with no page over it", shell.pageOverLoading === 0, "page over loading " + shell.pageOverLoading)
                        shell.finish()
                    }, 600)
                }, 1000)
            }, 600)
        }, 2500)
    }
}
