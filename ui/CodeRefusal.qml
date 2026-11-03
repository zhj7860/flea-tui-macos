import QtQuick
import "." as Flea

// The code preview's refusal frame, shared by Quick Look's text pane and Markdown Source.
Item {
    id: root

    property bool binary: false
    property bool tooLarge: false
    property bool failed: false
    property string markName: "file"
    // Quick Look places the frame below its bar; Source's host has already set that inset.
    property int topInset: 0
    readonly property string status: root.tooLarge ? "This file is too large to preview." : root.failed ? "This file could not be read." : "ready"

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.topInset + Math.round((parent.height - root.topInset - height) / 2)
        spacing: Theme.spacing.gap
        visible: root.binary || (root.tooLarge && !root.failed)

        Flea.Glyph {
            anchors.horizontalCenter: parent.horizontalCenter
            maxSize: Theme.stateMarkSize
            width: Theme.stateMarkSize
            height: Theme.stateMarkSize
            name: root.markName
            color: Theme.color.muted
            opacity: 0.7
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.binary ? "binary file" : "too large to preview"
            color: Theme.color.muted
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
            textFormat: Text.PlainText
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.topInset + Math.round((parent.height - root.topInset - height) / 2)
        visible: root.failed
        text: root.status
        color: Theme.color.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.body
        textFormat: Text.PlainText
    }
}
