pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "js/MakeDefault.js" as MakeDefault

// Settings > About's Make Flea the default, shared by every window: the handler xdg-mime answers, whether this build has a desktop entry, `flea --default [off]` and the portal restart after it; ui/js/MakeDefault.js holds the states and the words.
QtObject {
    id: root

    readonly property string binary: Quickshell.env("FLEA_BIN") || "flea"
    // The one answer the File manager row states and the box is ticked by.
    property string handler: ""
    property var claim: MakeDefault.idle()
    // Handler reads are numbered as they start, so a run is settled only by a read begun after it exited.
    property int reads: 0
    // True from a read's start until its exit and its text are both in, which is when the next may start.
    property bool readBusy: false
    // A run that exited during another window's read asks for one more behind it, since a running Process is not restarted.
    property bool readAgain: false
    // Each process's exit code and collector text, filled in whichever order they land.
    property var readAnswer: ({})
    property var runAnswer: ({})
    // What the run asked for, so a flea that never starts is named in the note.
    property var runCommand: []

    // About opening: the handler, and whether there is an entry for flea --default to point at.
    function read() {
        root.startRead()
        prober.command = MakeDefault.probeCommand(MakeDefault.entryPaths({
            HOME: Quickshell.env("HOME") || "",
            XDG_DATA_HOME: Quickshell.env("XDG_DATA_HOME") || "",
            XDG_DATA_DIRS: Quickshell.env("XDG_DATA_DIRS") || ""
        }))
        prober.running = true
    }

    // Enter, Space or a click on the row; a press during a run, or on a build with no entry, does nothing.
    function toggle() {
        var args = MakeDefault.press(root.handler, root.claim)
        if (args === null || runner.running)
            return
        root.claim = MakeDefault.started(root.claim, args)
        root.runAnswer = ({})
        root.runCommand = [root.binary].concat(args)
        runner.command = root.runCommand
        runner.running = true
    }

    // False when a read is already in flight, whose answer may predate whatever the caller is waiting on.
    function startRead() {
        if (root.readBusy)
            return false
        root.readBusy = true
        root.reads += 1
        root.readAnswer = ({})
        reader.running = true
        return true
    }

    // A half landing after the answer is whole, a stream ending behind a program that never ran, is ignored.
    function readLanded(half) {
        if (MakeDefault.whole(root.readAnswer))
            return
        root.readAnswer = MakeDefault.landed(root.readAnswer, half)
        if (!MakeDefault.whole(root.readAnswer))
            return
        root.readBusy = false
        root.handler = MakeDefault.handlerOf(root.readAnswer)
        root.claim = MakeDefault.settled(root.claim, root.reads)
        if (root.readAgain) {
            root.readAgain = false
            root.startRead()
        }
    }

    function runLanded(half) {
        if (MakeDefault.whole(root.runAnswer))
            return
        root.runAnswer = MakeDefault.landed(root.runAnswer, half)
        if (!MakeDefault.whole(root.runAnswer))
            return
        // The next read to start is the first that can see what this run wrote.
        root.claim = MakeDefault.finished(root.claim, root.runAnswer.code, root.runAnswer.text, root.reads + 1)
        if (!root.startRead())
            root.readAgain = true
        if (root.claim.restarting)
            restarter.running = true
    }

    property var readQuery: Process {
        id: reader
        command: ["xdg-mime", "query", "default", "inode/directory"]
        // Sample output: com.thisisgm.flea.desktop
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.readLanded({ text: this.text }) }
        onExited: function (code) { root.readLanded({ code: code }) }
        // An xdg-mime that cannot start raises no exited, so the read ends here, stating no handler.
        onRunningChanged: {
            if (MakeDefault.neverRan(root.readAnswer, reader.running))
                root.readLanded(MakeDefault.NEVER_RAN)
        }
    }

    property var probeQuery: Process {
        id: prober
        onExited: function (code) { root.claim = MakeDefault.probed(root.claim, code === 0) }
    }

    // Asynchronous like every Process, so the window keeps drawing while flea rewrites the four files.
    property var runQuery: Process {
        id: runner
        stderr: StdioCollector { waitForEnd: true; onStreamFinished: root.runLanded({ text: this.text }) }
        onExited: function (code) { root.runLanded({ code: code }) }
        // A flea that cannot start wrote nothing, so there is nothing to read again and no portal to restart.
        onRunningChanged: {
            if (MakeDefault.neverRan(root.runAnswer, runner.running)) {
                root.runAnswer = MakeDefault.landed(root.runAnswer, MakeDefault.NEVER_RAN)
                root.claim = MakeDefault.unstarted(root.claim, root.runCommand)
            }
        }
    }

    // Only this switch restarts the portal; flea --default on a command line prints the hint instead.
    property var restartQuery: Process {
        id: restarter
        command: MakeDefault.RESTART
        onExited: function (code) { root.claim = MakeDefault.restarted(root.claim, code === 0) }
        onRunningChanged: root.claim = MakeDefault.restartStopped(root.claim, restarter.running)
    }
}
