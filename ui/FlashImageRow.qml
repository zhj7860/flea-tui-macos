import QtQuick
import qs.Commons
import "." as Flea
import "js/Flash.js" as Flash
import "js/Format.js" as Format

// The IMAGE step: heading, the chosen image with its sizes or the picker row, and the refusal hint under a refused image.
Column {
    id: root
    property var image: null
    property bool cursor: false
    property bool focused: true
    property bool running: false
    signal choose()
    width: 0
    // The board's detail column, 190 px at bodySmall 13, scaled with the text.
    readonly property int detailBoard: 190
    readonly property int bodySmallBoard: 13
    // Detail ink lifts to foreground under the cursor, muted at rest, as Row.qml cellInk does.
    readonly property color detailInk: root.cursor ? Theme.color.foreground : Theme.color.muted
    Text {
        x: Theme.spacing.rowPaddingX
        // The first section opens one row padding under the strip, as the rail's PLACES does.
        topPadding: Theme.spacing.rowPaddingX + Math.ceil(font.pixelSize * 0.15)
        bottomPadding: Theme.spacing.gap
        text: "IMAGE"
        color: Theme.color.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
        font.letterSpacing: 1
        textFormat: Text.PlainText
    }
    Rectangle {
        width: root.width
        height: Theme.fileRowHeight
        // The cursor uses accent ink, as every listing row does; a refused image only dims.
        color: root.cursor ? (root.focused ? Style.selectedAccentFill : "transparent") : "transparent"
        opacity: root.image && root.image.refused ? Theme.disabledOpacity : 1
        // Twice the hairline, the cursor mark against the row edge, as Row.qml draws it.
        Rectangle {
            visible: root.cursor
            width: Theme.spacing.hairline * 2
            height: parent.height
            color: root.focused ? Theme.color.accent : Theme.color.mutedFrame
        }
        Row {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacing.rowPaddingX
            anchors.rightMargin: Theme.spacing.rowPaddingX
            spacing: Theme.spacing.gap
            Flea.Glyph { width: Theme.markSize; height: parent.height; name: root.image ? "file" : "folder-open"; color: Theme.color.foreground }
            Text {
                width: Math.max(0, parent.width - Theme.markSize - imageDetail.width - imageSize.width - 3 * parent.spacing)
                anchors.verticalCenter: parent.verticalCenter
                text: root.image ? Flash.leaf(root.image.path) : "Choose an image…"
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.color.foreground
                font { family: Theme.font.family; pixelSize: Theme.font.body }
            }
            Text {
                id: imageDetail
                width: Math.round(root.detailBoard * Theme.font.bodySmall / root.bodySmallBoard)
                anchors.verticalCenter: parent.verticalCenter
                text: Flash.imageDetail(root.image)
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.detailInk
                font { family: Theme.font.family; pixelSize: Theme.font.caption }
            }
            Text {
                id: imageSize
                width: Theme.column.size
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: root.image ? Format.size(root.image.bytes) : ""
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.detailInk
                font { family: Theme.font.family; pixelSize: Theme.font.caption }
            }
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onClicked: {
                if (!root.running)
                    root.choose()
            }
        }
    }
    Text {
        visible: root.image !== null && root.image.refused === true
        x: Theme.spacing.rowPaddingX + Theme.markSize + Theme.spacing.gap
        topPadding: Theme.spacing.rowPaddingY
        bottomPadding: Theme.spacing.rowPaddingY
        width: root.width - x - Theme.spacing.rowPaddingX
        wrapMode: Text.Wrap
        text: "This file is not a disk image."
        color: Theme.color.muted
        font { family: Theme.font.family; pixelSize: Theme.font.caption }
        textFormat: Text.PlainText
    }
}
