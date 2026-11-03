import QtQuick

// One piece of a path that a click can land on, the chrome's and a dual pane's alike; keys.toml's "chrome" rows are its contract.
Text {
    id: crumb

    required property var modelData
    // What an ancestor reads at rest: muted in the chrome, where only the leaf is lit, and the foreground on a dual pane's path.
    property color restColor: Theme.color.muted
    // ui/ChromeButton.qml's inputLive: the handlers stop while something covers the crumb.
    property bool inputLive: true
    // Drops callout 4: the pane whose collide sends a drop on this crumb, null where crumbs take none.
    property var dropPane: null
    // The hovered ancestor inside the row's drop frame: an accent hairline over the wash, inside the crumb's own advance.
    property bool dropTarget: false
    // Built when a drag first needs it and kept, so no DropArea per crumb stands at startup.
    property var dropArea: null
    // A platform drag sends no hover, so the lift is what builds the target; the first hover builds it too.
    readonly property bool dragLive: crumb.dropPane !== null && crumb.dropPane.dragActive === true
    onDragLiveChanged: if (crumb.dragLive) crumb.armDrop()

    signal chosen(string path)
    signal editRequested()

    // corner: a path is arbitrary text, so PlainText, the same rule every filename on this surface follows.
    text: crumb.modelData.text
    color: crumb.dropTarget ? Theme.color.accent
        : crumb.modelData.last || (crumbHover.hovered && !crumb.modelData.elided) ? Theme.color.foreground : crumb.restColor
    font.family: Theme.font.family
    font.pixelSize: Theme.font.caption
    textFormat: Text.PlainText
    verticalAlignment: Text.AlignVCenter

    function armDrop() {
        if (crumb.dropArea !== null || crumb.dropPane === null)
            return
        var dest = String(crumb.modelData.path || "")
        if (dest.length === 0 || crumb.modelData.last === true)
            return
        var area = Qt.createComponent("CrumbDrop.qml").createObject(crumb,
            { crumb: crumb, pane: crumb.dropPane, dest: dest, label: String(crumb.modelData.text || "") })
        if (area === null)
            return
        crumb.dropArea = area
    }

    HoverHandler {
        id: crumbHover
        enabled: crumb.inputLive
        cursorShape: crumb.modelData.last || crumb.modelData.elided ? Qt.IBeamCursor : Qt.PointingHandCursor
        onHoveredChanged: if (hovered) crumb.armDrop()
    }

    // No exclusiveSignals, decided 2026-09-22: the pair held every tap for the whole double-click interval, about 400 ms.
    // The gesture sits on the crumb because a TapHandler on a parent takes the second tap from the child under the pointer.
    TapHandler {
        enabled: crumb.inputLive
        acceptedButtons: Qt.LeftButton
        // The collapsed marker names no directory, so a press on it opens nothing rather than whichever crumb it stands for.
        onSingleTapped: if (!crumb.modelData.last && !crumb.modelData.elided) crumb.chosen(crumb.modelData.path)
        // Only where a tap opens nothing does a double click type the path; on a parent it is two taps.
        onDoubleTapped: if (crumb.modelData.last || crumb.modelData.elided) crumb.editRequested()
    }
}
