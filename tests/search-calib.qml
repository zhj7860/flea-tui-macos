//@ pragma ShellId flea-search-calib

import QtQuick
import Quickshell

// Calibration client: the query line echoes keys at once (masked, inside the watched window) and results change CALIB_DELAY_MS later (watched).
ShellRoot {
    id: root

    readonly property int delayMs: parseInt(Quickshell.env("CALIB_DELAY_MS") || "0")
    property string query: ""
    property int generation: 0
    property real keyAt: 0
    property real changedAt: 0
    property real wheelAt: 0
    property bool swapPending: false

    function change() {
        root.generation += 1
        root.changedAt = Date.now()
        root.swapPending = true
    }

    Timer {
        id: later
        interval: Math.max(1, root.delayMs)
        onTriggered: root.change()
    }

    FloatingWindow {
        id: win
        implicitWidth: 900
        implicitHeight: 700
        color: "#101010"

        // The query line: changes on the key itself, so a detector that fails to mask it reads a delay of zero.
        Rectangle {
            id: field
            width: parent.width
            height: 48
            color: "#202020"
            Text {
                anchors.verticalCenter: parent.verticalCenter
                x: 12
                color: "#ffffff"
                font.pixelSize: 22
                text: root.query + "|"
            }
        }

        // The results: twelve rows whose colour and text follow the generation.
        Item {
            id: results
            y: field.height
            width: parent.width
            height: parent.height - field.height
            Repeater {
                model: 12
                Rectangle {
                    required property int index
                    y: index * 48
                    width: results.width
                    height: 44
                    color: root.generation % 2 === 0 ? "#303030" : "#2b6a3a"
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 12
                        color: "#ffffff"
                        font.pixelSize: 20
                        text: "result " + index + " generation " + root.generation
                    }
                }
            }
        }

        Item {
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => {
                // A bare Shift is the driver's cursor hide (S.hide_cursor), never a key the client answers.
                if (event.key === Qt.Key_Shift)
                    return
                root.keyAt = Date.now()
                if (event.text.length > 0)
                    root.query += event.text
                console.log("CALIB key " + root.keyAt)
                if (root.delayMs <= 0)
                    root.change()
                else
                    later.restart()
            }

            // The first wheel event that carries pixels is logged on this client's clock and drawn as one generation change.
            WheelHandler {
                onWheel: event => {
                    if (root.wheelAt > 0)
                        return
                    if (event.pixelDelta.x === 0 && event.pixelDelta.y === 0) {
                        console.log("CALIB wheel-skip angle=" + event.angleDelta.y)
                        return
                    }
                    root.wheelAt = Date.now()
                    console.log("CALIB wheel at=" + root.wheelAt + " px=" + event.pixelDelta.y)
                    root.change()
                }
            }
        }

        Connections {
            target: results.Window.window
            function onFrameSwapped() {
                if (!root.swapPending)
                    return
                root.swapPending = false
                console.log("CALIB swap key=" + root.keyAt + " changed=" + root.changedAt + " swapped=" + Date.now())
            }
        }
    }
}
