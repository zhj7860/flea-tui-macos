import QtQuick
import "." as Flea

// The flasher's strip: Back, an unavailable Up and the title; every exit leaves through the view's close.
Rectangle {
    id: root
    signal back()
    width: 0
    height: Theme.chromeHeight
    color: Theme.color.surface
    Row {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacing.rowPaddingX
        anchors.rightMargin: Theme.spacing.rowPaddingX
        spacing: Theme.spacing.gap
        Flea.ChromeButton {
            ruleRows: Theme.spacing.hairline
            glyph: "arrow-left"
            onActivated: root.back()
        }
        Flea.ChromeButton {
            ruleRows: Theme.spacing.hairline
            glyph: "arrow-up"
            accessName: "Up unavailable in Flash"
            enabled: false
            Accessible.ignored: false
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Flash image"
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.color.foreground
            font { family: Theme.font.family; pixelSize: Theme.font.caption }
        }
    }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: Theme.spacing.hairline; color: Theme.color.foreground; opacity: 0.12 }
}
