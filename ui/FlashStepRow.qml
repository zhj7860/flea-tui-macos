import QtQuick
import qs.Commons
import "." as Flea
import "js/Flash.js" as Flash
import "js/Transfer.js" as Transfer

// The FLASH step: one 37 px row with the alert mark, erase line and action, then the running bar and the ending row.
Column {
    id: root
    property var transfer: null
    property real rate: 0
    property var words: ({ erase: "", action: "" })
    property bool live: false
    property bool running: false
    property var ending: null
    property bool ejected: false
    property bool cursor: false
    property bool focused: true
    signal pressFlash()
    signal pressCancel()
    signal pressEnd()
    readonly property var flashItem: flashButton
    readonly property var cancelItem: cancelButton
    readonly property var endItem: endButton
    width: 0
    // The running bar takes the transfer card's recipe: half a caption thick, a quarter-ink track.
    readonly property int barHeight: Math.round(Theme.font.caption / 2)
    readonly property real trackOpacity: 0.25
    Text {
        x: Theme.spacing.rowPaddingX
        // A later section opens a panel gap under the one above, as the rail's FAVORITES does.
        topPadding: Math.round(Style.spacing.panelGap * Theme.sizeRatio) + Math.ceil(font.pixelSize * 0.15)
        bottomPadding: Theme.spacing.gap
        text: "FLASH"
        color: Theme.color.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
        font.letterSpacing: 1
        textFormat: Text.PlainText
    }
    Rectangle {
        width: root.width
        height: Theme.rowHeight
        // The cursor uses accent ink, as every listing row does; the greyed Flash row only dims.
        color: root.cursor ? (root.focused ? Style.selectedAccentFill : "transparent") : "transparent"
        opacity: !root.running && root.ending === null && !root.live ? Theme.disabledOpacity : 1
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
            Flea.Glyph {
                width: Theme.markSize
                height: parent.height
                visible: !root.running && root.ending === null
                name: "alert"
                color: Theme.color.error
            }
            Flea.Spinner {
                width: Theme.markSize
                height: parent.height
                visible: root.running
                color: Theme.color.mutedFrame
            }
            Flea.Glyph {
                width: Theme.markSize
                height: parent.height
                visible: root.ending !== null
                name: root.ending ? root.ending.mark : "check"
                color: root.ending && root.ending.role === "error" ? Theme.color.error
                    : root.ending && root.ending.role === "foreground" ? Theme.color.foreground : Theme.color.mutedFrame
            }
            Text {
                width: Math.max(0, parent.width - Theme.markSize - flashControl.width - 2 * parent.spacing)
                anchors.verticalCenter: parent.verticalCenter
                text: root.running ? Transfer.head(root.transfer)
                    : root.ending ? root.ending.headline : root.words.erase
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Flash.stepRole(root.running, root.ending) === "error" ? Theme.color.error : Theme.color.foreground
                font { family: Theme.font.family; pixelSize: Theme.font.body }
            }
            Item {
                id: flashControl
                width: Math.max(flashButton.implicitWidth, cancelButton.implicitWidth, endButton.implicitWidth)
                height: parent.height
                Flea.DialogButton {
                    id: flashButton
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.running && root.ending === null
                    label: root.words.action
                    primary: true
                    available: root.live
                    onActivated: root.pressFlash()
                }
                Flea.DialogButton {
                    id: cancelButton
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.running
                    label: "Cancel"
                    available: Transfer.cancelEnabled(root.transfer)
                    onActivated: root.pressCancel()
                }
                Flea.DialogButton {
                    id: endButton
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.running && root.ending !== null && (root.ending.eject || root.ending.flashBack) && !root.ejected
                    label: root.ending && root.ending.flashBack ? root.words.action : "Eject"
                    primary: root.ending ? root.ending.flashBack : false
                    available: root.ending && root.ending.flashBack ? root.live : true
                    onActivated: root.pressEnd()
                }
            }
        }
    }
    // The running step's own lines under the label column, the bar and then the byte line.
    Column {
        visible: root.running
        x: Theme.spacing.rowPaddingX + Theme.markSize + Theme.spacing.gap
        width: root.width - x - Theme.spacing.rowPaddingX - Theme.column.size
        topPadding: Theme.spacing.rowPaddingY
        spacing: root.barHeight
        // The fill is a sibling of the track and not its child, because opacity multiplies down into children.
        Item {
            width: parent.width
            height: root.barHeight
            Rectangle {
                anchors.fill: parent
                color: Theme.color.mutedFrame
                opacity: root.trackOpacity
            }
            Rectangle {
                width: parent.width * Transfer.fraction(root.transfer)
                height: parent.height
                color: Theme.color.accentFrame
            }
        }
        Row {
            id: byteLine
            readonly property var parts: Transfer.byteParts(root.transfer, root.rate)
            Repeater {
                model: byteLine.parts
                delegate: Text {
                    required property var modelData
                    text: modelData.text
                    color: modelData.figure ? Theme.color.foreground : Theme.color.muted
                    font.family: Theme.font.family
                    font.pixelSize: Theme.font.caption
                    textFormat: Text.PlainText
                }
            }
        }
    }
    Text {
        visible: root.ending !== null && root.ending.hint.length > 0
        x: Theme.spacing.rowPaddingX + Theme.markSize + Theme.spacing.gap
        topPadding: Theme.spacing.rowPaddingY
        bottomPadding: Theme.spacing.rowPaddingY
        width: root.width - x - Theme.spacing.rowPaddingX
        wrapMode: Text.Wrap
        text: root.ending ? root.ending.hint : ""
        color: Theme.color.muted
        font { family: Theme.font.family; pixelSize: Theme.font.caption }
        textFormat: Text.PlainText
    }
}
