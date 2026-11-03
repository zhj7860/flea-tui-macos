import QtQuick
import "." as Flea
import "js/DropDev.js" as DropDev

// One crumb's drop target: the floor's own receiver, naming the crumb, with a frame inside the crumb's own advance so it never reaches the "/" either side.
Flea.DropInto {
    id: root

    required property var crumb
    anchors.fill: parent
    enabled: root.crumb.inputLive && root.pane !== null
    refuseLoading: root.pane ? root.pane.listInFlight === true : true
    // A plain drop moves on the source volume and copies across it; this crumb's device is the backend's answer, and an unanswered one copies.
    destDev: DropDev.devFor(root.pane && root.pane.backend ? root.pane.backend.pathDevs : null, root.dest)
    onContainsDragChanged: root.crumb.dropTarget = root.containsDrag

    Rectangle {
        anchors.fill: parent
        visible: root.containsDrag
        color: Theme.color.accent
        opacity: 0.08
        border.width: Theme.spacing.hairline
        border.color: Theme.color.accent
    }
}
