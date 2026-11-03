//@ pragma ShellId flea-trash-view-test
import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "qml-probe.js" as QmlProbe

// tests/trash-view.sh's harness: the real ui/TrashHost.qml and ui/TrashView.qml over fixture replies, with the real ui/ContextMenu.qml. Rows keep the order the backend gives; the harness hands them in newest deleted first, and the backend's own order is tested in src/backend/trashbrowse.rs.
ShellRoot {
    id: shell

    property int checks: 0
    property var failures: []
    property int step: 0
    property int ticks: 0
    property var live: JSON.parse(Quickshell.env("TRASHVIEW_ROWS"))
    property var sent: []
    property var queue: []
    // Non-empty rail entry sets the menu was handed: one per m, so a menu built twice shows here.
    property int menuBuilds: 0
    readonly property int tickBound: 150

    function log(line) { QmlProbe.log("TRASHVIEW", line) }
    function check(name, actual, expected) { QmlProbe.checkQuiet(shell, name, actual, expected) }
    function finish() {
        shell.step = 99
        shell.log("DONE checks=" + shell.checks + " failed=" + shell.failures.length)
        if (shell.failures.length === 0) shell.log("PASS " + shell.checks + " checks")
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    // What the backend answers for the ops this view sends; a restore drops its rows from the Trash.
    function answer(m) {
        var base = { t: "trashbrowse", id: m.id, op: m.op, ok: true }
        if (m.op === "list" || m.op === "window") {
            var start = m.start || 0
            return Object.assign(base, { total: shell.live.length, start: start, rows: shell.live.slice(start, start + (m.count || 100)),
                selectionToken: 0, selectionCount: 0, selectionStale: false, present: [], recoveredCount: 0, recoveryErrors: [] })
        }
        if (m.op === "summary") return Object.assign(base, { bytes: 1024, partial: false })
        if (m.op === "restore") {
            var gone = m.uris || []
            shell.live = shell.live.filter(function (row) { return gone.indexOf(row.uri) < 0 })
            return Object.assign(base, { done: gone.length, failed: 0, failures: [] })
        }
        return base
    }

    Timer {
        id: replies
        interval: 1
        repeat: true
        running: shell.queue.length > 0
        onTriggered: { var next = shell.queue[0]; shell.queue = shell.queue.slice(1); backend.trashResult(shell.answer(next)) }
    }
    QtObject {
        id: backend
        signal trashResult(var message)
        function send(message) { shell.sent = shell.sent.concat([message]); shell.queue = shell.queue.concat([message]) }
    }
    QtObject {
        id: pane
        property var preview: null
        property var sidebar: null
        property var statusBar: null
        property var focusView: ""
        property var backend: backend
        property var shareBrowser: QtObject { function close() {} }
        property var listArea: Item { function forceActiveFocus() {} }
        function clearSelection() {}
        function contextMenu() { return menu }
        function message(text, error) {}
        function operationResult(headline, detail, error) {}
        function act(action) {}
    }

    FloatingWindow {
        implicitWidth: 800
        implicitHeight: 560
        color: "#303030"

        Flea.TrashHost {
            id: host
            // The host's own relative source does not resolve through the symlinked ui/ directory this harness imports.
            source: Qt.resolvedUrl("flea/TrashView.qml")
            width: 800
            height: 500
            pane: pane
        }
        Flea.ContextMenu { id: menu; anchors.fill: parent }
        TestEvent { id: keys }
    }

    Connections {
        target: menu
        function onRailEntriesChanged() { if (menu.railEntries.length > 0) shell.menuBuilds += 1 }
    }

    function names() { return host.item.rows.map(function (row) { return row.original.split("/").pop() }) }
    function titleText(item, prefix) {
        if (item.text !== undefined && String(item.text).indexOf(prefix) === 0) return item.text
        for (var i = 0; i < item.children.length; i++) {
            var found = shell.titleText(item.children[i], prefix)
            if (found !== "") return found
        }
        return ""
    }
    function rowPoint(index) {
        var row = host.item.rowItemFor(index)
        return row.mapToItem(menu, Flea.Theme.spacing.rowPaddingX, row.height)
    }
    function menuLabels() { return menu.railEntries.filter(function (e) { return !e.separator }).map(function (e) { return e.label }) }
    function placed() { return { x: Math.round(menu.placeX), y: Math.round(menu.placeY) } }
    function at(point) { return { x: Math.round(point.x), y: Math.round(point.y) } }
    function ready(total) { return host.opened && host.item.total === total && !host.item.busy && host.item.rows.length === total && host.item.rowItemFor(total - 1) !== null }

    function advance() {
        shell.ticks += 1
        if (shell.ticks > shell.tickBound) {
            shell.log("state opened=" + host.opened + " total=" + (host.item ? host.item.total : -1) + " busy=" + (host.item ? host.item.busy : "") + " pending=" + (host.item ? host.item.pendingOp : "") + " rows=" + (host.item ? host.item.rows.length : -1) + " sent=" + shell.sent.map(function (m) { return m.op }).join(",") + " queued=" + shell.queue.length)
            shell.check("step " + shell.step + " finished inside " + shell.tickBound + " ticks", false, true)
            shell.finish()
            return
        }
        if (shell.step === 0) {
            host.open("")
            shell.step = 1
        } else if (shell.step === 1 && shell.ready(3)) {
            var view = host.item
            shell.check("rows keep the order the backend gives", shell.names(), ["photo.png", "notes.txt", "old-folder"])
            shell.check("the Deleted header draws the descending mark", shell.titleText(view, "Deleted"), "Deleted ▾")
            shell.check("the ipc header labels stay bare", view.headerLabels, ["Name", "Original location", "Deleted"])
            shell.check("the cursor opens on the newest row", view.cursor, 0)
            shell.check("and that row is marked in the selection look", view.rowItemFor(0).selected, true)
            shell.check("and only that row", view.selectedUris(), ["trash:///photo.png"])
            keys.keyClickChar("m", Qt.NoModifier, -1)
            shell.step = 2
        } else if (shell.step === 2 && menu.opened) {
            shell.check("m builds the menu once", shell.menuBuilds, 1)
            shell.check("m on the cursor row holds Restore alone", shell.menuLabels(), ["Restore"])
            shell.check("and it is the Trash rail menu", menu.railKey, "trash")
            shell.check("and it opens under the cursor row, the way the listing's own does", shell.placed(), shell.at(shell.rowPoint(0)))
            keys.keyClick(Qt.Key_Return, Qt.NoModifier, -1)
            shell.step = 3
        } else if (shell.step === 3 && shell.sent.some(function (m) { return m.op === "restore" })) {
            var restore = shell.sent.filter(function (m) { return m.op === "restore" })[0]
            shell.check("Enter on Restore restores the newest item", restore.uris, ["trash:///photo.png"])
            shell.check("and not the whole Trash", restore.all, false)
            shell.step = 4
        } else if (shell.step === 4 && shell.ready(2)) {
            var again = host.item
            shell.check("the restored row is gone and the next newest leads", shell.names(), ["notes.txt", "old-folder"])
            shell.check("nothing is marked after a restore", again.selectedUris(), [])
            shell.menuBuilds = 0
            keys.keyClickChar("m", Qt.NoModifier, -1)
            shell.step = 5
        } else if (shell.step === 5 && menu.opened) {
            shell.check("m with nothing marked opens the cursor row's menu", shell.menuLabels(), ["Restore"])
            shell.check("under the cursor row", shell.placed(), shell.at(shell.rowPoint(0)))
            shell.check("having marked that row for the action", host.item.selectedUris(), ["trash:///notes.txt"])
            keys.keyClick(Qt.Key_Escape, Qt.NoModifier, -1)
            shell.step = 6
        } else if (shell.step === 6 && !menu.opened) {
            keys.keyClick(Qt.Key_Down, Qt.ShiftModifier, -1)
            shell.check("shift+Down marks a second row", host.item.selectedUris().sort(), ["trash:///notes.txt", "trash:///old-folder"])
            shell.menuBuilds = 0
            keys.keyClickChar("m", Qt.NoModifier, -1)
            shell.step = 7
        } else if (shell.step === 7 && menu.opened) {
            var top = host.item.mapToItem(menu, host.item.width / 2, Flea.Theme.chromeHeight)
            shell.check("m with two rows marked opens the marked rows' menu", shell.menuLabels(), ["Restore"])
            shell.check("where it opened before, at the top centre", shell.placed(), shell.at(top))
            shell.check("built once", shell.menuBuilds, 1)
            keys.keyClick(Qt.Key_Escape, Qt.NoModifier, -1)
            shell.finish()
        }
    }

    Timer {
        interval: 40
        repeat: true
        running: shell.step < 99
        onTriggered: shell.advance()
    }
}
