//@ pragma ShellId flea-listnarrow-test

import QtQuick
import Quickshell
import "flea" as Flea

// listnarrow: a real ui/List.qml keeps its drawn delegates across a narrowing and a widening; tests/listnarrow.sh drives it.
ShellRoot {
    id: root

    property var failures: []
    property var allRows: []
    property var before: []
    property int pooled: 0
    property int resized: 0

    Component {
        id: backendStub
        QtObject {
            function peek(path, size, hidden) {}
            function thumb(rows, cacheOnly) {}
            function thumbcancel(rows) {}
            function dirsize(rows) {}
            function dirsizecancel() {}
            function window(start, count) {}
        }
    }

    Component {
        id: paneStub
        QtObject {
            property string path: "/probe"
            property var rows: []
            property var shown: null
            property int shownTotal: 0
            property int total: 0
            property int held: 0
            property int cursorIndex: 0
            property int renamingIndex: -1
            property string renameError: ""
            property bool renamePending: false
            property bool paneFocused: true
            property bool dualMode: false
            property var clipboard: ({ paths: [], moving: false })
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property var kindNames: []
            property string searchMode: ""
            property string searchQuery: ""
            property string recentMode: ""
            property string filterQuery: ""
            property var selectionBand: null
            property int previewIndex: -1
            property bool storageKnown: true
            property string storageClass: ""
            property bool listInFlight: false
            property string listingState: "ready"
            property int visibleRows: 8
            property int cacheRows: 0
            property int firstSettleMs: 70
            property int settleMs: 120
            property int coalesceMs: 16
            property int refetchMargin: 25
            property int buffer: 150
            property int windowSize: 35
            property var backend: null
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) { var o = index - held; return (o >= 0 && o < rows.length) ? rows[o] : null }
            function isSelected(index) { return false }
            function commitRename(newName) {}
        }
    }

    Component {
        id: menuStub
        QtObject {
            function close() {}
            function openBackground(point) {}
        }
    }

    property var stubBackend: backendStub.createObject(root)
    property var stubPane: paneStub.createObject(root, { backend: root.stubBackend })

    Flea.List {
        id: list
        width: 700
        height: 300
        pane: root.stubPane
        menu: menuStub.createObject(root)
    }

    // A kept count change emits resized; a reset never does and pools the drawn delegates instead.
    Connections {
        target: list.model
        function onResized() { root.resized++ }
    }

    Component.onCompleted: {
        var rows = []
        for (var i = 0; i < 40; i++)
            rows.push({ n: "row-" + (i < 10 ? "0" : "") + i + ".txt", d: false, i: "text-x-generic", p: 420, s: 13, m: 1758835200, t: false, k: 0, v: 0 })
        root.allRows = rows
        root.stubPane.rows = rows
        root.stubPane.total = rows.length
        root.stubPane.shownTotal = rows.length
        step.next = root.measureFull
        step.start()
    }

    Timer {
        id: step
        property var next: null
        interval: 400
        repeat: false
        onTriggered: { list.forceLayout(); step.next() }
    }

    function fail(text) { root.failures.push(text) }

    // The delegates drawn at view positions 0 up to the first unbuilt one.
    function drawn() {
        var out = []
        for (var i = 0; i < list.count; i++) {
            var d = list.itemAtIndex(i)
            if (d === null) break
            out.push(d)
        }
        return out
    }

    // Each drawn delegate shows the row its view position maps to.
    function checkRows(label, shown) {
        var ds = root.drawn()
        if (ds.length === 0) root.fail(label + " draws no delegate")
        for (var i = 0; i < ds.length; i++) {
            var want = root.allRows[shown === null ? i : shown[i]].n
            if (!ds[i].row || ds[i].row.n !== want)
                root.fail(label + " view " + i + " draws " + (ds[i].row ? ds[i].row.n : "nothing") + ", want " + want)
        }
        return ds
    }

    // Delegates that were not drawn before this step: a narrowing or widening that keeps the viewport full builds none.
    function built(ds) {
        var n = 0
        for (var i = 0; i < ds.length; i++)
            if (root.before.indexOf(ds[i]) < 0) n += 1
        return n
    }

    function measureFull() {
        root.before = root.checkRows("full", null)
        list.contentY = list.originY + 60
        step.next = root.narrow
        step.start()
    }

    function narrow() {
        var kept = root.resized
        var shown = []
        for (var i = 0; i < 40; i += 2) shown.push(i)
        root.stubPane.filterQuery = "row"
        root.stubPane.shown = shown
        root.stubPane.shownTotal = shown.length
        step.next = function () {
            if (root.resized === kept) root.fail("narrowing never resized the kept model, want the kept-view path")
            if (list.count !== 20) root.fail("narrowed lists " + list.count + " rows, want 20")
            // A count change still starts the view at its top, as the integer model's reset did.
            if (list.contentY !== list.originY - list.topMargin) root.fail("narrowed view sits at " + list.contentY + ", want its start")
            var ds = root.checkRows("narrowed", shown)
            var n = root.built(ds)
            if (n !== 0) root.fail("narrowing built " + n + " of " + ds.length + " drawn delegates, want 0")
            root.before = ds
            root.widen()
        }
        step.start()
    }

    function widen() {
        var kept = root.resized
        root.stubPane.filterQuery = ""
        root.stubPane.shown = null
        root.stubPane.shownTotal = 40
        step.next = function () {
            if (root.resized === kept) root.fail("widening never resized the kept model, want the kept-view path")
            var ds = root.checkRows("widened", null)
            var n = root.built(ds)
            if (n !== 0) root.fail("widening built " + n + " of " + ds.length + " drawn delegates, want 0")
            root.before = ds
            root.pool()
        }
        step.start()
    }

    // Three rows left puts most drawn delegates in the pool, where each reads listing row -1, the same number as "no rename".
    function pool() {
        root.stubPane.filterQuery = "row-0"
        root.stubPane.shown = [0, 2, 4]
        root.stubPane.shownTotal = 3
        step.next = function () {
            root.checkRows("pooled", [0, 2, 4])
            var pooled = 0
            var kids = list.contentItem.children
            for (var k = 0; k < kids.length; k++) {
                if (kids[k].listingIndex === undefined || kids[k].listingIndex >= 0) continue
                pooled++
                if (kids[k].renaming === true) root.fail("a pooled delegate past the narrowed count lights a rename editor")
            }
            if (pooled === 0) root.fail("narrowing to three rows left no pooled delegate to inspect")
            root.pooled = pooled
            root.renameControl()
        }
        step.start()
    }

    // The control for the pooled check: a rename on listing row 4, drawn at view 2, lights exactly that row.
    function renameControl() {
        root.stubPane.renamingIndex = 4
        step.next = function () {
            var lit = []
            var kids = list.contentItem.children
            for (var k = 0; k < kids.length; k++)
                if (kids[k].renaming === true) lit.push(kids[k])
            if (lit.length !== 1 || lit[0].listingIndex !== 4 || lit[0].index !== 2)
                root.fail("a rename on listing row 4 lights " + lit.length + " delegates, want view 2")
            root.stubPane.renamingIndex = -1
            root.hide()
        }
        step.start()
    }

    function hide() {
        root.stubPane.shown = []
        root.stubPane.shownTotal = 0
        list.visible = false
        step.next = function () {
            var left = 0
            for (var i = 0; i < list.contentItem.children.length; i++)
                if (list.contentItem.children[i].row !== undefined) left += 1
            if (left !== 0) root.fail("an emptied then hidden list holds " + left + " delegates, want none")
            if (root.failures.length === 0)
                console.log("LISTNARROW PASS drawn=" + root.before.length + " pooled=" + root.pooled)
            root.report()
        }
        step.start()
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("LISTNARROW FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
