import QtQuick
import "js/Drag.js" as DragOps

// The rail's Trash SidebarRow trashes rows dragged from this window through ui/js/TrashDrop.js; it lives outside the group-indexed ui/Sidebar.qml, which sits at its recorded ceiling.
SidebarRow {
    id: root

    required property var rail
    readonly property int railIndex: root.index + root.rail.homeLead.length + root.rail.recentEntries.length + root.rail.homeRest.length
    readonly property var pane: root.rail.navigationPane
    // Exposed so ui/PaneRail.qml keeps an overlay rail up while a drag rests on this row.
    readonly property bool dragOver: target.containsDrag

    // The drop cue is separate from the rail's own location and keyboard cursor.
    lit: root.railIndex === root.rail.litIndex
    highlighted: root.railIndex === root.rail.highlightedIndex
    cursor: root.rail.cursorDrawn && root.railIndex === root.rail.cursorIndex
    focused: root.rail.focused
    trailingLabel: dropLoader.item ? dropLoader.item.label : null
    onActivated: root.rail.activate(root.railIndex)
    onMenuRequested: function (idx, pos) { root.rail.openRailMenu(root.railIndex, pos) }

    function dropDecisions() {
        if (feedback.item) return feedback.item
        feedback.setSource(Qt.resolvedUrl("TrashDropHandler.qml"), { pane: Qt.binding(function () { return root.pane }) })
        feedback.active = true
        return feedback.item
    }

    Loader {
        id: feedback
        active: false
        onStatusChanged: if (status === Loader.Error) console.warn("TrashDropHandler.qml did not load: Loader status " + status)
    }

    Loader {
        id: dropLoader
        active: root.dragOver
        anchors.fill: parent
        // TrashDrop always moves to Trash, regardless of the drag's copy or link modifiers.
        onActiveChanged: dropLoader.setSource(dropLoader.active ? Qt.resolvedUrl("DropTarget.qml") : "", { text: DragOps.label(false, false) })
        onStatusChanged: if (status === Loader.Error) throw new Error("DropTarget.qml did not load: Loader status " + status)
    }

    DropArea {
        id: target
        anchors.fill: parent
        keys: [DragOps.ROWS_MIME]
        onEntered: function (drag) {
            var marker = drag.getDataAsString(DragOps.ROWS_MIME)
            var decisions = root.dropDecisions()
            if (!root.pane || !decisions || !decisions.accepts(marker, drag.urls, root.pane.path)) {
                drag.accepted = false
                return
            }
            decisions.feedback = DragOps.feedbackFor(marker, drag.urls, "")
            decisions.say(decisions.line(marker, drag.urls, root.pane.path))
        }
        onExited: if (feedback.item) feedback.item.leaveTarget()
        onDropped: function (drop) {
            var decisions = root.dropDecisions()
            if (decisions && decisions.drop(root.pane, drop.getDataAsString(DragOps.ROWS_MIME), drop.urls))
                drop.accept(Qt.CopyAction)
            if (decisions) decisions.leaveTarget()
        }
    }
}
