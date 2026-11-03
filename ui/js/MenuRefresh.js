.pragma library
.import "MenuContext.js" as MenuContext

// What a provider refresh does to an open menu: the answers it draws, whether a rebuild changes anything, where the cursor lands.

// The provider inputs off ui/ContextMenu.qml's own properties; the peers are the service's, not gated by the row.
function live(menu) {
    return MenuContext.live(menu)
}

// A finished refresh's answer, which the menu keeps drawing while the next refresh runs behind it.
function settle(answer) {
    return MenuContext.settle(answer)
}

// A kept answer for the same install state stands in while a refresh runs, e.g. now { refreshing: true, taildropPeers: [], dropboxPath: "", ... }.
function providerView(known, now) {
    return MenuContext.providerView(known, now)
}

// Whether a rebuilt inventory is exactly what is drawn, so an answer that changed nothing resets no row.
function unchanged(previous, next) {
    return JSON.stringify(previous) === JSON.stringify(next)
}

// Release or flyout close schedules the rebuild after tapped dispatch, so the original handler can finish choosing.
function pressChanged(menu, pressed) {
    if (!pressed && menu.refreshOwed)
        Qt.callLater(function() { if (menu.refreshOwed) menu.refreshProviderRows() })
}

// Only live delegates can hold a refresh; a destroyed pressed row leaves no state behind. A null flyout is a closed one, whose held rows only fade.
function anyPressed(main, flyout) {
    var repeaters = flyout === null ? [main] : [main, flyout]
    for (var group = 0; group < repeaters.length; group++) {
        var rows = repeaters[group]
        for (var i = 0; i < rows.count; i++) {
            var row = rows.itemAt(i)
            if (row && row.pressed) return true
        }
    }
    return false
}

// Preserve action and peer identity when refreshed capabilities change the inventory beneath the keyboard cursor.
function refreshedCursor(previous, next, cursor, submenuRow, submenuCursor) {
    var action = previous[cursor] ? previous[cursor].action : ""
    var selected = action ? next.findIndex(function(entry) { return entry.action === action }) : -1
    if (selected < 0) {
        selected = Math.min(Math.max(0, cursor), next.length - 1)
        while (selected < next.length && selected >= 0 && (next[selected].separator || next[selected].disabled)) selected++
        if (selected === next.length) {
            selected--
            while (selected >= 0 && (next[selected].separator || next[selected].disabled)) selected--
        }
    }
    var oldSubmenu = previous[submenuRow]
    var subRow = oldSubmenu ? next.findIndex(function(entry) { return entry.action === oldSubmenu.action }) : -1
    var sub = subRow >= 0 ? next[subRow] : null
    var oldTarget = oldSubmenu && oldSubmenu.submenu ? oldSubmenu.submenu[submenuCursor] : null
    var target = sub && !sub.disabled && oldTarget ? (sub.submenu || []).findIndex(function(entry) { return entry.id === oldTarget.id && !entry.disabled }) : -1
    return { cursor: selected, submenuRow: target >= 0 ? subRow : -1, submenuCursor: Math.max(0, target) }
}

// A changed answer replaces an open menu's rows; cursor and flyout follow their actions, the flyout inside the build hold so it reads its rows once.
function apply(menu, next) {
    var selection = refreshedCursor(menu.entries, next, menu.cursor, menu.openSubmenuRow, menu.submenuCursor)
    // A lone flyout's leaves come from Menu.flyoutEntries, which no provider answer changes, so it keeps its row and highlight.
    var lone = menu.loneFlyoutAction.length > 0
    menu.setEntries(next, lone ? undefined : selection.submenuRow)
    menu.cursor = selection.cursor
    if (!lone)
        menu.submenuCursor = selection.submenuCursor
}
