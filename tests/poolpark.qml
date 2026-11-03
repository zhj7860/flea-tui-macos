//@ pragma ShellId flea-poolpark-test

import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "flea/js/Nav.js" as Nav

// poolpark: a warm Enter in a real list, grid or columns view builds no delegate, and every reused row shows only its own state.
ShellRoot {
    id: root

    property string which: Quickshell.env("POOLPARK_VIEW") || "list"
    property string thumbDir: Quickshell.env("POOLPARK_THUMBS") || "/poolthumb"
    property bool finished: false
    property var failures: []
    // Plain JS state: a counted property would be read by the very bindings that bump it, a binding loop.
    property var counts: ({ rowFor: 0, readPast: 0, landTotal: 0, empty: false, watchDrop: false, renameAtDrop: [] })
    property var selectedSet: ({})
    // The listing index under the synthesized pointer, -1 while it rests off the view.
    property int hoverIndex: -1

    // Every third row has a thumbnail, on different rows in a and b, so a kept thumb lands on a row that has none.
    function thumbed(prefix, i) { return prefix !== null && i % 3 === (prefix === "a_" ? 0 : 1) }
    function thumbPath(prefix, i) { return root.thumbed(prefix, i) ? root.thumbDir + "/" + prefix + root.pad(i) + ".png" : "" }
    function rowsFor(prefix, count) {
        var out = []
        for (var i = 0; i < count; i++)
            out.push({ n: prefix + root.pad(i), d: false, i: "text-x-generic", p: 420, s: 0, m: 1758835200, t: root.thumbed(prefix, i), k: 0, v: 0 })
        return out
    }
    function thumbsFor(prefix, count) {
        var file = {}
        for (var i = 0; i < count; i++)
            if (root.thumbed(prefix, i)) file[i] = root.thumbPath(prefix, i)
        return { file: file, order: [] }
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
            onTotalChanged: if (root.counts.watchDrop) root.counts.renameAtDrop.push(renamingIndex)
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
            property var listArea: ({ primeSettle: function () {} })
            property var pendingSort: null
            property double trashArmedAt: 0
            property string stateMessage: ""
            property int lockedMode: 0
            property bool searchLeaving: false
            property bool filterTyping: false
            function clearSelection() {}
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) {
                root.counts.rowFor += 1
                // Only a delegate's read counts: the columns view's own cursor readers are not parked rows.
                if (index >= root.counts.landTotal && root.delegateRead(new Error().stack.split("\n")[1], index === renamingIndex))
                    root.counts.readPast += 1
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
    // Frame [1] of V4's stack is the calling binding; only Columns' one rename editor reading the renaming row is not a delegate.
    function delegateRead(frame, renamingRow) {
        return /(List|GridArea|ColumnPane)\.qml/.test(frame) && !(renamingRow && /(renamingFolder|expression for name)@\S*ColumnPane\.qml:/.test(frame))
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
        // Where the pointer rests off the view, inside the window, so it leaves every row.
        Item { id: pointerRest; y: 1292; width: 10; height: 6 }
        TestEvent { id: driver }
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
    function delegates(view) {
        var out = []
        var kids = view.contentItem.children
        for (var i = 0; i < kids.length; i++)
            if (kids[i].listingIndex !== undefined) out.push(kids[i])
        return out
    }
    function parked() { return root.delegates(root.listingView()).filter(function (d) { return d.live === false }).length }
    // The thumbnail path an Image in the delegate draws, read off its source, so a stale picture shows as well as a stale property.
    function drawnThumb(item) {
        var kids = item.children || []
        for (var i = 0; i < kids.length; i++) {
            var s = kids[i].source !== undefined ? String(kids[i].source) : ""
            if (s.indexOf("/poolthumb/") >= 0) return decodeURI(s.replace(/^file:\/\//, "").replace(/\?.*$/, ""))
            var deeper = root.drawnThumb(kids[i])
            if (deeper !== "") return deeper
        }
        return ""
    }

    // Grid tiles read rows from the held snapshot (GridGeometry.heldRow), never pane.rowFor, so the grid leg counts on the rows array itself: any read while the view holds no count, and a read of a row at or past the landed count after. heldRow tests the length before any index (GridGeometry.js:82), so a tile reads only the length of an empty array.
    function pastHeld(key) {
        return root.counts.empty || (key !== "length" && /^\d+$/.test(key) && Number(key) + root.stubPane.held >= root.counts.landTotal)
    }
    function watched(rows) {
        if (root.which !== "grid") return rows
        return new Proxy(rows, { get: function (target, key) {
            // Sample input, one frame of the stack: "expression for row@qs:@/qs/flea/GridArea.qml:195"
            if (typeof key === "string" && /expression for row@\S*GridArea\.qml/.test(new Error().stack) && root.pastHeld(key))
                root.counts.readPast += 1
            return target[key]
        } })
    }

    // Nav.forget then PaneSwap.land, in their order: count to 0, rows, then the new count; reads past it are counted.
    function land(path, total, rows, prefix) {
        var p = root.stubPane
        root.counts.landTotal = total
        root.counts.readPast = 0
        p.listInFlight = true
        root.counts.empty = true
        var renameOpen = p.renamingIndex >= 0
        root.counts.renameAtDrop = []
        root.counts.watchDrop = true
        Nav.forget(p)
        root.counts.watchDrop = false
        // The editor row must be gone when the count drops, or a row pooled mid-rename stays live and reads past it.
        if (renameOpen && (root.counts.renameAtDrop.length === 0 || root.counts.renameAtDrop.some(function (at) { return at !== -1 })))
            root.failures.push(path + ": renamingIndex was " + root.counts.renameAtDrop.join(",") + " when the count dropped mid-rename, want -1")
        p.rows = root.watched([])
        p.shown = null
        root.selectedSet = {}
        p.selectionVersion += 1
        p.rows = root.watched(rows)
        root.counts.empty = false
        p.total = total
        p.path = path
        p.listingState = total === 0 ? "empty" : "ready"
        p.listInFlight = false
        p.thumbState = root.thumbsFor(prefix, rows.length)
        if (root.counts.readPast > 0)
            root.failures.push(path + ": parked delegates read " + root.counts.readPast + " rows past the new count " + total)
    }

    // Every drawn delegate shows prefix's row (the parent's, for null) and only its own cursor, selection, rename, hover and thumb.
    function check(label, prefix) {
        var p = root.stubPane, view = root.listingView(), drawn = 0, lit = { renaming: 0, hovered: 0, thumb: 0 }
        var all = root.delegates(view)
        for (var i = 0; i < all.length; i++) {
            var d = all[i]
            if (d.live === false) {
                // A parked delegate keeps what it drew, so parking re-runs nothing, but holds no live state.
                if (d.selected || d.cursor || d.renaming || d.hovered)
                    root.failures.push(label + ": a parked delegate is still lit, " + (d.row ? d.row.n : "no row"))
                continue
            }
            if (d.listingIndex < 0) continue
            drawn += 1
            var want = prefix === null ? root.parentRows[d.listingIndex].n : prefix + root.pad(d.listingIndex)
            var thumb = root.thumbPath(prefix, d.listingIndex)
            var bad = []
            if (!d.row || d.row.n !== want) bad.push("row " + (d.row ? d.row.n : "null"))
            if (d.cursor !== (d.listingIndex === p.cursorIndex)) bad.push("cursor " + d.cursor)
            if (d.selected !== (root.selectedSet[d.listingIndex] === true)) bad.push("selected " + d.selected)
            if (d.renaming !== (d.listingIndex === p.renamingIndex)) bad.push("renaming " + d.renaming)
            if (d.hovered !== (d.listingIndex === root.hoverIndex)) bad.push("hovered " + d.hovered)
            if (d.thumb !== thumb) bad.push("thumb " + d.thumb)
            if (root.drawnThumb(d) !== thumb) bad.push("drawn thumb " + root.drawnThumb(d))
            lit.renaming += d.renaming ? 1 : 0
            lit.hovered += d.hovered ? 1 : 0
            lit.thumb += thumb.length > 0 && d.thumb === thumb ? 1 : 0
            if (bad.length > 0) root.failures.push(label + ": delegate for " + want + " shows " + bad.join(", "))
        }
        if (drawn === 0) root.failures.push(label + ": no delegate drawn")
        if (p.renamingIndex >= 0 && lit.renaming !== 1) root.failures.push(label + ": " + lit.renaming + " rows renaming, want 1")
        if (root.hoverIndex >= 0 && lit.hovered !== 1) root.failures.push(label + ": the pointer lit " + lit.hovered + " rows, want 1")
        if (prefix !== null && lit.thumb === 0) root.failures.push(label + ": no thumbnail drawn")
        console.log("POOLPARK " + root.which + " " + label + " drawn=" + drawn + " renaming=" + lit.renaming
                    + " hovered=" + lit.hovered + " thumbs=" + lit.thumb)
    }

    function built(label, before) {
        var after = root.delegates(root.listingView()), n = 0
        for (var i = 0; i < after.length; i++)
            if (before.indexOf(after[i]) < 0) n += 1
        console.log("POOLPARK " + root.which + " " + label + " built=" + n + " alive=" + after.length)
        if (n > 0) root.failures.push(label + " built " + n + " delegates, the pool should have held them")
    }

    function hoverOnto(listingIndex) {
        var all = root.delegates(root.listingView())
        for (var i = 0; i < all.length; i++) {
            if (all[i].live === false || all[i].listingIndex !== listingIndex) continue
            driver.mouseMove(all[i], all[i].width / 2, all[i].height / 2, 0, Qt.NoButton, Qt.NoModifier)
            root.hoverIndex = listingIndex
            return
        }
        root.failures.push("no live delegate for row " + listingIndex + " to hover")
    }
    function restPointer() {
        driver.mouseMove(pointerRest, 5, 3, 0, Qt.NoButton, Qt.NoModifier)
        root.hoverIndex = -1
    }

    // Positive control for readPast: with the bound pulled to 1, a fresh rows array makes every live row past it re-read.
    function readPastControl() {
        var p = root.stubPane, keep = root.counts.landTotal
        root.counts.landTotal = 1
        root.counts.readPast = 0
        p.rows = root.watched(p.rows.slice())
        var seen = root.counts.readPast
        root.counts.landTotal = keep
        root.counts.readPast = 0
        console.log("POOLPARK " + root.which + " readPast control=" + seen)
        if (seen === 0) root.failures.push("readPast control: a known past read counted 0, so the past-read check is blind")
    }

    // Positive control for the empty window: an index read while the view holds no count must be counted, and one inside the landed count must not.
    function emptyWindowControl() {
        var keepEmpty = root.counts.empty, keepTotal = root.counts.landTotal
        root.counts.landTotal = root.stubPane.held + 50
        root.counts.empty = true
        var inEmpty = root.pastHeld("3") && root.pastHeld("length")
        root.counts.empty = false
        var landed = root.pastHeld("3") || root.pastHeld("length")
        var past = root.pastHeld("60")
        root.counts.empty = keepEmpty
        root.counts.landTotal = keepTotal
        console.log("POOLPARK " + root.which + " empty window control=" + inEmpty + " landed=" + landed + " past=" + past)
        if (!inEmpty) root.failures.push("empty window control: an index read while the view holds no count was not counted")
        if (landed) root.failures.push("empty window control: a read inside the landed count was counted")
        if (!past) root.failures.push("empty window control: a read past the landed count was not counted")
    }

    property int step: 0
    property var before: []

    function finish() {
        if (root.finished) return
        root.finished = true
        if (root.failures.length > 0) console.log("POOLPARK FAIL " + root.which + " " + root.failures.slice(0, 8).join("; "))
        else console.log("POOLPARK DONE " + root.which)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    // One step a tick, so each landing's polish and cache buffer settle before the next.
    Timer {
        interval: 120
        running: true
        repeat: true
        onTriggered: {
            var p = root.stubPane
            if (root.step === 0) {
                root.restPointer()
                root.land("/probe", 1, root.parentRows, null)
            } else if (root.step === 1) {
                root.land("/probe/a", 1000, root.rowsFor("a_", 343), "a_")
                p.cursorIndex = 5
                p.renamingIndex = 5
                root.selectedSet = { 3: true, 7: true }
                p.selectionVersion += 1
            } else if (root.step === 2) {
                root.hoverOnto(10)
            } else if (root.step === 3) {
                root.check("enter a", "a_")
                // Back pools the hovered, renaming and thumbnailed rows while lit; the pointer then leaves them pooled.
                root.land("/probe", 1, root.parentRows, null)
                root.hoverIndex = -1
                root.check("back", null)
                root.restPointer()
            } else if (root.step === 4) {
                root.before = root.delegates(root.listingView())
                root.land("/probe/b", 1000, root.rowsFor("b_", 343), "b_")
                root.built("enter b", root.before)
                root.check("enter b in its turn", "b_")
            } else if (root.step === 5) {
                root.built("enter b settled", root.before)
                root.check("enter b settled", "b_")
                p.cursorIndex = 3
                root.selectedSet = { 2: true }
                p.selectionVersion += 1
                root.check("enter b moved", "b_")
                root.readPastControl()
                root.emptyWindowControl()
            } else if (root.step === 6) {
                // A filter narrows the listing below one screenful in every view, parking the tail, then clears and takes it back.
                var list = []
                for (var f = 0; f < 10; f++) list.push(f * 2)
                p.shown = list
                root.check("filter", "b_")
            } else if (root.step === 7) {
                var held = root.parked()
                console.log("POOLPARK " + root.which + " filter parked=" + held)
                if (held === 0) root.failures.push("filter parked no delegate, so its clear proves nothing")
                root.before = root.delegates(root.listingView())
                p.shown = null
                root.built("filter cleared", root.before)
                root.check("filter cleared", "b_")
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
