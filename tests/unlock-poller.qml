//@ pragma ShellId flea-unlock-poller-test

import QtQuick
import Quickshell
import "flea" as Flea
import "unlock-stdin-find.js" as Find

// tests/unlock-poller.sh's harness: the real UnlockHost against a held lsblk, proving the one-shot poller ends with its first listing, never starts on a touched card, latches the touch past an erase, retries a timed-out listing, and reads the LUKS version off the remembered rail for a null call rail.
ShellRoot {
    id: shell

    property var failures: []
    property int ticks: 0
    property int phase: 0
    property int waits: 0
    property int pollerBuilds: 0
    property var poller: null
    property bool sawPoller: false
    property bool sawListing: false
    property bool sawTimeout: false
    property int openTick: 0
    property bool reopened: false
    property int retryTick: 0
    property var rail: ({ deviceEntries: [{ device: "/dev/sdb1", label: "Backup", locked: true,
        size: 1, fstype: "crypto_LUKS", fsver: "2" }], placesEntries: [], networkEntries: [], cursorIndex: -1 })

    function log(line) { console.log("UNLOCKPOLLER " + line) }
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
    function testRoot() { return Quickshell.env("UNLOCK_TEST_ROOT") }
    function releaseLsblk() { Quickshell.execDetached(["sh", "-c", ": > \"$1/stub/go\"", "sh", shell.testRoot()]) }
    function armLsblk(body) {
        Quickshell.execDetached(["sh", "-c", "rm -f \"$1/stub/go\" && cp \"$1/stub/body-" + body + ".json\" \"$1/stub/body.json\"", "sh", shell.testRoot()])
    }
    // The poller is the host Loader built from a component, not the dialog one read from a file.
    function findPoller() {
        var kids = host.children
        for (var i = 0; i < kids.length; i++) {
            if (kids[i].sourceComponent !== null && kids[i].sourceComponent !== undefined) return kids[i]
        }
        return null
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

    Connections {
        target: shell.poller
        function onLoaded() { shell.pollerBuilds++ }
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
            // F4: a null call rail still reads the remembered rail's LUKS version.
            shell.poller = shell.findPoller()
            host.sidebar = shell.rail
            host.openFor("/dev/sdb1", "leaf", 0, "crypto_LUKS", null)
            shell.check("null-rail-reads-the-remembered-version", host.dialog.crypto === "LUKS2", host.dialog.crypto)
            shell.check("remembered-version-keeps-the-passed-label", host.dialog.driveLabel === "leaf", host.dialog.driveLabel)
            shell.check("no-pending-name-runs-no-poller", host.namePolling === false, "polling=" + host.namePolling)
            shell.step(1)
        } else if (shell.phase === 1) {
            if (shell.waits === 0) shell.armLsblk("row")
            if (shell.hold(4)) return
            host.openForDevice("/dev/loop9", null)
            shell.check("pending-card-shows-the-leaf", host.dialog.driveLabel === "loop9", host.dialog.driveLabel)
            shell.check("pending-card-waits-on-its-name", host.unnamedDevice === "/dev/loop9", host.unnamedDevice)
            shell.check("pending-name-starts-the-poller", host.namePolling === true, "polling=" + host.namePolling)
            shell.step(2)
        } else if (shell.phase === 2) {
            // F3: the built poller lists from its own entries, not the kept fallback copy.
            if (!shell.sawPoller && shell.until(shell.poller.item !== null, 20)) return
            if (!shell.sawPoller) {
                shell.sawPoller = true
                shell.check("built-poller-carries-its-own-entries", shell.poller.item !== null && host.fallbackEntries() === shell.poller.item.entries, typeof host.fallbackEntries())
            }
            // F2: the first listing ends the poller, named or not.
            if (shell.waits === 0) shell.releaseLsblk()
            if (shell.until(host._namePollDone === true, 100)) return
            shell.check("first-listing-names-the-card", host.dialog.driveLabel === "cap-loop9", host.dialog.driveLabel)
            shell.check("named-card-ends-the-wait", host.unnamedDevice === "", host.unnamedDevice)
            shell.check("first-listing-stops-the-poller", host.namePolling === false, "polling=" + host.namePolling)
            shell.check("built-poller-reported-the-row", host.fallbackEntries().length === 1, host.fallbackEntries().length)
            shell.step(3)
        } else if (shell.phase === 3) {
            if (shell.waits === 0) shell.armLsblk("empty")
            if (shell.hold(4)) return
            host.openForDevice("/dev/ghost", null)
            shell.check("unnamed-card-shows-the-leaf", host.dialog.driveLabel === "ghost", host.dialog.driveLabel)
            shell.step(4)
        } else if (shell.phase === 4) {
            // F2: a first listing without the row still ends the one-shot wait.
            if (shell.waits === 0) shell.releaseLsblk()
            if (shell.until(host._namePollDone === true, 100)) return
            shell.check("rowless-listing-keeps-the-leaf", host.dialog.driveLabel === "ghost", host.dialog.driveLabel)
            shell.check("rowless-listing-ends-the-wait", host.unnamedDevice === "", host.unnamedDevice)
            shell.check("rowless-listing-stops-the-poller", host.namePolling === false, "polling=" + host.namePolling)
            shell.step(5)
        } else if (shell.phase === 5) {
            // F2: a card touched before the first listing builds once while untouched, then stops.
            if (shell.waits === 0) { shell.armLsblk("row"); shell.pollerBuilds = 0 }
            if (shell.hold(4)) return
            host.openForDevice("/dev/loop9", null)
            var field = Find.findField(host.dialog)
            if (field) field.text = "typed"
            shell.check("touched-card-builds-once-then-stops", shell.poller.item === null && shell.pollerBuilds === 1, "item=" + String(shell.poller.item) + " builds=" + shell.pollerBuilds)
            host.nameDevice()
            shell.check("late-listing-names-no-touched-card", host.dialog.driveLabel === "loop9", host.dialog.driveLabel)
            shell.check("late-listing-ends-the-touched-wait", host.unnamedDevice === "", host.unnamedDevice)
            shell.step(6)
        } else if (shell.phase === 6) {
            // F1: after the release give any late listing time to arrive, then prove none did.
            if (shell.waits === 0) shell.releaseLsblk()
            if (shell.hold(10)) return
            shell.check("late-listing-keeps-the-touched-label", host.dialog.driveLabel === "loop9", host.dialog.driveLabel)
            shell.check("touched-card-never-rebuilds", shell.poller.item === null && shell.pollerBuilds === 1, "item=" + String(shell.poller.item) + " builds=" + shell.pollerBuilds)
            shell.step(7)
        } else if (shell.phase === 7) {
            // F4: typing latches the one-shot shut on a live poller, so the first lsblk is its last.
            if (shell.waits === 0 && host.unnamedDevice === "") shell.armLsblk("row")
            if (host.unnamedDevice === "" && shell.hold(4)) return
            if (host.unnamedDevice === "") {
                host.openForDevice("/dev/loop9", null)
                shell.check("reopened-card-waits-again", host.unnamedDevice === "/dev/loop9", host.unnamedDevice)
                return
            }
            if (!shell.sawListing && shell.until(shell.poller.item !== null && shell.poller.item._listingsStarted >= 1, 20)) return
            if (!shell.sawListing) {
                shell.sawListing = true
                shell.check("first-lsblk-starts-the-wait", shell.poller.item !== null && shell.poller.item._listingsStarted === 1, String(shell.poller.item !== null ? shell.poller.item._listingsStarted : "gone"))
            }
            var touchField = Find.findField(host.dialog)
            if (touchField) touchField.text = "x"
            if (shell.until(host._namePollDone === true, 20)) return
            shell.check("touch-latches-the-one-shot", host._namePollDone === true, String(host._namePollDone))
            shell.step(8)
        } else if (shell.phase === 8) {
            // F4: erasing past the latch restarts nothing, so the leaf stands with one lsblk spent.
            if (shell.waits === 0) {
                var eraseField = Find.findField(host.dialog)
                if (eraseField) eraseField.text = ""
                shell.releaseLsblk()
            }
            if (shell.hold(12)) return
            shell.check("erased-card-keeps-the-leaf", host.dialog.driveLabel === "loop9", host.dialog.driveLabel)
            shell.check("erased-card-starts-no-second-lsblk", shell.poller.item === null, String(shell.poller.item))
            shell.check("erase-keeps-the-latch", host._namePollDone === true, String(host._namePollDone))
            host.nameDevice()
            shell.step(9)
        } else if (shell.phase === 9) {
            // F5: the poller's first lsblk hangs past its bound, so the timeout ends it and the poller tries again.
            if (shell.waits === 0 && host.unnamedDevice === "") shell.armLsblk("row")
            if (host.unnamedDevice === "" && !shell.reopened && shell.hold(4)) return
            if (host.unnamedDevice === "") {
                if (!shell.reopened) {
                    shell.reopened = true
                    host.openForDevice("/dev/loop9", null)
                    shell.openTick = shell.ticks
                    return
                }
                // One reopen only; a card still unnamed after a short wait fails here instead of hanging.
                if (shell.hold(10)) return
                shell.check("reopened-card-waits-for-its-name", host.unnamedDevice !== "", host.unnamedDevice)
                shell.step(10)
                return
            }
            if (shell.retryTick === 0 && shell.poller.item !== null && shell.poller.item._listingsStarted >= 2) shell.retryTick = shell.ticks
            // The retry lands about 100 ticks past open (listTimeoutMs 10000 at 100 ms a tick, DeviceMounts.qml:31), so 130 stays under the 150 wait.
            if (!shell.sawTimeout && shell.until(shell.poller.item !== null && shell.poller.item._listingsStarted >= 2, 150)) return
            if (!shell.sawTimeout) {
                shell.sawTimeout = true
                shell.check("timed-out-card-keeps-the-leaf", host.dialog.driveLabel === "loop9", host.dialog.driveLabel)
                shell.check("timed-out-card-still-waits", host.unnamedDevice === "/dev/loop9", host.unnamedDevice)
                shell.check("timed-out-poller-polls-again", host.namePolling === true && shell.retryTick > 0 && shell.retryTick - shell.openTick < 130, "polling=" + host.namePolling + " retry=" + shell.retryTick + " open=" + shell.openTick)
                shell.check("retried-poller-cleared-the-timeout-flag", shell.poller.item !== null && shell.poller.item.listTimedOut === false, String(shell.poller.item !== null ? shell.poller.item.listTimedOut : "gone"))
            }
            shell.releaseLsblk()
            shell.step(10)
        } else if (shell.phase === 10) {
            if (shell.until(host._namePollDone === true, 100)) return
            shell.check("retried-listing-names-the-card", host.dialog.driveLabel === "cap-loop9", host.dialog.driveLabel)
            shell.finish()
        }
    }
}
