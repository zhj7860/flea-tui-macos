import QtQuick
import qs.Commons
import "." as Flea
import "js/Picker.js" as Picker

// Picker040's filter dropdown: one trigger at the menu's width, its menu opening flush above it.
Item {
    id: root
    required property var picker
    readonly property var chips: Picker.chips(root.picker.req)
    readonly property int current: root.chips.findIndex(function(chip) { return chip.index === root.picker.filterIndex })
    // The focus walk and the probe read these two the way they read a button's.
    readonly property string name: "Filter"
    readonly property bool available: root.enabled
    // The board draws the chevron in the foreground at four fifths.
    readonly property real chevronAlpha: 0.8
    // The chevron's box is the body text plus two pixels, the board's 16 px at base size 14.
    readonly property real chevronSize: Theme.font.body + 2
    // Built at the first open, so a picker that never opens it holds no menu.
    property Item menu: null

    width: Theme.menuWidth
    visible: root.chips.length > 0
    enabled: !root.picker.backendUnavailable && !root.picker.submitting
    opacity: root.enabled ? 1 : Theme.disabledOpacity
    activeFocusOnTab: root.enabled

    Accessible.role: Accessible.ComboBox
    Accessible.name: root.name
    Accessible.description: root.current >= 0 ? root.chips[root.current].label : ""
    Accessible.onPressAction: root.open()

    Keys.onTabPressed: function(event) { root.picker.stepFocus(root, (event.modifiers & Qt.ShiftModifier) !== 0) }
    Keys.onBacktabPressed: root.picker.stepFocus(root, true)
    Keys.onReturnPressed: root.open()
    Keys.onEnterPressed: root.open()
    Keys.onSpacePressed: root.open()
    Keys.onDownPressed: root.open()

    // One entry per filter then All files, the mark slot empty; the action carries the filter index.
    function open() {
        if (!root.enabled) return
        if (!root.menu) {
            root.menu = Qt.createComponent("ContextMenu.qml").createObject(root.picker.contentItem)
            root.menu.railChosen.connect(function(action) { if (root.enabled) root.picker.filterIndex = parseInt(action) })
        }
        var entries = root.chips.map(function(chip) { return {label: chip.label, action: String(chip.index), mark: "", hint: ""} })
        // The menu is as tall as its rows and padding, so its bottom edge is the trigger's top.
        var shut = root.mapToItem(root.picker.contentItem, 0, 0)
        root.menu.openForRail("filter", entries, Qt.point(shut.x, shut.y - entries.length * Theme.rowHeight - 2 * Theme.spacing.rowPaddingY))
        root.menu.cursor = root.current
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Theme.color.foreground, hover.hovered || press.pressed ? Theme.washHover : 0)
        border.width: Theme.spacing.hairline
        border.color: root.activeFocus ? Theme.color.accent : Theme.color.muted
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacing.gap
        anchors.right: chevron.left
        anchors.rightMargin: Theme.spacing.gap
        anchors.verticalCenter: parent.verticalCenter
        text: root.current >= 0 ? root.chips[root.current].label : ""
        color: Theme.color.foreground
        font.family: Theme.font.family
        font.pixelSize: Theme.font.body
        textFormat: Text.PlainText
        elide: Text.ElideRight
    }

    Flea.Glyph {
        id: chevron
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacing.gap
        anchors.verticalCenter: parent.verticalCenter
        width: root.chevronSize
        height: width
        maxSize: width
        name: "chevron-down"
        color: Qt.alpha(Theme.color.foreground, root.chevronAlpha)
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        id: press
        acceptedButtons: Qt.LeftButton
        onTapped: { root.forceActiveFocus(Qt.MouseFocusReason); root.open() }
    }
}
