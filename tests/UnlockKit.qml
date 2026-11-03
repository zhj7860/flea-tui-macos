import QtQuick
import Quickshell
import Quickshell.Io
import "unlock-stdin-find.js" as Find

// The stub controls tests/unlock-stdin.qml drives, over a stub whose state is files: mode word, unlocked marker, PATH target.
Item {
    id: kit

    property var dlg: null
    property string probed: ""

    // S6: no string the dialog holds may carry the canary once submitted.
    function sweepSecret() {
        var field = Find.findField(kit.dlg)
        var held = [field ? field.text : "", kit.dlg._secret, kit.dlg.noteText].join("\n")
        return held.indexOf("S3cr3t-canary-1006") < 0 ? "" : held
    }
    function arm(mode) {
        kit.setMode(mode, true)
    }
    function setMode(mode, reset) {
        var root = Quickshell.env("UNLOCK_TEST_ROOT")
        Quickshell.execDetached(["sh", "-c",
            "cd \"$1/stub\" && " + (reset ? "rm -f unlocked go && " : "") + "printf %s \"$2\" > mode"
            + " && case \"$2\" in dead) t=udisksctl.dead ;; *) t=udisksctl.live ;; esac && ln -sfn \"$1/stub/$t\" \"$1/bin/udisksctl\"",
            "sh", root, mode])
    }
    function probe(pidFile) {
        kit.probed = ""
        probeProcess.command = ["sh", "-c", "kill -0 \"$(cat \"$1/stub/$2\")\" 2>/dev/null && echo alive || echo dead",
            "sh", Quickshell.env("UNLOCK_TEST_ROOT"), pidFile]
        probeProcess.running = true
    }
    // Reap a stub client the dialog deliberately left running, so the next submit starts clean.
    function killStub(pidFile) {
        Quickshell.execDetached(["sh", "-c", "kill \"$(cat \"$1/stub/$2\" 2>/dev/null)\" 2>/dev/null",
            "sh", Quickshell.env("UNLOCK_TEST_ROOT"), pidFile])
    }
    // Release a stub unlock waiting on its go flag, so Cancel happens while the client runs.
    function touchGo() {
        Quickshell.execDetached(["sh", "-c", ": > \"$1/stub/go\"", "sh", Quickshell.env("UNLOCK_TEST_ROOT")])
    }
    // Counts the recorder's lines matching pattern, every line when omitted; one reader at a time, its value kept until read again.
    function stubCount(name, pattern) {
        if (probeProcess.running)
            return
        probeProcess.command = ["sh", "-c", "if [ -f \"$1/stub/$2\" ]; then grep -c -- \"$3\" \"$1/stub/$2\"; else echo 0; fi",
            "sh", Quickshell.env("UNLOCK_TEST_ROOT"), name, pattern || "."]
        probeProcess.running = true
    }
    function typeSecret() {
        var field = Find.findField(kit.dlg)
        if (field) field.text = "S3cr3t-canary-1006"
    }
    function openAndSubmit(device, label) {
        kit.dlg.openFor(device || "/dev/sdb1", label || "Backup", 500000000000, "LUKS2")
        kit.typeSecret()
        kit.dlg.submit()
    }

    Process {
        id: probeProcess
        stdout: StdioCollector { id: probeOut; waitForEnd: true }
        onExited: kit.probed = String(probeOut.text).trim()
    }
}
