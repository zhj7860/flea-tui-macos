//@ pragma ShellId flea-slowsource-load-test

import QtQuick
import Quickshell

// One preview under the real PreviewSwap: fast (30 ms) never draws the loading state, slow (200 ms) draws it by 100 ms for 100 ms, and starve's 60 ms reply is taken in the busy turn the cap comes due in, so it lands before the overdue cap can fire.
ShellRoot {
    id: shell

    property string leg: Quickshell.env("SLOWSOURCE_LEG") || "fast"
    property int landMs: shell.leg === "slow" ? 200 : shell.leg === "starve" ? 60 : 30
    property bool hog: shell.leg === "starve"
    property double askAt: 0
    property double markAt: 0
    property bool simReady: true
    property var failures: []

    function stamp(line) { console.log("SLOWSOURCE " + line) }
    function fail(line) { shell.failures.push(line); shell.stamp("FAIL leg=" + shell.leg + " " + line) }
    function busy(ms) { var t0 = Date.now(); while (Date.now() - t0 < ms) {} }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }

    FloatingWindow {
        implicitWidth: 800
        implicitHeight: 560
        color: "#303030"

        Rectangle {
            id: host
            color: "#101315"
            x: 20
            y: 20
            width: 752
            height: 470

            Loader {
                id: swapLoader
                anchors.fill: parent
                source: "file://" + (Quickshell.env("SLOWSOURCE_UI") || "") + "/PreviewSwap.qml"
                onLoaded: {
                    item.burstEnds = false
                    item.ground = "#101315"
                }
                onStatusChanged: if (status === Loader.Error) { shell.fail("the swap did not load"); shell.quit() }
            }
        }
    }

    property var swap: swapLoader.item

    Rectangle {
        id: previewBody
        visible: false
        width: 752
        height: 470
        color: "#8a3a3a"
        Text {
            anchors.centerIn: parent
            text: "next"
            color: "white"
            font.pixelSize: 48
        }
    }

    function move() {
        var apply = function () { shell.simReady = false }
        var loaded = function () {
            shell.simReady = false
            shell.swap.start(false)
            shell.askAt = Date.now()
            shell.stamp("ask leg=" + shell.leg + " at=" + shell.askAt)
            landTimer.interval = shell.landMs
            landTimer.restart()
        }
        shell.swap.hold(apply, "/slowload\n0")
        shell.swap.hold(loaded, "/slowload\n0", true)
    }

    Timer {
        id: landTimer
        repeat: false
        onTriggered: {
            shell.stamp("reply-arrived leg=" + shell.leg + " at=" + Date.now())
            if (shell.hog) {
                shell.busy(70)
                shell.stamp("hog-done at=" + Date.now())
                // The cap comes due by 100 ms, so it is overdue when the reply is taken here.
                if (Date.now() - shell.askAt < 100)
                    shell.fail("the busy turn ended " + (Date.now() - shell.askAt) + " ms after the ask, before the cap came due")
                shell.deliver()
                return
            }
            shell.deliver()
        }
    }

    function deliver() {
        shell.simReady = true
        shell.stamp("ready leg=" + shell.leg + " at=" + Date.now())
        if (shell.swap)
            shell.swap.check()
        settleTimer.restart()
    }

    // The loading state is drawn in the first frame synchronised with the swap fallen back.
    Connections {
        target: host.Window.window
        function onAfterAnimating() {
            if (shell.markAt === 0 && shell.askAt > 0 && shell.swap && shell.swap.fellBack) {
                shell.markAt = Date.now()
                shell.stamp("mark-drawn at=" + shell.markAt)
            }
        }
    }

    Timer {
        id: settleTimer
        interval: 400
        repeat: false
        onTriggered: shell.finish()
    }

    function finish() {
        var s = shell.swap.describe()
        var stood = s.shownMs || 0
        shell.stamp("finish fallbacks=" + s.fallbacks + " shownMs=" + stood + " holding=" + s.holding)
        if (s.holding !== false)
            shell.fail("still holding at settle")
        if (shell.leg === "fast" || shell.leg === "starve") {
            if (s.fallbacks !== 0)
                shell.fail(s.fallbacks + " fallback(s) on a fast decode")
            if (shell.markAt !== 0)
                shell.fail("the loading state drew on a fast decode")
        }
        if (shell.leg === "slow") {
            if (s.fallbacks !== 1)
                shell.fail("a 200 ms source fell back " + s.fallbacks + " time(s), want 1")
            if (shell.markAt === 0)
                shell.fail("a 200 ms source never drew the loading state")
            else if (shell.markAt - shell.askAt > 100)
                shell.fail("the loading state drew " + (shell.markAt - shell.askAt) + " ms after the ask, past 100")
            if (stood < 100)
                shell.fail("the loading state stood " + stood + " ms, under 100")
        }
        if (shell.failures.length === 0)
            shell.stamp("DONE leg=" + shell.leg + " fallbacks=" + s.fallbacks + " shownMs=" + stood)
        shell.quit()
    }

    Timer {
        id: kickoff
        interval: 400
        repeat: false
        onTriggered: {
            if (!shell.swap) {
                shell.fail("no swap item to drive")
                shell.quit()
                return
            }
            previewBody.visible = true
            previewBody.parent = shell.swap.contentItem()
            shell.swap.ready = Qt.binding(function () { return shell.simReady })
            shell.move()
        }
    }

    Component.onCompleted: waitSwap.restart()

    Timer {
        id: waitSwap
        interval: 50
        repeat: true
        onTriggered: {
            if (swapLoader.item) {
                stop()
                kickoff.restart()
            }
        }
    }
}
