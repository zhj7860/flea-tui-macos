import QtQuick
import "." as Flea
import "js/Focus.js" as Focus
import "js/Drag.js" as DragOps
import "js/Eject.js" as Eject
import "js/RailKeys.js" as RailKeys
import "js/RailMenu.js" as RailMenu
import "js/Motion.js" as Motion

// The pane's rail, and the two ways it comes and goes. With Auto-hide sidebar off it is part of the
// pane and Show sidebar governs it, which is 0.2.1's behaviour. Directive 77, the requirement:
// hovering over the left side shows it, like every other autohide feature in every other file
// manager. So with the switch on the rail is withdrawn at every width, the pointer at the
// window's left edge reveals it over the pane rather than reflowing it, and it withdraws a moment
// after the pointer or the keyboard leaves. It slides in and out on x, and is built once.
Item {
    id: root

    property var pane: null
    // The window-long network host from ui/WindowBody.qml, outliving the Sidebar loader so a late mount answer still lands.
    property var service: null
    readonly property bool overlay: ViewState.railAutoHide
    readonly property bool hidden: root.overlay ? !root.revealed : ViewState.railHidden
    // An overlay owes the pane no width, so the listing never reflows as the rail comes and goes.
    // This item is that width, and the rail itself draws past it.
    readonly property real inset: root.overlay ? 0 : rail.width
    // Zero whenever the rail is withdrawn, though an auto-hide Sidebar stays built through the slide and after it.
    readonly property real railWidth: root.hidden ? 0 : rail.width
    readonly property var item: root.hidden ? null : rail.item
    // Where the sliding rail stands, which tests and railState read.
    readonly property real railX: rail.x

    function focusPress(p) {
        var pane = root.pane
        if (p.x < 0 || p.y < 0 || p.x >= pane.width || p.y >= pane.height) return
        // The shown Sidebar can extend past its zero-width overlay host.
        var sidebar = root.item
        var r = sidebar ? sidebar.mapFromItem(pane, p.x, p.y) : null
        if (!root.hidden && r && r.x >= 0 && r.y >= 0 && r.x < sidebar.width && r.y < sidebar.height) {
            if (root.overlay) pane.railPane.focusView = Focus.RAIL
        } else { pane.focusView = Focus.LIST; pane.focusRequested() }
    }

    // Long enough that crossing the edge on the way somewhere else does not flash the rail, and that
    // leaving it by a pixel on the way to a row does not drop it.
    readonly property int settleMs: 220
    property bool revealed: false
    // The rail's own context menu takes the pointer with it, so without this the rail withdraws out
    // from under the menu it just opened.
    readonly property bool menuHere: root.pane !== null && root.pane.contextMenu().opened
                                     && root.pane.contextMenu().forRail
    // The rail stays up while the pointer is on it, which is the other half of the reveal.
    readonly property bool over: railHover.hovered
    // A release in flight keeps a revealed overlay rail up; the hold below is what keeps the Sidebar when it hides anyway.
    readonly property bool releasing: rail.item !== null && (rail.item as Flea.Sidebar).releasing === true
    // Keeps the Sidebar and its gio, undrawn, through a hide mid-release; latched from the release's edges, as a binding through hidden would loop.
    property bool releaseHold: false
    readonly property bool held: root.releaseHold && root.hidden
    function holdRelease(on) {
        if (on) { root.releaseHold = true; return }
        // Past the signal that ended it, where the unload the hold was keeping would destroy the sender mid-emission.
        Qt.callLater(function () { if (!root.releasing) root.releaseHold = false })
    }
    // The pointer has rested on the edge for the dwell, and stays so until it leaves the strip.
    property bool edgeShown: false
    // The Sidebar is built by the first strip entry or Tab and then kept, so later reveals spawn nothing and keep cursor and scroll.
    property bool built: false
    readonly property bool dragHere: dragReveal.containsDrag || root.rowDragOver(rail.item)
    readonly property bool pointerWanted: root.edgeShown || root.over || root.menuHere || root.releasing || root.dragHere
    readonly property bool focusWanted: root.pane !== null && root.pane.focusView === Focus.RAIL
    readonly property bool wanted: root.pointerWanted || root.focusWanted
    // 0 withdrawn to 1 shown; the rail's x follows it, and a reversal starts from where it stands.
    property real slide: root.revealed ? 1 : 0
    Behavior on slide {
        enabled: !Theme.reducedMotion
        NumberAnimation { duration: root.revealed ? Motion.durMs.open : Motion.durMs.close; easing.type: Easing.OutCubic }
    }

    onWantedChanged: {
        if (root.wanted) { settle.stop(); root.revealed = true }
        else if (root.revealed) settle.restart()
    }
    onRevealedChanged: if (root.revealed) root.built = true
    // Tab out has no pointer to wait for, so the rail slides away at once; the pointer on the rail keeps it up through pointerWanted.
    onFocusWantedChanged: if (!root.focusWanted && !root.pointerWanted && root.revealed) { settle.stop(); root.revealed = false }
    // The switch itself is a fresh start either way: nothing is revealed until the pointer asks.
    onOverlayChanged: { dwell.stop(); root.edgeShown = false; root.built = false; root.revealed = false }

    anchors { top: parent.top; bottom: parent.bottom }
    width: root.inset

    Timer {
        id: settle
        interval: root.settleMs
        onTriggered: root.revealed = false
    }
    Timer {
        id: dwell
        interval: Motion.dwellMs
        onTriggered: root.edgeShown = true
    }

    // The strip that answers the pointer, at the window's own left edge and only while the switch is
    // on. It holds no MouseArea, so a click on the listing under it still lands on the listing.
    Item {
        id: strip
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: Theme.spacing.rowPaddingX
        enabled: root.overlay
        HoverHandler {
            id: edge
            enabled: root.overlay
            // Entering also builds the Sidebar, so the dwell covers the build; a rail already up needs no dwell.
            onHoveredChanged: {
                if (!edge.hovered) { dwell.stop(); root.edgeShown = false; return }
                root.built = true
                if (root.revealed) root.edgeShown = true
                else dwell.restart()
            }
        }
    }

    // Below the rail so Trash answers first; refusing here keeps an overlay rail drop from falling through to the listing row under it.
    DropArea {
        id: dragReveal
        objectName: "dragReveal"
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: Math.max(strip.width, rail.width)
        enabled: root.overlay
        keys: [DragOps.ROWS_MIME]
        onDropped: function (drop) { drop.accepted = false }
    }

    Loader {
        id: rail
        anchors { top: parent.top; bottom: parent.bottom }
        // The slide moves x only, so the rail's width and rows never change with the motion; visible drops when the hide slide ends.
        x: root.overlay ? (root.slide - 1) * width : 0
        width: item && !root.held ? item.implicitWidth : 0
        visible: !root.held && (!root.overlay || root.slide > 0)
        active: root.pane !== null && !root.pane.listOnly && root.pane.sharedSidebar === null
                && (root.overlay ? (root.built || root.releaseHold) : (!root.hidden || root.releaseHold))
        // A Sidebar that went for another reason took its release with it, so there is nothing left to hold.
        onItemChanged: if (item === null) root.releaseHold = false
        sourceComponent: Flea.Sidebar {
            id: sidebar
            backend: root.pane.backend
            navigationPane: root.pane.railPane
            service: root.service
            polling: !root.overlay || root.revealed
            focused: root.pane.railPane.focusView === Focus.RAIL
            trashActive: root.pane.railPane.trash.opened
            onOpened: function(path) { RailKeys.openFrom(root.pane.railPane, path, sidebar) }
            // Sidebar040: the rail's Recent row answers with the history's own paths, which the
            // pane lists with listpaths; focus follows into the folder the way a mount's open does.
            onRecentRequested: function (paths, requester, visits) { var target = requester || root.pane.railPane; target.openRecent(paths, visits); RailKeys.landed(target, sidebar) }
            onTrashRequested: root.pane.railPane.trash.open()
            onMessage: function(text, isError) { RailKeys.messaged(sidebar, isError); root.pane.message(text, isError) }
            onOperationResult: function(headline, detail, isError) { RailKeys.messaged(sidebar, isError); root.pane.operationResult(headline, detail, isError) }
            onForgetMessage: function(text) { root.pane.forgetMessage(text) }
            menu: root.pane.railPane.contextMenu()
            onRenameFinished: root.pane.railPane.listArea.forceActiveFocus()
            // The pane's own PointHandler never sees a press a row grabs, so an overlay rail claims the keyboard itself; a docked rail leaves it.
            onPressed: if (root.overlay) root.pane.railPane.focusView = Focus.RAIL
            onReleasingChanged: root.holdRelease(sidebar.releasing)
        }
        // Disabled with the Sidebar, so an unload under the pointer clears it; a handler inside the Sidebar dies without reporting.
        HoverHandler { id: railHover; enabled: rail.active && !root.held }
    }

    // The rail's Sidebar renders the window-long service below; the service's answers
    // route once by origin in ui/WindowBody.qml, so this file carries no Connections of its
    // own and a dual-view open cannot fire twice.

    // Ctrl+E from a listing with the rail hidden. The rail Loader above unloads the Sidebar with
    // its DeviceMounts poll, eject verdict state and releaseChosen, so the key has nothing to read
    // and nothing to release through. It spins this transient instead: the same DeviceMounts
    // component the rail uses, never a second poller, alive only for this flow. Its first listing
    // resolves the holding volume through the same Mounts.holding and Mounts.railMenu verdict and
    // releases through the same RailMenu.release and devices.eject path with the same messages;
    // the verdict lands, the host unloads, and while nothing is pressed nothing here exists.
    property bool hiddenEjectArmed: false
    function unloadHiddenEject() {
        // Past the signal that asked, which a synchronous unload would destroy mid-emission; a release in flight keeps the host, whose end kills its gio.
        Qt.callLater(function () {
            if (!hiddenEject.item || !hiddenEject.item.releasing)
                hiddenEject.active = false
        })
    }
    function ejectHidden() {
        if (!root.pane)
            return
        if (!hiddenEject.active) {
            hiddenEjectArmed = true
            hiddenEject.active = true
            return
        }
        // A flow is already waiting on its first listing, or an eject is running: re-resolve
        // against the freshest entries, where the service refuses a concurrent eject itself.
        hiddenEjectArmed = true
        if (hiddenEject.item && hiddenEject.item.firstAnswered)
            root.hiddenEjectReady()
    }
    function hiddenEjectReady() {
        var device = hiddenEject.item
        if (!device || !hiddenEjectArmed)
            return
        hiddenEjectArmed = false
        // Sidebar shape with no network entries: only a volume resolves; a share keeps the pane's own answer.
        var adapter = { entries: device.entries, deviceEntries: device.entries, networkEntries: [] }
        adapter.releaseChosen = function (action, key) { RailMenu.release(action, key, device, null, adapter) }
        Eject.release(root.pane, adapter, false)
        root.unloadHiddenEject()
    }
    Loader {
        id: hiddenEject
        active: false
        sourceComponent: Flea.DeviceMounts {
            showUnmounted: ((ViewState.state.places || {}).showUnmounted !== false)
            onOpened: function (path) { root.pane.open(path) }
            onMessage: function (text, isError) { root.pane.message(text, isError) }
            onOperationResult: function (headline, detail, isError) { root.pane.operationResult(headline, detail, isError) }
            onReleasingChanged: root.unloadHiddenEject()
            onForgetMessage: function (text) { root.pane.forgetMessage(text) }
            onQuiesce: function (path) { root.pane.quiesceVolume(path) }
            onFirstAnsweredChanged: root.hiddenEjectReady()
        }
    }

    // A child row DropArea takes the drag from dragReveal; its live containsDrag binding keeps the rail up.
    function rowDragOver(item) {
        if (!item) return false
        if (item.containsDrag === true) return true
        for (var i = 0; i < item.children.length; i++) {
            if (root.rowDragOver(item.children[i])) return true
        }
        return false
    }
}
