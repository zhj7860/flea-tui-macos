pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import "js/Tags.js" as Tags

// The rail's TAGS section: the heading and one row per tag in use. The rail builds it once, when the setting is on and a tag is in use.
Column {
    id: root
    required property var sidebar
    width: parent.width
    // A rail that follows a pane with no tag in use draws no heading, and the network gap reserves no height for it.
    visible: sidebar.placesState.showTags === true && root.entries.length > 0
    height: root.visible ? root.implicitHeight : 0
    // Guarded as Sidebar.tagsListed is, because the rail can move to a pane that has built no tag state.
    readonly property var entries: Tags.railEntries(root.sidebar.navigationPane !== null && root.sidebar.navigationPane.tagState !== null
        ? root.sidebar.navigationPane.tagState.inUse : ({}))
    // Where this section's first row stands among the rail's entries.
    readonly property int base: root.sidebar.placesEntries.length - root.entries.length
    function itemAt(i) { return tagRepeater.itemAt(i) }
    // The Loader sizes its item to the 13 px slot, so the 14 px swatch is a child the Loader leaves alone.
    Component {
        id: markComponent
        Item {
            id: slot
            property var entry: ({})
            TagSwatch {
                anchors.centerIn: parent
                swatch: slot.entry.swatch || ""
                fallback: Theme.tag.fallback
                digit: slot.entry.digit || ""
                tagColors: Theme.tag.menuColors
            }
        }
    }

    RailHeading {
        text: "TAGS"
        topExtra: Style.spacing.panelGap
    }
    Repeater {
        id: tagRepeater
        model: root.entries
        delegate: SidebarRow {
            lit: index + root.base === root.sidebar.litIndex
            highlighted: index + root.base === root.sidebar.highlightedIndex
            cursor: root.sidebar.cursorDrawn && index + root.base === root.sidebar.cursorIndex
            focused: root.sidebar.focused
            tagMark: markComponent
            onActivated: function (idx) { root.sidebar.activate(idx + root.base) }
        }
    }
}
