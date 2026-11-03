//@ pragma ShellId flea-rail-highlight-test

import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import "flea" as Flea
import "sidebar-flows-palette.js" as PaletteFlow

// The real Sidebar chooses one visual row while keeping the current-place identity separate.
ShellRoot {
    id: shell
    property int checks: 0
    property int failures: 0
    function check(name, actual, expected) {
        shell.checks += 1
        var same = JSON.stringify(actual) === JSON.stringify(expected)
        if (!same) shell.failures += 1
        console.log("RAIL_HIGHLIGHT " + (same ? "ok " : "FAIL ") + name + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }
    function look(row) {
        var out = { fill: false, edge: false, frame: false, color: "transparent" }
        for (var i = 0; i < row.children.length; i++) {
            var c = row.children[i]
            if (c.color === undefined || c.border === undefined || !c.visible) continue
            if (c.color.a === 0) out.frame = out.frame || (c.width < row.width && c.height === row.height)
            else if (c.width === Flea.Theme.spacing.hairline * 2) out.edge = true
            else if (c.width === row.width && c.opacity === 1) { out.fill = true; out.color = c.color }
        }
        return out
    }
    function indices(part) {
        var out = []
        for (var i = 0; i < rail.entries.length; i++) {
            var row = rail.railItemFor(i)
            if (row && shell.look(row)[part]) out.push(i)
        }
        return out
    }
    FloatingWindow {
        implicitWidth: 260
        implicitHeight: 500
        Flea.Sidebar { id: rail; anchors.fill: parent; polling: false; menu: menu }
    }
    QtObject { id: menu; property bool opened: false; property bool forRail: true }
    Component.onCompleted: Flea.ViewState.state = { places: { showHome: true, showRecent: true, showTrash: true, showNetwork: false, showDevices: false } }
    Timer {
        interval: 1200
        running: true
        onTriggered: {
            PaletteFlow.withPalette(Flea.Theme, Commons.Color, PaletteFlow.COLOURED_THEME, function () {
                shell.check("selectedFill differs from normalFill", !Qt.colorEqual(Style.selectedFill, Style.normalFill), true)
                shell.check("two rows are drawn", rail.entries.length >= 2, true)
                if (rail.entries.length >= 2) {
                    rail.litIndex = 0
                    rail.cursorIndex = 1
                    rail.focused = true
                    shell.check("focused cursor fill", shell.indices("fill"), [1])
                    shell.check("focused cursor edge", shell.indices("edge"), [1])
                    shell.check("focused rows have no frame", shell.indices("frame"), [])
                    shell.check("focused selectedFill and transparent current place", [Qt.colorEqual(shell.look(rail.railItemFor(1)).color, Style.selectedFill), shell.look(rail.railItemFor(0)).fill], [true, false])
                    rail.focused = false
                    shell.check("unfocused current-place fill", shell.indices("fill"), [0])
                    shell.check("unfocused current-place edge", shell.indices("edge"), [0])
                    shell.check("unfocused rows have no frame", shell.indices("frame"), [])
                    shell.check("unfocused normalFill and transparent cursor", [Qt.colorEqual(shell.look(rail.railItemFor(0)).color, Style.normalFill), shell.look(rail.railItemFor(1)).fill], [true, false])
                    rail.focused = true
                    menu.opened = true
                    shell.check("open menu suppresses keyboard highlight", [shell.indices("fill"), shell.indices("frame")], [[0], []])
                    menu.opened = false
                    shell.check("closed menu restores keyboard fill", shell.indices("fill"), [1])
                    rail.pointerFocus = true
                    shell.check("pointer suppresses keyboard highlight", [shell.indices("fill"), shell.indices("frame")], [[0], []])
                    rail.pointerFocus = false
                    var trashAt = rail.entries.findIndex(function (e) { return e.kind === "trash" })
                    rail.cursorIndex = trashAt
                    shell.check("focused Trash cursor fill", [trashAt > 1, shell.indices("fill")], [true, [trashAt]])
                }
            })
            console.log("RAIL_HIGHLIGHT DONE checks=" + shell.checks + " failed=" + shell.failures)
            Quickshell.execDetached(["kill", String(Quickshell.processId)])
        }
    }
}
