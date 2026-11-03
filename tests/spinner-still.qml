//@ pragma ShellId flea-spinner-still-test

import QtQuick
import Quickshell
import qs.Commons
import "flea" as Flea

// tests/spinner-still.sh's harness: the real ui/Spinner.qml rests for its first second on screen, then crawls, and a hide resets it; frames and dash writes are counted, never timed.
ShellRoot {
    id: root

    property int checks: 0
    property var failures: []
    property int step: 0
    property real sample: 0
    property int frames: 0
    property int spinChanges: 0
    property int ownChanges: 0
    // Writes that moved the dash back toward its start; one wrap per loop is the crawl's own, anything more is a second writer.
    property int spinRises: 0
    property real lastOffset: 0
    property var marks: ({})

    function check(label, actual, expected) {
        root.checks += 1
        if (actual === expected) {
            console.log("SPINNERSTILL ok " + label)
            return
        }
        root.failures.push(label)
        console.log("SPINNERSTILL FAIL " + label + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function report() {
        if (root.failures.length === 0)
            console.log("SPINNERSTILL PASS " + root.checks + " checks")
        root.quit()
    }
    // The mark's ShapePath: the Shape is the spinner's only child item, and the path is the Shape's only data entry.
    function path(spinner) { return spinner.children[0].data[0] }
    function offset(spinner) { return root.path(spinner).dashOffset }
    // A mark is the counters at a step; since() is what changed from it to now, plus the ms for the per-second line only.
    function mark(name) { root.marks[name] = { frames: root.frames, spin: root.spinChanges, own: root.ownChanges, rises: root.spinRises, at: Date.now() } }
    function since(name) {
        var m = root.marks[name]
        return { frames: root.frames - m.frames, spin: root.spinChanges - m.spin, own: root.ownChanges - m.own, rises: root.spinRises - m.rises, ms: Date.now() - m.at }
    }

    FloatingWindow {
        implicitWidth: 200
        implicitHeight: 100
        color: Flea.Theme.color.background

        Item {
            id: frameProbe
            Connections {
                target: frameProbe.Window.window
                function onFrameSwapped() { root.frames += 1 }
            }
        }
        Item {
            id: host
            width: 48
            height: 48
            Flea.Spinner { id: spin; anchors.fill: parent }
        }
        Flea.Spinner { id: own; x: 100; width: 48; height: 48 }
    }

    Connections {
        target: root.path(spin)
        function onDashOffsetChanged() {
            var now = root.offset(spin)
            if (now > root.lastOffset) root.spinRises += 1
            root.lastOffset = now
            root.spinChanges += 1
        }
    }
    Connections {
        target: root.path(own)
        function onDashOffsetChanged() { root.ownChanges += 1 }
    }

    // Each entry runs once its ms have passed since the last show or hide (the start first), so a late step never moves a window.
    readonly property var plan: [
        [400, function () {
            root.check("still at 400 ms", spin.crawling, false)
            root.check("rest offset at 400 ms", root.offset(spin), 0)
            root.mark("rest")
        }],
        [850, function () {
            root.check("rest offset at 850 ms", root.offset(spin), 0)
            var rest = root.since("rest")
            root.check("a resting mark asks for no frame between 400 and 850 ms", rest.frames, 0)
            root.check("a resting mark writes no dash offset", root.spinChanges, 0)
        }],
        [1300, function () {
            root.check("crawling after its first second", spin.crawling, true)
            root.sample = root.offset(spin)
            root.mark("crawl")
        }],
        [2300, function () {
            var crawl = root.since("crawl")
            // The counts a second of crawl makes, printed for the record and never compared with a number.
            console.log("SPINNERSTILL rate frames=" + crawl.frames + " spin-dash-changes=" + crawl.spin + " own-dash-changes=" + crawl.own + " in " + crawl.ms + " ms")
            root.check("the crawl writes the dash offset", crawl.spin > 0, true)
            root.check("the crawl is drawn", crawl.frames > 0, true)
            root.check("the crawl writes the dash offset no oftener than the window draws", crawl.spin <= crawl.frames, true)
            root.check("the crawl walks the dash one way and wraps once a loop", crawl.rises <= 1, true)
        }],
        [2450, function () {
            root.check("the dash moves once crawling", root.offset(spin) !== root.sample, true)
            root.mark("hidden")
            host.visible = false
            root.anchor = Date.now()
        }],
        [100, function () {
            root.check("an ancestor's hide stops the crawl", spin.crawling, false)
            root.check("an ancestor's hide resets the dash", root.offset(spin), 0)
        }],
        [1300, function () {
            root.check("no crawl starts while hidden", spin.crawling, false)
            root.check("the dash stays at rest while hidden", root.offset(spin), 0)
            // The hide reset writes the offset once; nothing after it does, and its own mark is the one still drawing.
            root.check("a hidden mark writes no dash offset after its reset", root.since("hidden").spin <= 1, true)
            host.visible = true
            root.anchor = Date.now()
        }],
        [500, function () {
            root.check("still again 500 ms after the show", spin.crawling, false)
            root.check("rest offset again 500 ms after the show", root.offset(spin), 0)
        }],
        [1300, function () {
            root.check("crawling again a second after the show", spin.crawling, true)
            root.check("its own mark crawls too", own.crawling, true)
            own.visible = false
            root.anchor = Date.now()
        }],
        [100, function () {
            root.check("its own hide stops the crawl", own.crawling, false)
            root.check("its own hide resets the dash", root.offset(own), 0)
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
        interval: 15000
        running: true
        onTriggered: { console.log("SPINNERSTILL FAIL timed out at step " + root.step); root.quit() }
    }
}
