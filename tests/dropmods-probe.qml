import QtQuick
import QtQuick.Window

// #259 case (c): a foreign DropArea, run with qml6, never qs, printing what the platform offered and what it chose.
Window {
    id: root
    title: "DropProbe"
    width: 420
    height: 300
    visible: true

    property int drops: 0

    function actionName(action) {
        if (action === Qt.CopyAction) return "copy"
        if (action === Qt.MoveAction) return "move"
        if (action === Qt.LinkAction) return "link"
        if (action === Qt.IgnoreAction) return "ignore"
        return "mask-" + action
    }

    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list", "text/plain", "application/x-flea-rows", "application/x-flea-shelf"]
        onEntered: function (drag) {
            console.log("PROBE entered offered=" + drag.supportedActions + " proposed=" + drag.proposedAction
                + " formats=" + drag.formats.join(","))
            drag.accepted = true
        }
        onDropped: function (drop) {
            root.drops++
            console.log("PROBE drop#" + root.drops + " offered=" + drop.supportedActions + " proposed=" + drop.proposedAction
                + " urls=" + drop.urls.length + " marker=" + drop.getDataAsString("application/x-flea-rows").split("\n")[0].length + "chars"
                + " formats=" + drop.formats.join(","))
            drop.acceptProposedAction()
            console.log("PROBE drop#" + root.drops + " chose=" + actionName(drop.action))
        }
    }

    Text {
        anchors.centerIn: parent
        text: "drop here"
    }
}
