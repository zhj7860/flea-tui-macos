pragma ComponentBehavior: Bound

import QtQuick
import "js/Tags.js" as Tags

// One row's tag swatches: 14 px squares at 3 px gaps, each carrying its digit in the fallback.
Item {
    id: root
    readonly property int swatchGap: 3
    property var tags: []
    // A row reserves the 88 px slot and a tile its own cell, so only the whole swatches that fit are drawn, with no counter.
    readonly property real room: root.below && root.parent ? root.parent.width : Theme.tagSlotWidth
    readonly property var drawn: root.tags.slice(0, Math.max(0, Math.floor((root.room + root.swatchGap) / (Tags.SWATCH_SIZE + root.swatchGap))))
    // The item this slot follows on a row, or the caption it sits under on a tile; hug follows a text's own end.
    property Item after: null
    property Item below: null
    property bool hug: false
    visible: root.tags.length > 0
    width: Math.max(0, root.drawn.length * (Tags.SWATCH_SIZE + root.swatchGap) - root.swatchGap)
    height: Tags.SWATCH_SIZE
    anchors.left: root.after ? (root.hug ? root.after.left : root.after.right) : undefined
    anchors.leftMargin: root.after && root.hug ? root.after.contentWidth + Theme.spacing.gap : Theme.spacing.gap
    anchors.verticalCenter: root.after ? root.after.verticalCenter : undefined
    anchors.top: root.below ? root.below.bottom : undefined
    anchors.horizontalCenter: root.below ? parent.horizontalCenter : undefined

    Repeater {
        model: root.drawn
        delegate: TagSwatch {
            id: cell
            required property int index
            required property string modelData
            x: cell.index * (Tags.SWATCH_SIZE + root.swatchGap)
            swatch: cell.modelData
            fallback: Theme.tag.fallback
            digit: Tags.keyFor(cell.modelData)
            tagColors: Theme.tag.colors
        }
    }
}
