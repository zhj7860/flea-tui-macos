//@ pragma ShellId flea-dualdivider-test
import QtQuick
import QtTest
import Quickshell
import "flea" as Flea

// The Dual divider in the real WindowBody: its default split, its drag, its click, its double click, its clamp and the rail states.
ShellRoot {
    id: root

    readonly property real tolerance: 0.1
    readonly property real handleDrag: 100
    readonly property real farDrag: 5000
    readonly property real narrowBy: 20
    // The 0.3.9 left pane: the room right of the rail, split equally.
    readonly property var rails: [{name: "shown", rail: "shown", autoHide: false}, {name: "hidden", rail: "hidden", autoHide: false}, {name: "autohide", rail: "shown", autoHide: true}]
    property int checks: 0
    property int failed: 0
    property var steps: []
    property int next: 0
    property var counts: ({left: 0, right: 0})
    property bool wired: false

    function check(ok, label) {
        root.checks++
        if (!ok) {
            root.failed++
            console.log("DUALDIV FAIL " + label)
        }
    }
    function near(a, b) { return Math.abs(a - b) <= root.tolerance }

    // Each item once: a Loader lists its item both as a child and as .item.
    function walk(top, type) {
        var out = []
        var seen = []
        var stack = [top]
        while (stack.length > 0) {
            var item = stack.pop()
            if (item === null || item === undefined || seen.indexOf(item) >= 0) continue
            seen.push(item)
            if (String(item).indexOf(type + "_") === 0) out.push(item)
            var kids = item.children !== undefined ? item.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
            if (item.item !== undefined && item.item !== null && typeof item.item === "object") stack.push(item.item)
        }
        return out
    }
    function panes() {
        var all = root.walk(body, "Pane")
        var byX = all.map(function (p) { return {p: p, x: p.mapToItem(body, 0, 0).x} }).sort(function (a, b) { return a.x - b.x })
        return {left: byX[0].p, right: byX[byX.length - 1].p}
    }
    // The divider's handle names no column; the list header's handles do.
    function handles() { return root.walk(body, "ResizeHandle").filter(function (h) { return h.columnKey === "" }) }
    function leftWidth() { return root.panes().left.width - root.panes().left.railInset }
    function rightWidth() { return root.panes().right.width - root.panes().right.railInset }
    function room() { return body.width - root.panes().left.railInset - Flea.Theme.spacing.hairline }
    function owed() { return JSON.stringify(Flea.ViewState.unsaved) }
    function split() { return (Flea.ViewState.state.dual || {}).split }

    // The handle's own MouseArea, the item the compositor cancels; its canceled signal is what a stolen grab emits.
    function zoneOf(h) {
        for (var i = 0; i < h.children.length; i++)
            if (typeof h.children[i].canceled === "function" && h.children[i].acceptedButtons !== undefined) return h.children[i]
        return null
    }
    function press(h) { h.pressed({x: 0, y: 100}) }
    function move(h, dx) { h.moved({x: dx, y: 100}) }
    function drag(h, dx) { root.press(h); root.move(h, dx) }

    // Counts the width changes of the two panes from here on; the connections are made once.
    function wireCounts() {
        var p = root.panes()
        root.counts = {left: 0, right: 0}
        if (root.wired) return
        root.wired = true
        p.left.widthChanged.connect(function () { root.counts.left++ })
        p.right.widthChanged.connect(function () { root.counts.right++ })
    }

    // The rail is built before auto-hide takes it away, so its delayed host call never lands on a torn-down rail.
    function railStep(r) {
        return function () { Flea.ViewState.changeLeaf("places", {rail: r.rail, autoHide: false}) }
    }
    function autoStep(r) {
        return function () {
            Flea.ViewState.changeLeaf("places", {autoHide: r.autoHide})
            Flea.ViewState.changeLeaf("dual", {split: 5000})
        }
    }

    function defaults(r) {
        return function () {
            var p = root.panes()
            var formula = p.left.railInset + (body.width - p.left.railInset - Flea.Theme.spacing.hairline) / 2
            root.check(r.name === "shown" ? p.left.railInset > 0 : p.left.railInset === 0, r.name + " rail inset")
            root.check(root.near(p.left.width, formula), r.name + " default left pane is the 0.3.9 pane " + p.left.width + " vs " + formula)
            root.check(root.near(root.leftWidth(), root.rightWidth()), r.name + " default listings equal")
            root.check(root.split() === 5000, r.name + " default split 5000")
            var h = root.handles()
            root.check(h.length === 1, r.name + " one handle in Dual, got " + h.length)
            var zone0 = h[0].mapToItem(body, 0, 0).x
            var zone1 = zone0 + h[0].width
            var lane = root.walk(body, "ViewportScrollBar").filter(function (b) { return b.mapToItem(body, 0, 0).x < zone0 })
            var laneRight = lane.length > 0 ? lane[0].mapToItem(body, 0, 0).x + lane[0].width : -1
            var first = p.right.mapToItem(body, 0, 0).x + Flea.Theme.spacing.rowPaddingX
            root.check(lane.length > 0 && lane[0].visible, r.name + " the left listing shows a scroll lane")
            root.check(zone0 >= laneRight, r.name + " zone starts at or right of the lane edge " + zone0 + " vs " + laneRight)
            root.check(zone1 <= first, r.name + " zone ends at or left of the right listing's first content pixel")
            root.check(root.near(zone0, p.left.width), r.name + " zone starts on the divider pixel")
            console.log("DUALDIV measure " + r.name + " left=" + root.leftWidth() + " right=" + root.rightWidth()
                + " zone=" + zone0 + ".." + zone1 + " lane=" + (lane.length > 0 ? lane[0].mapToItem(body, 0, 0).x : -1) + ".." + laneRight
                + " firstContent=" + first + " lineX=" + h[0].lineX)
        }
    }

    function clickStep(r) {
        return function () {
            var h = root.handles()[0]
            var before = root.owed()
            root.press(h)
            h.released()
            root.check(root.owed() === before && root.split() === 5000, r.name + " a click writes nothing")
        }
    }

    // A grab the compositor takes mid-drag aborts it: no split is written, no listing moves, the line returns, and the release that follows finds nothing to commit.
    function cancelStep(r) {
        return function () {
            var h = root.handles()[0]
            var zone = root.zoneOf(h)
            root.check(zone !== null, r.name + " the handle holds its mouse area")
            var leftBefore = root.leftWidth()
            var before = root.owed()
            root.drag(h, root.handleDrag)
            root.check(h.hot && root.near(h.lineX, root.handleDrag), r.name + " the drag is live before the cancel")
            zone.canceled()
            root.check(!h.hot && root.near(h.lineX, 0), r.name + " a cancel rests the handle and returns the line")
            root.check(root.split() === 5000 && root.owed() === before, r.name + " a cancel writes nothing, split " + root.split())
            root.check(root.near(root.leftWidth(), leftBefore), r.name + " a cancel moves no listing")
            h.released()
            h.moved({x: root.handleDrag, y: 100})
            root.check(root.split() === 5000 && root.owed() === before && root.near(h.lineX, 0), r.name + " a release or move after a cancel does nothing")
        }
    }

    // A real pointer drag over the second listing's rows: a row's DragHandler passes its threshold on the first move and must not take the grab from the handle.
    function pointerStep(r) {
        return function () {
            var h = root.handles()[0]
            var zone = root.zoneOf(h)
            var lifts = root.walk(root.panes().right, "RowDrag")
            var y = 100
            var under = lifts.filter(function (l) { var t = l.mapFromItem(h, 4, y); return t.x >= 0 && t.x < l.width && t.y >= 0 && t.y < l.height })
            root.check(under.length > 0, r.name + " a row lift sits under the handle at y " + y + ", of " + lifts.length)
            var cancels = 0
            var count = function () { cancels++ }
            zone.canceled.connect(count)
            var leftBefore = root.leftWidth()
            keys.mousePress(h, 4, y, Qt.LeftButton, Qt.NoModifier, -1)
            keys.mouseMove(h, 4 + 40, y, -1, Qt.LeftButton, Qt.NoModifier)
            keys.mouseMove(h, 4 + root.handleDrag, y, -1, Qt.LeftButton, Qt.NoModifier)
            root.check(cancels === 0, r.name + " a real drag over a row is not canceled, cancels " + cancels)
            root.check(h.hot && root.near(h.lineX, root.handleDrag), r.name + " the real drag is live at the end, lineX " + h.lineX)
            keys.mouseRelease(h, 4 + root.handleDrag, y, Qt.LeftButton, Qt.NoModifier, -1)
            zone.canceled.disconnect(count)
            root.check(root.near(root.leftWidth(), leftBefore + root.handleDrag), r.name + " the real drag grew the left listing " + root.leftWidth() + " from " + leftBefore)
            Flea.ViewState.changeLeaf("dual", {split: 5000})
        }
    }

    function dragStep(r) {
        return function () {
            var h = root.handles()[0]
            var leftBefore = root.leftWidth()
            var before = root.owed()
            root.wireCounts()
            root.drag(h, root.handleDrag)
            root.check(h.hot, r.name + " the handle is hot during the drag")
            root.check(root.near(h.lineX, root.handleDrag), r.name + " the accent line follows the pointer " + h.lineX)
            root.check(root.near(root.leftWidth(), leftBefore) && root.owed() === before && root.counts.left === 0 && root.counts.right === 0,
                r.name + " only the handle moves during the drag")
            h.released()
            root.check(!h.hot, r.name + " the handle rests after release")
            root.check(root.near(root.leftWidth(), leftBefore + root.handleDrag), r.name + " the left listing grew by the drag " + root.leftWidth())
            root.check(root.near(root.rightWidth(), root.room() - leftBefore - root.handleDrag), r.name + " the right listing shrank by the drag")
            root.check(root.counts.left === 1 && root.counts.right === 1, r.name + " both panes re-lay once, " + root.counts.left + "/" + root.counts.right)
            var want = Math.round(10000 * (leftBefore + root.handleDrag) / root.room())
            root.check(root.split() === want, r.name + " split " + root.split() + " vs " + want)
            var patch = (Flea.ViewState.unsaved.dual || {}).split
            root.check(patch === want, r.name + " one split leaf is owed, " + patch)
        }
    }

    function clampStep(r, direction) {
        return function () {
            var h = root.handles()[0]
            var low = Flea.Theme.dualMinWidth
            root.drag(h, direction * root.farDrag)
            var left = root.leftWidth() + h.lineX
            root.check(root.near(direction > 0 ? root.room() - left : left, low), r.name + " the accent line stops at the minimum " + left)
            h.released()
            var stopped = direction > 0 ? root.rightWidth() : root.leftWidth()
            root.check(root.near(stopped, low), r.name + " the listing stops at the minimum " + stopped + " vs " + low)
            root.check(root.rightWidth() + root.leftWidth() > 0 && root.near(root.leftWidth() + root.rightWidth(), root.room()), r.name + " the listings still fill the room")
        }
    }

    function doubleClickStep(r) {
        return function () {
            var h = root.handles()[0]
            h.doubleClicked()
            root.check(root.split() === 5000, r.name + " double click restores 5000")
            root.check(root.near(root.leftWidth(), root.rightWidth()), r.name + " double click restores equal listings")
            root.check(root.near(root.leftWidth(), root.room() / 2), r.name + " equal means half the room")
        }
    }

    function storedStep(r) {
        return function () {
            Flea.ViewState.changeLeaf("dual", {split: 100})
        }
    }

    function storedCheck(r) {
        return function () {
            root.check(root.split() === 100, r.name + " the stored split is never rewritten by the clamp")
            root.check(root.near(root.leftWidth(), Flea.Theme.dualMinWidth), r.name + " a stored 100 lays the left listing at the minimum")
            Flea.ViewState.changeLeaf("dual", {split: 6500})
        }
    }

    function sharedCheck(r) {
        return function () {
            root.check(root.near(root.leftWidth(), root.room() * 0.65), r.name + " a stored 6500 lays the left listing at 65 percent")
            root.check(root.near(root.panes().left.width, root.panes().left.railInset + root.room() * 0.65), r.name + " the rail keeps narrowing the left pane")
            Flea.ViewState.changeLeaf("dual", {split: 5000})
        }
    }

    // The pane's own focus save carries {focus, paths} and must leave the stored split alone.
    function focusStep(r) {
        return function () {
            Flea.ViewState.changeLeaf("dual", {split: 6500})
            body.focusPane(1)
        }
    }

    function focusCheck(r) {
        return function () {
            root.check((Flea.ViewState.state.dual || {}).focus === 1, r.name + " the focus save landed")
            root.check(root.split() === 6500, r.name + " switching the focused side keeps the stored split, got " + root.split())
            root.check(root.near(root.leftWidth(), root.room() * 0.65), r.name + " the listings keep the 65 percent split after the switch")
            body.focusPane(0)
            Flea.ViewState.changeLeaf("dual", {split: 5000})
        }
    }

    // A window too narrow for two narrowest listings: nothing can move, so a drag leaves the stored split alone.
    function narrowStep() {
        Flea.ViewState.changeLeaf("dual", {split: 6500})
        frame.width = 2 * Flea.Theme.dualMinWidth + root.panes().left.railInset + Flea.Theme.spacing.hairline - root.narrowBy
    }

    function narrowCheck() {
        var h = root.handles()[0]
        root.check(Flea.Theme.dualMinWidth / root.room() > 0.5, "the window is too narrow for two minimum listings, room " + root.room())
        root.check(root.near(root.leftWidth(), root.rightWidth()), "a narrow window lays the listings equal")
        var before = root.owed()
        root.drag(h, root.handleDrag)
        h.released()
        root.check(root.split() === 6500, "a drag in a narrow window keeps the stored split, got " + root.split())
        root.check(root.owed() === before, "a drag in a narrow window owes nothing")
        frame.width = window.width
    }

    function single() {
        root.panes().left.chooseView("list")
    }

    function singleCheck() {
        root.check(root.handles().length === 0, "a single pane builds no handle, got " + root.handles().length)
    }

    function build() {
        var list = []
        for (var i = 0; i < root.rails.length; i++) {
            var r = root.rails[i]
            list.push(root.railStep(r), root.autoStep(r), root.defaults(r), root.clickStep(r), root.cancelStep(r), root.pointerStep(r), root.dragStep(r),
                root.clampStep(r, 1), root.clampStep(r, -1), root.doubleClickStep(r), root.storedStep(r), root.storedCheck(r), root.sharedCheck(r), root.focusStep(r), root.focusCheck(r))
        }
        list.push(root.narrowStep, root.narrowCheck, root.single, root.singleCheck)
        return list
    }

    function advance() {
        if (root.steps.length === 0) {
            if (Flea.ViewState.state.view !== "dual") {
                root.panes().left.chooseView("dual")
                return
            }
            root.steps = root.build()
        }
        if (root.next >= root.steps.length) {
            stepper.running = false
            console.log("DUALDIV DONE checks=" + root.checks + " failed=" + root.failed)
            Quickshell.execDetached(["kill", String(Quickshell.processId)])
            return
        }
        try {
            root.steps[root.next]()
        } catch (e) {
            root.check(false, "step " + root.next + " threw " + e)
        }
        root.next++
    }

    Timer { id: stepper; interval: 400; running: true; repeat: true; onTriggered: root.advance() }

    FloatingWindow {
        id: window
        implicitWidth: 1100
        implicitHeight: 700
        TestEvent { id: keys }
        Item {
            id: frame
            height: parent.height
            width: parent.width
            Flea.WindowBody { id: body; host: window }
        }
    }
}
