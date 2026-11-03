import QtQuick
import "js/Permissions.js" as Permissions

// Read-only menu observations: a retained asked path is not a pending read, so record the backend's receipt.
QtObject {
    id: root
    property var pane: null
    property var fleaWindow: null
    property var shebangReply: ({})
    property var shebangLastReply: ({})
    onPaneChanged: root.shebangReply = ({})

    property Connections replies: Connections {
        target: root.pane ? root.pane.backend : null
        function onShebang(path, hasShebang, id) {
            var reply = {pane: String(root.pane), path: path, hasShebang: hasShebang, id: id}
            root.shebangLastReply = reply
            if (Permissions.landsShebang(path, id, root.pane.shebangAsked, root.pane.shebangId))
                root.shebangReply = reply
        }
    }

    // What each main-frame row laid out for itself (ui/MenuRow.qml parts), null for a row not built; never widestRow's answer.
    function menuRows(menu) {
        var rows = []
        for (var i = 0; i < menu.entries.length; i++) { var it = menu.itemFor(i); rows.push(it ? it.parts() : null) }
        return rows
    }

    function state() {
        var menu = root.pane.contextMenu()
        var marked = root.pane.selectedIndices().map(function (index) {
            var row = root.pane.rowFor(index)
            return { index: index, name: row ? row.n : null, p: row ? row.p : null }
        })
        return JSON.stringify({pane: String(root.pane), opened: menu.opened, entries: menu.entries, cursor: menu.cursor,
            snapshotReady: root.pane.menuActions.ready, snapshotId: root.pane.menuActions.requestId,
            compareKinds: menu.compareKinds, snapshotKinds: root.pane.menuActions.selectedKinds,
            snapshotIdentity: root.pane.menuActions.identity, menuSelectionIdentity: root.pane.menuSelectionIdentity(),
            markedRows: marked,
            shebangAsked: root.pane.shebangAsked, shebangHas: root.pane.rowHasShebang,
            shebangId: root.pane.shebangId, shebangReply: root.shebangReply, shebangLastReply: root.shebangLastReply,
            submenu: menu.submenuOpen, submenuCursor: menu.submenuCursor, submenuEntries: menu.submenuEntries,
            frame: root.fleaWindow.rectOf(menu.frameItem), flyout: root.fleaWindow.rectOf(menu.submenuFrameItem),
            workArea: menu.workArea, forHeader: menu.forHeader, forRail: menu.forRail, hasRow: menu.hasRow,
            rows: root.menuRows(menu)})
    }
}
