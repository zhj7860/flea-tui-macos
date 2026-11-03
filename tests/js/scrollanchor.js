.import "../../ui/js/Selection.js" as Selection
.import "../../ui/js/Filter.js" as Filter
.import "../../ui/js/Marks.js" as Marks
.import "../../ui/js/Ops.js" as Ops

// Issue 286: a Shift range started after the wheel pulled the cursor onto the viewport starts where the cursor was.
function pane() {
    var p = {
        rows: [], held: 0, total: 500, cursorIndex: 0, cursorSeq: 0,
        shown: null, shownTotal: 500, filterQuery: "", selectionAnchor: 0,
        selectionVersion: 0, path: "/d", listInFlight: false, cursorPulled: null,
        clipPending: null, clipQueue: [], clipSequence: 0, pathsPending: null,
        clipboard: null, clipboardState: null
    }
    p.selection = Selection.create()
    p.selectedIndices = function () { return p.selection.indices() }
    moveWindow(p, 0)
    p.rowFor = function (index) {
        var offset = index - p.held
        return offset < 0 || offset >= p.rows.length ? null : p.rows[offset]
    }
    p.join = function (a, b) { return a + "/" + b }
    p.showRow = function () {}
    p.message = function () {}
    p.backend = {
        heldListing: 1,
        asked: [],
        askPaths: function (rows) { p.backend.asked.push(rows.slice()) },
        send: function () {}
    }
    return p
}

// A window move lands new rows; the selection stands, as ui/PaneSwap.qml does.
function moveWindow(p, start) {
    p.held = start
    p.rows = []
    for (var i = start; i < start + 60; i++) p.rows.push({ n: "f" + i + ".txt", d: false })
}

// ui/Pane.qml selectOnly: a plain click latches the anchor at the clicked row.
function click(p, i) {
    Filter.setCursor(p, i, 0)
    p.selection.only(p.cursorIndex)
    p.selectionAnchor = p.cursorIndex
    p.selectionVersion++
}

// Copy through the real key path, resolving every asked row in listing order as the backend's paths answer does.
function copyResolved(p) {
    Ops.clip(p, false)
    var asked = p.backend.asked
    var rows = asked.length > 0 ? asked[asked.length - 1] : []
    var list = []
    for (var i = 0; i < rows.length; i++) list.push("/d/f" + rows[i] + ".txt")
    Ops.pathsResolved(p, list)
    return rows
}

function run(check) {
    // The reported gesture: click row 5, wheel the anchor out of view, Shift+click 400.
    var p = pane()
    click(p, 5)
    moveWindow(p, 340)
    Filter.clampCursor(p, 370, 399)
    check("the wheel pulls the cursor onto the viewport", p.cursorIndex, 370)
    Marks.extendToRow(p, 400)
    check("Shift+click across the scrolled window keeps the clicked anchor", p.selectionAnchor, 5)
    var rows = copyResolved(p)
    check("copy asks for every row between anchor and click", rows.length, 396)
    check("copy starts at the anchor row", p.clipboard.paths[0], "/d/f5.txt")
    check("copy ends at the clicked row", p.clipboard.paths[p.clipboard.paths.length - 1], "/d/f400.txt")
    var ordered = true
    for (var i = 0; i < p.clipboard.paths.length; i++) {
        if (p.clipboard.paths[i] !== "/d/f" + (5 + i) + ".txt") { ordered = false; break }
    }
    check("copy holds all 396 paths in order", ordered && p.clipboard.paths.length === 396, true)

    // Shift+J after the same scroll keeps the anchor too, not the pulled cursor.
    var k = pane()
    click(k, 5)
    moveWindow(k, 340)
    Filter.clampCursor(k, 370, 399)
    Marks.extend(k, 1)
    check("Shift+J after a scroll ranges from the anchor", k.selectedIndices().length, 367)

    // Two Ctrl+click marks, then the wheel: the range starts at the last mark, beside the first.
    var m = pane()
    click(m, 5)
    Marks.toggleRow(m, 10)
    moveWindow(m, 340)
    Filter.clampCursor(m, 370, 399)
    Marks.extendToRow(m, 400)
    var marked = m.selectedIndices()
    check("Shift+click after two marks and a scroll keeps both and ranges from the last",
          marked.length + "|" + marked.slice(0, 3).join(","), "392|5,10,11")

    // A second pull while the first is still the cursor's last move keeps the first row it left.
    var twice = pane()
    click(twice, 5)
    moveWindow(twice, 340)
    Filter.clampCursor(twice, 370, 399)
    Filter.clampCursor(twice, 380, 409)
    Marks.extendToRow(twice, 400)
    check("two pulls in a row still range from the clicked row", twice.selectedIndices().length, 396)

    // Any move after the pull is the user's own, so the range starts at the cursor again.
    var moved = pane()
    click(moved, 5)
    moveWindow(moved, 340)
    Filter.clampCursor(moved, 370, 399)
    Filter.moveCursor(moved, 1)
    Marks.extend(moved, 1)
    check("j after the pull ranges from the cursor j left", moved.selectedIndices().join(","), "5,371,372")
    var jumped = pane()
    click(jumped, 5)
    moveWindow(jumped, 340)
    Filter.clampCursor(jumped, 370, 399)
    jumped.cursorIndex = 120
    Marks.extend(jumped, 1)
    check("a direct cursor write after the pull ranges from that row", jumped.selectedIndices().join(","), "5,120,121")
    var cleared = pane()
    click(cleared, 5)
    moveWindow(cleared, 340)
    Filter.clampCursor(cleared, 370, 399)
    cleared.selection.clear()
    cleared.selectionVersion++
    Marks.extendToRow(cleared, 380)
    check("a selection change after the pull, as a new listing makes, ranges from the cursor",
          cleared.selectionAnchor, 370)

    // With no pull a lone row away from the cursor never anchors: the range starts at the cursor.
    var lone = pane()
    click(lone, 40)
    lone.selection.only(5)
    Filter.setCursor(lone, 200, 0)
    Marks.extend(lone, 1)
    check("Shift+J with a lone row elsewhere ranges from the cursor", lone.selectedIndices().join(","), "5,200,201")
    var kept = pane()
    click(kept, 5)
    Marks.toggleSelect(kept)
    Filter.moveCursor(kept, 15)
    Marks.extend(kept, 1)
    check("and a kept mark behind a j move stays a mark of its own", kept.selectedIndices().join(","), "5,20,21")

    // Ctrl+clicks are window-independent: one mark per click, anchor at each click.
    var c = pane()
    click(c, 5)
    moveWindow(c, 340)
    Filter.clampCursor(c, 370, 399)
    Marks.toggleRow(c, 400)
    check("Ctrl+clicks spanning two windows keep both marks", c.selectedIndices().join(","), "5,400")
    var crows = copyResolved(c)
    check("copy asks for every Ctrl+click mark", crows.join(","), "5,400")
    check("copy resolves both marks in order",
          c.clipboard.paths.join(","), "/d/f5.txt,/d/f400.txt")
}
