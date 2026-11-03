//@ pragma ShellId flea-transferhold-test

import Quickshell
import QtQuick
import "flea/js/Ops.js" as Ops

// tests/transferhold.sh's harness: ok item lines through the real ui/PaneWire.qml, its Connections, its flush and its beat.
ShellRoot {
    id: shell

    readonly property string uiDir: Quickshell.env("PREVIEW_UI")
    // Longer than the beat, so a held line that waits on it has landed.
    readonly property int beatWaitMs: 400
    property var failures: []
    property var stickies: []
    property var messages: []
    property int step: 0

    function log(line) { console.log("TRANSFERHOLD " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(name, cond, detail) {
        if (!cond) failures.push(name)
        log((cond ? "PASS " : "FAIL ") + name + (cond ? "" : " got " + detail))
    }
    function card() { return JSON.stringify(pane.transfer) }

    QtObject {
        id: backend
        signal transferStarted(int id, int n, bool moving, bool extract)
        signal transferProgress(int id, int index, string name, real bytes, real total, real scanned, string phase, string drive)
        signal transferItem(int id, int index, string name, bool ok, string err)
        signal transferDone(int id, int ok, int failed, int skipped, bool cancelled, var retryPaths, bool durable, string note, int merged, int keptBoth, string into)
        function send(message) {}
    }

    QtObject {
        id: pane
        property string path: "/t"
        property var transfer: Ops.emptyTransfer()
        property var rows: []
        property var kindNames: []
        property var thumbState: ({})
        property int cursorIndex: 0
        property string storageClass: ""
        property bool storageKnown: true
        property bool listInFlight: false
        property var backend: backend
        property string searchMode: ""
        property string recentMode: ""
        property string filterQuery: ""
        property string listingState: "ready"
        property int total: 0
        property string viewMode: "list"
        property string dropPath: "/t"
        property int thumbCap: 240
        property int renamingIndex: -1
        property bool renamePending: false
        property bool menuVisible: false
        property bool filterTyping: false
        property var selectionBand: null
        property var collide: null
        property var menuActions: null
        property var trash: ({ opened: false })
        property var listSlot: ({ x: 0, y: 0, width: 100, height: 100 })
        property var listArea: ({ forceActiveFocus: function () {}, restartSettle: function () {} })
        function rowFor(index) { return null }
        function join(base, name) { return base + "/" + name }
        function selectionCount() { return 0 }
        function sticky(text) { shell.stickies.push(text) }
        function message(text, isError) { shell.messages.push({ text: text, error: isError }) }
        function refresh(selected) {}
    }

    FloatingWindow {
        implicitWidth: 400
        implicitHeight: 300

        Loader {
            id: wire
            anchors.fill: parent
            active: true
            source: "file://" + shell.uiDir + "/PaneWire.qml"
            onLoaded: { item.pane = pane; kick.start() }
            onStatusChanged: if (status === Loader.Error) { shell.check("the wire loads", false, "load error"); shell.quit() }
        }
    }

    // One thousand ok lines, then a pause past the beat.
    function legA() {
        backend.transferStarted(7, 1000, false, false)
        shell.check("a-started-card-is-drawn", pane.transfer.id === 7 && shell.stickies.length === 1, shell.card())
        for (var i = 0; i < 1000; i++) backend.transferItem(7, i, "f" + i, true, "")
        shell.check("a-thousand-ok-lines-wait-off-the-card", pane.transfer.done === 0, shell.card())
        shell.check("and-draw-no-status-line", shell.stickies.length === 1, "stickies " + shell.stickies.length)
        return shell.beatWaitMs
    }
    function legAFold() {
        shell.check("the-beat-folds-them-into-the-card", pane.transfer.done === 1000, shell.card())
        shell.check("with-the-last-one-named", pane.transfer.name === "f999", shell.card())
        shell.check("in-one-redraw", shell.stickies.length === 2, "stickies " + shell.stickies.length)
        shell.check("and-the-line-is-the-card's-own", shell.stickies[shell.stickies.length - 1] === Ops.progressLine(pane.transfer), shell.stickies[shell.stickies.length - 1])
        shell.check("the-beat-is-at-most-a-tenth-of-a-second", wire.item.heldItemBeatMs <= 100, "beat " + wire.item.heldItemBeatMs)
    }
    // A held line meets a sample: the sample is later, so it must stay the card's last word.
    function legB() {
        backend.transferStarted(8, 10, false, false)
        backend.transferItem(8, 0, "a", true, "")
        backend.transferProgress(8, 1, "b", 50, 100, 0, "", "")
        return shell.beatWaitMs
    }
    function legBCheck() {
        shell.check("a-held-line-never-overwrites-a-later-sample", pane.transfer.index === 1 && pane.transfer.name === "b", shell.card())
    }
    // A held line meets a failure: the failure is later, and it reports at once.
    function legC() {
        backend.transferItem(8, 2, "c", true, "")
        backend.transferItem(8, 3, "d", false, "denied")
        shell.check("a-failure-reports-at-once", shell.messages.length === 1 && shell.messages[0].error === true, JSON.stringify(shell.messages))
        return shell.beatWaitMs
    }
    function legCCheck() {
        shell.check("a-held-line-never-overwrites-a-later-failure", pane.transfer.done === 4 && pane.transfer.name === "d", shell.card())
    }
    // A held line meets the done line: nothing may rebuild a card after it.
    function legD() {
        backend.transferItem(8, 4, "e", true, "")
        backend.transferDone(8, 4, 1, 0, false, [], false, "", 0, 0, "")
        shell.check("done-clears-the-card", pane.transfer.id === 0, shell.card())
        return shell.beatWaitMs
    }
    function legDCheck() {
        shell.check("a-held-line-never-rebuilds-a-card-after-done", pane.transfer.id === 0 && pane.transfer.done === 0, shell.card())
        shell.check("or-draws-a-status-line-after-it", shell.stickies[shell.stickies.length - 1] === "", String(shell.stickies[shell.stickies.length - 1]))
    }
    // A held line of one transfer never lands on the next; a line of a stale id is not held.
    function legE() {
        backend.transferStarted(9, 5, false, false)
        backend.transferItem(9, 0, "a", true, "")
        backend.transferStarted(10, 5, false, false)
        backend.transferItem(9, 1, "stale", true, "")
        // Read before the beat, so a stale line held and dropped at the flush cannot pass for one never held.
        shell.check("a-stale-id-line-is-never-queued", wire.item.heldItems.length === 0, JSON.stringify(wire.item.heldItems))
        return shell.beatWaitMs
    }
    function legECheck() {
        shell.check("a-new-transfer-drops-lines-held-for-the-old", pane.transfer.id === 10 && pane.transfer.done === 0, shell.card())
        shell.check("and-a-stale-id-line-is-not-held", pane.transfer.done === 0 && pane.transfer.name === "", shell.card())
    }
    // A failure never waits on the beat.
    function legF() {
        var before = shell.messages.length
        backend.transferItem(10, 0, "x", false, "denied")
        shell.check("a-failure-reaches-the-card-at-once", pane.transfer.done === 1 && pane.transfer.failureReported === true, shell.card())
        shell.check("and-its-message-with-it", shell.messages.length === before + 1 && shell.messages[before].error === true, JSON.stringify(shell.messages))
        return 0
    }

    readonly property var steps: [legA, legAFold, legB, legBCheck, legC, legCCheck, legD, legDCheck, legE, legECheck, legF]

    Timer {
        id: kick
        interval: 100
        repeat: false
        onTriggered: shell.next()
    }

    Timer {
        id: pause
        repeat: false
        onTriggered: shell.next()
    }

    function next() {
        if (shell.step >= shell.steps.length) {
            shell.log("DONE failures=" + shell.failures.length + (shell.failures.length > 0 ? " [" + shell.failures.join(",") + "]" : ""))
            shell.quit()
            return
        }
        var wait = shell.steps[shell.step++]()
        if (wait > 0) {
            pause.interval = wait
            pause.start()
        } else {
            shell.next()
        }
    }
}
