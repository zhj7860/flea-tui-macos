import QtQuick

// The hairline track of the media strip, drawn for the seek and, under Quick Look, the volume: the played part and a square handle in the accent frame ink, the host adds its MouseArea.
Item {
    id: root

    property real fraction: 0
    // A square handle, sized off the caption token so it scales with the text like everything else.
    readonly property int handle: Math.round(Theme.font.caption * 0.5)

    function fractionAt(x) {
        return Math.max(0, Math.min(1, x / Math.max(1, root.width)))
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: Theme.spacing.hairline * 2
        color: Theme.color.mutedFrame
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width * root.fraction
        height: Theme.spacing.hairline * 2
        color: Theme.color.accentFrame
    }

    Rectangle {
        x: Math.round(parent.width * root.fraction) - root.handle / 2
        anchors.verticalCenter: parent.verticalCenter
        width: root.handle
        height: root.handle
        color: Theme.color.accentFrame
    }
}
