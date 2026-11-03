//@ pragma ShellId flea-button-hueless-test

import QtQuick
import Quickshell
import "flea" as Flea
import "button-probe.js" as Probe
import "qml-probe.js" as QmlProbe

// tests/button-system.sh's third harness: where a theme's accent carries no colour (stock kanagawa and white) a focused set member (a chip or the Format segment) draws its own frame 2 px in the foreground, because an accent frame there would read as picked and a foreground hairline would read as current.
ShellRoot {
    id: shell

    // Quiet ticks, a count of frames and never time, before the window is up and the chips can take focus.
    readonly property int settleTicks: 4
    readonly property int tickMs: 16
    readonly property int outerTimeoutS: Number(Quickshell.env("BUTTONSYS_TIMEOUT_S")) || 60
    readonly property int capShare: 2
    readonly property int msPerSecond: 1000
    readonly property double startedAt: Date.now()
    readonly property int capMs: shell.outerTimeoutS * shell.msPerSecond / shell.capShare
    readonly property string rootDir: Quickshell.env("BUTTONSYS_ROOT") || ""
    // The thick own frame a focused member draws where a hairline would not read.
    readonly property int thick: 2

    property int checks: 0
    property int ticks: 0
    property var failures: []

    function log(line) { QmlProbe.log("HUELESS", line) }
    function check(name, actual, expected) { QmlProbe.checkLoud(shell, name, actual, expected) }
    function finish() {
        QmlProbe.logDone(shell)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    FloatingWindow {
        id: window
        implicitWidth: 400
        implicitHeight: 120
        color: "#303030"

        Item {
            anchors.fill: parent
            Flea.ProtocolChip { id: picked; x: 20; y: 10; label: "Picked"; picked: true }
            Flea.ProtocolChip { id: unpicked; x: 140; y: 10; label: "Unpicked" }
            Flea.SettingsSegment { id: format; x: 20; y: 60; options: ["7z", "zip"]; value: "7z"; tabStop: true }
            Item { id: parking; y: 100; width: 10; height: 10; focus: true }
        }
    }

    // The Format segment's current cell, the one that marks keyboard focus.
    function currentCell() {
        for (var i = 0; i < format.children.length; i++)
            if (format.children[i].current === true) return format.children[i]
        return null
    }
    // A focused segment frames its own current cell; nothing it draws, in the cell or beside it in the row, reaches past that cell.
    function segmentRead() {
        format.forceActiveFocus()
        var cell = shell.currentCell(), inside = true
        for (var i = 0; cell && i < cell.children.length; i++) {
            var k = cell.children[i]
            if (k.x < 0 || k.y < 0 || k.x + k.width > cell.width || k.y + k.height > cell.height) inside = false
        }
        // The row's children are its cells and its repeater; any other item is a frame drawn outside a cell.
        for (var j = 0; j < format.children.length; j++)
            if (format.children[j].current === undefined && format.children[j].delegate === undefined) inside = false
        var read = cell ? { frameColor: Probe.rgba(cell.border.color), frameWidth: cell.border.width, inside: inside } : null
        parking.forceActiveFocus()
        return read
    }

    // One theme: its accent has no colour, so each focused chip draws its own frame 2 px in the foreground, inward, and moves nothing.
    function hueless(name, body) {
        var c = Flea.Theme.color, rgba = Probe.rgba
        Flea.Theme.applyColors(body)
        parking.forceActiveFocus()
        var h = Flea.Theme.spacing.hairline
        var restCold = Probe.read(unpicked)
        var restWarm = Probe.read(picked)
        var cold = Probe.focusRead(unpicked)
        var warm = Probe.focusRead(picked)
        shell.check(name + ": the accent carries no colour", c.accentHasHue, false)
        shell.check(name + ": a resting picked member is one foreground hairline and an unpicked one a muted hairline",
                    [restWarm.frameColor, restWarm.frameWidth, restCold.frameColor, restCold.frameWidth], [rgba(c.foreground), h, rgba(c.mutedFrame), h])
        shell.check(name + ": a focused unpicked member draws its own frame 2 px in the foreground and keeps its muted label, with no ring item",
                    [cold.frameColor, cold.frameWidth, cold.ink, cold.ringItem], [rgba(c.foreground), shell.thick, rgba(c.muted), false])
        shell.check(name + ": a focused picked member draws its own frame 2 px in the foreground and keeps its label, with no ring item",
                    [warm.frameColor, warm.frameWidth, warm.ink, warm.ringItem], [rgba(c.foreground), shell.thick, rgba(c.foreground), false])
        shell.check(name + ": a focused member never reads as the picked one at rest", cold.frameWidth !== restWarm.frameWidth, true)
        shell.check(name + ": focus moves nothing on either member", [cold.box, cold.frameBox, cold.labelBox, warm.box, warm.frameBox, warm.labelBox],
                    [restCold.box, restCold.frameBox, restCold.labelBox, restWarm.box, restWarm.frameBox, restWarm.labelBox])
        shell.check(name + ": the wash lies inside the 2 px frame", [cold.washInsetX, cold.washShrink], [shell.thick, 2 * shell.thick])
        var seg = shell.segmentRead()
        shell.check(name + ": a focused Format segment draws its current cell's own frame 2 px in the foreground, nothing outside it",
                    seg ? [seg.frameColor, seg.frameWidth, seg.inside] : null, [rgba(c.foreground), shell.thick, true])
    }

    function run() {
        var c = Flea.Theme.color, rgba = Probe.rgba
        var inside = shell.rootDir.length > 0 && (Quickshell.env("HOME") || "").indexOf(shell.rootDir + "/") === 0
        shell.check("sandbox: HOME lies under the harness root", inside, true)
        if (!inside) { shell.finish(); return }
        Flea.Theme.applyColors(Probe.COLOURED_THEME)
        shell.check("tokyo-night's accent has a hue, apart from its foreground", [c.accentHasHue, rgba(c.accent) !== rgba(c.foreground)], [true, true])
        shell.hueless("kanagawa", Probe.KANAGAWA_THEME)
        shell.hueless("white", Probe.WHITE_THEME)
        Flea.Theme.applyColors(Probe.COLOURED_THEME)
        parking.forceActiveFocus()
        var back = Probe.focusRead(unpicked)
        shell.check("the coloured accent is back with its accent hairline focus frame", [c.accentHasHue, back.frameColor, back.frameWidth, back.ringItem], [true, rgba(c.accent), Flea.Theme.spacing.hairline, false])
        var seg = shell.segmentRead()
        shell.check("a focused Format segment on the coloured accent is its accent hairline", seg ? [seg.frameColor, seg.frameWidth, seg.inside] : null, [rgba(c.accent), Flea.Theme.spacing.hairline, true])
        shell.finish()
    }

    Timer {
        interval: shell.tickMs
        repeat: true
        running: true
        onTriggered: {
            if (Date.now() - shell.startedAt > shell.capMs) {
                shell.failures.push("the harness did not finish")
                shell.log("FAIL the harness did not finish")
                shell.finish()
                running = false
                return
            }
            shell.ticks += 1
            if (shell.ticks === shell.settleTicks) { running = false; shell.run() }
        }
    }
}
