import QtQuick

// ui/SettingsSegment.qml's surface as the compress card's format row sets it.
Item {
    property var options: []
    property string value: ""
    property bool tabStop: false

    signal picked(int index)
}
