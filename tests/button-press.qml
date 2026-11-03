//@ pragma ShellId flea-button-press-test

import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "flea/js/TextSize.js" as TextSize
import "button-probe.js" as Probe
import "qml-probe.js" as QmlProbe

// Native text stays fixed while the frame shrinks on whole pixels, only while the held point is inside.
ShellRoot {
    id: shell
    property int checks: 0
    property var failures: []
    readonly property var cases: [[12, false, false], [14, false, false], [12, true, false], [14, true, false], [12, false, true], [14, true, true]]
    property int caseIndex: 0
    property int phase: 0
    property double since: Date.now()
    readonly property double started: Date.now()
    property var restLabel: []
    property var restFrame: []
    property bool wholeFrames: true
    property bool fixedLabels: true
    property bool insetTransition: false
    property int activations: 0

    function log(line) { QmlProbe.log("PRESS", line) }
    function check(name, actual, expected) { QmlProbe.checkLoud(shell, "case " + shell.caseIndex + " " + name, actual, expected) }
    function finish() {
        pulse.running = false
        QmlProbe.logDone(shell)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
    function labelBox() {
        var label = Probe.find(button, "buttonLabel")
        var a = label.mapToItem(host, 0, 0), b = label.mapToItem(host, label.width, label.height)
        return [label.scale, a.x, a.y, b.x - a.x, b.y - a.y]
    }
    function frameBox() {
        var frame = Probe.find(button, "buttonFrame"), a = frame.mapToItem(button, 0, 0)
        return [a.x, a.y, frame.width, frame.height]
    }
    function sample() {
        var frame = shell.frameBox()
        shell.wholeFrames = shell.wholeFrames && frame.every(function (v) { return v === Math.round(v) })
        shell.fixedLabels = shell.fixedLabels && JSON.stringify(shell.labelBox()) === JSON.stringify(shell.restLabel)
        shell.insetTransition = shell.insetTransition || JSON.stringify(frame) !== JSON.stringify(shell.expectedPressedFrame())
    }
    function expectedPressedFrame() {
        var reduced = shell.cases[shell.caseIndex][2]
        var x = reduced ? 0 : Math.round(button.width * (1 - 0.96) / 2)
        var y = reduced ? 0 : Math.round(button.frameHeight * (1 - 0.96) / 2)
        return [x, shell.restFrame[1] + y, shell.restFrame[2] - 2 * x, shell.restFrame[3] - 2 * y]
    }
    function washAlpha() { return Probe.find(button, "buttonWash").color.a }
    function move(inside) { driver.mouseMove(button, inside ? button.width / 2 : -40, inside ? button.height / 2 : -40, 0, Qt.LeftButton, Qt.NoModifier) }
    function nextPhase() { shell.phase += 1; shell.since = Date.now() }

    FloatingWindow {
        implicitWidth: 360
        implicitHeight: 140
        color: "#303030"
        Item {
            id: host
            anchors.fill: parent
            Flea.DialogButton {
                id: button
                x: 30
                y: 30
                width: shell.caseIndex % 2 === 0 ? 154 : implicitWidth
                label: "Cancel"
                onActivated: shell.activations += 1
            }
            TestEvent { id: driver }
        }
    }

    Timer {
        id: pulse
        interval: 16
        repeat: true
        running: true
        onTriggered: shell.advance()
    }
    function advance() {
        if (Date.now() - shell.started > 20000) { shell.check("completed inside deadline", false, true); shell.finish(); return }
        var elapsed = Date.now() - shell.since
        if (shell.phase === 0) {
            var c = shell.cases[shell.caseIndex]
            Flea.ViewState.state = { display: { textSize: { mode: TextSize.nearest(c[0]) } } }
            Flea.Theme.reducedMotion = c[2]
            button.inStrip = c[1]
            shell.nextPhase()
        } else if (shell.phase === 1 && elapsed >= 250) {
            shell.restLabel = shell.labelBox()
            shell.restFrame = shell.frameBox()
            shell.wholeFrames = true
            shell.fixedLabels = true
            shell.insetTransition = false
            shell.check("rest frame is on whole pixels", shell.restFrame.every(function (v) { return v === Math.round(v) }), true)
            shell.check("rest label scale", shell.restLabel[0], 1)
            shell.check("rest frame rounds the control size", shell.restFrame.slice(2), [Math.round(button.width), Math.round(button.frameHeight)])
            driver.mousePress(button, button.width / 2, button.height / 2, Qt.LeftButton, Qt.NoModifier, 0)
            shell.nextPhase()
            // Sample before the first animation tick: a 1 px inset has no whole-pixel midpoint.
            shell.sample()
        } else if (shell.phase === 2) {
            shell.sample()
            if (elapsed < 300) return
            shell.check("held point inside is pressed", button.pressed, true)
            shell.check("held label never transforms, including mid-animation", shell.fixedLabels, true)
            shell.check("rest, mid-animation and settled frame stay whole", shell.wholeFrames, true)
            shell.check(shell.cases[shell.caseIndex][2] ? "reduced motion snaps without inset transition" : "press inset transitions before settling", shell.insetTransition, !shell.cases[shell.caseIndex][2])
            shell.check("pressed frame uses whole pixel insets", shell.frameBox(), shell.expectedPressedFrame())
            shell.check("inside press wash is 14 percent", Math.abs(shell.washAlpha() - 0.14) < 0.002, true)
            shell.move(false)
            shell.nextPhase()
        } else if (shell.phase === 3 && elapsed >= 300) {
            shell.check("held outside has no wash", shell.washAlpha(), 0)
            shell.check("held outside frame returns to rest", shell.frameBox(), shell.restFrame)
            shell.check("held outside label stays fixed", shell.labelBox(), shell.restLabel)
            shell.move(true)
            shell.nextPhase()
        } else if (shell.phase === 4 && elapsed >= 300) {
            shell.check("held back inside presses again", Math.abs(shell.washAlpha() - 0.14) < 0.002, true)
            shell.check("held back inside shrinks frame again", shell.frameBox(), shell.expectedPressedFrame())
            driver.mouseRelease(button, -40, -40, Qt.LeftButton, Qt.NoModifier, 0)
            shell.nextPhase()
        } else if (shell.phase === 5 && elapsed >= 300) {
            shell.check("release outside never activates", shell.activations, 0)
            shell.check("released frame returns to rest", shell.frameBox(), shell.restFrame)
            shell.check("released label stays fixed", shell.labelBox(), shell.restLabel)
            shell.caseIndex += 1
            if (shell.caseIndex === shell.cases.length) { shell.finish(); return }
            shell.phase = 0
        }
    }
}
