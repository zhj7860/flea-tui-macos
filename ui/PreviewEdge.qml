import QtQuick
import qs.Commons

// The Columns view's preview column edge: ui/ResizeHandle.qml over the edge, and on hover the Media040 board's move-horizontal mark beside the accent line.
Item {
    id: root

    // The preview column's left edge in the parent's pixels; the zone is centred on the hairline just left of it.
    property int edge: 0
    // True from the press to the release, so the line and mark stay up while the pointer is dragged off the zone.
    property bool dragging: false
    // The pointer's pixels left or right of where it pressed, on every move of a drag.
    signal dragged(int shift)
    signal grabbed()
    signal released()
    signal restored()

    objectName: "previewEdge"
    width: handle.width
    x: root.edge - 1 - Math.floor(root.width / 2)

    property real pressX: 0
    // False from the press until the pointer is past the platform drag distance, so a click or a jitter keeps the stored width.
    property bool pulled: false

    ResizeHandle {
        id: handle
        anchors.fill: parent
        hot: root.dragging
        onPressed: function (mouse) {
            root.pressX = handle.mapToItem(null, mouse.x, mouse.y).x
            root.dragging = true
            root.pulled = false
            root.grabbed()
        }
        // The zone reports hover moves too, so only a held drag moves the edge.
        onMoved: function (mouse) {
            if (!root.dragging) return
            var shift = Math.round(handle.mapToItem(null, mouse.x, mouse.y).x - root.pressX)
            if (!root.pulled && Math.abs(shift) > Qt.styleHints.startDragDistance) root.pulled = true
            if (root.pulled) root.dragged(shift)
        }
        onReleased: { root.dragging = false; root.released() }
        onDoubleClicked: root.restored()
    }

    HoverHandler { id: hover }

    // The mark is built with the line: left 12 px of the edge, top at the column's middle.
    Loader {
        x: root.edge - 12 - root.x
        y: root.height / 2
        width: 16
        height: 16
        active: hover.hovered || root.dragging
        sourceComponent: Glyph {
            anchors.fill: parent
            name: "move-horizontal"
            color: Theme.color.foreground
            maxSize: 16
        }
    }
}
