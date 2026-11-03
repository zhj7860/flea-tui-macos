//@ pragma ShellId flea-dropline-peek-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Ops.js" as Ops
import "flea/js/Status.js" as Status

// The drag line a peek column's FileDrag speaks has no pane of its own, so the activity observer must name the pane that owns the peek, not read the null pane.
ShellRoot {
    id: root

    property int checks: 0
    property int failures: 0

    // The window the drag speaks in: a path and a focus flag are all the observer reads from its owner.
    readonly property QtObject paneStub: QtObject {
        property var statusBar: root.barStub
        property string path: "/fx/cap-drops/Photos"
        property bool paneFocused: true
    }
    // The status strip's activity list, with the setter the product strip runs.
    readonly property QtObject barStub: QtObject {
        property var activities: []
        property var dragFeedbackOwner: null
        property var errors: []
        property string notice: ""
        property bool hasUndo: false
        property var transferCard: null
        property var undoItem: null
        function setActivity(owner, text, transfer) { activities = Status.activityChanged(activities, owner, text, transfer) }
    }
    readonly property QtObject otherOwner: QtObject {
        property string path: "/fx/other"
        property bool paneFocused: false
    }

    Flea.FileDrag { id: own; pane: root.paneStub }
    Flea.FileDrag { id: peek; pane: null; peekSource: ({ pane: root.paneStub, dir: "/fx/cap-drops", v: 1, w: true }) }
    QtObject { id: windowStub; function centreOf(item) { return "" } function rectOf(item) { return "" } }
    Flea.Ipc { id: ipc; pane: root.paneStub; bar: root.barStub; fleaWindow: windowStub }

    function check(label, actual, expected) {
        root.checks += 1
        if (JSON.stringify(actual) === JSON.stringify(expected)) return
        root.failures += 1
        console.log("DROPLINEPEEK FAIL " + label + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }

    // Sample output: {"text":"Move 1 item to deep","ownerPath":"/fx/cap-drops/Photos","ownerFocused":true} for a line read, or {"threw":"TypeError: ..."} when the observer threw.
    function line() {
        try {
            var activities = JSON.parse(ipc.seam.statusActivityState()).activities
            return activities.length ? { text: activities[0].text, ownerPath: activities[0].ownerPath, ownerFocused: activities[0].ownerFocused } : { text: "" }
        } catch (e) { return { threw: String(e) } }
    }

    Timer {
        interval: 200
        running: true
        onTriggered: {
            var photos = { text: "Move 1 item to deep", ownerPath: "/fx/cap-drops/Photos", ownerFocused: true }
            own.say("Move 1 item to deep")
            root.check("a listing's drag line names its pane", root.line(), photos)
            own.say("")
            root.check("a cleared line leaves no activity", root.line(), { text: "" })
            peek.say("Move 1 item to deep")
            root.check("a peek column's drag line names the pane that owns the peek", root.line(), photos)
            peek.say("")
            root.check("the peek's cleared line leaves no activity", root.line(), { text: "" })
            root.barStub.setActivity(root.otherOwner, "Copy 1 item to x", Ops.emptyTransfer())
            root.check("a transfer owner is read as itself", root.line(), { text: "Copy 1 item to x", ownerPath: "/fx/other", ownerFocused: false })
            console.log("DROPLINEPEEK DONE checks=" + root.checks + " failed=" + root.failures)
            Quickshell.execDetached(["kill", String(Quickshell.processId)])
        }
    }
}
