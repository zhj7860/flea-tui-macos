//@ pragma ShellId flea-gridcapbreak-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/GridGeometry.js" as GridGeometry
import "flea/js/Match.js" as Match
import "flea/js/Places.js" as Places

// The Grid caption state names the break Flea drew, so a query can straddle it: the long fixture name at text size 14 under a 1320 px window, one tile per sidebar stop; a name Qt must wrap again reads broken false, a one-line name reads wrapAt -1.
ShellRoot {
    id: root

    readonly property string fixtureName: "grid-caption-that-wraps.txt"
    // Circled digits fall back to a face wider than Flea's cell, so at the narrowest pane the first line Flea broke is wrapped again by Qt: three lines, two shown, truncated.
    readonly property string againName: "①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱.txt"
    readonly property string singleName: "a.txt"
    // The width the native captures open at (tests/ui-captures-filter.sh cap_filter_width_default).
    readonly property int windowWidth: 1320
    // The tile widths that window gives the grid beside each sidebar stop (ui/js/Places.js WIDTH_STOPS), the cell maths GridArea runs.
    readonly property var paneWidths: Places.WIDTH_STOPS.map(function (stop) { return root.windowWidth - stop })
    readonly property var cases: root.paneWidths.map(function (w) { return { kind: "break", name: root.fixtureName, pane: w } }).concat([
        { kind: "again", name: root.againName, pane: root.paneWidths[root.paneWidths.length - 1] },
        { kind: "single", name: root.singleName, pane: root.paneWidths[0] }])

    function rowOf(name) { return { n: name, i: "text-x-generic", p: 0, d: false, s: 1, m: 0, t: false, v: 0 } }

    function cellW(pane) {
        var th = Flea.Theme, columns = GridGeometry.columnsFor(pane, th.grid.minCellWidth, Flea.ViewState.thumbnailPixels, th.spacing.rowPaddingX, th.spacing.gap, th.spacing.rowPaddingX)
        return GridGeometry.cellWidthFor(pane, columns, th.spacing.gap, th.spacing.rowPaddingX)
    }

    property var tiles: []
    QtObject {
        id: stubPane
        property var backend: null
        function visibleItemFor(i) { return root.tiles[i] || null }
    }
    QtObject { id: windowStub; function centreOf(item) { return "" } function rectOf(item) { return "" } }
    Flea.Ipc { id: ipc; pane: stubPane; fleaWindow: windowStub }

    Column {
        Repeater {
            id: reps
            model: root.cases
            Flea.GridTile { required property var modelData; width: root.cellW(modelData.pane); height: 200; row: root.rowOf(modelData.name) }
        }
    }
    FontMetrics { id: face; font.family: Flea.Theme.font.family; font.pixelSize: Flea.Theme.font.bodySmall }

    property int phase: 0
    property var failures: []
    property var queries: []

    function check(cond, label) {
        if (!cond) root.failures.push(label)
    }

    // The wash item a tile builds under its markQuery, found by the boxes it carries.
    function washOf(tile) {
        var stack = [tile]
        while (stack.length > 0) {
            var o = stack.pop()
            if (o.boxes !== undefined) return o
            for (var i = 0; i < o.children.length; i++) stack.push(o.children[i])
        }
        return null
    }

    // Why a tile's state does not name the drawn break, "" when it does: lines, letters kept, widths fitting the caption.
    function verdict(state, cap) {
        if (state.wrapAt === undefined || state.broken === undefined) return "state has no wrapAt or broken"
        if (state.lines !== 2 || state.broken !== true) return "Qt draws " + state.lines + " lines, broken=" + state.broken
        var shown = String(state.name).split("\n").join("")
        if (shown !== root.fixtureName) return "the caption drops letters: " + JSON.stringify(state.name)
        if (!(state.wrapAt > 0 && state.wrapAt < shown.length)) return "wrapAt " + state.wrapAt + " is no inner index"
        var a = shown.substring(0, state.wrapAt), b = shown.substring(state.wrapAt)
        if (String(state.name) !== a + "\n" + b) return "wrapAt " + state.wrapAt + " is not the break of " + JSON.stringify(state.name)
        // Line 1 and line 2 each fit the caption, so Qt had no reason to wrap again where Flea did not.
        if (face.advanceWidth(a) > cap.width || face.advanceWidth(b) > cap.width) return "a line is wider than the caption " + cap.width
        if (state.textHeight > state.slotHeight) return "the text overflows its slot"
        return ""
    }

    // A caption Flea broke in two whose first line Qt wrapped again: three lines, the cap shows two, so Qt drew more than Flea broke.
    function againVerdict(state) {
        if (state.wrapAt === undefined || state.broken === undefined) return "state has no wrapAt or broken"
        if (String(state.name).split("\n").length !== 2 || !(state.wrapAt > 0)) return "Flea did not break " + JSON.stringify(state.name) + " in two, wrapAt " + state.wrapAt
        if (state.lines !== 2 || state.truncated !== true) return "Qt draws " + state.lines + " lines, truncated=" + state.truncated + ", want two shown and a cut"
        if (state.broken !== false) return "broken=" + state.broken + " for a caption Qt wrapped again and cut"
        return ""
    }

    // A name that fits one line: no break, wrapAt -1, and Qt draws that one line.
    function singleVerdict(state) {
        if (state.wrapAt === undefined || state.broken === undefined) return "state has no wrapAt or broken"
        if (state.name !== root.singleName || state.wrapAt !== -1) return "wrapAt " + state.wrapAt + " for " + JSON.stringify(state.name) + ", want -1 for one line"
        if (state.lines !== 1 || state.broken !== true || state.truncated !== false) return "Qt draws " + state.lines + " lines, broken=" + state.broken + ", truncated=" + state.truncated
        return ""
    }

    function measure() {
        for (var i = 0; i < reps.count; i++) {
            var tile = reps.itemAt(i)
            root.tiles[i] = tile
        }
        for (i = 0; i < reps.count; i++) {
            tile = reps.itemAt(i)
            var kind = root.cases[i].kind
            var state = JSON.parse(ipc.seam.gridCaptionState(i))
            var why = kind === "again" ? root.againVerdict(state) : kind === "single" ? root.singleVerdict(state) : root.verdict(state, tile.captionItem)
            root.check(why === "", kind + " tile " + i + " width " + tile.width + ": " + why)
            if (why !== "" || kind !== "break") continue
            var shown = String(state.name).split("\n").join("")
            var query = shown.substring(state.wrapAt - 2, state.wrapAt + 1)
            root.check(Match.run(shown, query).start === state.wrapAt - 2, "tile " + i + " query " + query + " is not the letters either side of the break")
            root.queries[i] = query
            tile.markQuery = query
        }
    }

    // The wash a straddling query draws: one box on each drawn line, the first ending where line 1 does.
    function washed() {
        for (var i = 0; i < reps.count; i++) {
            if (root.cases[i].kind !== "break") continue
            var tile = reps.itemAt(i), wash = root.washOf(tile)
            var boxes = wash ? wash.boxes : []
            root.check(boxes.length === 2, "tile " + i + " query " + root.queries[i] + " draws " + boxes.length + " wash boxes, want one per line")
            if (boxes.length !== 2) continue
            var lh = Flea.Theme.grid.captionLineHeight
            root.check(boxes[0].y === 0 && boxes[1].y === lh, "tile " + i + " boxes sit on lines at y " + boxes[0].y + " and " + boxes[1].y)
            root.check(boxes[0].width > 0 && boxes[1].width > 0, "tile " + i + " a wash box has no width")
            var state = JSON.parse(ipc.seam.gridCaptionState(i)), cap = tile.captionItem
            var line0 = String(state.name).split("\n")[0]
            root.check(Math.abs(boxes[0].x + boxes[0].width - (cap.width + face.advanceWidth(line0)) / 2) < 1, "tile " + i + " the first box does not end at the end of line 1")
            root.check(Math.abs(boxes[1].x - (cap.width - face.advanceWidth(String(state.name).split("\n")[1])) / 2) < 1, "tile " + i + " the second box does not start at the start of line 2")
        }
    }

    Timer {
        interval: 700; running: true; repeat: true
        onTriggered: {
            if (root.phase === 0) Flea.ViewState.setTextSize({ mode: 14 })
            else if (root.phase === 2) root.measure()
            else if (root.phase === 4) root.washed()
            else if (root.phase === 5) {
                running = false
                if (root.failures.length === 0)
                    console.log("GRIDCAPBREAK PASS base=14 window=" + root.windowWidth + " tiles=" + reps.count + " widths=" + root.paneWidths.map(root.cellW).join(",") + " queries=" + root.queries.filter(function (q) { return q !== undefined }).join(","))
                for (var f = 0; f < root.failures.length; f++)
                    console.log("GRIDCAPBREAK FAIL " + root.failures[f])
                Quickshell.execDetached(["kill", String(Quickshell.processId)])
            }
            root.phase++
        }
    }
}
