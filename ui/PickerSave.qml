import QtQuick
import "." as Flea
import "js/Format.js" as Format
import "js/Picker.js" as Picker

// The save area: Filename and its field in one column, and under it the collision review's error line.
Item {
    id: root
    required property var picker
    property Item keyTarget: null
    // Only keys left unhandled by Filename reach the listing, after editing and the field's Tab walk.
    Keys.forwardTo: root.keyTarget ? [root.keyTarget] : []
    signal nameEdited(string text)
    signal accepted()
    readonly property alias fieldItem: field
    readonly property alias scrollItem: body
    readonly property alias statusItem: statusLine
    readonly property string askedName: root.picker.saveName || root.picker.req.name
    readonly property bool refused: root.askedName.length > 0 && !Picker.validName(root.askedName)
    visible: root.picker.saving
    property real maximumHeight: parent.height
    // The answer row below is the column's last row and brings the gap under the field; the column keeps only its top padding.
    implicitHeight: visible ? Math.min(maximumHeight, body.wanted + Theme.spacing.rowPaddingX) : 0

    Rectangle { anchors.fill: parent; color: Theme.color.surface }
    Rectangle {
        width: parent.width
        height: Theme.spacing.hairline
        color: root.picker.edge
    }
    Flea.CardScroll {
        id: body
        bleed: Theme.focusClearance
        anchors.fill: parent
        anchors.margins: Theme.spacing.rowPaddingX - Theme.focusClearance
        anchors.bottomMargin: -Theme.focusClearance
        Column {
            id: column
            width: parent.width
            spacing: Theme.spacing.gap

            Text {
                text: "Filename"
                textFormat: Text.PlainText
                color: Theme.color.foreground
                font { family: Theme.font.family; pixelSize: Theme.font.caption }
            }
            Rectangle {
                width: parent.width
                height: Math.max(Theme.hitMin, Theme.rowHeight - Theme.spacing.rowPaddingY)
                color: Theme.color.background
                border.width: Theme.spacing.hairline
                // Muted at rest, accent on focus: the frame DialogField, MenuActionDialog, OpenWithDialog and PermissionsDialog draw.
                border.color: field.activeFocus ? Theme.color.accent : Theme.color.mutedFrame
                TextInput {
                    id: field
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacing.gap
                    anchors.rightMargin: Theme.spacing.gap
                    verticalAlignment: TextInput.AlignVCenter
                    text: root.picker.saveName
                    color: Theme.color.foreground
                    selectionColor: Theme.color.accent
                    selectedTextColor: Theme.color.background
                    font { family: Theme.font.family; pixelSize: Theme.font.body }
                    clip: true
                    activeFocusOnTab: true
                    enabled: !root.picker.submitting
                    Accessible.name: "Filename"
                    onTextEdited: root.nameEdited(text)
                    onAccepted: root.accepted()
                    // Enter remains the field's save action when it opens a collision review.
                    Keys.onReturnPressed: root.accepted()
                    Keys.onEnterPressed: root.accepted()
                    Keys.onTabPressed: function(event) { root.picker.stepFocus(field, (event.modifiers & Qt.ShiftModifier) !== 0) }
                    Keys.onBacktabPressed: root.picker.stepFocus(field, true)
                }
            }
            Text {
                id: statusLine
                width: parent.width
                visible: text.length > 0
                text: root.refused ? Format.fill(Picker.SAVE_REFUSED, root.askedName, Picker.NAME_REFUSED)
                    : root.picker.saveError || (root.picker.collisionReview ? Picker.collisionLine(Picker.jointName(root.picker.saveName)) : "")
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: Theme.color.errorOnSurface
                font { family: Theme.font.family; pixelSize: Theme.font.caption }
            }
        }
    }
    // The review returns the keyboard to the field with the stem selected and the caret at its end.
    function selectStem() {
        field.forceActiveFocus(Qt.TabFocusReason)
        field.select(0, Picker.stemEnd(field.text))
    }
    function focusItems() { return root.visible ? [field] : [] }
    function controls() {
        return root.focusItems().map(function(item) { return root.picker.control("Filename", item, item.enabled) })
    }
}
