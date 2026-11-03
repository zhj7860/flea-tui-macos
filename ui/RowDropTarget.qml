import QtQuick
import "js/Drag.js" as DragOps

// The file row's shared drop cue and clipboard mark, compiled only when either is drawn.
DropTarget {
    id: root

    required property var row
    property alias mark: clipGlyph
    anchors.fill: parent
    shown: root.row.dropTarget
    paintWidth: root.row.paintWidth
    text: DragOps.label(root.row.dropCopying, root.row.dropLinking)

    // A clipboard row under a drag keeps its mark beside the label, one pixel above the text centre line.
    Glyph {
        id: clipGlyph
        visible: root.row.clipMark.length > 0 && !root.row.renaming && !root.row.searching
        width: root.row.clipPx
        height: root.row.clipPx
        x: root.row.clipMark.length > 0 ? root.row.nameItem().x + Math.min(root.row.nameItem().implicitWidth, root.row.nameItem().width) + Theme.spacing.gap : 0
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -1
        name: root.row.clipMark
        color: Theme.color.mutedFrame
    }
}
