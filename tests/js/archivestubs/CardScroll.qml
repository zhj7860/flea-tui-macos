import QtQuick

// ui/CardScroll.qml's surface as the cards set it.
Item {
    property real bleedY: 0
    property real contentY: 0
    readonly property real wanted: childrenRect.height
}
