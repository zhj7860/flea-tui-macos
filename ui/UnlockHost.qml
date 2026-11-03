import QtQuick
import "." as Flea
import "js/Unlock.js" as Unlock

// Unlock (U039): the encrypted-drive dialog's host, over the whole window.
// Created once per window on first use, so no placeholder object stands before it; the unlocked-drive follow lives here.
Item {
    id: root
    anchors.fill: parent
    property var window: null
    property var footer: null
    property var sidebar: null
    property string pendingPath: ""
    property int lockedCursor: -1
    // The device flea --unlock opened on, until a rail row names it.
    property string unnamedDevice: ""
    // The pending poller answered once, so its Loader never runs again for this card.
    property bool _namePollDone: false
    // The poller's last listing, kept after its Loader ends, so the first row still names the card.
    property var _pollEntries: []
    readonly property bool opened: loader.item !== null && loader.item.opened
    // The test seam reads the card through this, so no writer ever reaches past the host.
    readonly property var dialog: loader.item
    // The test seam reads the poller's life through this, never its item.
    readonly property bool namePolling: namePoller.active

    function openFor(device, label, size, fstype, rail) {
        if (rail !== undefined && rail !== null)
            root.sidebar = rail
        root.lockedCursor = root.cursorOnRow(device)
        loader.active = true
        loader.item.openFor(device, label, size, fstype, root.versionFor(root.sidebar, device))
    }
    // The rail row carries lsblk's FSVER, so the card reads LUKS1 or LUKS2 with no signal change.
    function versionFor(rail, device) {
        var row = Unlock.namingRow(rail ? rail.deviceEntries : [], root.fallbackEntries(), device)
        return row ? String(row.fsver || "") : ""
    }
    // The locked row wherever the device list lives, the rail first; a hidden rail unloads its own list with the Sidebar.
    function lookupRow(device) {
        return Unlock.namingRow(root.sidebar ? root.sidebar.deviceEntries : [], root.fallbackEntries(), device)
    }
    // A hidden rail unloads its poll with the Sidebar, so this one-shot lister names the CLI card instead.
    function fallbackEntries() {
        return namePoller.item ? namePoller.item.entries : root._pollEntries
    }
    // flea --unlock may open before the rail's first lsblk, so the card shows the device's leaf until its locked row names it.
    function openForDevice(devicePath, rail) {
        var leaf = String(devicePath || "").split("/").pop()
        openFor(devicePath, leaf, 0, "LUKS", rail)
        root._namePollDone = false
        root._pollEntries = []
        root.unnamedDevice = String(devicePath || "")
        root.nameDevice()
    }
    // A card the user has started on never takes a name, so its poller never starts.
    function cardTouched() {
        var unlockDialog = loader.item
        return !!unlockDialog && (unlockDialog.phase !== "typing" || unlockDialog.noteText.length > 0 || unlockDialog.masked)
    }
    // The first touch latches the one-shot shut, so erasing never restarts the poller.
    readonly property bool _touched: root.cardTouched()
    on_TouchedChanged: if (root._touched) root._namePollDone = true
    // Only an untouched card takes the name, so nothing the user has started on changes the drive it names.
    function nameDevice() {
        var unlockDialog = loader.item
        if (root.unnamedDevice.length === 0 || !unlockDialog || !unlockDialog.opened || unlockDialog.device !== root.unnamedDevice) {
            root.unnamedDevice = ""
            return
        }
        // A touched card ends the pending name for good, so no later listing renames it.
        if (root.cardTouched()) {
            root._namePollDone = true
            root.unnamedDevice = ""
            return
        }
        var row = root.lookupRow(root.unnamedDevice)
        // One-shot: the poller's first listing ends the wait whether it named the card or not.
        if (!row) {
            if (root._namePollDone)
                root.unnamedDevice = ""
            return
        }
        root.unnamedDevice = ""
        unlockDialog.describe(row.label, row.size, row.fstype, row.fsver)
    }

    // After an unlock the locked row is a crypt row in the same place; put the cursor on it,
    // so the unlocked drive stays current. Matched by mountpoint: udisksctl names /dev/dm-N, lsblk /dev/mapper/.
    function followUnlocked(path) {
        root.pendingPath = String(path || "")
        root.landCursor(true)
    }
    // Answers whether the cursor landed; stashes for the next rebuild when asked.
    function landCursor(stash) {
        var rail = root.sidebar
        var want = root.pendingPath
        if (!rail || want.length === 0) {
            root.pendingPath = ""
            return false
        }
        var at = rail.placesEntries.length + rail.networkEntries.length
        for (var i = 0; i < rail.deviceEntries.length; i++) {
            if (String(rail.deviceEntries[i].path || "") === want) {
                root.pendingPath = ""
                rail.cursorIndex = at + i
                return true
            }
        }
        if (stash !== true)
            root.pendingPath = ""
        return false
    }

    // The rail index of the cursor when it sits on this device's own row, else -1: the locked row the unlock was asked on.
    function cursorOnRow(device) {
        var rail = root.sidebar
        if (!rail || rail.cursorIndex < 0)
            return -1
        var row = rail.deviceEntries[rail.cursorIndex - rail.placesEntries.length - rail.networkEntries.length]
        return row && String(row.device || "") === device ? rail.cursorIndex : -1
    }

    // A rebuilt rail ends the follow when the cursor moved off the locked row, and lands it otherwise.
    function settleFollow() {
        if (root.pendingPath.length === 0)
            return
        var rail = root.sidebar
        if (!rail || (rail.cursorIndex !== -1 && rail.cursorIndex !== root.lockedCursor)) {
            root.pendingPath = ""
            return
        }
        root.landCursor(false)
    }

    // The CLI card's own poll while its name is pending, one listing only; it overlaps the rail's poll because the rail's first lsblk can lag the CLI open.
    Loader {
        id: namePoller
        active: root.unnamedDevice.length > 0 && root.opened && !root._namePollDone && !root.cardTouched()
        sourceComponent: pollerComponent
    }
    Component {
        id: pollerComponent
        Flea.DeviceMounts {}
    }
    Connections {
        target: namePoller.item
        // The first answer ends the Loader below, so its listing is kept here first.
        function onEntriesChanged() { root._pollEntries = namePoller.item.entries }
        // An empty first listing changes no entries, so its answer latches here instead.
        function onFirstAnsweredChanged() {
            if (namePoller.item && namePoller.item.firstAnswered) {
                // A listing the timeout ended answered nothing, so the one-shot polls again for one that did.
                if (namePoller.item.listTimedOut) {
                    namePoller.item.firstAnswered = false
                    namePoller.item.poll()
                    return
                }
                root._namePollDone = true
                root.nameDevice()
            }
        }
    }
    Loader {
        id: loader
        anchors.fill: parent
        z: 2
        active: false
        source: "UnlockDialog.qml"
        onLoaded: {
            item.closed.connect(root.onDialogClosed)
            item.unlocked.connect(root.onDialogUnlocked)
            item.lockFailed.connect(root.onDialogLockFailed)
        }
    }
    Connections {
        // A plain test rail emits nothing, so only a rail with the signal is the target.
        target: root.sidebar && root.sidebar.entriesChanged ? root.sidebar : null
        function onEntriesChanged() { root.settleFollow(); root.nameDevice() }
    }
    function onDialogClosed() {
        if (root.window)
            root.window.currentPane.forceActiveFocus()
    }
    // A dialog that ended without a volume could not put the container back; the drive is named.
    function onDialogLockFailed(note) {
        if (root.footer)
            root.footer.say(note, true)
    }
    // The rail's own open, so a rail Enter's focus claim lands in the folder as any mount-first open does (RailKeys.landed).
    function onDialogUnlocked(path, label, note) {
        if (!root.window)
            return
        if (!root.sidebar) {
            // No rail to open through, so the current pane opens the folder itself, with the note said below.
            root.window.currentPane.open(path)
        } else {
            root.sidebar.opened(path)
            // The unlocked row and its eject mark land now, not at the rail's next five second poll.
            root.sidebar.pollDevices()
            root.followUnlocked(path)
        }
        if (root.footer)
            root.footer.say(note, false)
    }
}
