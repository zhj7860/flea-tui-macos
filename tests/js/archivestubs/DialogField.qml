import QtQuick

// ui/DialogField.qml's surface: text is what the operator typed, accepted is Enter in the field.
Item {
    property string label: ""
    property string placeholder: ""
    property bool secret: false
    property string text: ""
    property bool error: false
    property int heldMask: 0
    readonly property Item input: box
    readonly property bool revealed: false
    readonly property real labelSpacing: 0.1

    signal accepted()
    signal edited()
    signal tabbed(var from, bool back)

    function takeFocus() { box.forceActiveFocus() }
    function eyeCentre() { return "0 0" }

    Item { id: box }
}
