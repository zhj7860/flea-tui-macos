//@ pragma ShellId flea-hidden-release-test
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "flea" as Flea
import "flea/js/Focus.js" as Focus
import "flea/js/Mounts.js" as Mounts

// A release in flight outlives the surface that asked for it: the real window, PaneRail and DeviceMounts against slow gio doubles.
ShellRoot {
    id: root
    readonly property var pane: body.currentPane
    readonly property string box: Quickshell.env("FLEA_HR_BOX")
    readonly property string home: Quickshell.env("HOME")
    property int checks: 0
    property int failures: 0
    property int stage: 0
    property double started: 0
    property bool executing: false
    property string waiting: ""
    property var said: []
    property var errors: []
    property var found: ({})
    property string heldSidebar: ""

    function check(name, actual, expected) {
        checks++
        var equal = JSON.stringify(actual) === JSON.stringify(expected)
        if (!equal) failures++
        console.log("HIDDEN_RELEASE " + (equal ? "ok " : "FAIL ") + name
                    + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }
    function at(name) { return root.box + "/mnt/" + name }
    function ready(path) { return !pane.listInFlight && pane.path === path && pane.listingState === "ready" }
    function until(label, condition) {
        root.waiting = label
        return condition
    }
    function press(key, modifiers) {
        pane.listArea.forceActiveFocus()
        driver.keyClick(key, modifiers || Qt.NoModifier, -1)
    }
    function find(item, type) {
        if (String(item).indexOf(type + "_") === 0) return item
        var children = item && item.children ? item.children : []
        for (var i = 0; i < children.length; i++) {
            var hit = root.find(children[i], type)
            if (hit) return hit
        }
        return null
    }
    // The doubles leave a marker file at each step of a release; the probe reads one per tick.
    function seen(name) {
        if (!probe.running) {
            probe.target = name
            probe.command = ["test", "-e", root.box + "/" + name]
            probe.running = true
        }
        return root.found[name] === true
    }
    // What a failed wait leaves in the log: the pane, its messages, the transient host and the rows it read.
    function snapshot() {
        var host = root.find(pane, "DeviceMounts")
        return JSON.stringify({ path: pane.path, said: root.said, host: host !== null, releasing: host ? host.releasing : null,
                                rows: host ? host.entries.map(function (e) { return e.label + ":" + e.mounted + ":" + e.path }) : null,
                                found: root.found })
    }
    // The status bar's error entries naming a volume: where the user reads a refusal.
    function barErrors(volume) {
        var bar = root.find(body, "StatusBar")
        return bar ? bar.errors.filter(function (e) { return e.text.indexOf(volume) >= 0 }).length : -1
    }
    function volumeRow(label) {
        var rows = pane.sidebar ? pane.sidebar.entries : []
        for (var i = 0; i < rows.length; i++)
            if (rows[i].kind === "volume" && rows[i].label === label) return rows[i]
        return null
    }

    FloatingWindow {
        id: window
        implicitWidth: 1000
        implicitHeight: 650
        Flea.WindowBody { id: body; host: window }
        Item { anchors.fill: parent; TestEvent { id: driver } }
    }
    Connections {
        target: root.pane
        function onMessage(text, isError) {
            root.said = root.said.concat([text])
            if (isError) root.errors = root.errors.concat([text])
        }
        // A failed unmount or eject rides operationResult, whose error headline the status bar lists (ui/WindowBody.qml).
        function onOperationResult(headline, detail, isError) {
            if (!isError) return
            root.said = root.said.concat([headline])
            root.errors = root.errors.concat([headline])
        }
    }
    Process {
        id: probe
        property string target: ""
        onExited: function (code) {
            var next = root.found
            next[target] = code === 0
            root.found = next
        }
    }

    readonly property var steps: [
        function () { return until("the first listing", ready(at("Data"))) },
        function () { Flea.ViewState.changeLeaf("places", { rail: "hidden" }); return true },
        // A fixed volume has no Eject, so Ctrl+E unmounts it, and the hidden rail's own host carries the unmount.
        function () {
            if (!until("the rail to hide", pane.sidebar === null)) return false
            root.said = []
            root.press(Qt.Key_E, Qt.ControlModifier)
            return true
        },
        function () {
            if (!until("the unmount to start", seen("data.started"))) return false
            return true
        },
        function () {
            if (!until("the unmount to finish", seen("data.done"))) return false
            check("hidden rail: Ctrl+E inside a fixed volume lets gio finish its unmount", true, true)
            check("and the pane left the volume first", pane.path, root.home)
            check("and a silent success says nothing", root.said, [])
            return true
        },
        function () {
            if (!until("the host to unload", root.find(pane, "DeviceMounts") === null)) return false
            check("and the host unloads once the unmount ends", true, true)
            pane.open(at("Busy"))
            return true
        },
        // A refusal is a message first and an unload after it.
        function () {
            if (!until("the busy volume's listing", ready(at("Busy")))) return false
            root.said = []
            root.errors = []
            root.press(Qt.Key_E, Qt.ControlModifier)
            return true
        },
        function () {
            if (!until("the refusal", root.errors.length > 0)) return false
            check("a refused unmount says so once, naming the volume", root.errors.length + "|" + (root.errors[0].indexOf("Busy") >= 0), "1|true")
            check("and the status bar lists it once", root.barErrors("Busy"), 1)
            return true
        },
        function () {
            if (!until("the host to unload after a refusal", root.find(pane, "DeviceMounts") === null)) return false
            check("and the host unloads after the refusal", true, true)
            pane.open(at("Slow"))
            return true
        },
        // A second unmount while one runs is answered, and the host the first one needs stays up.
        function () {
            if (!until("the slow volume's listing", ready(at("Slow")))) return false
            root.press(Qt.Key_E, Qt.ControlModifier)
            return true
        },
        function () {
            if (!until("the slow unmount to start", seen("slow.started"))) return false
            check("a user unmount quiesces its volume first, so the pane left it", pane.path, root.home)
            pane.open(at("Other"))
            return true
        },
        function () {
            if (!until("the other volume's listing", ready(at("Other")))) return false
            root.said = []
            root.press(Qt.Key_E, Qt.ControlModifier)
            return true
        },
        function () {
            if (!until("the busy sentence", root.said.length > 0)) return false
            check("a second unmount while one runs says what it waits for", root.said, ["Still unmounting Slow; wait for its result"])
            return true
        },
        function () {
            if (!until("the slow unmount to finish", seen("slow.done"))) return false
            check("and the first unmount still finished", true, true)
            return true
        },
        function () {
            if (!until("the host to unload after the slow unmount", root.find(pane, "DeviceMounts") === null)) return false
            pane.open(root.home)
            // Auto-hide first, so the rail never shows for a moment and builds a Sidebar that the next change destroys.
            Flea.ViewState.changeLeaf("places", { autoHide: true })
            Flea.ViewState.changeLeaf("places", { rail: "shown" })
            return true
        },
        // An auto-hide rail that withdraws mid-unmount keeps its Sidebar until the unmount ends.
        function () {
            if (!until("the home listing", ready(root.home) && pane.sidebar === null)) return false
            pane.focusView = Focus.RAIL
            return true
        },
        function () {
            if (!until("the rail's Rail row", pane.sidebar !== null && root.volumeRow("Rail") !== null)) return false
            pane.sidebar.releaseChosen("unmountVolume", Mounts.railKey(root.volumeRow("Rail")))
            pane.focusView = Focus.LIST
            return true
        },
        function () {
            if (!until("the rail's unmount to finish", seen("rail.done"))) return false
            check("an auto-hide rail withdrawn mid-unmount lets gio finish", true, true)
            return true
        },
        function () {
            if (!until("the rail to withdraw after the unmount", pane.sidebar === null)) return false
            check("and it withdraws once the unmount ends", true, true)
            return true
        },
        // A docked rail hidden with Ctrl+B mid-unmount keeps its Sidebar, undrawn, until the unmount ends.
        function () {
            Flea.ViewState.changeLeaf("places", { autoHide: false })
            Flea.ViewState.changeLeaf("places", { rail: "shown" })
            return true
        },
        function () {
            if (!until("the docked rail's Held row", pane.sidebar !== null && root.volumeRow("Held") !== null)) return false
            root.said = []
            root.errors = []
            pane.sidebar.releaseChosen("unmountVolume", Mounts.railKey(root.volumeRow("Held")))
            return true
        },
        function () {
            if (!until("the Held unmount to start", seen("held.started"))) return false
            root.heldSidebar = String(pane.sidebar)
            root.press(Qt.Key_B, Qt.ControlModifier)
            return true
        },
        function () {
            if (!until("the docked rail to hide", pane.sidebar === null)) return false
            var held = root.find(pane, "Sidebar")
            check("a docked rail hidden mid-unmount keeps its Sidebar, still unmounting", held !== null && held.releasing, true)
            check("undrawn, with no width and no inset", (held ? held.visible : "no Sidebar") + "|" + pane.sidebarWidth + "|" + pane.railInset, "false|0|0")
            check("and the rail stays hidden", Flea.ViewState.railHidden, true)
            root.press(Qt.Key_B, Qt.ControlModifier)
            return true
        },
        function () {
            if (!until("a second Ctrl+B to show the rail", pane.sidebar !== null)) return false
            check("a second Ctrl+B shows the same Sidebar at once, still unmounting",
                  String(pane.sidebar) === root.heldSidebar && pane.sidebar.releasing, true)
            root.press(Qt.Key_B, Qt.ControlModifier)
            return true
        },
        function () {
            if (!until("a third Ctrl+B to hide the rail", pane.sidebar === null)) return false
            var held = root.find(pane, "Sidebar")
            check("a third Ctrl+B hides it again without losing the hold", held !== null && held.releasing, true)
            return true
        },
        function () {
            if (!until("the held unmount to end", seen("held.ended"))) return false
            return true
        },
        function () {
            if (!until("the held Sidebar to go", root.find(pane, "Sidebar") === null)) return false
            check("the held unmount's refusal lands once, naming the volume", root.errors.length + "|" + (root.errors.length > 0 && root.errors[0].indexOf("Held") >= 0), "1|true")
            check("and the status bar lists it once", root.barErrors("Held"), 1)
            check("and the rail is still hidden once the hold ends", Flea.ViewState.railHidden, true)
            return true
        }
    ]

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (root.executing) return
            if (root.stage >= root.steps.length) {
                stop()
                console.log("HIDDEN_RELEASE DONE checks=" + root.checks + " failed=" + root.failures)
                body.quitBackends()
                return
            }
            if (!root.started) root.started = Date.now()
            root.executing = true
            var done = false
            try { done = root.steps[root.stage]() }
            catch (error) { root.check("step " + root.stage + " threw", String(error), "no exception"); done = true }
            root.executing = false
            if (!done && Date.now() - root.started > 7000) {
                root.check("waiting for " + root.waiting + " " + root.snapshot(), false, true)
                done = true
            }
            if (done) { root.stage++; root.started = 0 }
        }
    }
}
