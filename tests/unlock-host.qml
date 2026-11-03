//@ pragma ShellId flea-unlock-host-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Unlock.js" as Unlock

// tests/unlock-host.sh's harness: the real UnlockHost with no rail, proving an unlock opens the folder and says the note.
ShellRoot {
    id: shell

    property var failures: []
    property int ticks: 0
    property int phase: 0
    property int waits: 0

    function log(line) { console.log("UNLOCKHOST " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(name, cond, detail) {
        if (cond) shell.log("PASS " + name)
        else shell.failures.push(name + " got " + detail)
    }
    function step(next) { shell.phase = next; shell.waits = 0 }
    function hold(ticks) {
        if (shell.waits++ < ticks) return true
        shell.waits = 0
        return false
    }
    function until(done, ticks) {
        if (!done && shell.waits++ < ticks) return true
        shell.waits = 0
        return false
    }
    function finish() {
        for (var i = 0; i < shell.failures.length; i++)
            shell.log("FAIL " + shell.failures[i])
        shell.log("DONE failures=" + shell.failures.length)
        shell.phase = 99
        shell.quit()
    }

    QtObject {
        id: fakePane
        property string openedPath: ""
        function open(path) { fakePane.openedPath = String(path) }
    }
    QtObject {
        id: fakeWindow
        property var currentPane: fakePane
    }
    QtObject {
        id: fakeFooter
        property string lastNote: ""
        property bool lastError: false
        function say(note, isError) { fakeFooter.lastNote = String(note); fakeFooter.lastError = !!isError }
    }

    FloatingWindow {
        implicitWidth: 640
        implicitHeight: 480
        color: "#303030"

        Flea.UnlockHost {
            id: host
            anchors.fill: parent
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: shell.advance()
    }

    function advance() {
        shell.ticks += 1
        if (shell.ticks < 2) return
        if (shell.phase === 0) {
            host.window = fakeWindow
            host.footer = fakeFooter
            host.openFor("/dev/sdb1", "Backup", 500000000000, "crypto_LUKS")
            if (shell.until(host.dialog !== null && host.dialog.opened, 100)) return
            shell.check("no-rail-card-opens", host.dialog.opened === true, "opened=" + host.dialog.opened)
            shell.check("host-holds-no-rail", host.sidebar === null, String(host.sidebar))
            shell.step(1)
        } else if (shell.phase === 1) {
            // An unlock with no rail opens the folder and says the note.
            host.dialog.unlocked("/run/media/gm/Backup", "Backup", Unlock.unlockedNote("Backup"))
            shell.check("no-rail-unlock-opens-the-folder", fakePane.openedPath === "/run/media/gm/Backup", fakePane.openedPath)
            shell.check("no-rail-unlock-says-the-note",
                fakeFooter.lastNote === Unlock.unlockedNote("Backup") && fakeFooter.lastError === false,
                fakeFooter.lastNote + "|" + fakeFooter.lastError)
            shell.check("no-rail-unlock-stashes-no-follow", host.pendingPath === "", host.pendingPath)
            shell.finish()
        }
    }
}
