//@ pragma ShellId flea-columnnarrow-test

import QtQuick
import Quickshell
import "flea" as Flea

// columnnarrow: a real ui/ColumnPane keeps its drawn rows across a narrowing and a widening; tests/columnnarrow.sh drives it.
ShellRoot {
    id: root

    property var failures: []
    property var allRows: []
    property var before: []

    Component {
        id: backendStub
        QtObject {
            property int dirDev: 0
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
            property var clipboard: ({ paths: [], moving: false })
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property var kindNames: []
            property bool storageKnown: false
            property string storageClass: ""
            property int previewIndex: -1
            property var trash: ({ opened: false })
            property string searchMode: ""
            property var selectionBand: null
            property bool listInFlight: false
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
            function thumbFor(index) { return "" }
        }
    }

    property var stubBackend: backendStub.createObject(root)
    property var stubPane: paneStub.createObject(root, { backend: root.stubBackend })

    Flea.ColumnPane {
        id: column
        width: 400
        height: 600
        pane: root.stubPane
        // A pooled row reads listingIndex -1, so no selection is the state that lights one when a guard is missing.
        selectedIndex: -1
    }

    Component.onCompleted: {
        var rows = []
        for (var i = 0; i < 40; i++)
            rows.push({ n: "row-" + (i < 10 ? "0" : "") + i + ".txt", d: false, i: "text-x-generic", p: 420, s: 13 })
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
        onTriggered: { column.viewport.forceLayout(); step.next() }
    }

    function fail(text) { root.failures.push(text) }

    function drawn() {
        var out = []
        for (var i = 0; i < column.viewport.count; i++) {
            var d = column.itemAtIndex(i)
            if (d === null) break
            out.push(d)
        }
        return out
    }

    function checkRows(label, shown) {
        var ds = root.drawn()
        if (ds.length === 0) root.fail(label + " draws no row")
        for (var i = 0; i < ds.length; i++) {
            var want = root.allRows[shown === null ? i : shown[i]].n
            if (!ds[i].row || ds[i].row.n !== want)
                root.fail(label + " view " + i + " draws " + (ds[i].row ? ds[i].row.n : "nothing") + ", want " + want)
        }
        return ds
    }

    function measureFull() {
        root.before = root.checkRows("full", null)
        if (root.before.length <= 20) root.fail("full column draws " + root.before.length + " rows, want more than 20 so the narrowing pools some")
        // Every other row stays, so rows past the new count go to the pool alive.
        var shown = []
        for (var i = 0; i < 40; i += 2) shown.push(i)
        root.stubPane.shown = shown
        root.stubPane.shownTotal = shown.length
        step.next = function () {
            if (column.viewport.count !== 20) root.fail("narrowed column lists " + column.viewport.count + " rows, want 20")
            var ds = root.checkRows("narrowed", shown)
            var built = ds.filter(function (d) { return root.before.indexOf(d) < 0 }).length
            if (built !== 0) root.fail("narrowing built " + built + " of " + ds.length + " drawn rows, want 0")
            var kids = column.viewport.contentItem.children
            var pooled = 0
            for (var k = 0; k < kids.length; k++) {
                var c = kids[k]
                if (c.listingIndex === undefined || c.listingIndex >= 0) continue
                pooled++
                if (c.cursor === true || c.renaming === true || c.dropTarget === true)
                    root.fail("a pooled row past the narrowed count lights its cursor, rename or drop mark")
            }
            if (pooled === 0) root.fail("narrowing left no pooled row to inspect")
            root.measureWide(ds.length, pooled)
        }
        step.start()
    }

    function measureWide(narrowed, pooled) {
        root.stubPane.shown = null
        root.stubPane.shownTotal = root.allRows.length
        step.next = function () {
            if (column.viewport.count !== 40) root.fail("widened column lists " + column.viewport.count + " rows, want 40")
            var ds = root.checkRows("widened", null)
            var built = ds.filter(function (d) { return root.before.indexOf(d) < 0 }).length
            if (built !== 0) root.fail("widening built " + built + " of " + ds.length + " drawn rows, want 0")
            if (root.failures.length === 0)
                console.log("COLUMNNARROW PASS drawn=" + narrowed + " pooled=" + pooled + " widened=" + ds.length)
            root.report()
        }
        step.start()
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("COLUMNNARROW FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
