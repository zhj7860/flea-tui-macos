.import "../../ui/js/GridGeometry.js" as GridGeometry

// The grid now insets one gap on the left and top, and counts tiles on the width less it.

// A text size 14 box: minCellWidth 146, thumbnailPixels 96, rowPaddingX 7, gap 8, hairline 1.
var MIN_CELL = 146
var THUMB_PX = 96
var PAD_X = 7
var GAP = 8

function run(check) {
    // Sample input: (800, 146, 96, 7, 8) is 5, five 158 px cells in 792.
    var widths = [500, 800, 1200]
    for (var w = 0; w < widths.length; w++) {
        var width = widths[w]
        var columns = GridGeometry.columnsFor(width, MIN_CELL, THUMB_PX, PAD_X, GAP)
        var cell = GridGeometry.cellWidthFor(width, columns, GAP)
        check("columns at " + width + " leave the edge gap out",
              columns, Math.max(1, Math.floor((width - GAP) / Math.max(MIN_CELL, THUMB_PX + 2 * PAD_X))))
        check("cell width at " + width + " divides the width less the gap",
              cell, Math.max(1, Math.floor((width - GAP) / Math.max(1, columns))))
        check("cells at " + width + " fit the width they were divided from",
              columns * cell <= width - GAP, true)
        check("one more column at " + width + " would not fit beside them",
              (columns + 1) * Math.max(MIN_CELL, THUMB_PX + 2 * PAD_X) > width - GAP, true)
        // The frame clearance is measured, not computed: tests/grid-gap.qml reads the real frame.
    }

    // Empty, unreadable and huge: a window narrower than the gap still draws one column.
    check("a width the gap already spent still draws one column",
          GridGeometry.columnsFor(GAP - 1, MIN_CELL, THUMB_PX, PAD_X, GAP), 1)
    check("that column is never narrower than a pixel",
          GridGeometry.cellWidthFor(GAP - 1, 1, GAP), 1)
    check("zero columns never divide",
          GridGeometry.cellWidthFor(800, 0, GAP), 800 - GAP)

    // The grid keeps the same lane clear on its right: tiles are counted and sized on the width less the gap and the lane.
    // Sample input: (738, 146, 96, 7, 8, 7) is 4, four 180 px cells beside a 7 px lane, while the lane-blind count is 5.
    var laneWidths = [500, 738, 1200]
    for (var l = 0; l < laneWidths.length; l++) {
        var laneWidth = laneWidths[l]
        var laneColumns = GridGeometry.columnsFor(laneWidth, MIN_CELL, THUMB_PX, PAD_X, GAP, PAD_X)
        var laneCell = GridGeometry.cellWidthFor(laneWidth, laneColumns, GAP, PAD_X)
        check("columns at " + laneWidth + " leave the gap and the lane out",
              laneColumns, Math.max(1, Math.floor((laneWidth - GAP - PAD_X) / Math.max(MIN_CELL, THUMB_PX + 2 * PAD_X))))
        check("cell width at " + laneWidth + " divides the width less the gap and the lane",
              laneCell, Math.max(1, Math.floor((laneWidth - GAP - PAD_X) / Math.max(1, laneColumns))))
        check("cells at " + laneWidth + " fit the width they were divided from",
              laneColumns * laneCell <= laneWidth - GAP - PAD_X, true)
        check("one more column at " + laneWidth + " would not fit beside them",
              (laneColumns + 1) * Math.max(MIN_CELL, THUMB_PX + 2 * PAD_X) > laneWidth - GAP - PAD_X, true)
    }
    // At 738 the lane costs a column, so a lane-blind columnsFor fails here.
    check("at 738 the lane costs a column",
          GridGeometry.columnsFor(738, MIN_CELL, THUMB_PX, PAD_X, GAP, PAD_X)
          + "|" + GridGeometry.columnsFor(738, MIN_CELL, THUMB_PX, PAD_X, GAP), "4|5")
    // Five arguments keep the old shape: no lane named is no lane kept, so the callers that never name one cannot change what they draw.
    check("an unnamed lane keeps nothing back",
          GridGeometry.columnsFor(800, MIN_CELL, THUMB_PX, PAD_X, GAP),
          GridGeometry.columnsFor(800, MIN_CELL, THUMB_PX, PAD_X, GAP, 0))
    check("an unnamed lane sizes nothing down",
          GridGeometry.cellWidthFor(800, 5, GAP),
          GridGeometry.cellWidthFor(800, 5, GAP, 0))

    // The window a grid holds is the list's context rebuilt in tile rows: 150 rows of 26 px each side is 32 tiles of 124 px, 18 across.
    // Sample input: (18, 11, 150, 26, 124, 25) is 576 items of buffer, a 1350 window and a margin of two tile rows.
    var plan = GridGeometry.windowFor(18, 11, 150, 26, 124, 25)
    check("the grid window keeps the list's context in tile rows",
          JSON.stringify(plan), JSON.stringify({ columns: 18, visible: 11, buffer: 576, size: 1350, margin: 36 }))
    check("a window is whole tile rows", plan.size % 18 + "|" + plan.buffer % 18, "0|0")
    check("a narrow grid keeps the list's own refetch margin", GridGeometry.windowFor(2, 3, 150, 26, 124, 25).margin, 25)
    check("a grid with no columns yet still holds a row each side", GridGeometry.windowFor(0, 0, 0, 26, 0, 25).size, 3)

    // The drift ask fires near the edge the held rows have more beyond, and never at an edge that is the listing's own.
    var drift = function (first, last, held, length) { return JSON.stringify(GridGeometry.driftAsk(plan, first, last, held, length, 2000)) }
    check("rows well inside the held window ask nothing", drift(1000, 1200, 0, 1350), "null")
    check("rows near the held end ask a window around the view", drift(1000, 1330, 0, 1350), JSON.stringify({ start: 424, count: 1350 }))
    check("rows near the held start ask a window around the view", drift(620, 700, 600, 1350), JSON.stringify({ start: 44, count: 1350 }))
    check("the top of the listing is not an edge to refetch", drift(5, 100, 0, 1350), "null")
    check("the end of the listing is not an edge to refetch", drift(1700, 1990, 650, 1350), "null")
    check("no rows held asks the window around the view", drift(0, 50, 0, 0), JSON.stringify({ start: 0, count: 1350 }))

    // A landing far from the view asks the tiles the move will draw before the move, and a step or a covered landing asks nothing.
    // Sample input: (plan, 1999, 0, 2000, 0, 352) is the tail of the listing, 254 items from 1746.
    var landing = function (cursor, first, held, length) { return JSON.stringify(GridGeometry.landingAsk(plan, cursor, first, 2000, held, length)) }
    check("a jump to the last item asks the tail of the listing", landing(1999, 0, 0, 352), JSON.stringify({ start: 1746, count: 254 }))
    check("a jump the held rows already reach asks nothing", landing(1999, 0, 700, 1500), "null")
    check("a jump to the first item asks the head once the held rows left it", landing(0, 1980, 1000, 1000), JSON.stringify({ start: 0, count: 252 }))
    check("a step of a few tile rows asks nothing", landing(90, 0, 0, 0), "null")
    check("a page of twelve tile rows the held rows reach asks nothing", landing(216, 0, 0, 352), "null")

    // A reply that repeats a row hands its tile nothing to redraw.
    check("equal rows draw the same tile", GridGeometry.sameRow({ n: "a", tg: [2] }, { n: "a", tg: [2] }), true)
    check("a changed list field draws a different tile", GridGeometry.sameRow({ n: "a", tg: [2] }, { n: "a", tg: [3] }), false)
    check("a row with another set of fields draws a different tile", GridGeometry.sameRow({ n: "a" }, { n: "a", d: true }), false)
    check("a row is never the same as no row", GridGeometry.sameRow({ n: "a" }, null) + "|" + GridGeometry.sameRow(undefined, { n: "a" }), "false|false")
    check("no row is the same as no row", GridGeometry.sameRow(null, null), true)

    // The row a tile draws: the held one, kept as the same object when a reply repeats it, kept past the window on the same listing, dropped on a new one.
    var a = { n: "a" }, b = { n: "b" }, memo = { row: null, index: -1, listing: 0 }
    check("a tile reads the held row at its index", GridGeometry.heldRow(memo, { start: 10, rows: [a, b], listing: 1 }, 11), b)
    check("a reply that repeats the row leaves the tile the object it has",
          GridGeometry.heldRow(memo, { start: 10, rows: [{ n: "a" }, { n: "b" }], listing: 1 }, 11), b)
    check("the window leaving the index keeps the row on the same listing", GridGeometry.heldRow(memo, { start: 100, rows: [a], listing: 1 }, 11), b)
    check("a tile moved to an index no window holds reads nothing", GridGeometry.heldRow(memo, { start: 100, rows: [a], listing: 1 }, 12), null)
    // A stale row sits in the memo at the same index, so only the listing compare can drop it.
    memo.row = a
    check("a new listing leaves no row behind", GridGeometry.heldRow(memo, { start: 100, rows: [a], listing: 2 }, 12), null)
}
