import QtQuick

// The parked Back's listing wait, built on the first park by ui/PaneSwap.qml so a window that never parks starts no Timer.
Timer {
    required property var swap
    interval: swap.parkedWaitMs
    repeat: false
    onTriggered: swap.landParked()
}
