.pragma library

.import "Eject.js" as Eject
.import "Mounts.js" as Mounts
.import "Nav.js" as Nav

// What the rail does with a key, split out of Focus.js at its 300-line hard cap the same way
// ui/js/PreviewKeys.js was: Focus.js decides which surface owns a key, and this is the surface.

// A mount-first Enter's open has landed in root: focus follows it into the folder unless the user already left the rail.
function landed(root, sidebar) {
    if (!sidebar || !sidebar.focusOnOpen) return
    sidebar.focusOnOpen = false
    if (root.focusView === "rail") root.focusView = "list"
}

// A Sidebar open (opened or networkOpened): the pane that asked opens it, and a waiting claim lands; no pane spends the claim.
function openFrom(pane, path, sidebar) {
    if (!pane) { if (sidebar) sidebar.focusOnOpen = false; return }
    Nav.openPlace(pane, path)
    if (sidebar) landed(pane, sidebar)
}

// A mount that failed has no open to land, so its focus claim goes with the error.
function messaged(sidebar, isError) {
    if (isError && sidebar) sidebar.focusOnOpen = false
}

// The keyboard cursor takes the rail's highlight only while the keyboard holds it, never under an open rail menu or after a pointer press until a rail key.
function cursorDrawn(focused, menuOpen, pointerFocus) {
    return Boolean(focused && !menuOpen && !pointerFocus)
}

// Right Arrow from a row whose mark releases moves the keyboard onto that mark, read raw because the table resolves Right to opening the row in every preset.
function markKey(event, root, sidebar) {
    if (event && (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) !== 0) return false
    var key = event ? event.key : 0
    if (!sidebar.markFocused) {
        if (key !== Qt.Key_Right || !Eject.releasable(sidebar.entries[sidebar.cursorIndex])) return false
        sidebar.markFocused = true
        return true
    }
    if (key === Qt.Key_Left || key === Qt.Key_Escape) sidebar.markFocused = false
    else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
        sidebar.markFocused = false
        Eject.release(root, sidebar, true)
    } else if (key !== Qt.Key_Right) return false
    return true
}

// The rail answers ten of the key table's action names and ignores the rest while it has focus; event is the key itself, for the ones the table does not name.
function act(action, root, sidebar, event) {
    // Any other rail key ends a mount-first open's claim on focus and restores the keyboard highlight a pointer press hid.
    sidebar.focusOnOpen = false
    sidebar.pointerFocus = false
    if (markKey(event, root, sidebar)) return
    // A cursor key leaves the mark for the rows, even on the first or last row where the cursor stays.
    if (action.indexOf("cursor") === 0) sidebar.markFocused = false
    switch (action) {
    case "cursorDown": sidebar.cursorIndex = Math.min(sidebar.entries.length - 1, sidebar.cursorIndex + 1); return
    case "cursorUp": sidebar.cursorIndex = Math.max(0, sidebar.cursorIndex - 1); return
    // The sheet advertises g and G as first and last row, and the rail is a cursored list too, so
    // they answered nothing here while every other cursor key worked.
    case "cursorFirst": sidebar.cursorIndex = 0; return
    case "cursorLast": sidebar.cursorIndex = Math.max(0, sidebar.entries.length - 1); return
    // activate(), not opened(path), so a Network entry mounts first and focus follows the open into the folder.
    case "open":
        if (sidebar.entries.length === 0) return
        // Focus follows the open only when it lands (ui/PaneRail.qml), since a mount or a share's gio info can take long or never answer.
        sidebar.focusOnOpen = true
        sidebar.activate(sidebar.cursorIndex)
        return
    // Focus.LIST's own value, written out because importing Focus.js back would be a cycle.
    case "escape":
        if (root.statusBar && root.statusBar.escapePressed()) return
        root.focusView = "list"; return
    case "addNetwork": sidebar.addRequested(); return
    // Favorites are not offered: Sidebar.startRename ignores an index outside the Network group.
    case "rename": sidebar.startRename(sidebar.cursorIndex); return
    // Eject and Unmount are menu rows, so this opens the menu rather than inventing a second route.
    case "menu":
        if (sidebar.entries[sidebar.cursorIndex] && sidebar.entries[sidebar.cursorIndex].kind === "trash") sidebar.openCursorMenu()
        else Mounts.raiseMenu(root, sidebar)
        return
    case "eject": Eject.release(root, sidebar, true); return
    }
}
