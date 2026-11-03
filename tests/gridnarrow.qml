//@ pragma ShellId flea-gridnarrow-test

import QtQuick
import Quickshell
import "flea" as Flea

// gridnarrow: a real ui/GridArea.qml keeps its drawn tiles and its cursor tile across a narrowing; tests/gridnarrow.sh drives it.
ShellRoot {
    id: root

    property var failures: []
    property int cursorRow: 45
    property int rowCount: 60
    property var before: []
    property int pooled: 0

    // Built by call: initializers run before onCompleted and would hand it the empty array.
    function buildRows() {
        var rows = []
        for (var i = 0; i < root.rowCount; i++) {
            var n = "item" + (i < 10 ? "0" + i : i) + ".txt"
            var photo = i % 5 === 0
            rows.push({ n: n, d: i % 3 === 0, i: photo ? "image-x-generic" : "text-x-generic",
                p: 420, s: 13, m: 1758835200, t: photo, k: 0, v: 0 })
        }
        return rows
    }

    Component {
        id: backendStub
        QtObject {
            property int windowCalls: 0
            property int thumbCalls: 0
            property int dirsizescancelCalls: 0
            function peek(path, size, hidden) {}
            function thumb(rows, cacheOnly) { thumbCalls += 1 }
            function thumbcancel(rows) {}
            function dirsize(rows) {}
            function dirsizecancel() { dirsizescancelCalls += 1 }
            function window(start, count) { windowCalls += 1 }
        }
    }

    Component {
        id: paneStub
        QtObject {
            property string path: "/probe"
            property var rows: []
            property var shown: null
            property int shownTotal: 60
            property int total: 60
            property int held: 0
            property int cursorIndex: 45
            property int renamingIndex: -1
            property string renameError: ""
            property bool renamePending: false
            property bool paneFocused: true
            property bool dualMode: false
            property var clipboard: ({ paths: ["/probe/item45.txt"], moving: false })
            property var selected: ({ 44: true })
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property string searchMode: ""
            property string searchQuery: ""
            property string filterQuery: ""
            property var selectionBand: null
            property var sidebar: null
            property int previewIndex: -1
            property bool storageKnown: true
            property string storageClass: ""
            property bool listInFlight: false
            property string listingState: "ready"
            property var statusBar: null
            property int firstSettleMs: 70
            property int settleMs: 120
            property int coalesceMs: 16
            property int refetchMargin: 25
            property int buffer: 150
            property int windowSize: 35
            property var backend: null
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) { var o = index - held; return (o >= 0 && o < rows.length) ? rows[o] : null }
            function isSelected(index) { return selected[index] === true }
            function commitRename(newName) {}
        }
    }

    Component {
        id: menuStub
        QtObject {
            property int closeCalls: 0
            function close() { closeCalls += 1 }
            function openBackground(point) {}
        }
    }

    Component {
        id: statusStub
        QtObject { property var activities: [] }
    }

    property var stubBackend: backendStub.createObject(root)
    property var stubMenu: menuStub.createObject(root)
    property var stubStatus: statusStub.createObject(root)
    property var stubPane: paneStub.createObject(root, { backend: root.stubBackend, rows: root.buildRows(), statusBar: root.stubStatus })

    FloatingWindow {
        implicitWidth: 900
        implicitHeight: 500
        color: Flea.Theme.color.background

        Flea.GridArea {
            id: grid
            width: 700
            height: 300
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            pane: root.stubPane
            menu: root.stubMenu
        }
    }

    Timer {
        id: step
        property var next: null
        interval: 600
        repeat: false
        onTriggered: step.next()
    }
    Component.onCompleted: { step.next = root.measureShown; step.start() }

    function fail(text) { root.failures.push(text) }

    // Every tile the grid holds, drawn or pooled.
    function tiles() {
        var out = []
        var kids = grid.contentItem.children
        for (var i = 0; i < kids.length; i++)
            if (kids[i].listingIndex !== undefined) out.push(kids[i])
        return out
    }

    function drawn() {
        var out = []
        for (var i = 0; i < grid.count; i++) {
            var d = grid.itemAtIndex(i)
            if (d !== null && d.visible) out.push(d)
        }
        return out
    }

    function checkTiles(label, shown) {
        var ds = root.drawn()
        for (var i = 0; i < ds.length; i++) {
            var want = root.stubPane.rows[shown === null ? ds[i].index : shown[ds[i].index]].n
            if (!ds[i].row || ds[i].row.n !== want)
                root.fail(label + " tile " + ds[i].index + " draws " + (ds[i].row ? ds[i].row.n : "nothing") + ", want " + want)
        }
        var lit = root.tiles().filter(function (t) { return t.renaming === true })
        if (lit.length !== 0) root.fail(label + " lights " + lit.length + " rename editors with no rename asked")
        return ds
    }

    function measureShown() {
        root.before = root.checkTiles("shown", null)
        if (grid.itemAtIndex(root.cursorRow) === null) root.fail("shown builds no cursor tile " + root.cursorRow)
        // Rows up to the cursor stay, so it keeps its view position; every other row after it goes, so later tiles change rows.
        var shown = []
        for (var i = 0; i <= root.cursorRow; i++) shown.push(i)
        for (var j = root.cursorRow + 2; j < root.rowCount && shown.length < 50; j += 2) shown.push(j)
        root.stubPane.filterQuery = "item"
        root.stubPane.shown = shown
        root.stubPane.shownTotal = shown.length
        step.next = function () {
            if (grid.count !== 50) root.fail("narrowed grids " + grid.count + " tiles, want 50")
            if (grid.currentIndex !== root.cursorRow) root.fail("narrowed grid stands on " + grid.currentIndex + ", want the cursor tile " + root.cursorRow)
            if (grid.itemAtIndex(root.cursorRow) === null) root.fail("narrowed grid does not draw the cursor tile " + root.cursorRow)
            var ds = root.checkTiles("narrowed", shown)
            var built = ds.filter(function (d) { return root.before.indexOf(d) < 0 }).length
            if (built !== 0) root.fail("narrowing built " + built + " of " + ds.length + " drawn tiles, want 0")
            root.pooled = root.tiles().filter(function (t) { return t.listingIndex < 0 }).length
            if (root.pooled === 0) root.fail("narrowing left no pooled tile to inspect")
            root.renameControl(shown)
        }
        step.start()
    }

    // The control for the pooled check: a rename on a remapped tile (view 46, listing 47) lights exactly that tile.
    function renameControl(shown) {
        root.stubPane.renamingIndex = shown[root.cursorRow + 1]
        step.next = function () {
            var lit = root.tiles().filter(function (t) { return t.renaming === true })
            if (lit.length !== 1 || lit[0].listingIndex !== shown[root.cursorRow + 1] || lit[0].index !== root.cursorRow + 1)
                root.fail("a rename on listing row " + shown[root.cursorRow + 1] + " lights " + lit.length + " tiles, want view " + (root.cursorRow + 1))
            root.stubPane.renamingIndex = -1
            root.empty()
        }
        step.start()
    }

    function empty() {
        root.stubPane.shown = []
        root.stubPane.shownTotal = 0
        step.next = function () {
            grid.visible = false
            step.next = function () {
                var left = root.tiles().length
                if (left !== 0) root.fail("an emptied then hidden grid holds " + left + " tiles, want none")
                if (root.failures.length === 0)
                    console.log("GRIDNARROW PASS drawn=" + root.before.length + " pooled=" + root.pooled + " cursor=" + root.cursorRow)
                root.report()
            }
            step.start()
        }
        step.start()
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("GRIDNARROW FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
