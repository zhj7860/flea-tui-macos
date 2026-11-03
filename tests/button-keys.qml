//@ pragma ShellId flea-button-keys-test

import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "qml-probe.js" as QmlProbe

// tests/button-system.sh's key harness: a focused dialog button and a focused close mark answer Return, keypad Enter and Space as a press does, and Tab on a button reports to its dialog's own order.
ShellRoot {
    id: shell

    readonly property int noDelay: 0
    readonly property int tickMs: 16
    readonly property int readyTicks: 4
    readonly property string rootDir: Quickshell.env("BUTTONSYS_ROOT") || ""

    property int checks: 0
    property var failures: []
    property int ticks: 0
    property var menuSent: []
    property var permSent: []

    function log(line) { QmlProbe.log("KEYS", line) }
    function check(name, actual, expected) { QmlProbe.checkLoud(shell, name, actual, expected) }
    function finish() {
        QmlProbe.logDone(shell)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
    function underRoot(path) {
        return shell.rootDir.length > 0 && path.indexOf(shell.rootDir + "/") === 0 && path.split("/").indexOf("..") < 0
    }
    function key(code) {
        driver.keyClick(code, code === Qt.Key_Enter ? Qt.KeypadModifier : Qt.NoModifier, shell.noDelay)
    }
    function ops(sent, op) { return sent.filter(function (m) { return m.op === op }).length }

    // One Permissions card for one file, inspected and editable, so Cancel and Apply are both live.
    function openPermissions() {
        perm.open("/box/a", parking)
        perm.receive({ op: "inspect", id: perm.requestId, ok: true, mode: "0644", reason: "" })
    }
    function permControl(name) {
        var controls = perm.controls()
        for (var i = 0; i < controls.length; i++) if (controls[i].name === name) return controls[i].item
        return null
    }

    function menuKeys() {
        var keys = [["Return", Qt.Key_Return], ["keypad Enter", Qt.Key_Enter], ["Space", Qt.Key_Space]]
        for (var i = 0; i < keys.length; i++) {
            copyTo.open("copyTo", 1, "/box", parking)
            copyTo.closeItem.forceActiveFocus()
            shell.key(keys[i][1])
            shell.check("Copy to: " + keys[i][0] + " on the focused Cancel closes the card", copyTo.opened, false)
            copyTo.open("copyTo", 1, "/box", parking)
            copyTo.submitItem.forceActiveFocus()
            var before = shell.ops(shell.menuSent, "validate")
            shell.key(keys[i][1])
            shell.check("Copy to: " + keys[i][0] + " on the focused Copy submits once", shell.ops(shell.menuSent, "validate") - before, 1)
            copyTo.busy = false
            copyTo.close()
        }
        copyTo.open("copyTo", 1, "/box", parking)
        copyTo.closeItem.forceActiveFocus()
        shell.key(Qt.Key_Tab)
        shell.check("Copy to: Tab on Cancel reaches Copy", [copyTo.closeItem.activeFocus, copyTo.submitItem.activeFocus], [false, true])
        shell.key(Qt.Key_Tab)
        shell.check("Copy to: Tab on Copy wraps to the field", copyTo.fieldItem.activeFocus, true)
        copyTo.close()
    }

    function permissionKeys() {
        var keys = [["Return", Qt.Key_Return], ["keypad Enter", Qt.Key_Enter], ["Space", Qt.Key_Space]]
        for (var i = 0; i < keys.length; i++) {
            shell.openPermissions()
            permControl("Cancel").forceActiveFocus()
            shell.key(keys[i][1])
            shell.check("Permissions: " + keys[i][0] + " on the focused Cancel closes the card", perm.opened, false)
            shell.openPermissions()
            perm.stripItems.close.forceActiveFocus()
            shell.key(keys[i][1])
            shell.check("Permissions: " + keys[i][0] + " on the focused close mark closes the card", perm.opened, false)
            shell.openPermissions()
            permControl("Apply").forceActiveFocus()
            var before = shell.ops(shell.permSent, "apply")
            shell.key(keys[i][1])
            shell.check("Permissions: " + keys[i][0] + " on the focused Apply applies once", shell.ops(shell.permSent, "apply") - before, 1)
            perm.busy = false
            perm.close()
        }
        shell.openPermissions()
        permControl("Cancel").forceActiveFocus()
        shell.key(Qt.Key_Tab)
        shell.check("Permissions: Tab on Cancel reaches Apply", [permControl("Cancel").activeFocus, permControl("Apply").activeFocus], [false, true])
        shell.key(Qt.Key_Backtab)
        shell.check("Permissions: Shift Tab on Apply returns to Cancel", permControl("Cancel").activeFocus, true)
        perm.facts = ({ ok: true, reason: "read-only", mode: "0644" })
        var walk = []
        perm.focusItems(perm.cardItem, walk)
        shell.check("Permissions: an unavailable Apply is out of the Tab walk", [walk.indexOf(permControl("Cancel")) >= 0, walk.indexOf(permControl("Apply")) >= 0], [true, false])
        perm.close()
    }

    FloatingWindow {
        id: window
        implicitWidth: 800
        implicitHeight: 700
        color: "#303030"

        Item { id: menuHost; width: 800; height: 700; Flea.MenuActionDialog { id: copyTo } }
        Item { id: permHost; width: 800; height: 700; Flea.PermissionsDialog { id: perm } }
        Item { id: parking; y: 690; width: 10; height: 10; focus: true }

        TestEvent { id: driver }
    }

    Timer {
        interval: shell.tickMs
        repeat: true
        running: true
        onTriggered: {
            shell.ticks += 1
            if (shell.ticks < shell.readyTicks) return
            running = false
            var inside = shell.underRoot(Flea.ViewState.store.path) && shell.underRoot(Quickshell.env("HOME") || "")
            shell.check("sandbox: the state file and HOME lie under the harness root", inside, true)
            if (inside) {
                shell.menuKeys()
                shell.permissionKeys()
            }
            shell.finish()
        }
    }

    Component.onCompleted: {
        copyTo.requested.connect(function (m) { shell.menuSent.push(m) })
        perm.requested.connect(function (m) { shell.permSent.push(m) })
    }
}
