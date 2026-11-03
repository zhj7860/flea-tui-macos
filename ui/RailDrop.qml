import QtQuick
import "js/Drag.js" as DragOps
import "js/DragOut.js" as DragOut
import "js/RailDrop.js" as RailDrop
import "js/Tabs.js" as Tabs

// One receiver under the rail's rows; Trash keeps its own receiver above it.
DropArea {
    id: root

    required property var sidebar
    property Item viewport: root.sidebar
    readonly property var pane: root.sidebar.navigationPane
    property var entered: null
    property int rowIndex: -1
    property var targetRow: null
    property var held: null
    property point pointer: Qt.point(0, 0)
    property point cuePoint: Qt.point(0, 0)
    anchors.fill: parent
    keys: [DragOps.ROWS_MIME, DragOps.SHELF_MIME, "text/uri-list", "text/plain"]

    function session() {
        if (feedback.item) return feedback.item
        feedback.setSource(Qt.resolvedUrl("FileDrag.qml"), { pane: Qt.binding(function () { return root.pane }) })
        feedback.active = true
        return feedback.item
    }

    // Sample input: a drag offers a marker, a shelf token, text/plain and file:///d/a.txt.
    function read(drag) {
        var urls = []
        for (var i = 0; i < drag.urls.length; i++) urls.push(String(drag.urls[i]))
        return { marker: drag.getDataAsString(DragOps.ROWS_MIME), urls: urls,
            shelf: drag.getDataAsString(DragOps.SHELF_MIME), plain: drag.getDataAsString("text/plain"),
            proposed: drag.proposedAction }
    }

    function clearTarget() {
        if (root.targetRow) root.targetRow.trailingLabel = null
        root.targetRow = null
        root.held = null
        root.rowIndex = -1
        if (feedback.item) feedback.item.leaveTarget()
    }

    function aim(x, y) {
        root.pointer = Qt.point(x, y)
        if (!root.entered) return
        var index = RailDrop.rowAt(root.sidebar, x, y)
        var entry = index >= 0 ? root.sidebar.entries[index] : null
        var data = root.entered
        var path = root.pane && !root.pane.listInFlight
            ? RailDrop.destination(entry, data.marker, data.urls, data.shelf, data.plain) : ""
        var row = index >= 0 ? root.sidebar.railItemFor(index) : null
        if (index === root.rowIndex && row === root.targetRow && root.held && root.held.path === path) {
            root.cuePoint = row.mapToItem(root.viewport, 0, 0)
            root.sayTarget()
            return
        }
        root.clearTarget()
        if (!path) return
        root.rowIndex = index
        root.targetRow = row
        root.cuePoint = row.mapToItem(root.viewport, 0, 0)
        root.held = RailDrop.pending(path)
        root.sayTarget()
        root.pane.backend.send({ c: "devs", paths: [path], id: root.held.id })
    }

    function sayTarget() {
        if (!root.held || !feedback.item) return
        feedback.item.showTarget(root.sidebar.entries[root.rowIndex].label, root.held.dev)
        if (root.targetRow && cue.item) root.targetRow.trailingLabel = cue.item.label
    }

    function leave() {
        root.clearTarget()
        root.entered = null
    }

    function reaim() { if (root.entered) root.aim(root.pointer.x, root.pointer.y) }

    onPaneChanged: root.leave()
    Component.onDestruction: root.clearTarget()
    Connections {
        target: root.sidebar
        function onEntriesChanged() {
            root.clearTarget()
            // The aggregate changes before its repeaters finish replacing rows.
            Qt.callLater(root.reaim)
        }
    }
    Connections {
        target: root.pane ? root.pane.backend : null
        function onMetaResult(message) {
            if (message.t !== "devs" || !root.entered) return
            root.held = RailDrop.answer(root.held, message.id, message.devs)
            root.sayTarget()
        }
    }

    Loader {
        id: feedback
        active: false
        onStatusChanged: if (status === Loader.Error) throw new Error("FileDrag.qml did not load: Loader status " + status)
    }
    Loader {
        id: cue
        active: root.held !== null
        parent: root.viewport
        x: root.cuePoint.x
        y: root.cuePoint.y
        width: root.targetRow ? root.targetRow.width : 0
        height: root.targetRow ? root.targetRow.height : 0
        z: 1
        onActiveChanged: {
            if (!cue.active) { cue.source = ""; return }
            cue.setSource(Qt.resolvedUrl("DropTarget.qml"), {
                text: Qt.binding(function () { return DragOps.label(feedback.item ? feedback.item.dragCopy : true, feedback.item ? feedback.item.dragLink : false) })
            })
        }
        onLoaded: root.sayTarget()
        onStatusChanged: if (status === Loader.Error) throw new Error("DropTarget.qml did not load: Loader status " + status)
    }

    function enterAt(drag) {
        if (!root.pane || !root.pane.backend || drag.getDataAsString(Tabs.TAB_MIME) !== "") { drag.accepted = false; return }
        root.entered = root.read(drag)
        DragOut.keys.enter(root.entered.marker, drag.getDataAsString(DragOut.keys.liftMime))
        var session = root.session()
        if (!session) { root.leave(); drag.accepted = false; return }
        session.enterTarget(root.entered.marker, root.entered.urls, "", DragOps.markerDev(root.entered.marker), root.entered.shelf, drag.proposedAction)
        root.aim(drag.x, drag.y)
    }
    function dropAt(drop) {
        var ctrl = DragOut.keys.ctrl, shift = DragOut.keys.shift
        DragOut.keys.clear()
        root.aim(drop.x, drop.y)
        var data = root.read(drop)
        var entry = root.rowIndex >= 0 ? root.sidebar.entries[root.rowIndex] : null
        if (RailDrop.drop(root.pane, entry, root.held, data.marker, data.urls, data.shelf, data.plain, drop.proposedAction, ctrl, shift)) {
            drop.accept(Qt.CopyAction)
            // The rail's key table ignores undo, so an accepted drop gives the receiving listing the keyboard.
            root.pane.focusView = "list"
            root.pane.focusRequested()
            root.pane.listArea.forceActiveFocus()
        }
        root.leave()
    }
    onEntered: function (drag) { root.enterAt(drag) }
    onPositionChanged: function (drag) { root.aim(drag.x, drag.y) }
    onExited: { DragOut.keys.leave(); root.leave() }
    onDropped: function (drop) { root.dropAt(drop) }
}
