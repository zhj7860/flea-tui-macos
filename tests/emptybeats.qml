//@ pragma ShellId flea-emptybeats-test

import QtQuick
import Quickshell
import qs.Commons
import "flea" as Flea

// tests/emptybeats.sh's harness: the real ui/EmptyState.qml plays three beats after each appearance, then rests on the third.
ShellRoot {
    id: root

    property int checks: 0
    property var failures: []
    property int step: 0
    property int hiddenIndex: -1
    property int returnBase: -1

    function check(label, actual, expected) {
        root.checks += 1
        if (actual === expected) {
            console.log("EMPTYBEATS ok " + label)
            return
        }
        root.failures.push(label)
        console.log("EMPTYBEATS FAIL " + label + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function report() {
        if (root.failures.length === 0)
            console.log("EMPTYBEATS PASS " + root.checks + " checks")
        root.quit()
    }
    // The rest frame is the third beat drawn whole: its phrase, the caption fully in, the mark settled.
    function checkRest(label, index) {
        root.check(label + ": phrase", empty.messageIndex, index)
        root.check(label + ": caption in", empty.captionItem.opacity, 1)
        root.check(label + ": mark settled", empty.markItem.settled, true)
    }

    FloatingWindow {
        implicitWidth: 400
        implicitHeight: 300
        color: Flea.Theme.color.background

        Item {
            id: host
            anchors.fill: parent
            Flea.EmptyState { id: empty; anchors.fill: parent }
        }
    }

    // Each entry runs once its ms have passed since the last show or hide (the start first). A beat lands every 2.8 s.
    readonly property var plan: [
        [2000, function () { root.check("no beat inside the first 2.8 s", empty.messageIndex, 0) }],
        [9300, function () { root.check("three beats by 9.3 s", empty.messageIndex, 3) }],
        [12500, function () { root.checkRest("rests after the third beat", 3) }],
        [14600, function () {
            root.checkRest("still resting at 14.6 s", 3)
            host.visible = false
            root.anchor = Date.now()
        }],
        // Past one 2800 ms interval plus the 140 ms fade-out, so a Timer that ran while hidden would have swapped the phrase.
        [3500, function () {
            root.check("no beat while hidden", empty.messageIndex, 3)
            host.visible = true
            root.anchor = Date.now()
        }],
        [2000, function () { root.check("no beat inside 2.8 s of the show", empty.messageIndex, 3) }],
        [9300, function () { root.check("three beats again after the show", empty.messageIndex, 6) }],
        [12500, function () {
            root.checkRest("rests again after the third beat", 6)
            host.visible = false
            root.anchor = Date.now()
        }],
        // A fresh appearance, so the next hide lands mid-rotation with beats left to catch.
        [500, function () {
            host.visible = true
            root.anchor = Date.now()
        }],
        // Past one 2800 ms interval plus the 140 ms fade-out, so exactly one beat has landed.
        [3500, function () {
            root.check("one beat in before the mid-rotation hide", empty.messageIndex, 7 % empty.messages.length)
            root.hiddenIndex = empty.messageIndex
            host.visible = false
            root.anchor = Date.now()
        }],
        // Past two 2800 ms intervals plus the fade-out, so a Timer that ran while hidden would have swapped the phrase twice.
        [6500, function () {
            root.check("no beat while hidden mid-rotation", empty.messageIndex, root.hiddenIndex)
            root.returnBase = empty.messageIndex
            host.visible = true
            root.anchor = Date.now()
        }],
        [2000, function () { root.check("no beat inside 2.8 s of the return", empty.messageIndex, root.returnBase) }],
        [9300, function () { root.check("three beats again after the return", empty.messageIndex, (root.returnBase + 3) % empty.messages.length) }],
        [12500, function () {
            root.checkRest("rests again after the return", (root.returnBase + 3) % empty.messages.length)
            root.report()
        }]
    ]
    property double anchor: Date.now()

    Timer {
        interval: 20
        repeat: true
        running: true
        onTriggered: {
            if (root.step < root.plan.length && Date.now() - root.anchor >= root.plan[root.step][0]) {
                root.plan[root.step][1]()
                root.step += 1
            }
        }
    }
    Timer {
        interval: 100000
        running: true
        onTriggered: { console.log("EMPTYBEATS FAIL timed out at step " + root.step); root.quit() }
    }
}
