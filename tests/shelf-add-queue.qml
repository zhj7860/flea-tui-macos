//@ pragma ShellId flea-shelf-add-queue-test

import QtQuick
import Quickshell
import "flea" as Flea

// tests/shelf-add-queue.sh harness: a second shelf add while one runs waits its turn.
ShellRoot {
    id: shell

    property var failures: []
    property int ticks: 0
    property int phase: 0
    property int waits: 0

    function log(line) { console.log("SHELFQUEUE " + line) }
    function check(name, cond, detail) {
        if (cond) shell.log("PASS " + name)
        else shell.failures.push(name + " got " + detail)
    }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }

    Item {
        Item {
            id: stubBackend
            signal menuResult(var message)
            signal formatsResult(var message)
            signal changed(string path)
            signal located(var message)
            signal localSendPeers(var peers, string reason)
            signal localSendSent(bool ok, string reason)
            signal failed(string where, string input, string message, int mode)
            property var sent: []
            function send(m) { sent.push(m) }
            function askFormats() { return 0 }
        }

        Item {
            id: stubMenu
            property bool opened: false
            property bool hasRow: true
            function refreshProviderRows() {}
            function providersSettled() {}
            function validateChoice(action, subId) { return true }
        }

        Item {
            id: stubPane
            property string menuSelectionIdentity: "ID-A"
            property string path: "/payload"
            property int cursorIndex: 0
            property bool listInFlight: false
            property var cursorRow: null
            property bool renamePending: false
            property var messages: []
            property var backend: stubBackend
            property var taildropService: null
            property var dropboxService: null
            function contextMenu() { return stubMenu }
            function message(text, isError) { messages.push(text + "|" + isError) }
            function join(folder, name) { return folder + "/" + name }
        }
    }

    FloatingWindow {
        implicitWidth: 640
        implicitHeight: 480
        color: "#303030"

        Flea.PaneMenuActions {
            id: actions
            pane: stubPane
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: shell.advance()
    }

    // Two adds in one turn overlap because the stub sleeps on every call.
    function advance() {
        shell.ticks += 1
        if (shell.ticks < 2) return
        if (shell.phase === 0) {
            stubPane.messages = []
            actions.shelve(["/a", "/b", "/c"])
            actions.shelve(["/d"])
            shell.waits = 0
            shell.phase = 1
        } else if (shell.phase === 1) {
            if (stubPane.messages.length >= 2) {
                shell.check("two-queued-adds-report-in-order", stubPane.messages.length === 2
                    && stubPane.messages[0] === "Added 3 items to the shelf|false"
                    && stubPane.messages[1] === "Added it to the shelf|false",
                    stubPane.messages.join(";"))
                stubPane.messages = []
                actions.shelve(["/e", "/f"])
                actions.shelve(["/g"])
                shell.waits = 0
                shell.phase = 2
            } else if (++shell.waits > 60) {
                shell.check("two-queued-adds-report-in-order", false,
                    "timed out with " + stubPane.messages.length + ": " + stubPane.messages.join(";"))
                shell.finish()
            }
        } else if (shell.phase === 2) {
            if (stubPane.messages.length >= 2) {
                shell.check("failed-first-still-runs-queued-add", stubPane.messages.length === 2
                    && stubPane.messages[0] === "shelf exploded|true"
                    && stubPane.messages[1] === "Added it to the shelf|false",
                    stubPane.messages.join(";"))
                shell.finish()
            } else if (++shell.waits > 60) {
                shell.check("failed-first-still-runs-queued-add", false,
                    "timed out with " + stubPane.messages.length + ": " + stubPane.messages.join(";"))
                shell.finish()
            }
        }
    }

    function finish() {
        for (var i = 0; i < shell.failures.length; i++)
            shell.log("FAIL " + shell.failures[i])
        shell.log("DONE failures=" + shell.failures.length)
        shell.phase = 3
        shell.quit()
    }
}
