import QtQuick
import "." as Flea

// A 0.4.0 dialog card's header (MergeFolders, RunFile, Unlock): DialogTitle, the boards' air, then a hairline rule.
Item {
    id: root

    property alias text: title.text
    property alias elide: title.elide
    readonly property bool truncated: title.truncated
    readonly property alias ruleItem: rule

    // The boards draw 8 px of air under the title at their 13 px reference body.
    readonly property real boardAir: 8
    readonly property real referenceBody: 13
    implicitHeight: title.implicitHeight + Math.round(root.boardAir * Theme.font.bodySmall / root.referenceBody) + Theme.spacing.hairline

    Flea.DialogTitle {
        id: title
        width: parent.width
    }

    Rectangle {
        id: rule
        anchors.bottom: parent.bottom
        width: parent.width
        height: Theme.spacing.hairline
        color: Theme.color.mutedFrame
        opacity: 0.4
    }
}
