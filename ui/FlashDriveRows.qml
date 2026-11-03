import QtQuick
import qs.Commons
import "." as Flea
import "js/Flash.js" as Flash
import "js/Format.js" as Format

// The DRIVES step: one file row per drive with its refusal hint, or the empty row while no drive is plugged in.
Column {
    id: root
    property var drives: []
    property bool drivesReady: false
    property int selected: -1
    property int cursor: 0
    property bool focused: true
    property bool running: false
    signal chooseDrive(int index)
    width: 0
    // The board's detail column, 190 px at bodySmall 13, scaled with the text.
    readonly property int detailBoard: 190
    readonly property int bodySmallBoard: 13
    Text {
        x: Theme.spacing.rowPaddingX
        // A later section opens a panel gap under the one above, as the rail's FAVORITES does.
        topPadding: Math.round(Style.spacing.panelGap * Theme.sizeRatio) + Math.ceil(font.pixelSize * 0.15)
        bottomPadding: Theme.spacing.gap
        text: "DRIVES"
        color: Theme.color.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
        font.letterSpacing: 1
        textFormat: Text.PlainText
    }
    Repeater {
        model: root.drives
        delegate: Column {
            required property var modelData
            required property int index
            // Read once through the delegate: every bare modelData or index below would warn on its own.
            readonly property var row: modelData
            readonly property int idx: index
            // Detail ink lifts to foreground on the cursor or chosen row, muted at rest.
            readonly property color detailInk: (root.cursor === idx + 1 || root.selected === idx) ? Theme.color.foreground : Theme.color.muted
            width: root.width
            Rectangle {
                width: parent.width
                height: Theme.fileRowHeight
                // The cursor uses accent ink; the chosen drive keeps the marked rung, as Row.qml draws both.
                color: root.cursor === idx + 1 ? (root.focused ? Style.selectedAccentFill : "transparent")
                    : root.selected === idx ? Style.selectionFill : "transparent"
                opacity: Flash.fits(row) ? 1 : Theme.disabledOpacity
                Rectangle {
                    visible: root.cursor === idx + 1
                    width: Theme.spacing.hairline * 2
                    height: parent.height
                    color: root.focused ? Theme.color.accent : Theme.color.mutedFrame
                }
                Row {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacing.rowPaddingX
                    anchors.rightMargin: Theme.spacing.rowPaddingX
                    spacing: Theme.spacing.gap
                    Flea.Glyph { width: Theme.markSize; height: parent.height; name: "drive"; color: Theme.color.foreground }
                    Text {
                        width: Math.max(0, parent.width - Theme.markSize - driveDetail.width - driveSize.width - 3 * parent.spacing)
                        anchors.verticalCenter: parent.verticalCenter
                        text: row ? Flash.driveName(row, root.drives) : ""
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Theme.color.foreground
                        font { family: Theme.font.family; pixelSize: Theme.font.body }
                    }
                    Text {
                        id: driveDetail
                        width: Math.round(root.detailBoard * Theme.font.bodySmall / root.bodySmallBoard)
                        anchors.verticalCenter: parent.verticalCenter
                        text: row ? Flash.driveDetail(row, root.drives) : ""
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: detailInk
                        font { family: Theme.font.family; pixelSize: Theme.font.caption }
                    }
                    Text {
                        id: driveSize
                        width: Theme.column.size
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        text: row ? Format.size(row.bytes) : ""
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: detailInk
                        font { family: Theme.font.family; pixelSize: Theme.font.caption }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    onClicked: {
                        if (!root.running && Flash.fits(row))
                            root.chooseDrive(idx)
                    }
                }
            }
            Text {
                visible: !Flash.fits(row)
                x: Theme.spacing.rowPaddingX + Theme.markSize + Theme.spacing.gap
                topPadding: Theme.spacing.rowPaddingY
                bottomPadding: Theme.spacing.rowPaddingY
                width: parent.width - x - Theme.spacing.rowPaddingX
                wrapMode: Text.Wrap
                text: Flash.refusedHint(row)
                color: Theme.color.muted
                font { family: Theme.font.family; pixelSize: Theme.font.caption }
                textFormat: Text.PlainText
            }
        }
    }
    Item {
        visible: root.drivesReady && root.drives.length === 0
        width: root.width
        height: Theme.fileRowHeight
        Row {
            anchors.fill: parent
            anchors.leftMargin: Theme.spacing.rowPaddingX
            anchors.rightMargin: Theme.spacing.rowPaddingX
            spacing: Theme.spacing.gap
            Flea.Glyph { width: Theme.markSize; height: parent.height; name: "drive"; color: Theme.color.mutedFrame }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Plug in a USB drive or SD card"
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.color.muted
                font { family: Theme.font.family; pixelSize: Theme.font.body }
            }
        }
    }
}
