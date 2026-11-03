import QtQuick
import "js/Focus.js" as Focus
import "js/Flash.js" as Flash
import "js/FlashPane.js" as FlashPane

// Built once per window on first use with no placeholder; one host serves every later open and marks its pane active.
Loader {
    id: root
    property var coverPane: null
    active: false
    visible: opened
    readonly property bool opened: item !== null && item.opened
    readonly property int count: item ? item.driveCount : 0
    // The counts zone's own line while the host owns the pane, read by the window.
    readonly property string countText: Flash.drivesLine(root.count)

    // Covers the opening pane's slot as Trash does; a second pane cannot take it while a flash runs.
    function openFor(pane, image, device) {
        if (root.item && root.item.pane !== pane && root.item.transfer.running === true) {
            pane.message(Flash.alreadyRunning(), false)
            return
        }
        FlashPane.cover(root, pane)
        root.parent = pane
        root.anchors.fill = pane
        root.anchors.leftMargin = pane.sidebarWidth
        root.active = true
        if (!root.item || root.item.pane !== pane)
            root.setSource("FlashView.qml", { pane: pane, statusBar: pane.statusBar })
        if (image && image.length > 0)
            root.item.openWithImage(image)
        else
            root.item.openWithDrive(device)
    }
    function close() {
        if (root.opened)
            root.item.close()
        FlashPane.uncover(root)
    }
    // The read-only seam's own flash readers, so ui/Ipc.qml stays one call per entry point.
    function describe() {
        var view = root.item
        if (!view)
            return "{\"opened\":false}"
        return JSON.stringify({ opened: view.opened, cursor: view.cursor,
            image: view.image ? view.image.path : "", drives: view.drives.length,
            selected: view.selected, live: view.live, running: view.running,
            phase: view.running ? view.transfer.phase : "",
            ending: view.ending ? view.ending.headline : "" })
    }
    function controlItem(name) {
        var view = root.item
        if (!view)
            return null
        return name === "flash" ? view.flashItem : name === "cancel" ? view.cancelItem
            : name === "end" ? view.endItem : null
    }
    Connections {
        target: root.item
        function onBackRequested() {
            if (!root.coverPane)
                return
            FlashPane.uncover(root)
            root.coverPane.focusView = Focus.LIST
            root.coverPane.listArea.forceActiveFocus()
        }
        function onFocusRailRequested() {
            if (root.coverPane)
                root.coverPane.focusView = Focus.RAIL
        }
    }
}
