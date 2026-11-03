//@ pragma ShellId flea-griddroplive-test

import QtQuick
import Quickshell
import "flea" as Flea

// The shipped GridArea over the pane's floor under a real Qt drag (no mime data, so entry and drop are read from the area and the pane): who takes a folder tile, a file tile, the margin and bare ground.
ShellRoot {
    id: root

    property var failures: []
    property int checks: 0
    property var said: []
    property var steps: []
    property var gridPane: null
    property var floorPane: null
    property var floorItem: null
    property int polls: 0

    function check(label, actual, expected) {
        root.checks++
        if (JSON.stringify(actual) !== JSON.stringify(expected))
            root.failures.push(label + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }
    function row(name, dir) { return { n: name, d: dir, i: dir ? "folder" : "text-plain", p: dir ? 493 : 420, s: 0, m: 1758835200, t: false, k: 0, v: 0 } }
    property var rows: [root.row("dirA", true), root.row("f1.txt", false), root.row("dirB", true), root.row("f2.txt", false), root.row("dirC", true)]

    Component {
        id: backendStub
        QtObject {
            property var pathDevs: ({})
            property int dirDev: 0
            function peek(path, size, hidden) {}
            function thumb(rows, cacheOnly) {}
            function thumbcancel(rows) {}
            function dirsize(rows) {}
            function dirsizecancel() {}
            function window(start, count) {}
            function askMeta(index, text, media, archive) { return 0 }
        }
    }
    Component {
        id: paneStub
        QtObject {
            property string tag: ""
            property string path: "/probe"
            property string dropPath: "/probe"
            property string searchMode: ""
            property string searchBase: ""
            property string recentMode: ""
            property string viewMode: "grid"
            property string filterQuery: ""
            property bool filterTyping: false
            property var rows: []
            property var shown: null
            readonly property int shownTotal: shown === null ? total : shown.length
            property int total: 0
            property int held: 0
            property int cursorIndex: 2
            property int renamingIndex: -1
            property bool renamePending: false
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property var clipboard: ({ paths: [], moving: false })
            property var selectionBand: null
            property int previewIndex: -1
            property bool listInFlight: false
            property int settleMs: 120
            property int coalesceMs: 16
            property int refetchMargin: 25
            property int buffer: 150
            property int windowSize: 35
            property var backend: null
            property var sidebar: null
            function join(base, name) { return base + "/" + name }
            function message(text) { root.said.push(tag) }
            function rowFor(index) { var o = index - held; return (o >= 0 && o < rows.length) ? rows[o] : null }
            function isSelected(index) { return false }
        }
    }
    Component { id: menuStub; QtObject { function close() {} } }
    Component { id: floorMaker; Flea.DropInto { z: -1; width: 900; height: 700; pane: root.floorPane; dest: "/probe" } }
    Component { id: decoyMaker; Item { z: 20 } }

    FloatingWindow {
        implicitWidth: 900
        implicitHeight: 700
        color: "black"
        Item {
            id: stage
            width: 900
            height: 700
            Loader {
                id: viewLoader
                active: false
                width: 900
                height: 700
                sourceComponent: Flea.GridArea { pane: root.gridPane; menu: menuStub.createObject(root) }
            }
            Item {
                id: puck
                z: 10
                width: 2
                height: 2
                Drag.dragType: Drag.Internal
                Drag.supportedActions: Qt.CopyAction
                Drag.proposedAction: Qt.CopyAction
                Drag.keys: ["text/plain"]
            }
        }
    }

    function view() { return viewLoader.item }
    function tileOf(name) {
        for (var i = 0; i < root.rows.length; i++)
            if (root.rows[i].n === name) return root.view().itemAtIndex(i)
        return null
    }
    // The icon box of a tile as a point in the stage, the part of a tile a drop hits.
    function pointOf(name) {
        var tile = root.tileOf(name)
        return tile.thumbItem.mapToItem(stage, tile.thumbItem.width / 2, tile.thumbItem.height / 2)
    }
    // The corner of a tile's cell, bare ground that belongs to no icon or caption.
    function marginOf(name) {
        var tile = root.tileOf(name)
        return tile.mapToItem(stage, 2, 2)
    }
    // The built tiles that read the shared hover index, by row name, or by index in the long listing.
    function hoveredTiles() {
        var out = [], v = root.view()
        for (var i = 0; i < v.count; i++) {
            var tile = v.itemAtIndex(i)
            if (tile && tile.hovered) out.push(root.rows.length <= 5 ? root.rows[i].n : i)
        }
        return out
    }
    function target() { return root.view().dropListingIndex }
    function floorHolds() { return root.floorItem.containsDrag }
    function moveTo(point) {
        puck.x = point.x
        puck.y = point.y
    }
    function lift(point) {
        root.moveTo(point)
        puck.Drag.active = true
    }
    function drop() {
        puck.Drag.drop()
        puck.Drag.active = false
    }
    function land() {
        var p = root.gridPane
        p.listInFlight = true
        p.total = 0
        p.held = 0
        p.rows = []
        p.rows = root.rows
        p.total = root.rows.length
        p.listInFlight = false
    }
    // Who holds the drag at a point: the grid's tile (its row index) or the floor, never both.
    function holder(label, tileIndex, floor) {
        root.check(label + ", the tile", root.target(), tileIndex)
        root.check(label + ", the floor", root.floorHolds(), floor)
    }

    Timer { id: step; interval: 120; repeat: false; onTriggered: root.advance() }
    Timer { id: watchdog; interval: 40000; repeat: false; onTriggered: { root.failures.push("timed out"); root.report() } }

    function advance() {
        if (root.steps.length === 0) { root.report(); return }
        root.steps.shift()()
        step.restart()
    }
    function plan() {
        var s = root.steps, ground = { x: 850, y: 650 }
        // Any other item of the content lying over the cursor tile must not hide it.
        s.push(function () {
            var cursorTile = root.tileOf("dirB")
            var decoy = decoyMaker.createObject(root.view().contentItem, { x: cursorTile.x, y: cursorTile.y, width: cursorTile.width, height: cursorTile.height })
            root.check("the decoy lies over the cursor tile", root.view().contentItem.childAt(cursorTile.x + 3, cursorTile.y + 3) === decoy, true)
            root.lift(ground)
        })
        s.push(function () { root.holder("bare ground", -1, true); root.moveTo(root.pointOf("dirA")) })
        s.push(function () { root.holder("a folder tile", 0, false); root.moveTo(root.pointOf("f1.txt")) })
        s.push(function () { root.holder("a file tile", -1, true); root.moveTo(root.pointOf("dirB")) })
        s.push(function () { root.holder("the cursor folder tile", 2, false); root.moveTo(root.pointOf("dirC")) })
        s.push(function () { root.holder("the next folder tile", 4, false); root.moveTo(root.marginOf("dirA")) })
        s.push(function () { root.holder("a folder cell's margin", -1, true); root.moveTo(ground) })
        s.push(function () { root.holder("bare ground again", -1, true); root.moveTo(root.pointOf("dirA")) })
        s.push(function () { root.drop() })
        s.push(function () {
            root.check("a drop on a folder tile goes to the grid", root.said.join(","), "grid")
            root.check("a dropped tile is let go", root.target(), -1)
            root.said = []
            root.lift(ground)
        })
        s.push(function () { root.drop() })
        s.push(function () {
            root.check("a drop on bare ground goes to the floor", root.said.join(","), "floor")
            root.said = []
            root.lift(root.pointOf("f1.txt"))
        })
        s.push(function () { root.drop() })
        s.push(function () {
            root.check("a drop on a file tile goes to the floor", root.said.join(","), "floor")
            root.said = []
            root.lift(root.pointOf("dirB"))
        })
        s.push(function () { root.drop() })
        s.push(function () {
            root.check("a drop on the cursor folder tile goes to the grid", root.said.join(","), "grid")
            var v = root.view(), pt = root.pointOf("f1.txt")
            v.hoverAt(pt.x, pt.y)
            root.check("a hover point lights the tile under it", v.hoveredIndex, 1)
            root.check("the tile reads the shared index", root.tileOf("f1.txt").hovered, true)
            root.check("no other tile reads it", root.hoveredTiles(), ["f1.txt"])
            v.hoverAt(ground.x, ground.y)
            root.check("a hover point on bare ground lights none", root.hoveredTiles(), [])
            var big = []
            for (var i = 0; i < 120; i++) big.push(root.row("g" + i, false))
            root.rows = big
            root.land()
        })
        s.push(function () {
            var v = root.view()
            v.contentY = v.cellHeight * 3
        })
        s.push(function () {
            var v = root.view(), tile = null
            for (var i = 0; i < v.count && !tile; i++) {
                var t = v.itemAtIndex(i)
                if (t && t.y - v.contentY > v.cellHeight * 2 && t.y - v.contentY + t.height < v.height - v.cellHeight) tile = t
            }
            root.check("a scrolled view holds a tile in view", tile !== null, true)
            if (!tile) return
            var at = tile.thumbItem.mapToItem(v, tile.thumbItem.width / 2, tile.thumbItem.height / 2)
            v.hoverAt(at.x, at.y)
            root.check("the content offset keeps the hover on the tile under the point", v.hoveredIndex, tile.index)
            root.check("a scrolled hover lights that tile alone", root.hoveredTiles(), [tile.index])
        })
    }
    function report() {
        step.stop()
        watchdog.stop()
        if (root.failures.length === 0)
            console.log("GRIDDROPLIVE PASS checks=" + root.checks)
        for (var f = 0; f < root.failures.length; f++)
            console.log("GRIDDROPLIVE FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
    Timer {
        id: ready
        interval: 50
        repeat: true
        onTriggered: {
            var v = root.view()
            if (!v) return
            if (v.count < root.rows.length || !v.itemAtIndex(root.rows.length - 1)) {
                if (++root.polls > 200) { root.failures.push("the tiles never built"); root.report() }
                return
            }
            ready.stop()
            root.plan()
            step.restart()
        }
    }
    Component.onCompleted: {
        watchdog.start()
        root.gridPane = paneStub.createObject(root, { tag: "grid", backend: backendStub.createObject(root) })
        root.floorPane = paneStub.createObject(root, { tag: "floor", backend: backendStub.createObject(root) })
        root.floorItem = floorMaker.createObject(stage)
        root.land()
        viewLoader.active = true
        ready.start()
    }
}
