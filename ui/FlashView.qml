import QtQuick
import Quickshell
import Quickshell.Io
import "." as Flea
import "js/Flash.js" as Flash
import "js/FlashPane.js" as FlashPane
import "js/Keymap.js" as Keymap
import "js/Ops.js" as Ops

// Flash image swaps the listing like Trash does; Esc, Back and Backspace leave the pane and never cancel a flash.
FocusScope {
    id: root
    required property var pane
    property var statusBar: null
    property bool opened: false
    // The image under test, or null before the picker names one.
    property var image: null
    // A rail volume's device path waiting for the drive list to name its disk.
    property string pendingDrive: ""
    property var drives: []
    property bool drivesReady: false
    // The chosen drive's row, held by identity so a poll that reorders the list never retargets Flash or Eject.
    property var chosen: null
    // Set once this opening holds a drive, so a choice that left stays empty instead of falling to the one fitting drive left.
    property bool held: false
    readonly property int selected: FlashPane.indexOf(root.drives, root.chosen)
    property int cursor: 0
    property int requestId: 0
    property bool ejected: false
    // The flash's own run, answered by the backend; the view owns the cursor and the rows.
    readonly property var transfer: runner.transfer
    readonly property bool running: runner.running
    readonly property var ending: runner.ending
    readonly property real rate: runner.rate
    readonly property int driveCount: root.drives.length
    readonly property var chosenDrive: root.selected >= 0 && root.selected < root.drives.length ? root.drives[root.selected] : null
    readonly property int flashRow: Flash.flashPos(root.drives.length)
    readonly property bool imageOk: root.image !== null && root.image.refused !== true
    readonly property bool live: Flash.flashLive(root.imageOk, root.chosenDrive)
    readonly property var words: Flash.flashWords(root.imageOk, root.chosenDrive, root.drives)
    signal backRequested()
    signal focusRailRequested()
    anchors.fill: parent
    visible: opened
    // The seam's own handles onto the step's controls, so a driven case clicks what it named.
    readonly property var flashItem: stepRow.flashItem
    readonly property var cancelItem: stepRow.cancelItem
    readonly property var endItem: stepRow.endItem

    function open() {
        // Reopening onto a running flash shows it, never restarts it, and takes its card back from the pane.
        if (runner.running) {
            FlashPane.reclaim(root.pane)
            root.opened = true
            root.forceActiveFocus()
            return
        }
        runner.reset()
        root.ejected = false
        root.opened = true
        root.drives = []
        root.drivesReady = false
        root.forceActiveFocus()
    }

    function openWithImage(path) {
        if (runner.running)
            return root.open()
        root.image = { path: path, kind: "", bytes: 0, unpacked: 0, known: false, member: "", refused: false }
        root.pendingDrive = ""
        root.chosen = null
        root.cursor = 0
        root.open()
        root.pane.backend.flashImage(path)
        root.pane.backend.flashTargets(path)
    }

    function openWithDrive(device) {
        if (runner.running)
            return root.open()
        root.pendingDrive = device
        root.chosen = null
        root.cursor = 0
        root.open()
        if (root.image)
            root.pane.backend.flashImage(root.image.path)
        root.pane.backend.flashTargets(root.image ? root.image.path : "")
    }

    function close() {
        if (!root.opened)
            return
        root.opened = false
        // After Back the running flash joins the pane's transfer the way a copy's does.
        if (root.running) {
            root.pane.transfer = root.transfer
            root.pane.sticky(Ops.progressLine(root.transfer))
        }
        root.backRequested()
    }

    function chooseImage() {
        if (chooser.running || root.running)
            return
        var home = Quickshell.env("HOME") || ""
        chooser.command = [Quickshell.env("FLEA_BIN") || "flea", "flash", "choose", home + "/Downloads"]
        chooser.running = true
    }

    function pressFlash() {
        if (runner.pressSent || !root.live || root.running)
            return
        var drive = root.chosenDrive
        root.requestId += 1
        runner.pressSent = true
        runner.pendingId = root.requestId
        root.pane.backend.flash(root.requestId, root.image.path, drive.dev, drive.seq, drive.serial, drive.bytes)
    }

    function pressCancel() {
        if (!root.running)
            return
        root.pane.backend.flashCancel(root.transfer.id)
    }

    function ejectChosen() {
        var drive = root.chosenDrive
        if (!drive || root.running || root.ejected)
            return
        root.pane.backend.flashEject(drive.dev, drive.seq)
    }

    function cursorDrive() {
        return root.cursor > 0 && root.cursor <= root.drives.length ? root.cursor - 1 : -1
    }

    function moveCursor(delta) {
        // While a flash runs the cursor stays between the drive being flashed and Cancel.
        if (root.running) {
            root.cursor = root.cursor === root.flashRow ? root.selected + 1 : root.flashRow
            root.parkFocus()
            return
        }
        root.cursor = Flash.step(root.cursor, delta, root.drives, root.image !== null, true)
        root.chosen = FlashPane.chooseKept(root.cursor, root.drives, root.chosen)
        root.parkFocus()
    }

    function parkFocus() {
        if (!root.opened)
            return
        // After Eject no button is drawn, so the keyboard rests on the pane itself.
        if (root.ejected) {
            root.forceActiveFocus()
            return
        }
        if (root.cursor === root.flashRow && !root.running) {
            if (root.ending && (root.ending.flashBack || root.ending.eject) && stepRow.endItem)
                stepRow.endItem.forceActiveFocus()
            else if (!root.ending && stepRow.flashItem)
                stepRow.flashItem.forceActiveFocus()
            else
                root.forceActiveFocus()
        } else if (root.cursor === root.flashRow && stepRow.cancelItem) {
            stepRow.cancelItem.forceActiveFocus()
        } else {
            root.forceActiveFocus()
        }
    }

    // A focused button owns Enter and Space itself, so the scope stands aside for those keys.
    function buttonFocused() {
        return (stepRow.flashItem && stepRow.flashItem.activeFocus)
            || (stepRow.cancelItem && stepRow.cancelItem.activeFocus)
            || (stepRow.endItem && stepRow.endItem.activeFocus)
    }

    // The ending row's own action: Eject where one is offered, Flash again under a failure.
    function pressEnd() {
        if (root.ending && root.ending.flashBack)
            root.pressFlash()
        else
            root.ejectChosen()
    }

    function contextPress() {
        var atDrive = root.cursorDrive()
        if (root.running) {
            if (root.cursor === root.flashRow)
                root.pressCancel()
            return
        }
        if (root.ending !== null) {
            if (root.cursor === root.flashRow) {
                if (root.ending.eject)
                    root.ejectChosen()
                else if (root.ending.flashBack)
                    root.pressFlash()
            } else if (root.cursor === 0) {
                root.chooseImage()
            } else if (atDrive >= 0) {
                root.chosen = root.drives[atDrive]
                root.cursor = root.flashRow
                root.parkFocus()
            }
            return
        }
        if (root.cursor === 0) {
            root.chooseImage()
            return
        }
        if (atDrive >= 0) {
            root.chosen = root.drives[atDrive]
            root.cursor = root.flashRow
            root.parkFocus()
            return
        }
        if (root.cursor === root.flashRow)
            root.pressFlash()
    }

    function receiveImage(message) {
        if (!root.opened && !root.running)
            return
        var image = Flash.imageFrom(root.image, message)
        if (image)
            root.image = image
    }

    function receiveTargets(message) {
        if (!root.opened && !root.running)
            return
        var rows = message.drives || []
        var was = root.drives
        var first = !root.drivesReady
        root.drives = rows
        root.drivesReady = true
        if (root.running)
            return
        // A fitting drive plugged in after Eject brings the Flash row back.
        if (root.ejected) {
            if (rows.filter(function (drive) { return Flash.fits(drive) }).length === 0)
                return
            root.ejected = false
            runner.ending = null
        }
        var next = FlashPane.reconcile({ chosen: root.chosen, cursor: root.cursor, drives: was, first: first,
            held: root.held, pendingDisk: root.pendingDrive }, rows)
        FlashPane.land(root, next)
        if (next.moved)
            root.parkFocus()
    }

    function startTransfer(id, total, known) {
        var drive = root.chosenDrive
        var label = drive ? Flash.driveName(drive, root.drives) : ""
        runner.startTransfer(id, total, known, root.image ? Flash.leaf(root.image.path) : "", label, root.opened)
        root.cursor = root.flashRow
        root.parkFocus()
    }

    function progressTransfer(id, phase, bytes, total, permille) {
        runner.progressTransfer(id, phase, bytes, total, permille, root.opened)
    }

    function finishTransfer(message) {
        var imageName = root.image ? Flash.leaf(root.image.path) : ""
        var landed = runner.finishTransfer(message, imageName, root.transfer.drive,
            root.chosen ? root.chosen.bytes : 0, root.opened)
        if (landed === "refused")
            root.pane.backend.flashImage(root.image ? root.image.path : "")
        else if (landed) {
            root.cursor = root.flashRow
            root.parkFocus()
        }
    }

    function finishEject(message) {
        var drive = root.chosenDrive
        runner.finishEject(message, drive ? Flash.driveName(drive, root.drives) : "")
        if (message.ok === true) {
            root.ejected = true
            root.parkFocus()
        }
    }

    Keys.onPressed: function (event) {
        var action = Keymap.lookup(event.key, event.text, event.modifiers, "listing", "gui")
        var unmodified = (event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier | Qt.AltModifier | Qt.MetaModifier)) === 0
        if (action === "escape" && root.statusBar && root.statusBar.escapePressed()) { event.accepted = true; return }
        if (action === "escape" || (event.key === Qt.Key_Backspace && unmodified)) root.close()
        else if (action === "cursorDown") root.moveCursor(1)
        else if (action === "cursorUp") root.moveCursor(-1)
        else if (action === "eject") root.ejectChosen()
        else if (action === "focusNext") root.focusRailRequested()
        else if (action === "open" || (event.key === Qt.Key_Space && unmodified)) {
            if (root.buttonFocused()) { event.accepted = true; return }
            // A held Enter stops on Flash instead of pressing it: only a fresh press confirms.
            if (event.isAutoRepeat && root.cursor === root.flashRow && root.ending === null) { event.accepted = true; return }
            root.contextPress()
        }
        event.accepted = true
    }

    Process {
        id: chooser
        stdout: StdioCollector { id: chosenText }
        // A chooser that never answers is the backend's refusal, so the pane keeps its drives.
        onExited: function (exitCode, exitStatus) {
            if (exitCode !== 0)
                return
            var path = chosenText.text.trim()
            if (path.length > 0)
                root.openWithImage(path)
        }
    }

    Connections {
        target: root.pane.backend
        function onFlashImageResult(message) { root.receiveImage(message) }
        function onFlashTargetsResult(message) { root.receiveTargets(message) }
        function onFlashStartedLine(id, total, known) { root.startTransfer(id, total, known) }
        function onFlashProgressLine(id, phase, bytes, total, permille) { root.progressTransfer(id, phase, bytes, total, permille) }
        function onFlashDoneLine(message) { root.finishTransfer(message) }
        function onFlashEjectLine(message) { root.finishEject(message) }
    }

    // A fitting drive plugged in after Eject brings the Flash row back; the rail's own poll period is the tick.
    readonly property int pollMs: 5000
    Timer {
        interval: root.pollMs
        repeat: true
        running: root.opened && !root.running
        onTriggered: root.pane.backend.flashTargets(root.image ? root.image.path : "")
    }

    // The flash's own run, answered by the backend; the view owns the cursor and the rows.
    Flea.FlashRunner {
        id: runner
        pane: root.pane
    }

    Rectangle { anchors.fill: parent; color: Theme.color.background }

    Column {
        anchors.fill: parent
        spacing: 0
        // The strip without an action: Back, an unavailable Up, the title, nothing else.
        Flea.FlashStrip {
            width: parent.width
            onBack: root.close()
        }
        Flea.FlashImageRow {
            width: parent.width
            image: root.image
            cursor: root.cursor === 0
            focused: root.activeFocus
            running: root.running
            onChoose: {
                root.cursor = 0
                root.parkFocus()
                root.contextPress()
            }
        }
        Flea.FlashDriveRows {
            width: parent.width
            drives: root.drives
            drivesReady: root.drivesReady
            selected: root.selected
            cursor: root.cursor
            focused: root.activeFocus
            running: root.running
            onChooseDrive: function (index) {
                root.chosen = root.drives[index]
                root.cursor = root.flashRow
                root.parkFocus()
            }
        }
        // The Flash step: one 37 px row carrying the alert mark, the erase line and the action.
        Flea.FlashStepRow {
            id: stepRow
            width: parent.width
            transfer: root.transfer
            rate: root.rate
            words: root.words
            live: root.live
            running: root.running
            ending: root.ending
            ejected: root.ejected
            cursor: root.cursor === root.flashRow
            focused: root.activeFocus
            onPressFlash: root.pressFlash()
            onPressCancel: root.pressCancel()
            onPressEnd: root.pressEnd()
        }
    }
}
