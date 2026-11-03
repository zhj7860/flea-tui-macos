import QtQuick

// The tall kinds' one facts line: the Kind elides at its end so the size and the count stay whole.
Item {
    id: root

    // The Kind, and the " · size · count" tail, as ui/js/Facts.js compactLine returns them.
    property string kind: ""
    property string tail: ""

    // One row of the full table, so the line sits where its first row would.
    height: Math.round(Theme.font.caption * 1.5)

    Text {
        id: kindText
        width: Math.min(implicitWidth, Math.max(0, root.width - tailText.implicitWidth))
        text: root.kind
        color: Theme.color.foreground
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
        textFormat: Text.PlainText
        elide: Text.ElideRight
    }

    Text {
        id: tailText
        anchors.left: kindText.right
        text: root.tail
        color: Theme.color.foreground
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
        textFormat: Text.PlainText
    }
}
