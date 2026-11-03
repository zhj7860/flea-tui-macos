//@ pragma ShellId flea-cursormark-test

import QtQuick
import Quickshell
import qs.Commons
import "flea" as Flea

// cursormark: in a real list, grid and columns view, the cursor row and only it draws the cursor in the turn that moves it.
ShellRoot {
    id: root

    property string which: Quickshell.env("CURSORMARK_VIEW") || "list"
    property bool finished: false
    property var failures: []
    property var selectedSet: ({})

    function rowsFor(prefix, count) {
        var out = []
        for (var i = 0; i < count; i++)
            out.push({ n: prefix + root.pad(i), d: false, i: "text-x-generic", p: 420, s: 0, m: 1758835200, t: false, k: 0, v: 0 })
        return out
    }
    function pad(i) {
        var n = String(i)
        while (n.length < 4) n = "0" + n
        return n
    }
    property var parentRows: [{ n: "big", d: true, i: "folder", p: 493, s: 0, m: 1758835200, t: false, k: 0, v: 0 }]

    Component {
        id: backendStub
        QtObject {
            signal peeked(string path, bool hidden, int total, var rows, bool readFailed, int mode, bool hiddenLast, int first)
            property int dirDev: 0
            property string sortBy: "name"
            property bool sortDesc: false
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
            property string path: "/probe"
            property var rows: []
            property var shown: null
            readonly property int shownTotal: shown === null ? total : shown.length
            property int total: 0
            property int held: 0
            property int cursorIndex: 0
            property int renamingIndex: -1
            property int renameRequest: 0
            property string renameError: ""
            property bool renamePending: false
            property int selectionVersion: 0
            property bool paneFocused: true
            property bool dualMode: false
            property bool showHidden: false
            property var trash: ({ opened: false })
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
            property string pendingSelect: ""
            property bool pendingMenu: false
            property string focusView: root.which
            property int visibleRows: 43
            property int cacheRows: 2
            property int firstSettleMs: 70
            property int settleMs: 120
            property int coalesceMs: 16
            property int refetchMargin: 25
            property int buffer: 150
            property int windowSize: 35
            property var backend: null
            property var sidebar: null
            property var listArea: null
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) {
                var o = index - held
                return (o >= 0 && o < rows.length) ? rows[o] : null
            }
            function isSelected(index) { return selectionVersion >= 0 && root.selectedSet[index] === true }
            function selectedIndices() { return Object.keys(root.selectedSet).map(Number) }
            function selectionCount() { return Object.keys(root.selectedSet).length }
            function thumbFor(index) { var v = thumbState.file[index]; return typeof v === "string" ? v : "" }
            function setCursor(index, mode) {}
            function slowClickWasSole(index) { return false }
            function pressSlowClick() {}
            function cancelSlowClick() {}
            function armSlowClick() {}
            function commitRename(newName) {}
            function open(path) {}
            function openFile(path) {}
            function focusRequested() {}
        }
    }
    Component {
        id: menuStub
        QtObject {
            function close() {}
            function openBackground(point) {}
        }
    }

    property var stubPane: paneStub.createObject(root, { backend: backendStub.createObject(root) })

    FloatingWindow {
        implicitWidth: 2300
        implicitHeight: 1300
        color: "black"

        Loader {
            id: viewLoader
            width: 2300
            height: 1290
            sourceComponent: root.which === "grid" ? gridView : root.which === "columns" ? columnsView : listView
        }
    }

    Component { id: listView; Flea.List { pane: root.stubPane; menu: menuStub.createObject(root) } }
    Component { id: gridView; Flea.GridArea { pane: root.stubPane; menu: menuStub.createObject(root) } }
    Component { id: columnsView; Flea.ColumnsArea { pane: root.stubPane; menu: menuStub.createObject(root) } }

    // The ListView or GridView that draws the pane's own listing: the view itself, or the columns view's active column.
    function listingView() {
        if (root.which !== "columns") return viewLoader.item
        var found = null
        function walk(o) {
            if (found || !o) return
            if (o.viewport !== undefined && o.pane === root.stubPane) { found = o.viewport; return }
            for (var i = 0; o.children && i < o.children.length; i++) walk(o.children[i])
        }
        walk(viewLoader.item)
        return found
    }
    // Every delegate the view holds, pooled ones and an off-screen current item included.
    function delegates(view) {
        var out = []
        var kids = view.contentItem.children
        for (var i = 0; i < kids.length; i++)
            if (kids[i].listingIndex !== undefined) out.push(kids[i])
        return out
    }
    function viewOf(row) { var s = root.stubPane.shown; return s === null ? row : s.indexOf(row) }
    // Pane.showRow's scroll, which follows the cursor in the same turn; the grid reveals its own current tile.
    function reveal() {
        var view = root.listingView(), at = root.viewOf(root.stubPane.cursorIndex)
        if (at >= 0) view.positionViewAtIndex(at, root.which === "grid" ? GridView.Contain : ListView.Contain)
    }
    function land(path, total, rows) {
        var p = root.stubPane
        p.listInFlight = true
        p.total = 0
        p.held = 0
        p.rows = []
        p.cursorIndex = 0
        p.renamingIndex = -1
        p.shown = null
        p.listingState = "loading"
        root.selectedSet = {}
        p.selectionVersion += 1
        p.rows = rows
        p.total = total
        p.path = path
        p.listingState = total === 0 ? "empty" : "ready"
        p.listInFlight = false
    }

    // Checked in the turn that changed the state, so frame 1 draws what this sees; shown says the cursor row must have a delegate.
    function check(label, shown) {
        var p = root.stubPane, all = root.delegates(root.listingView()), live = 0, lit = 0, want = 0
        for (var i = 0; i < all.length; i++) {
            var d = all[i]
            if (d.live === false) {
                if (d.cursor) root.failures.push(label + ": a parked delegate draws the cursor")
                continue
            }
            live += 1
            var on = d.listingIndex >= 0 && d.listingIndex === p.cursorIndex
            if (d.cursor !== on) root.failures.push(label + ": row " + d.listingIndex + " cursor " + d.cursor + ", cursor row " + p.cursorIndex)
            if (d.renaming !== (d.listingIndex >= 0 && d.listingIndex === p.renamingIndex)) root.failures.push(label + ": row " + d.listingIndex + " renaming " + d.renaming)
            lit += d.cursor ? 1 : 0
            want += on ? 1 : 0
        }
        if (want > 1) root.failures.push(label + ": " + want + " live delegates hold the cursor row")
        if (shown && want !== 1) root.failures.push(label + ": the cursor row " + p.cursorIndex + " has no live delegate")
        console.log("CURSORMARK " + root.which + " " + label + " live=" + live + " lit=" + lit)
    }
    function move(label, row, scroll) {
        root.stubPane.cursorIndex = row
        if (scroll) root.reveal()
        root.check(label, scroll && root.viewOf(row) >= 0)
    }

    // An imperative write to a bound property is what Qt reports as an overwritten binding: selected is the live control.
    function bindingProbe() {
        var all = root.delegates(root.listingView())
        for (var i = 0; i < all.length; i++) {
            var d = all[i]
            if (d.live === false || d.listingIndex < 0) continue
            console.log("CURSORMARK PROBE begin")
            d.selected = d.selected
            d.cursor = d.cursor
            console.log("CURSORMARK PROBE end")
            return
        }
        root.failures.push("binding probe: no live delegate")
    }

    // The first child of a Row is its fill Rectangle; a row in a pane without focus keeps the selection in the inactive rung.
    function fillOf(d) { return d.children.length > 0 && d.children[0].color !== undefined ? d.children[0].color : null }
    function fillAt(index) {
        var all = root.delegates(root.listingView())
        for (var i = 0; i < all.length; i++)
            if (all[i].live !== false && all[i].listingIndex === index) return root.fillOf(all[i])
        return null
    }
    function fillIs(label, index, want) {
        var got = root.fillAt(index)
        if (got === null || !Qt.colorEqual(got, want)) root.failures.push(label + ": row " + index + " fill " + got + ", wanted " + want)
    }
    function hoverRow(index) {
        var all = root.delegates(root.listingView())
        for (var i = 0; i < all.length; i++)
            if (all[i].live !== false && all[i].listingIndex === index) { all[i].hovered = true; return }
        root.failures.push("no live delegate for row " + index)
    }

    property int step: 0
    // The delegates drawn before the wheel scroll, so step 7 can pick one that came back out of the pool.
    property var preScroll: []
    property var markProbe: null
    property var deadCell: null
    property var liveCell: null
    Component { id: markProbeComponent; Flea.CursorMark {} }
    Component { id: fakeCell; Item { property int listingIndex: -1; property int markRow: -1; property bool cursor: false } }

    function finish() {
        if (root.finished) return
        root.finished = true
        if (root.failures.length > 0) console.log("CURSORMARK FAIL " + root.which + " " + root.failures.slice(0, 8).join("; "))
        else console.log("CURSORMARK DONE " + root.which)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    // One state a tick, so each landing's polish and cache buffer settle before the next; every state is checked again settled.
    Timer {
        interval: 120
        running: true
        repeat: true
        onTriggered: {
            var p = root.stubPane, k
            if (root.step > 1) root.check("settled " + (root.step - 1), false)
            if (root.step === 0) {
                root.land("/probe", 1, root.parentRows)
            } else if (root.step === 1) {
                root.land("/probe/a", 1000, root.rowsFor("a_", 343))
                root.check("enter", true)
            } else if (root.step === 2) {
                for (k = 1; k <= 8; k++) root.move("step " + k, k, true)
                for (k = 7; k >= 3; k--) root.move("step up " + k, k, true)
            } else if (root.step === 3) {
                root.move("page down", 48, true)
                root.move("page down again", 96, true)
                root.move("page up", 52, true)
            } else if (root.step === 4) {
                root.move("end", 999, true)
            } else if (root.step === 5) {
                root.move("home", 0, true)
            } else if (root.step === 6) {
                // A wheel scroll leaves the cursor behind, so the rows drawn next are reused delegates.
                var view = root.listingView()
                root.preScroll = root.delegates(view)
                view.contentY = view.contentY + 4000
                root.check("scrolled away", false)
            } else if (root.step === 7) {
                var reused = root.delegates(root.listingView()).filter(function (d) { return d.live !== false && d.listingIndex > 40 && root.preScroll.indexOf(d) >= 0 })
                if (reused.length === 0) root.failures.push("no delegate drawn before the scroll came back past row 40")
                else root.move("onto a reused row", reused[Math.floor(reused.length / 2)].listingIndex, false)
                root.move("home unscrolled", 0, false)
                root.move("home revealed", 0, true)
            } else if (root.step === 8) {
                var evens = []
                for (k = 0; k < 100; k++) evens.push(k * 2)
                p.shown = evens
                root.check("filter typed", true)
                root.move("filter step", 4, true)
            } else if (root.step === 9) {
                var odds = []
                for (k = 0; k < 100; k++) odds.push(k * 2 + 1)
                p.shown = odds
                root.check("filter hides the cursor", false)
                root.move("filter onto a match", 7, true)
                p.shown = null
                root.check("filter cleared", true)
            } else if (root.step === 10) {
                p.renamingIndex = p.cursorIndex
                root.check("rename open", true)
            } else if (root.step === 11) {
                p.renamingIndex = -1
                root.check("rename end", true)
                root.move("after rename", 9, true)
            } else if (root.step === 12) {
                root.move("before resize", 2, true)
                p.total = 200
                root.check("resize shrink", true)
                p.total = 1000
                root.check("resize grow", true)
            } else if (root.step === 13) {
                root.land("/probe", 1, root.parentRows)
                root.check("back", true)
            } else if (root.step === 14) {
                root.land("/probe/b", 1000, root.rowsFor("b_", 343))
                root.move("enter onto a remembered row", 11, true)
            } else if (root.step === 15) {
                root.bindingProbe()
            } else if (root.step === 16) {
                // A delegate destroyed without parking leaves its entry behind; the mark must drop it, not light it.
                root.markProbe = markProbeComponent.createObject(root)
                root.deadCell = fakeCell.createObject(root, { listingIndex: 5 })
                root.markProbe.place(root.deadCell)
                root.deadCell.destroy()
            } else if (root.step === 17) {
                var m = root.markProbe
                m.row = 5
                if (m.lit !== null) root.failures.push("stale entry: a destroyed delegate was lit")
                if (m.cells.has(5)) root.failures.push("stale entry: row 5 is still filed")
                root.liveCell = fakeCell.createObject(root, { listingIndex: 6 })
                m.place(root.liveCell)
                m.row = 6
                if (m.lit !== root.liveCell || !root.liveCell.cursor) root.failures.push("stale entry: the live row 6 did not light after the drop")
                console.log("CURSORMARK " + root.which + " stale entry dropped lit=" + (m.lit === root.liveCell))
            } else if (root.step === 18 && root.which === "list") {
                // Q11: marked rows in a pane without focus keep the inactive rung, and hover never replaces it.
                root.land("/probe/c", 1000, root.rowsFor("c_", 343))
                p.paneFocused = false
                // Row 0 sits under the headless pointer, so the cursor stands on a row clear of it.
                p.cursorIndex = 5
                root.selectedSet = { 1: true, 2: true }
                p.selectionVersion += 1
                root.hoverRow(4)
            } else if (root.step === 19 && root.which === "list") {
                root.fillIs("unfocused marked row", 1, Style.selectedFill)
                root.fillIs("unfocused marked row", 2, Style.selectedFill)
                root.fillIs("unfocused unmarked row", 3, "transparent")
                root.fillIs("unfocused unmarked cursor", 5, "transparent")
                root.fillIs("unfocused hovered unmarked row", 4, Style.hoverFill)
                root.hoverRow(1)
                root.fillIs("unfocused hovered marked row", 1, Style.selectedFill)
                p.paneFocused = true
                root.fillIs("focused marked row", 2, Style.selectionFill)
                root.fillIs("focused cursor", 5, Style.selectedAccentFill)
                root.fillIs("focused hovered unmarked row", 4, Style.hoverFill)
                console.log("CURSORMARK list inactive selection checked")
            } else {
                root.finish()
                return
            }
            root.step += 1
        }
    }

    Timer {
        interval: 30000
        running: true
        onTriggered: { root.failures.push("timeout at step " + root.step); root.finish() }
    }
}
