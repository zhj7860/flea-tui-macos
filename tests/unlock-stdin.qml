//@ pragma ShellId flea-unlock-stdin-test

import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "flea" as Flea
import "flea/js/Unlock.js" as Unlock
import "unlock-stdin-find.js" as Find

// tests/unlock-stdin.sh's harness: the real UnlockDialog against a stub udisksctl, canary S3cr3t-canary-1006; attempts 1 and 2 refuse, 3 unlocks, phases 4 and up arm the stub by failure mode, and a wrong phase proves stdin closed (the recorder cat exits only on EOF).
UnlockSteps {
    id: shell

    property string unlockedPath: ""
    property string unlockedLabel: ""
    property string unlockedNote: ""
    property string lockFailedNote: ""

    // Reads the stub's recorder until it says want ("" takes any count) or the bound passes.
    function counted(name, pattern, want, ticks) {
        if (shell.waits === 0)
            kit.probed = ""
        kit.stubCount(name, pattern)
        return shell.until(want === "" ? kit.probed !== "" : kit.probed === want, ticks)
    }

    // Counts the bullet-only text the dialog draws while the field is empty.
    function drawnMasks() {
        var dots = 0
        var stack = [dlg]
        while (stack.length > 0) {
            var it = stack.pop()
            if (it && typeof it.text === "string" && it.visible === true && shell.isBullets(it.text))
                dots += it.text.length
            var kids = (it && it.children) || []
            for (var i = 0; i < kids.length; i++)
                stack.push(kids[i])
        }
        return dots
    }

    // True when every character is a mask bullet and at least one stands.
    function isBullets(s) {
        if (typeof s !== "string" || s.length === 0)
            return false
        for (var i = 0; i < s.length; i++) {
            if (s[i] !== "\u2022")
                return false
        }
        return true
    }

    FloatingWindow {
        implicitWidth: 640
        implicitHeight: 480
        color: "#303030"

        // The pane the host hands focus back to when the dialog closes, so a late focus grab shows as a stolen owner.
        Item {
            id: sink
            anchors.fill: parent
            focus: true
        }

        TestEvent { id: driver }

        Flea.UnlockDialog {
            id: dlg
            onClosed: sink.forceActiveFocus()
            onLockFailed: function (note) { shell.lockFailedNote = note }
            onUnlocked: function (path, label, note) {
                shell.unlockedPath = path
                shell.unlockedLabel = label
                shell.unlockedNote = note
            }
        }
    }

    UnlockKit {
        id: kit
        dlg: dlg
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
            dlg.openFor("/dev/sdb1", "Backup", 500000000000, "LUKS2")
            var field = Find.findField(dlg)
            shell.check("dialog-opens-typing", dlg.opened && dlg.phase === "typing"
                && dlg.noteText === "" && field !== null, "opened=" + dlg.opened + " phase=" + dlg.phase)
            if (field) field.text = "S3cr3t-canary-1006"
            shell.check("field-takes-text", field && field.text === "S3cr3t-canary-1006",
                field ? "<hidden>" : "no field")
            var typed = field ? field.text.length : 0
            dlg.submit()
            shell.check("submit-clears-the-field", !field || field.text === "", "field kept text")
            shell.check("submit-moves-the-keyboard-to-cancel", dlg.focusPart() === "cancel", dlg.focusPart())
            shell.check("submit-holds-the-submitted-count", field && field.text === "" && field.heldMask === typed && typed > 0,
                "held=" + (field ? field.heldMask : -1))
            shell.check("submit-draws-that-many-masks", field && shell.drawnMasks() === field.heldMask && field.heldMask > 0,
                "drawn=" + shell.drawnMasks())
            shell.goto(1)
        } else if (shell.phase === 1) {
            // The stub's recorder only exits on EOF, so the wrong phase is the close proof.
            if (dlg.phase !== "wrong" && shell.waits++ < 100) return
            shell.check("refused-passphrase-is-wrong", dlg.phase === "wrong", dlg.phase)
            shell.check("refusal-returns-the-keyboard-to-the-field", dlg.focusPart() === "field", dlg.focusPart())
            shell.check("localized-failed-keeps-wrong-note", dlg.noteText === Unlock.wrongNote("Backup"), dlg.noteText)
            shell.check("wrong-holds-no-secret", kit.sweepSecret() === "", "a property holds it")
            var wrong = Find.findField(dlg)
            shell.check("wrong-holds-the-submitted-count", wrong && wrong.text === "" && wrong.heldMask > 0,
                "held=" + (wrong ? wrong.heldMask : -1))
            shell.check("wrong-draws-that-many-masks", wrong && shell.drawnMasks() === wrong.heldMask && wrong.heldMask > 0,
                "drawn=" + shell.drawnMasks())
            if (wrong) driver.keyClick(Qt.Key_X, Qt.NoModifier, 0)
            shell.check("retry-edit-drops-the-held-mask", wrong && wrong.heldMask === 0 && wrong.text.length === 1,
                "held=" + (wrong ? wrong.heldMask : -1))
            shell.check("retry-draws-the-new-text-mask", wrong && wrong.input && wrong.heldMask === 0 && wrong.text.length === 1 && wrong.input.echoMode === TextInput.Password && shell.isBullets(wrong.input.displayText),
                "echo=" + (wrong && wrong.input ? wrong.input.echoMode + "|" + wrong.input.displayText : "no field"))
            kit.typeSecret()
            dlg.submit()
            shell.goto(2)
        } else if (shell.phase === 2) {
            if (dlg.phase !== "wrong" && shell.waits++ < 100) return
            shell.check("other-refusal-names-no-passphrase", dlg.noteText === Unlock.unlockFailedNote("Backup"), dlg.noteText)
            shell.check("other-refusal-returns-the-keyboard-to-the-field", dlg.focusPart() === "field", dlg.focusPart())
            shell.check("failed-holds-no-secret", kit.sweepSecret() === "", "a property holds it")
            kit.typeSecret()
            dlg.submit()
            shell.goto(3)
        } else if (shell.phase === 3) {
            // A retry after a closed stdin needs stdinEnabled true again before the start.
            if (shell.unlockedPath === "" && shell.waits++ < 100) return
            shell.check("retry-unlocks-and-mounts", shell.unlockedPath === "/run/media/gm/Backup"
                && shell.unlockedLabel === "Backup" && shell.unlockedNote === Unlock.unlockedNote("Backup"),
                shell.unlockedPath + "|" + shell.unlockedLabel + "|" + shell.unlockedNote)
            shell.check("success-clears-and-closes", dlg.opened === false, "opened=" + dlg.opened)
            shell.check("success-holds-no-secret", kit.sweepSecret() === "", "a property holds it")
            kit.arm("dead")
            shell.goto(4)
        } else if (shell.phase === 4) {
            // UL2: a command that cannot start still ends the attempt, and the passphrase goes with it.
            if (shell.hold(4)) return
            dlg.unlockTimeoutMs = 1500
            kit.openAndSubmit()
            shell.goto(5)
        } else if (shell.phase === 5) {
            if (shell.until(dlg.phase !== "unlocking", 100)) return
            var dead = Find.findField(dlg)
            shell.check("never-started-says-what-happened", dlg.phase === "wrong" && dlg.noteText === Unlock.unlockFailedNote("Backup"),
                dlg.phase + "|" + dlg.noteText)
            shell.check("never-started-holds-no-secret", dlg._secret === "" && (!dead || dead.text === "") && kit.sweepSecret() === "",
                "a property holds it")
            shell.check("never-started-leaves-the-dialog-actionable", dead !== null && dead.enabled === true, "field disabled")
            kit.arm("hang")
            shell.goto(6)
        } else if (shell.phase === 6) {
            // UL1 and UL8: no timer ends a started child; Cancel is the way out.
            if (shell.hold(4)) return
            kit.openAndSubmit()
            shell.goto(7)
        } else if (shell.phase === 7) {
            if (shell.until(dlg._started, 100)) return
            shell.goto(8)
        } else if (shell.phase === 8) {
            if (shell.hold(25)) return
            kit.probe("hangpid")
            shell.goto(9)
        } else if (shell.phase === 9) {
            if (shell.until(kit.probed !== "", 100)) return
            shell.check("timer-leaves-a-started-child-running", kit.probed === "alive" && dlg.phase === "unlocking", kit.probed + "|" + dlg.phase)
            dlg.close()
            shell.goto(10)
        } else if (shell.phase === 10) {
            if (shell.hold(10)) return
            kit.probe("hangpid")
            shell.goto(11)
        } else if (shell.phase === 11) {
            if (shell.until(kit.probed !== "", 100)) return
            shell.check("cancel-leaves-the-client-running", kit.probed === "alive", kit.probed)
            shell.check("cancel-closes-and-holds-no-secret", dlg.opened === false && dlg._secret === "" && kit.sweepSecret() === "", "opened=" + dlg.opened)
            kit.killStub("hangpid")
            kit.probe("hangpid")
            shell.goto(12)
        } else if (shell.phase === 12) {
            // The harness reaps its own stub; Cancel itself never kills.
            if (shell.until(kit.probed !== "", 100)) return
            kit.arm("mounthang")
            shell.goto(13)
        } else if (shell.phase === 13) {
            // UL7: a mount killed by close exits late, and that exit does nothing visible and takes no focus.
            if (shell.hold(4)) return
            kit.openAndSubmit()
            shell.goto(14)
        } else if (shell.phase === 14) {
            if (shell.until(dlg._stage === "mount", 100)) return
            dlg.close()
            shell.goto(15)
        } else if (shell.phase === 15) {
            if (shell.hold(20)) return
            var gone = Find.findField(dlg)
            shell.check("close-during-mount-stays-closed", dlg.opened === false && dlg.phase !== "wrong" && dlg.noteText !== Unlock.mountNote("Backup"),
                "opened=" + dlg.opened + " phase=" + dlg.phase)
            shell.check("close-during-mount-takes-no-focus", sink.activeFocus === true && (!gone || gone.focused === false),
                "sink=" + sink.activeFocus)
            shell.check("close-during-mount-holds-no-secret", kit.sweepSecret() === "", "a property holds it")
            kit.arm("mountfail")
            shell.goto(16)
        } else if (shell.phase === 16) {
            // UL9: a mount that fails puts the container back, so the retry starts from a locked one.
            if (shell.hold(4)) return
            kit.openAndSubmit()
            shell.goto(17)
        } else if (shell.phase === 17) {
            if (shell.until(dlg.phase !== "unlocking", 100)) return
            shell.check("failed-mount-says-so-and-holds-no-secret", dlg.phase === "wrong" && dlg.noteText === Unlock.mountNote("Backup")
                && kit.sweepSecret() === "", dlg.phase + "|" + dlg.noteText)
            kit.setMode("ok", false)
            shell.goto(18)
        } else if (shell.phase === 18) {
            if (shell.hold(4)) return
            shell.unlockedPath = ""
            kit.typeSecret()
            dlg.submit()
            shell.goto(19)
        } else if (shell.phase === 19) {
            if (shell.until(shell.unlockedPath !== "", 100)) return
            shell.check("retry-after-a-failed-mount-unlocks", shell.unlockedPath === "/run/media/gm/Backup", shell.unlockedPath)
            shell.check("retry-after-a-failed-mount-closes-clean", dlg.opened === false && kit.sweepSecret() === "", "opened=" + dlg.opened)
            kit.arm("mounthang,lockfail")
            shell.goto(20)
        } else if (shell.phase === 20) {
            if (shell.hold(4)) return
            shell.lockFailedNote = ""
            kit.openAndSubmit()
            shell.goto(21)
        } else if (shell.phase === 21) {
            if (shell.until(dlg._stage === "mount", 100)) return
            dlg.close()
            shell.goto(22)
        } else if (shell.phase === 22) {
            if (shell.hold(25)) return
            shell.check("close-during-mount-lock-refusal-is-posted", shell.lockFailedNote === Unlock.lockNote("Backup"), shell.lockFailedNote)
            kit.arm("mountfail,lockfail")
            shell.goto(23)
        } else if (shell.phase === 23) {
            if (shell.hold(4)) return
            shell.lockFailedNote = ""
            kit.openAndSubmit()
            shell.goto(24)
        } else if (shell.phase === 24) {
            if (shell.until(dlg.phase !== "unlocking", 100)) return
            shell.check("failed-mount-with-a-refused-lock-tells-both", dlg.phase === "wrong" && dlg.noteText === Unlock.mountNote("Backup")
                && shell.lockFailedNote === Unlock.lockNote("Backup"), dlg.phase + "|" + dlg.noteText + "|" + shell.lockFailedNote)
            kit.arm("latesuccess")
            shell.goto(25)
        } else if (shell.phase === 25) {
            // Cancel during unlock leaves the client running; its late success locks back with no focus.
            if (shell.hold(4)) return
            shell.lockFailedNote = ""
            shell.unlockedPath = ""
            kit.openAndSubmit()
            shell.goto(26)
        } else if (shell.phase === 26) {
            if (shell.until(dlg._started, 100)) return
            kit.probe("hangpid")
            shell.goto(27)
        } else if (shell.phase === 27) {
            if (shell.until(kit.probed !== "", 100)) return
            shell.check("cancel-during-unlock-leaves-the-client-running", kit.probed === "alive", kit.probed)
            dlg.close()
            shell.goto(28)
        } else if (shell.phase === 28) {
            if (shell.hold(4)) return
            kit.touchGo()
            shell.goto(29)
        } else if (shell.phase === 29) {
            if (shell.counted("lockcalls", "", "5", 150)) return
            shell.check("cancelled-unlock-locks-after-success", kit.probed === "5", kit.probed)
            shell.check("cancelled-unlock-stays-closed", dlg.opened === false, "opened=" + dlg.opened)
            shell.check("cancelled-unlock-takes-no-focus", sink.activeFocus === true, "sink=" + sink.activeFocus)
            shell.check("successful-late-lock-posts-nothing", shell.lockFailedNote === "", shell.lockFailedNote)
            shell.goto(30)
        } else if (shell.phase === 30) {
            if (shell.hold(4)) return
            kit.arm("latesuccess,lockfail")
            shell.goto(31)
        } else if (shell.phase === 31) {
            if (shell.hold(4)) return
            shell.lockFailedNote = ""
            kit.openAndSubmit()
            shell.goto(32)
        } else if (shell.phase === 32) {
            if (shell.until(dlg._started, 100)) return
            kit.probe("hangpid")
            shell.goto(33)
        } else if (shell.phase === 33) {
            if (shell.until(kit.probed !== "", 100)) return
            dlg.close()
            shell.goto(34)
        } else if (shell.phase === 34) {
            if (shell.hold(4)) return
            kit.touchGo()
            shell.goto(35)
        } else if (shell.phase === 35) {
            if (shell.counted("lockcalls", "", "6", 150)) return
            shell.check("refused-late-lock-names-the-drive", shell.lockFailedNote === Unlock.lockNote("Backup"), shell.lockFailedNote)
            shell.check("refused-late-lock-stays-closed", dlg.opened === false, "opened=" + dlg.opened)
            shell.goto(36)
        } else if (shell.phase === 36) {
            if (shell.hold(4)) return
            kit.arm("latefail")
            shell.goto(37)
        } else if (shell.phase === 37) {
            if (shell.hold(4)) return
            shell.lockFailedNote = ""
            kit.openAndSubmit()
            shell.goto(38)
        } else if (shell.phase === 38) {
            if (shell.until(dlg._started, 100)) return
            dlg.close()
            shell.goto(39)
        } else if (shell.phase === 39) {
            if (shell.hold(4)) return
            kit.touchGo()
            shell.goto(40)
        } else if (shell.phase === 40) {
            if (shell.hold(15)) return
            kit.probe("hangpid")
            shell.goto(41)
        } else if (shell.phase === 41) {
            if (shell.until(kit.probed !== "", 100)) return
            shell.check("failed-late-unlock-exits", kit.probed === "dead", kit.probed)
            shell.goto(42)
        } else if (shell.phase === 42) {
            if (shell.counted("lockcalls", "", "", 100)) return
            shell.check("failed-late-unlock-issues-no-lock", kit.probed === "6", kit.probed)
            shell.check("failed-late-unlock-stays-closed", dlg.opened === false, "opened=" + dlg.opened)
            shell.check("failed-late-unlock-posts-nothing", shell.lockFailedNote === "", shell.lockFailedNote)
            kit.arm("latesuccess")
            shell.goto(43)
        } else if (shell.phase === 43) {
            // A submit behind a Cancelled client queues, and that client's late lock goes to the drive it was opened on.
            if (shell.hold(4)) return
            kit.openAndSubmit()
            shell.goto(44)
        } else if (shell.phase === 44) {
            if (shell.until(dlg._started, 100)) return
            dlg.close()
            kit.openAndSubmit("/dev/sdc1", "Stick")
            var queued = Find.findField(dlg)
            shell.check("resubmit-behind-a-running-client-queues", dlg._queued && dlg.phase === "unlocking" && queued
                && queued.text === "" && dlg.noteText === Unlock.unlockingNote("Stick"), "queued=" + dlg._queued + " phase=" + dlg.phase)
            kit.touchGo()
            shell.goto(45)
        } else if (shell.phase === 45) {
            if (shell.counted("lockcalls", "^lock --block-device /dev/sdb1$", "7", 150)) return
            shell.check("late-lock-locks-the-cancelled-drive", kit.probed === "7" && dlg._lockLabel === "Backup"
                && shell.lockFailedNote === "", kit.probed + " " + dlg._lockLabel)
            shell.goto(46)
        } else if (shell.phase === 46) {
            if (shell.until(shell.unlockedLabel === "Stick", 100)) return
            shell.check("queued-unlock-runs-after-the-late-lock", shell.unlockedLabel === "Stick" && !dlg.opened, shell.unlockedLabel)
            kit.arm("hang")
            shell.goto(47)
        } else if (shell.phase === 47) {
            // A queued submit dies with Cancel, and one left waiting is refused at the bound with nothing started after.
            if (shell.hold(4)) return
            kit.openAndSubmit()
            shell.goto(48)
        } else if (shell.phase === 48) {
            if (shell.until(dlg._started, 100)) return
            dlg.close()
            kit.openAndSubmit("/dev/sdc1", "Stick")
            dlg.close()
            shell.check("close-drops-the-queued-submit", !dlg._queued && dlg._secret === "", "queued=" + dlg._queued)
            kit.openAndSubmit("/dev/sdc1", "Stick")
            shell.goto(49)
        } else if (shell.phase === 49) {
            if (shell.until(dlg.phase === "wrong", 100)) return
            shell.check("queued-submit-is-bounded", dlg.noteText === Unlock.unlockFailedNote("Stick") && dlg._secret === ""
                && !dlg._queued, dlg.noteText)
            kit.killStub("hangpid")
            shell.goto(50)
        } else if (shell.phase === 50) {
            if (shell.hold(10)) return
            shell.check("bounded-queue-starts-nothing-later", dlg.phase === "wrong" && dlg._stage === "idle", dlg.phase + " " + dlg._stage)
            kit.arm("mounthang")
            shell.goto(51)
        } else if (shell.phase === 51) {
            // Cancel kills the mount, and a submit made before that exit lands waits for the lock the exit runs.
            if (shell.hold(4)) return
            kit.openAndSubmit()
            shell.goto(52)
        } else if (shell.phase === 52) {
            if (shell.until(dlg._stage === "mount", 100)) return
            dlg.close()
            kit.openAndSubmit("/dev/sdc1", "Stick")
            shell.check("resubmit-behind-a-killed-mount-queues", dlg._queued && dlg._stage === "abandon", "queued=" + dlg._queued + " stage=" + dlg._stage)
            shell.goto(53)
        } else if (shell.phase === 53) {
            if (shell.counted("lockcalls", "^lock --block-device /dev/sdb1$", "8", 150)) return
            shell.check("killed-mount-locks-its-own-drive", kit.probed === "8", kit.probed)
            shell.goto(54)
        } else if (shell.phase === 54) {
            if (shell.until(dlg._stage === "mount" && dlg.device === "/dev/sdc1", 100)) return
            shell.check("queued-unlock-runs-after-the-killed-mount", dlg._stage === "mount" && dlg.device === "/dev/sdc1", dlg._stage + " " + dlg.device)
            dlg.close()
            shell.goto(55)
        } else if (shell.phase === 55) {
            if (shell.counted("lockcalls", "^lock --block-device /dev/sdc1$", "1", 150)) return
            shell.check("cancelled-queued-mount-locks-its-drive", kit.probed === "1", kit.probed)
            shell.goto(56)
        } else if (shell.phase === 56) {
            if (shell.hold(4)) return
            kit.arm("ok")
            shell.goto(57)
        } else if (shell.phase === 57) {
            // A Cancel before the client starts still ends it: submit then close in one turn.
            if (shell.hold(4)) return
            shell.unlockedPath = ""
            kit.openAndSubmit()
            dlg.close()
            shell.check("cancel-before-start-closes", dlg.opened === false && dlg._stage === "abandon" && dlg._started === false,
                "opened=" + dlg.opened + " stage=" + dlg._stage + " started=" + dlg._started)
            shell.goto(58)
        } else if (shell.phase === 58) {
            // The fix closes stdin on the late start, so the cat-until-EOF stub exits and the abandon locks back.
            if (shell.counted("lockcalls", "", "10", 150)) return
            shell.check("cancel-before-start-still-ends-it", kit.probed === "10", kit.probed)
            shell.check("cancel-before-start-stays-closed", dlg.opened === false, "opened=" + dlg.opened)
            shell.goto(59)
        } else if (shell.phase === 59) {
            if (shell.until(dlg._stage === "idle", 100)) return
            shell.check("early-cancel-settles-idle", dlg._stage === "idle", dlg._stage)
            shell.unlockedPath = ""
            shell.unlockedLabel = ""
            kit.openAndSubmit()
            shell.goto(60)
        } else if (shell.phase === 60) {
            if (shell.until(shell.unlockedPath !== "", 100)) return
            shell.check("submit-after-an-early-cancel-unlocks", shell.unlockedPath === "/run/media/gm/Backup", shell.unlockedPath)
            shell.goto(61)
        } else if (shell.phase === 61) {
            // An empty submit after a Cancel still locks the late unlock back: late-unlock stub, Cancel, reopen, empty Enter.
            if (shell.hold(4)) return
            kit.arm("latesuccess")
            shell.goto(62)
        } else if (shell.phase === 62) {
            if (shell.hold(4)) return
            shell.lockFailedNote = ""
            kit.openAndSubmit()
            shell.goto(63)
        } else if (shell.phase === 63) {
            if (shell.until(dlg._started, 100)) return
            dlg.close()
            dlg.openFor("/dev/sdb1", "Backup", 500000000000, "LUKS2")
            dlg.submit()
            shell.check("empty-submit-after-cancel-refuses", dlg.phase === "wrong" && dlg.noteText === Unlock.wrongNote("Backup"),
                dlg.phase + "|" + dlg.noteText)
            shell.check("empty-submit-after-cancel-keeps-the-abandon", dlg._stage === "abandon", dlg._stage)
            kit.touchGo()
            shell.goto(64)
        } else if (shell.phase === 64) {
            if (shell.counted("lockcalls", "", "11", 150)) return
            shell.check("empty-submit-after-cancel-still-locks-the-late-unlock", kit.probed === "11", kit.probed)
            shell.goto(65)
        } else if (shell.phase === 65) {
            if (shell.until(dlg._stage === "idle", 100)) return
            shell.check("late-lock-after-empty-submit-settles-idle", dlg._stage === "idle", dlg._stage)
            shell.finish()
        }
    }
}
