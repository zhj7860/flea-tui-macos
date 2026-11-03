//@ pragma ShellId flea-button-heldmask-test

import QtQuick
import QtTest
import Quickshell
import "flea" as Flea

// tests/button-system.sh's fourth harness: a wrong archive password keeps its bullets as DialogField's heldMask, and clearing them is an edit, so the error sentence goes with them.
ShellRoot {
    id: shell

    // Quiet ticks, a count of frames and never time, before the window is up and the field can take focus.
    readonly property int settleTicks: 4
    readonly property int tickMs: 16
    readonly property int noDelay: 0
    readonly property int held: 3
    readonly property string rootDir: Quickshell.env("BUTTONSYS_ROOT") || ""

    property int checks: 0
    property int ticks: 0
    property int edits: 0
    property var failures: []

    function log(line) { console.log("HELDMASK " + line) }
    function check(name, actual, expected) {
        shell.checks += 1
        if (JSON.stringify(actual) === JSON.stringify(expected)) { shell.log("ok " + name); return }
        shell.failures.push(name)
        shell.log("FAIL " + name + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }
    function finish() {
        shell.log("DONE checks=" + shell.checks + " failed=" + shell.failures.length)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    FloatingWindow {
        implicitWidth: 400
        implicitHeight: 80
        color: "#303030"

        Flea.DialogField { id: field; x: 20; y: 10; width: 360; label: "Password"; secret: true; onEdited: shell.edits += 1 }
        TestEvent { id: driver }
    }

    function run() {
        var inside = shell.rootDir.length > 0 && (Quickshell.env("HOME") || "").indexOf(shell.rootDir + "/") === 0
        shell.check("sandbox: HOME lies under the harness root", inside, true)
        if (!inside) { shell.finish(); return }
        field.heldMask = shell.held
        field.takeFocus()
        driver.keyClick(Qt.Key_Backspace, Qt.NoModifier, shell.noDelay)
        shell.check("Backspace on held bullets clears them as one edit", [field.heldMask, field.text, shell.edits], [0, "", 1])
        driver.keyClick(Qt.Key_Backspace, Qt.NoModifier, shell.noDelay)
        shell.check("Backspace on an empty field with nothing held is no edit", shell.edits, 1)
        field.heldMask = shell.held
        driver.keyClick(Qt.Key_Delete, Qt.NoModifier, shell.noDelay)
        shell.check("Delete on held bullets clears them as one edit too", [field.heldMask, shell.edits], [0, 2])
        shell.finish()
    }

    Timer {
        interval: shell.tickMs
        repeat: true
        running: true
        onTriggered: {
            shell.ticks += 1
            if (shell.ticks === shell.settleTicks) { running = false; shell.run() }
        }
    }
}
