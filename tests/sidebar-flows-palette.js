// Sample input: the four colors.toml roles of stock tokyo-night, whose selected and normal fills differ.
var COLOURED_THEME = 'accent = "#7aa2f7"\nmuted = "#414868"\nbackground = "#1a1b26"\nforeground = "#a9b1d6"\n'

function snapshot(theme, color) {
    var colors = {}
    for (var role of ["foreground", "background", "accent", "urgent", "muted"]) colors[role] = String(color[role])
    return { palette: theme.palette, colors: colors }
}

// Color.loadColors keeps missing roles, so even an empty starting palette needs its effective OEM colors restored.
function withPalette(theme, color, body, run) {
    var before = snapshot(theme, color)
    try {
        theme.applyColors(body)
        return run()
    } finally {
        for (var role in before.colors) color[role] = before.colors[role]
        theme.applyColors(Object.keys(before.palette).map(function (key) { return key + ' = "' + before.palette[key] + '"' }).join("\n"))
        color.muted = before.colors.muted
    }
}

// The color-sensitive lit-place checks own their palette for this flow only.
function litPlace(root, pane, theme, style, color, driver) {
    var before = snapshot(theme, color)
    var result = withPalette(theme, color, COLOURED_THEME, function () {
        var rail = pane.sidebar
        rail.cursorIndex = root.railHome
        pane.focusView = "rail"
        root.check("lit-place: keyboard focus moves the fill and accent edge to the cursor, with no frame", [root.railIndices("frame"), root.railLit(), root.railIndices("edge")], [[], [root.railHome], [root.railHome]])
        root.check("lit-place: the keyboard cursor takes selectedFill and the current place is transparent", [Qt.colorEqual(root.railLook(rail.railItemFor(root.railHome)).color, style.selectedFill), root.railLook(rail.railItemFor(root.railRecent)).fill], [true, false])
        rail.cursorIndex = root.railTrash
        root.check("lit-place: the cursor on Trash takes the fill without changing its IPC current state", [root.railIndices("frame"), root.railLit(), root.ipc(true).trashRail().current], [[], [root.railTrash], false])
        root.check("lit-place: highlighted Trash takes selectedAccentFill and keeps its label in the foreground, as 0.3.9 drew it", [Qt.colorEqual(root.railLook(rail.railItemFor(root.railTrash)).color, style.selectedAccentFill), Qt.colorEqual(rail.railItemFor(root.railTrash).labelItem.color, theme.color.foreground)], [true, true])
        rail.cursorIndex = root.railRecent
        root.check("lit-place: the cursor on the current place draws one fill and no frame", [root.railIndices("frame"), root.railLit()], [[], [root.railRecent]])
        // Release past the drag threshold so the rail's PointHandler press never fires the row's tap.
        var litRow = rail.railItemFor(root.railRecent)
        driver.mousePress(litRow, litRow.width / 2, litRow.height / 2, Qt.LeftButton, Qt.NoModifier, 1)
        root.check("lit-place: a pointer press on the focused rail hides the keyboard highlight and keeps the current place", [rail.pointerFocus, root.railIndices("frame"), root.railLit()], [true, [], [root.railRecent]])
        driver.mouseMove(litRow, litRow.width * 3, litRow.height / 2, 1, Qt.LeftButton, Qt.NoModifier)
        driver.mouseRelease(litRow, litRow.width * 3, litRow.height / 2, Qt.LeftButton, Qt.NoModifier, 1)
        rail.pointerFocus = false
        // Trash always offers its menu, where Home's rows sit behind the Places menu switch.
        rail.openRailMenu(root.railTrash, Qt.point(40, 80))
        root.check("lit-place: a rail menu open on a row draws no frame there", [rail.menu.opened, rail.cursorIndex, root.railIndices("frame")], [true, root.railTrash, []])
        rail.menu.close()
        root.check("lit-place: closing the menu restores the keyboard fill on its row", [root.railIndices("frame"), root.railLit()], [[], [root.railTrash]])
        pane.focusView = "list"
        root.check("lit-place: giving up rail focus highlights only the current place with no frame", [root.railIndices("frame"), root.railLit(), root.railIndices("edge")], [[], [root.railRecent], [root.railRecent]])
        root.check("lit-place: an unfocused current place takes normalFill", Qt.colorEqual(root.railLook(rail.railItemFor(root.railRecent)).color, style.normalFill), true)
        pane.closeRecent()
        return true
    })
    root.check("lit-place: the starting palette and OEM roles are restored", snapshot(theme, color), before)
    return result
}
