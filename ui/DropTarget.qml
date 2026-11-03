import QtQuick
import qs.Commons

// States.dc.html's drop cue, shared by the file row and the rail's Trash row.
Item {
    id: root

    property bool shown: true
    property real paintWidth: 0
    property alias text: dropLabel.text
    property alias label: dropLabel

    // The board's accent hairline over a faint wash at the hover rung's alpha.
    Rectangle {
        visible: root.shown
        width: root.paintWidth > 0 ? root.paintWidth : parent.width
        height: parent.height
        color: Util.alpha(Theme.color.accent, Style.hoverFillAlpha)
        border.width: Theme.spacing.hairline
        border.color: Theme.color.accent
    }

    // Caption type in the accent, against the row padding, in place of trailing columns.
    Text {
        id: dropLabel
        visible: root.shown
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacing.rowPaddingX
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.color.accent
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
        textFormat: Text.PlainText
    }
}
