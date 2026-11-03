import QtQuick

// The dimmed ground under a dialog card: it takes hover, both buttons and the wheel, and a click on it dismisses the dialog.
Rectangle {
    id: root

    signal dismissed()

    anchors.fill: parent
    color: Theme.color.background
    opacity: 0.5

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: root.dismissed()
        onWheel: function(wheel) { wheel.accepted = true }
    }
}
