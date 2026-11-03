import QtQuick
import qs.Commons

// The bulk card's old-names column: one still row per selected name.
Column {
    id: root
    required property var oldNames
    // The dialog's own half-width gap and stack gap, bound by the card so both halves stay equal.
    required property int columnGap
    required property int headGap
    // How far a column's first name sits under its label: the new names box's hairline and 2 px of padding, in this column and in that box alike.
    readonly property int rowsInset: Theme.spacing.hairline + 2
    width: (parent.width - columnGap) / 2
    spacing: headGap
    Text {
        text: "OLD NAMES"
        color: Theme.color.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
        textFormat: Text.PlainText
    }
    Column {
        width: parent.width
        topPadding: root.rowsInset
        spacing: 0
        Repeater {
            model: root.oldNames
            // The name centres in its row the way the new names' fields do, so both rest on the same pixel rows.
            delegate: Item {
                required property var modelData
                required property int index
                width: parent.width
                height: Theme.fileRowHeight
                Text {
                    width: parent.width
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.modelData
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Theme.color.muted
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.body
                }
            }
        }
    }
}
