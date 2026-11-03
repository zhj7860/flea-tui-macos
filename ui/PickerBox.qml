import QtQuick
import "." as Flea
import "js/MarkBox.js" as MarkBox

// The picker's mark box, one copy for the list and the grid; js/MarkBox.js holds its sizes.
Rectangle {
    id: root

    property bool marked: false
    readonly property int innerSize: MarkBox.inner(Theme.font.bodySmall, Theme.spacing.hairline)
    readonly property int borderWidth: MarkBox.border(Theme.spacing.hairline)

    width: MarkBox.outer(Theme.font.bodySmall, Theme.spacing.hairline)
    height: root.width
    color: "transparent"
    border.width: root.borderWidth
    border.color: root.marked ? Theme.color.accent : Theme.color.mutedFrame

    Flea.Glyph {
        anchors.fill: parent
        visible: root.marked
        name: "check"
        maxSize: root.innerSize - root.borderWidth * 2
        color: Theme.color.accent
    }
}
