import QtQuick
import qs.Commons
import "js/Eject.js" as Eject
import "js/Format.js" as Format
import "js/TabMove.js" as TabMove

// One rail row, shared by the Favorites, Network and Devices groups so the three read alike; see
// ui/Sidebar.qml "The rail" for the entry shape each group feeds this delegate.
Item {
    id: root

    required property int index
    required property var modelData
    // Current-place identity stays separate from the keyboard's visual highlight, including over IPC.
    property bool lit: false
    property bool highlighted: root.lit
    property bool cursor: false
    property bool focused: false
    // A drop cue replaces the trailing detail and reserves its caption's width.
    property Item trailingLabel: null
    // The keyboard is on this row's eject mark, which then draws its own frame in the foreground at its hit box.
    property bool markFocused: false
    // Network only, driven from ui/Sidebar.qml's renamingIndex; swaps the label for the editor.
    property bool renaming: false

    signal activated(int index)
    // A click on the eject mark releases the row at once, the same Eject or Unmount the
    // menu row and Ctrl+E take; carrying the index, because the rail rebuilds on its poll
    // and a position taken later can name a different row.
    signal ejectRequested(int index)
    // Right click asks the rail to raise the menu over this row, carrying the point it opens at.
    // The rail decides what the menu offers and opens none on a row with nothing to release. It is
    // ui/Pane.qml's own single ui/ContextMenu.qml: a second instance in this tree took the keyboard
    // away from the list, see AGENTS.md "A second ContextMenu instance breaks the whole window's
    // keyboard focus", which is why the rail had no menu at all until now.
    signal menuRequested(int index, var scenePosition)
    // Middle click: the row's folder in a new tab; ui/js/PlaceMenu.js openTabAt decides which rows have one.
    signal tabRequested(int index)
    signal renameCommitted(int index, string text)
    signal renameCancelled(int index)
    // Favourites reorder by drag; a favourite carries its store index, others leave -1.
    property int dragFrom: -1
    property int lineCount: 0
    signal moved(int to)
    signal reorderAt(int line)

    // A share or a removable volume carries a mount-state dot; the internal disk is always there
    // and always mounted, so a dot on it would say nothing, and a favourite is not a mount at all.
    readonly property var placesState: ViewState.state.places || ({})
    // The eject mark's accessible name, one whole sentence per kind of row, each filled by Format.fill.
    readonly property var ejectWords: ({ eject: "Eject %1", unmount: "Unmount %1" })
    readonly property string detail: root.modelData.kind === "trash"
        ? (root.placesState.trashCount === true && root.modelData.count > 0 ? String(root.modelData.count) : "")
        : root.modelData.group === "device" && root.placesState.driveSize === true && root.modelData.size !== null
            ? Format.size(root.modelData.size) : ""
    // PhoneMark: a phone is a volume, so its row carries the same mount-state square a removable
    // disk and a share carry, in the same fixed slot.
    readonly property bool showsDot: (root.modelData.group === "network" && root.modelData.kind !== "dropbox")
        || (root.modelData.group === "device"
            && (root.modelData.kind === "volume" || root.modelData.kind === "phone"))
    // The Trash row draws its count where every other row draws its indicator, and never both.
    readonly property bool countIsIndicator: root.modelData.kind === "trash" && root.detail.length > 0
    // Small and fixed: a status dot is not part of the type or icon scale.
    readonly property int dotSize: 6
    // The canvas's own value for a bookmark nothing has mounted yet.
    readonly property real unmountedOpacity: 0.5

    // The favourite under the pointer while its reorder drag runs; it ghosts the way a dragged tab does, the bar says where it lands.
    property bool held: false
    opacity: root.held ? Theme.disabledOpacity : 1

    width: parent ? parent.width : 0
    // The rail reads denser than the list it sits beside; see Theme.qml's railRowHeight comment.
    height: Theme.railRowHeight

    Accessible.role: Accessible.ListItem
    Accessible.name: root.modelData.label

    // The rail rounds nothing: a lit place is the list row's square full-bleed fill, see ui/Row.qml.
    Rectangle {
        anchors.fill: parent
        color: root.highlighted
            ? (root.modelData.kind === "trash" ? Style.selectedAccentFill : root.focused ? Style.selectedFill : Style.normalFill)
            : "transparent"
    }

    // The eject mark's hover lift, the board's 8% rung; the mark itself lifts to foreground below.
    Rectangle {
        anchors.fill: parent
        visible: ejectLoader.item !== null && ejectLoader.item.hovered
        color: Theme.color.foreground
        opacity: Theme.washHover
    }

    Rectangle {
        visible: root.highlighted
        width: Theme.spacing.hairline * 2
        height: parent.height
        color: Theme.color.accent
    }

    // The TAGS section hands its rows their own swatch mark; every other row keeps the glyph.
    property Component tagMark: null

    Loader {
        id: mark
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.rowPaddingX
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.railIconSize
        height: Theme.railIconSize
        sourceComponent: root.modelData.kind === "dropbox" ? dropboxMark : root.tagMark !== null ? root.tagMark : glyphMark
        onLoaded: if (root.tagMark !== null) item.entry = root.modelData
    }

    // ThemeRoles.html gives every rail label and glyph the foreground role, selected rows included:
    // the cursor reads through the fill and the accent edge above, never by dimming the rows it is not on.
    Component {
        id: glyphMark
        Glyph {
            name: root.modelData.glyph
            color: root.highlighted && root.modelData.kind === "trash" ? Theme.color.accent : Theme.color.foreground
        }
    }

    // The brand marks are reproductions, so they take their own component rather than Glyph sizing.
    Component {
        id: dropboxMark
        DropboxMark {
            iconSize: Theme.railIconSize
            color: Theme.color.foreground
        }
    }

    Text {
        id: label
        visible: !root.renaming
        anchors.left: mark.right
        anchors.leftMargin: Style.spacing.rowGap
        // The label ends one gap before any trailing number, square or mark.
        anchors.right: root.trailingLabel ? parent.right : root.detail.length > 0 ? detailText.left : dot.left
        anchors.rightMargin: root.trailingLabel ? Math.min(root.width - label.x,
            Theme.spacing.rowPaddingX + root.trailingLabel.implicitWidth + Theme.spacing.gap)
            : root.keepsTrailingGap ? Style.spacing.rowGap : 0
        anchors.verticalCenter: parent.verticalCenter
        text: root.modelData.label
        color: root.modelData.error ? Theme.color.error : Theme.color.foreground
        font.family: Theme.font.family
        font.pixelSize: Theme.font.body
        // A label too long for the rail keeps its start and ends in an ellipsis.
        elide: Text.ElideRight
        clip: root.trailingLabel !== null
        textFormat: Text.PlainText
    }

    // The label's slot, holding the product's one editor, ui/RenameField.qml, in rail type.
    Loader {
        id: renameLoader
        active: root.renaming
        anchors.left: mark.right
        anchors.leftMargin: Style.spacing.rowGap
        anchors.right: root.detail.length > 0 ? detailText.left : dot.left
        anchors.rightMargin: root.keepsTrailingGap ? Style.spacing.rowGap : 0
        // The editor owns its height, one line box; the rail row centres it on whole pixels.
        y: Math.round((root.height - renameLoader.height) / 2)
        sourceComponent: RenameField {
            height: implicitHeight
            name: root.modelData.label
            onCommitted: function (newName) { root.renameCommitted(root.index, newName) }
            onAbandoned: root.renameCancelled(root.index)
        }
    }

    // What the editor holds right now, for tests through ui/Ipc.qml's railRenameEditorText.
    readonly property string editorText: renameLoader.item ? renameLoader.item.current : ""
    readonly property bool editorShown: renameLoader.item !== null && renameLoader.item.visible
    // The rail's editor as ui/Row.qml hands its own, so a test measures every host's frame the same way.
    readonly property Item editorField: renameLoader.item as Item
    // RailEject: a mounted row draws the eject mark in place of the square.
    readonly property bool showsEject: Eject.releasable(root.modelData)
    readonly property real ejectMarkSize: Theme.font.caption
    // The keyboard frame on the eject mark, read by tests/keyreach.qml.
    readonly property Item markFrameItem: ejectLoader.item ? ejectLoader.item.frame : null
    // The rail's real trailing indicator slot, so ui/Ipc.qml measures this dot instead of recomputing it.
    readonly property Item indicatorSlot: dot
    readonly property Item detailItem: root.trailingLabel || detailText
    readonly property Item labelItem: label
    readonly property bool indicatorVisible: root.showsDot && root.trailingLabel === null
    // One gap before any trailing number, square or mark; detail covers the Trash count's zero-width dot.
    readonly property bool keepsTrailingGap: root.detail.length > 0 || dot.width > 0

    Text {
        id: detailText
        visible: root.trailingLabel === null
        anchors.right: dot.left
        anchors.rightMargin: dot.width > 0 ? Style.spacing.rowGap : 0
        anchors.verticalCenter: parent.verticalCenter
        text: root.detail
        color: Theme.color.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
        font.features: { "tnum": 1 }
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
    }

    // Every right-aligned mark in the rail is centred in a caption-wide slot, so this dot and the
    // NETWORK header's "+" share one centre line whatever their ink does: align by slot, never by ink.
    Item {
        id: dot
        visible: root.trailingLabel === null
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.rowPaddingX
        anchors.verticalCenter: parent.verticalCenter
        // RailDetails rules 1 and 3 with their 2026-09-14 amendment: a drive size is a number, so
        // every device row ends its size on one x with this slot reserved after it, dot or no dot;
        // the Trash count is an indicator rather than a size, so it sits in the slot itself, on the
        // same edge as the mount dots and the NETWORK plus.
        width: root.countIsIndicator ? 0 : (root.showsDot || root.detail.length > 0 ? Theme.font.caption : 0)
        height: Theme.font.caption

        // Green once gio mount -l lists it, muted at half strength while it is only a bookmark waiting
        // to be mounted. A square, not a disc: the cut is hard corners, and the canvas draws it square.
        Rectangle {
            visible: root.showsDot && !root.showsEject
            anchors.centerIn: parent
            width: root.dotSize
            height: root.dotSize
            color: root.modelData.mounted ? Theme.color.executable : Theme.color.mutedFrame
            opacity: root.modelData.mounted ? 1 : root.unmountedOpacity
        }

        // The one-click release: the eject mark in the square's own slot, muted at rest and
        // foreground under the cursor or the pointer, the way a lifted row's metadata is. Built
        // only on a row that releases, the way the menu builds a brand mark only on its row.
        Loader {
            id: ejectLoader
            anchors.centerIn: parent
            width: root.ejectMarkSize
            height: root.ejectMarkSize
            active: root.showsEject
            sourceComponent: ejectMark
        }
    }

    // The mark and its hit box, standing only while the row releases. The hit box grows to the
    // WCAG floor and centres on the ink, the way the NETWORK header's own addMark does: a centre
    // anchor quantises an odd size difference and leaves the two centres half a pixel apart.
    Component {
        id: ejectMark
        Item {
            property alias hit: hitBox
            property alias frame: markFrame
            property alias hovered: hitHover.hovered
            width: root.ejectMarkSize
            height: root.ejectMarkSize

            Glyph {
                id: ink
                anchors.centerIn: parent
                name: "eject"
                color: root.cursor || hitHover.hovered || root.markFocused ? Theme.color.foreground : Theme.color.mutedFrame
                width: root.ejectMarkSize
                height: root.ejectMarkSize
            }

            Rectangle {
                id: markFrame
                anchors.fill: hitBox
                color: "transparent"
                border.width: Theme.spacing.hairline
                border.color: Theme.color.foreground
                visible: root.markFocused
            }

            Item {
                id: hitBox
                width: Math.max(Theme.hitMin, root.ejectMarkSize)
                height: width
                x: ink.x + (ink.width - width) / 2
                y: ink.y + (ink.height - height) / 2
                Accessible.role: Accessible.Button
                Accessible.name: Format.fill(root.modelData.group === "device" ? root.ejectWords.eject : root.ejectWords.unmount, root.modelData.label)
                Accessible.onPressAction: { if (!root.renaming) root.ejectRequested(root.index) }
                HoverHandler { id: hitHover }
                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    enabled: root.showsEject && !root.renaming
                    onTapped: root.ejectRequested(root.index)
                }
            }
        }
    }

    // Whether a scene point lands in the mark's hit box, so the row's own tap never
    // answers a press the mark's tap already took. The hit box overflows the slot it is
    // centred on, so the slot alone would hand its rim to the row underneath.
    function ejectAt(scene) {
        var target = ejectLoader.item && ejectLoader.item.hit ? ejectLoader.item.hit : dot
        var p = target.mapFromItem(null, scene.x, scene.y)
        return p.x >= 0 && p.y >= 0 && p.x < target.width && p.y < target.height
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        // Overlay taps take the grab so the covered listing cannot select the same click.
        gesturePolicy: ViewState.railAutoHide ? TapHandler.ReleaseWithinBounds : TapHandler.DragThreshold
        onTapped: function (eventPoint, button) {
            // The field owns clicks inside itself while editing; this only covers the rest of the row.
            if (root.renaming)
                return
            if (button === Qt.MiddleButton) {
                root.tabRequested(root.index)
                return
            }
            // The mark releases on its own left tap; the row must not activate underneath
            // it, while a right tap still raises the menu it always did.
            if (button === Qt.LeftButton && root.showsEject && root.ejectAt(eventPoint.scenePosition))
                return
            // A right click never activates, whatever the row is: it either raised a menu or the
            // row had nothing to offer, and it must not mount and open a stick nobody asked to open.
            if (button === Qt.RightButton) {
                root.menuRequested(root.index, eventPoint.scenePosition)
                return
            }
            root.activated(root.index)
        }
    }

    // Only favourites build a reorder handler; the row stays fixed and Sidebar draws the boundary.
    Loader {
        active: root.dragFrom >= 0
        anchors.fill: parent
        sourceComponent: Item {
            DragHandler {
                target: null
                xAxis.enabled: false
                property real startY: 0
                onActiveChanged: {
                    root.held = active
                    if (active) {
                        startY = persistentTranslation.y
                        return
                    }
                    var to = TabMove.railReorder(persistentTranslation.y - startY, root.dragFrom, Theme.railRowHeight, root.lineCount).to
                    root.reorderAt(-1)
                    if (to !== root.dragFrom)
                        root.moved(to)
                }
                onCentroidChanged: {
                    if (active)
                        root.reorderAt(TabMove.railReorder(persistentTranslation.y - startY, root.dragFrom, Theme.railRowHeight, root.lineCount).line)
                }
            }
        }
    }
}
