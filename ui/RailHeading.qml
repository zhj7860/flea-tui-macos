import QtQuick
import qs.Commons

// One rail heading: the caption text with the rail's lead and tracking.
Text {
    id: root
    property real topExtra: 0
    property bool noBottom: false
    readonly property real headingLead: 0.15
    readonly property real headingTracking: 1
    x: Style.spacing.rowPaddingX
    topPadding: root.topExtra + Math.ceil(font.pixelSize * root.headingLead)
    bottomPadding: root.noBottom ? 0 : Style.spacing.rowGap
    color: Theme.color.muted
    font.family: Theme.font.family
    font.pixelSize: Theme.font.caption
    font.letterSpacing: root.headingTracking
    textFormat: Text.PlainText
}
