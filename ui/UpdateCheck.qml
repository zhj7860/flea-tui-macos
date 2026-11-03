pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "js/Update.js" as Update

// The one updater every surface shares: `flea --update check` asks the installing source, `flea --update` opens Omarchy's updater, and ui/js/Update.js holds the state and the words.
QtObject {
    id: root

    readonly property string binary: Quickshell.env("FLEA_BIN") || "flea"
    property var status: Update.idle()
    // The background menu builds its Update Flea row from this, and builds none while it is empty.
    readonly property string menuVersion: Update.menuVersion(root.status)
    // The pane whose footer says what a launch did; it can close meanwhile, which say() allows for.
    property var asker: null
    // Set by ui/WindowBody.qml when the window opens; nothing else starts the poll.
    property bool polling: false

    // Settings > About's row: Enter checks, launches, or does nothing while a check or an update runs.
    function activate(pane) {
        var next = Update.onActivate(root.status)
        if (next === "check")
            root.check()
        else if (next === "launch")
            root.launch(pane)
    }

    function check() {
        if (checker.running || root.status.state === "launched")
            return
        root.status = Update.checking(root.status)
        checker.running = true
    }

    // Settings > About opening, which asks only when ui/js/Update.js says the last answer no longer stands.
    function checkIfDue() {
        if (Update.due(root.status, Date.now(), ViewState.updateAutoCheck))
            root.check()
    }

    // The background menu's row lands here directly: it exists only while there is something to install.
    function launch(pane) {
        if (launcher.running)
            return
        root.asker = pane
        launcher.running = true
    }

    function startPolling() {
        root.polling = true
    }

    function say(pane, words) {
        if (pane)
            pane.message(words[0], words[1])
    }

    property var checkQuery: Process {
        id: checker
        command: [root.binary, "--update", "check"]
        stdout: StdioCollector { waitForEnd: true }
        // The line is the answer and the exit status only repeats it, so the status decides nothing here.
        onExited: function (code) {
            root.status = Update.answered(root.status, checker.stdout.text, Date.now())
            // The next poll counts from this answer, whichever trigger asked for it.
            if (poll.running)
                poll.restart()
        }
    }

    property var launchQuery: Process {
        id: launcher
        command: [root.binary, "--update"]
        onExited: function (code) {
            root.status = Update.launchedFrom(root.status, code === 0)
            root.say(root.asker, Update.launchSentence(code === 0))
            root.asker = null
        }
    }

    // Once, a minute after the window opens, so a session sees an update without opening About or waiting six hours.
    property var firstTimer: Timer {
        interval: Update.FIRST_CHECK_MS
        running: root.polling && ViewState.updateAutoCheck
        onTriggered: root.checkIfDue()
    }

    // Every six hours while the window lives and the switch is on; a click never waits on it.
    property var pollTimer: Timer {
        id: poll
        interval: Update.INTERVAL_MS
        repeat: true
        running: root.polling && ViewState.updateAutoCheck
        onTriggered: root.check()
    }
}
