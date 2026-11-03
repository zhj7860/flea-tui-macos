import QtQuick

// ui/DialogButton.qml's surface: the card reads activated as the click and Enter that press it.
Item {
    property string label: ""
    property bool primary: false
    property bool focused: false
    property bool available: true

    signal activated()
    signal tabbed(var from, bool back)
}
