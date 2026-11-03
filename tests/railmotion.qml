//@ pragma ShellId flea-railmotion-test
import QtQuick
import QtTest
import Quickshell
import "flea" as Flea

// The auto-hidden rail slides in and out on x: the real window offscreen, a synthetic pointer, and a fast sampler of x, visible, width and row y; FLEA_REDUCED_MOTION=1 runs the snap leg only.
ShellRoot {
    id: root
    readonly property var pane: body.currentPane
    readonly property string home: Quickshell.env("HOME")
    readonly property bool reduced: Quickshell.env("FLEA_REDUCED_MOTION") === "1"
    readonly property string tag: root.reduced ? "RAILMOTION reduced " : "RAILMOTION "
    property var host: null
    property int checks: 0
    property int failures: 0
    property int stage: 0
    property double started: 0
    property bool executing: false
    property string waiting: ""
    property var samples: []
    property bool sampling: false
    property var marks: ({})
    property var revealedAt: []
    property var hiddenAt: []
    property real railW: 0
    property string sidebarId: ""
    property int keptCursor: -1
    property real xRe: 0
    property real listWidth: 0
    property int polls: 0

    RailIpc { id: railIpc; report: root.check }
    function check(name, actual, expected) {
        checks++
        var equal = JSON.stringify(actual) === JSON.stringify(expected)
        if (!equal) failures++
        console.log(root.tag + (equal ? "ok " : "FAIL ") + name + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }
    function ready(path) { return !pane.listInFlight && pane.path === path && pane.listingState === "ready" }
    function until(label, condition) {
        root.waiting = label
        return condition
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
    // The Sidebar is built once, so the sampler keeps the first one it finds instead of walking the tree every 2 ms.
    property var sidebarRef: null
    function sidebar() {
        if (!root.sidebarRef && root.host) root.sidebarRef = root.find(root.host, "Sidebar")
        return root.sidebarRef
    }
    // Listings the Sidebar's DeviceMounts has started; the rail keeps polling only while revealed.
    function devicePolls() { var d = root.find(root.sidebar(), "DeviceMounts"); return d ? d._listingsStarted : -1 }
    // The keep-running cases of DeviceMounts' poll, each held on a withdrawn rail; a release reveals the rail at once, so it is held on the parked poll itself.
    readonly property var holds: [
        { name: "a mount awaiting its folder", set: function (d) { d._pendingOpenDevice = "/dev/flea-rail-test" }, clear: function (d) { d._pendingOpenDevice = "" } },
        { name: "a power-off chain", set: function (d) { d._powerOffDisk = "/dev/flea-rail-test" }, clear: function (d) { d._powerOffDisk = "" } },
        { name: "no first answer yet", set: function (d) { d.firstAnswered = false }, clear: function (d) { } },
        { name: "a release in flight", set: function (d) { d.polling = false; d._unmounting = true },
          clear: function (d) { d._unmounting = false; d.polling = Qt.binding(function () { return root.sidebar().polling }) } }
    ]
    // The DEVICES poll's own Timer, found by its interval; running false is the parked state.
    function pollParked() {
        var d = root.find(root.sidebar(), "DeviceMounts")
        for (var i = 0; d && i < d.data.length; i++)
            if (d.data[i].interval === d.pollMs && d.data[i].triggeredOnStart) return !d.data[i].running
        return false
    }
    // Each hold starts parked and ends parked, so a step's growth is its own and never the case before's leftover polling.
    function holdSteps() {
        var out = []
        root.holds.forEach(function (hold) {
            out.push(function () { return until("the rail withdrawn and the poll parked before " + hold.name, root.gone() && root.pollParked()) })
            out.push(function () { root.polls = root.devicePolls(); hold.set(root.find(root.sidebar(), "DeviceMounts")); root.mark("hold"); return true })
            out.push(function () {
                var d = root.find(root.sidebar(), "DeviceMounts")
                var grew = root.devicePolls() > root.polls
                if (!grew && root.since("hold") < 1500) return false
                check(hold.name + " keeps a parked poll running", [d.polling === false, grew], [true, true])
                hold.clear(d)
                return true
            })
            out.push(function () {
                if (!until("the poll parked again after " + hold.name, root.pollParked())) return false
                check(hold.name + " parks the poll again once cleared", [root.find(root.sidebar(), "DeviceMounts").firstAnswered, root.pollParked()], [true, true])
                return true
            })
        })
        return out
    }
    function mark(name) { root.marks[name] = Date.now() }
    function since(name) { return Date.now() - root.marks[name] }
    // The pointer: x 1 is inside the edge strip and over the rail's first pixel, x at 60% of the pane is on the listing.
    function pointer(x) { return driver.mouseMove(pane, x, pane.height / 2, 1, Qt.NoButton, Qt.NoModifier) }
    function edgeIn() { root.pointer(1) }
    function edgeOut() { root.pointer(pane.width * 0.6) }
    function key(k) { driver.keyClick(k, Qt.NoModifier, -1) }
    function rowSig(sb) {
        if (!sb) return ""
        var out = []
        for (var i = 0; i < sb.entries.length; i++) {
            var row = sb.railItemFor(i)
            out.push(row ? Math.round(row.mapToItem(null, 0, 0).y) : "-")
        }
        return out.join(",")
    }
    function sample() {
        var sb = root.sidebar()
        var loader = sb ? sb.parent : null
        root.samples.push({ t: Date.now(), x: root.host.railX, rev: root.host.revealed, vis: loader ? loader.visible : false,
                            w: loader ? loader.width : 0, sig: root.rowSig(sb), lw: pane.listArea.width })
    }
    function startSampling() { root.samples = []; root.sampling = true }
    // One last sample, because the step that sees the slide end can run before the sampler's next tick.
    function endSampling() { root.sample(); root.sampling = false }
    function shown() { return root.host.railX === 0 && root.host.revealed }
    function gone() {
        var sb = root.sidebar()
        return !root.host.revealed && sb !== null && !sb.parent.visible && root.host.railX === -root.railW
    }
    function between(from, to) {
        return root.samples.filter(function (s) { return s.t >= from && s.t <= to })
    }
    function firstAt(predicate, from) {
        for (var i = 0; i < root.samples.length; i++)
            if (root.samples[i].t >= from && predicate(root.samples[i])) return root.samples[i].t
        return -1
    }
    function distinct(list) {
        var seen = {}
        list.forEach(function (v) { seen[v] = true })
        return Object.keys(seen).length
    }
    // The shape of one slide in the samples from `from`: rises or falls, never jumps, never changes the rail's width.
    function slide(from, to, up) {
        var run = root.between(from, to)
        var xs = run.map(function (s) { return s.x })
        var ordered = true, widest = 0
        for (var i = 1; i < xs.length; i++) {
            var step = up ? xs[i] - xs[i - 1] : xs[i - 1] - xs[i]
            if (step < 0) ordered = false
            widest = Math.max(widest, step)
        }
        return { ordered: ordered, widest: widest, distinct: root.distinct(xs), widths: root.distinct(run.map(function (s) { return s.w })) }
    }

    FloatingWindow {
        id: window
        implicitWidth: 1000
        implicitHeight: 650
        Flea.WindowBody { id: body; host: window }
        Item { anchors.fill: parent; TestEvent { id: driver } }
        RailDragHold {
            id: dragHold
            pane: root.pane
            host: root.host
            report: root.check
        }
    }
    Connections {
        target: root.host
        function onRevealedChanged() {
            var list = root.host.revealed ? root.revealedAt : root.hiddenAt
            list.push(Date.now())
        }
    }
    Timer {
        interval: 2
        repeat: true
        running: root.sampling && root.host !== null
        onTriggered: root.sample()
    }

    readonly property var snapSteps: [
        function () { return until("the first listing", ready(root.home)) },
        function () {
            root.host = root.find(pane, "PaneRail")
            check("the reduced leg opens in the single view with the switch on", [body.dualMode, Flea.Theme.reducedMotion], [false, true])
            root.mark("settle")
            return true
        },
        function () { if (since("settle") < 300) return false; root.edgeIn(); root.mark("in"); return true },
        function () {
            if (!until("the snap reveal", root.host.revealed)) return false
            // This poll is the first to see the reveal.
            var sb = root.sidebar()
            check("with reduced motion x reads 0 on the first poll after the dwell", root.host.railX, 0)
            check("and the rail is visible", sb !== null && sb.parent.visible, true)
            check("after the dwell and not before it", root.revealedAt[0] - root.marks.in >= 100, true)
            root.railW = sb ? sb.parent.width : 0
            root.edgeOut()
            root.mark("out")
            return true
        },
        function () {
            if (!until("the snap hide", !root.host.revealed)) return false
            var sb = root.sidebar()
            check("the settle still applies with reduced motion", root.hiddenAt[0] - root.marks.out >= 200, true)
            check("and x reads minus the width on the first poll after the hide", root.host.railX, -root.railW)
            check("with the rail not visible", sb !== null && sb.parent.visible, false)
            return true
        }
    ].concat(dragHold.steps())

    readonly property var steps: [
        function () { return until("the first listing", ready(root.home)) },
        function () {
            root.host = root.find(pane, "PaneRail")
            check("auto-hide is on", root.host.overlay, true)
            check("no Sidebar exists at launch", root.sidebar(), null)
            check("the rail is not built at launch", root.host.built, false)
            root.mark("settle")
            return true
        },
        function () { return until("railState over IPC", railIpc.is("railState reads hidden at rest with width 0", { hidden: true, width: 0, revealed: false, x: 0 })) },
        // A crossing shorter than the dwell builds the Sidebar and never reveals it.
        function () { if (since("settle") < 300) return false; root.startSampling(); root.edgeIn(); root.mark("in"); return true },
        function () { if (since("in") < 50) return false; root.edgeOut(); root.mark("out"); return true },
        // Held past the rail gate, so every later slide runs on settled rows; the sampler reports when the gated rows landed.
        function () {
            var held = root.sidebar()
            if (since("in") < 1200 || !held || !held.railDeadlineElapsed) return false
            root.endSampling()
            var built = root.samples.filter(function (s) { return s.sig !== "" })
            var landed = built.filter(function (s) { return s.sig !== built[0].sig })
            console.log(root.tag + "NOTE the Sidebar built at +" + (built[0].t - root.marks.in) + " ms after strip entry; its gated rows "
                      + (landed.length > 0 ? "landed at +" + (landed[0].t - built[0].t) + " ms after the build" : "did not change after the build")
                      + "; a dwell reveal slides from +120 to +300 ms after strip entry")
            var sb = root.sidebar()
            check("a crossing shorter than the dwell never reveals", root.revealedAt.length, 0)
            check("but it built the Sidebar, undrawn", sb !== null && sb.parent.visible, false)
            root.railW = sb ? sb.parent.width : 0
            check("parked at minus its width", root.host.railX, -root.railW)
            check("and railWidth still reads 0", pane.sidebarWidth, 0)
            root.sidebarId = String(sb)
            return true
        },
        // First dwell reveal.
        function () { root.startSampling(); root.edgeIn(); root.mark("in"); return true },
        function () {
            if (!until("x to reach 0", root.shown())) return false
            root.endSampling()
            var shownAt = root.firstAt(function (s) { return s.x === 0 && s.rev }, 0)
            var from = root.revealedAt[0]
            check("a dwell reveals", root.revealedAt.length, 1)
            check("after about the dwell", root.revealedAt[0] - root.marks.in >= 100, true)
            check("x reaches 0 within 250 ms of the reveal", shownAt - from <= 250, true)
            var shape = root.slide(from, shownAt, true)
            check("x rises every sample", shape.ordered, true)
            check("with no jump over 60% of the width", shape.widest <= root.railW * 0.6, true)
            check("through at least three positions", shape.distinct >= 3, true)
            check("the rail's width never changes", shape.widths, 1)
            check("railWidth reads the width at rest", pane.sidebarWidth, root.railW)
            check("every rail row keeps its y through the first reveal", root.distinct(root.samples.map(function (s) { return s.sig })), 1)
            return true
        },
        function () { return until("railState over IPC", railIpc.is("railState reads the shown rail", { hidden: false, width: root.railW, revealed: true, x: 0 })) },
        function () {
            var sb = root.sidebar()
            sb.cursorIndex = 3
            root.keptCursor = sb.cursorIndex
            check("the cursor can sit on a rail row", root.keptCursor, 3)
            root.startSampling()
            root.edgeOut()
            root.mark("out")
            return true
        },
        function () {
            if (!until("the settle", root.hiddenAt.length > 0)) return false
            check("leaving waits the settle", root.hiddenAt[0] - root.marks.out >= 200, true)
            return true
        },
        function () {
            if (!until("the hide slide", root.gone())) return false
            root.endSampling()
            var endAt = root.firstAt(function (s) { return s.x === -root.railW && !s.vis }, root.hiddenAt[0])
            check("x reaches minus the width and visible is false", endAt > 0, true)
            check("within 250 ms of the hide", endAt - root.hiddenAt[0] <= 250, true)
            var shape = root.slide(root.hiddenAt[0], endAt, false)
            check("x falls every sample", shape.ordered, true)
            check("with no jump over 60% of the width", shape.widest <= root.railW * 0.6, true)
            check("through at least three positions", shape.distinct >= 3, true)
            check("the rail's width never changes", shape.widths, 1)
            check("and every rail row keeps its y through the hide", root.distinct(root.samples.map(function (s) { return s.sig })), 1)
            check("railWidth reads 0 hidden", pane.sidebarWidth, 0)
            root.polls = root.devicePolls()
            check("the built Sidebar's DeviceMounts listed before it was withdrawn", root.polls >= 1, true)
            root.mark("parked")
            return true
        },
        // The built Sidebar stays, but its DEVICES poll (5000 ms) is parked while the rail is withdrawn, and a reveal lists at once.
        function () {
            if (since("parked") < 5600) return false
            check("a withdrawn rail lists no devices over a full poll interval", root.devicePolls() - root.polls, 0)
            root.edgeIn()
            return true
        },
        function () {
            if (!until("the reveal that polls", root.shown())) return false
            check("the reveal lists devices at once", root.devicePolls() - root.polls >= 1, true)
            root.edgeOut()
            return true
        },
        function () { return until("the hide after the poll check", root.gone()) },
        // Re-entry mid-hide: show, leave, wait for the hide to start, come back.
        function () { root.edgeIn(); return true },
        function () {
            if (!until("the second reveal", root.shown())) return false
            root.edgeOut()
            return true
        },
        function () {
            if (!until("the hide to be underway", !root.host.revealed && root.host.railX < -root.railW * 0.25)) return false
            root.xRe = root.host.railX
            root.revealedAt = []
            root.startSampling()
            root.edgeIn()
            root.mark("back")
            return true
        },
        function () {
            if (!until("the reversal to reach 0", root.shown())) return false
            root.endSampling()
            check("re-entry mid-hide found the rail part way", root.xRe > -root.railW && root.xRe < 0, true)
            check("and reveals it at once, with no dwell", root.revealedAt.length === 1 && root.revealedAt[0] - root.marks.back < 60, true)
            var low = Math.min.apply(null, root.samples.map(function (s) { return s.x }))
            check("it reverses from the current x, not from minus the width", low >= root.xRe - root.railW * 0.3, true)
            var shape = root.slide(root.revealedAt[0], Date.now(), true)
            check("and x rises from there without a jump", shape.ordered && shape.widest <= root.railW * 0.6, true)
            return true
        },
        // The third reveal, from fully hidden, still on the one Sidebar.
        function () { root.edgeOut(); return true },
        function () { if (!until("the hide", root.gone())) return false; root.edgeIn(); root.startSampling(); return true },
        function () {
            if (!until("the third reveal", root.shown())) return false
            root.endSampling()
            var sb = root.sidebar()
            check("three reveals keep one Sidebar object", String(sb) === root.sidebarId, true)
            check("and its cursor", sb.cursorIndex, root.keptCursor)
            check("every rail row keeps its y through the third reveal", root.distinct(root.samples.map(function (s) { return s.sig })), 1)
            check("and the rail's width", root.distinct(root.samples.map(function (s) { return s.w })), 1)
            root.edgeOut()
            return true
        },
        // Tab: no dwell, focus before the slide ends.
        function () {
            if (!until("the hide", root.gone())) return false
            pane.listArea.forceActiveFocus()
            root.revealedAt = []
            root.startSampling()
            root.mark("tab")
            root.key(Qt.Key_Tab)
            check("Tab moves focus to the rail before the slide ends", pane.focusView + "|" + (root.host.railX < 0), "rail|true")
            check("with the reveal in the same turn, no dwell", root.revealedAt.length === 1 && root.revealedAt[0] - root.marks.tab < 60, true)
            return true
        },
        function () {
            if (!until("the Tab reveal", root.shown())) return false
            root.endSampling()
            var shownAt = root.firstAt(function (s) { return s.x === 0 && s.rev }, 0)
            check("x reaches 0 within 250 ms of Tab", shownAt - root.marks.tab <= 250, true)
            root.revealedAt = []
            root.hiddenAt = []
            root.startSampling()
            root.mark("tabout")
            root.key(Qt.Key_Tab)
            check("Tab out hands the keyboard on to the bar", pane.focusView, "chrome")
            return true
        },
        function () {
            if (!until("the Tab out hide", root.gone())) return false
            root.endSampling()
            check("Tab out skips the settle", root.hiddenAt[0] - root.marks.tabout < 100, true)
            check("and x reaches minus the width, undrawn", root.host.railX, -root.railW)
            // Tab out with the pointer on the rail keeps it up until the pointer leaves.
            pane.focusView = "list"; pane.listArea.forceActiveFocus()
            root.key(Qt.Key_Tab)
            return true
        },
        function () {
            if (!until("the second Tab reveal", root.shown())) return false
            root.pointer(60)
            root.mark("on")
            return true
        },
        function () {
            if (since("on") < 100) return false
            root.hiddenAt = []
            root.key(Qt.Key_Tab)
            root.mark("tabout2")
            return true
        },
        function () {
            if (since("tabout2") < 400) return false
            check("Tab out with the pointer on the rail keeps it up", root.hiddenAt.length + "|" + root.host.revealed, "0|true")
            root.edgeOut()
            root.mark("away")
            return true
        },
        function () {
            if (!until("the hide once the pointer leaves", root.gone())) return false
            check("and the settle then applies", root.hiddenAt[0] - root.marks.away >= 200, true)
            return true
        },
        // Dual: the primary list holds its width through a reveal.
        function () { Flea.ViewState.changeKey("view", "dual"); root.mark("dual"); return true },
        function () {
            if (since("dual") < 700 || !until("the dual view", body.dualMode && ready(root.home))) return false
            root.listWidth = pane.listArea.width
            root.startSampling()
            root.edgeIn()
            return true
        },
        function () {
            if (!until("the dual reveal", root.shown())) return false
            root.edgeOut()
            return true
        },
        function () {
            if (!until("the dual hide", root.gone())) return false
            root.endSampling()
            check("in Dual the primary list width holds through a reveal and a hide",
                  root.distinct(root.samples.map(function (s) { return s.lw })) + "|" + (pane.listArea.width === root.listWidth), "1|true")
            return true
        }
    ].concat(root.holdSteps(), dragHold.steps())

    Timer {
        interval: 20
        repeat: true
        running: true
        onTriggered: {
            var list = root.reduced ? root.snapSteps : root.steps
            if (root.executing) return
            if (root.stage >= list.length) {
                stop()
                console.log(root.tag + "DONE checks=" + root.checks + " failed=" + root.failures)
                body.quitBackends()
                return
            }
            if (!root.started) root.started = Date.now()
            root.executing = true
            var done = false
            try { done = list[root.stage]() }
            catch (error) { root.check("step " + root.stage + " threw", String(error), "no exception"); done = true }
            root.executing = false
            if (!done && Date.now() - root.started > 7000) {
                root.check("waiting for " + root.waiting, false, true)
                done = true
            }
            if (done) { root.stage++; root.started = 0 }
        }
    }
}
