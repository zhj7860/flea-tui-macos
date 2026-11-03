import QtQuick
import "js/Tags.js" as Tags

// One tag swatch: the fill, the fallback border, the digit text.
Rectangle {
    id: root
    property string swatch: ""
    property bool fallback: false
    property string digit: ""
    required property var tagColors
    property int size: Tags.SWATCH_SIZE
    readonly property int fallbackBorder: 2
    width: root.size
    height: root.size
    color: root.fallback ? "transparent" : root.tagColors[root.swatch] || "transparent"
    border.width: root.fallback ? root.fallbackBorder : 0
    border.color: root.tagColors[root.swatch] || "transparent"
    Text {
        visible: root.fallback
        anchors.centerIn: parent
        text: root.digit
        color: root.tagColors[root.swatch] || "transparent"
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
        font.bold: true
        textFormat: Text.PlainText
    }
}
