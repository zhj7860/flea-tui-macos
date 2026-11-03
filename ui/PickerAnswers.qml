import QtQuick
import qs.Commons
import "." as Flea
import "js/Picker.js" as Picker

// The one row under the listing in every mode: the filter at the left, Cancel and the answer at the right.
Item {
    id: root
    objectName: "pickerAnswers"
    required property var picker
    readonly property alias filterItem: filter
    readonly property alias cancelItem: cancelButton
    anchors.left: parent.left
    anchors.right: parent.right
    // A save sits in the save column: no rule of its own and one gap under the field; an open keeps its own strip.
    readonly property real lead: root.picker.saving ? Theme.spacing.gap : Theme.spacing.hairline + Theme.spacing.rowPaddingX
    height: root.lead + Theme.spacing.rowPaddingX + cancelButton.height

    // Every answer is the one body control every dialog draws; the picker owns Tab.
    component Answer: Flea.DialogButton {
        id: answer
        property string name: answer.label
        tabHandle: true
        tabStop: true
        onTabbed: function(from, back) { root.picker.stepFocus(answer, back) }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.color.surface
    }

    Rectangle {
        visible: !root.picker.saving
        anchors.top: parent.top
        width: parent.width
        height: Theme.spacing.hairline
        color: root.picker.edge
    }

    Flea.PickerFilter {
        id: filter
        picker: root.picker
        x: Theme.spacing.rowPaddingX
        y: root.lead
        height: cancelButton.height
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacing.rowPaddingX
        y: root.lead
        spacing: Theme.spacing.gap

        Answer {
            id: cancelButton
            label: "Cancel"
            onActivated: root.picker.cancel()
        }

        Answer {
            id: acceptButton
            label: root.picker.collisionReview ? "Replace" : Picker.acceptLabel(root.picker.req, root.picker.marks.length)
            primary: !root.picker.collisionReview
            destructive: root.picker.collisionReview
            available: root.picker.canAccept
            onActivated: root.picker.collisionReview ? root.picker.replace() : root.picker.accept()
        }
    }

    function focusItems() { return (filter.visible ? [filter] : []).concat([cancelButton, acceptButton]) }
    function controls() {
        return root.focusItems().map(function(item) { return root.picker.control(item.name, item, item.available) })
    }
}
