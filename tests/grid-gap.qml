//@ pragma ShellId flea-grid-gap-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/GridGeometry.js" as GridGeometry

// The first tile's frame stood 1 px from both edge lines; the live view is read at three widths.
ShellRoot {
    id: root

    // The pane GridArea reads at startup; functions are inert because nothing is pressed here.
    Component {
        id: paneStub
        QtObject {
            signal filterQueryChanged
            signal pathChanged
            property int shownTotal: 20
            property var shown: null
            property int total: 20
            property int held: 0
            property var rows: []
            property int cursorIndex: 0
            property int renamingIndex: -1
            property string renameError: ""
            property bool renamePending: false
            property bool listInFlight: false
            property string listingState: "ready"
            property bool visible: true
            property int previewIndex: -1
            property int coalesceMs: 16
            property int settleMs: 120
            property int refetchMargin: 25
            property int buffer: 150
            property int windowSize: 200
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property var selectionBand: null
            property var backend: ({
                thumb: function (rows) {}, thumbcancel: function (rows) {},
                dirsize: function (rows) {}, dirsizecancel: function () {}, window: function (start, count) {}
            })
            function rowFor(index) {
                return ({ n: "tile-" + index + ".txt", i: "text-x-generic", p: 0, d: false, s: 1, m: 0, t: false, v: 0 })
            }
            function isSelected(index) { return false }
            function commitRename(name) {}
            function setCursor(index) {}
            function focusRequested() {}
        }
    }

    // GridArea closes the menu on every scroll, so the stub answers close and nothing else.
    Component {
        id: menuStub
        QtObject {
            function close() {}
        }
    }

    Column {
        Flea.GridArea { id: narrow; width: 500; height: 320; pane: paneStub.createObject(root); menu: menuStub.createObject(root) }
        Flea.GridArea { id: middle; width: 800; height: 320; pane: paneStub.createObject(root); menu: menuStub.createObject(root) }
        Flea.GridArea { id: wide; width: 1200; height: 320; pane: paneStub.createObject(root); menu: menuStub.createObject(root) }
    }

    // Delegates are built on the polish pass, so each read waits one turn like mount-listing.qml.
    Timer {
        interval: 800
        running: true
        repeat: false
        onTriggered: root.measure()
    }
    // The last row builds only after the reveal scrolls to it, so its read waits one more turn.
    Timer {
        id: bottomTimer
        interval: 800
        running: false
        repeat: false
        onTriggered: root.measureBottom()
    }
    Timer {
        id: midTimer
        interval: 800
        running: false
        repeat: false
        onTriggered: root.measureMid()
    }
    // The show waits its own turn, so the hold is read while hidden first.
    Timer {
        id: hideTimer
        interval: 800
        running: false
        repeat: false
        onTriggered: root.measureHide()
    }
    Timer {
        id: restoreTimer
        interval: 800
        running: false
        repeat: false
        onTriggered: root.measureRestore()
    }
    property var failures: []
    // Ticks the hidden restore actually spent; only restoreCursorView moves it.
    property int restoreTicksSeen: 0
    Connections {
        target: narrow
        function onRestoreTicksChanged() { root.restoreTicksSeen += 1 }
    }

    function measure() {
        root.failures = []
        var failures = root.failures
        var gap = Flea.Theme.spacing.gap
        var hairline = Flea.Theme.spacing.hairline
        var minCell = Flea.Theme.grid.minCellWidth
        var thumbPx = Flea.ViewState.thumbnailPixels
        var padX = Flea.Theme.spacing.rowPaddingX
        var grids = [narrow, middle, wide]
        for (var g = 0; g < grids.length; g++) {
            var grid = grids[g]
            var at = "at width " + grid.width
            var expColumns = GridGeometry.columnsFor(grid.width, minCell, thumbPx, padX, gap, padX)
            var expCell = GridGeometry.cellWidthFor(grid.width, expColumns, gap, padX)
            if (grid.leftMargin !== gap)
                failures.push("leftMargin " + grid.leftMargin + " " + at)
            if (grid.topMargin !== gap)
                failures.push("topMargin " + grid.topMargin + " " + at)
            if (grid.bottomMargin !== gap)
                failures.push("bottomMargin " + grid.bottomMargin + " " + at)
            if (grid.columns !== expColumns)
                failures.push("columns " + grid.columns + " != " + expColumns + " " + at)
            if (grid.cellWidth !== expCell)
                failures.push("cellWidth " + grid.cellWidth + " != " + expCell + " " + at)
            // The rows must overflow the view at every width, or the lift has nothing to do.
            var rows = Math.ceil(grid.count / grid.columns)
            var rowsPx = rows * grid.cellHeight + grid.topMargin + grid.bottomMargin
            console.log("GRID_GAP ROWS " + at + " columns=" + grid.columns + " rows=" + rows + " count=" + grid.count + " cellH=" + grid.cellHeight + " rowsPx=" + rowsPx + " height=" + grid.height)
            if (rowsPx <= grid.height)
                failures.push("rows fit without scrolling " + rowsPx + " in " + grid.height + " " + at)
            var first = grid.itemAtIndex(0)
            if (first === null) {
                failures.push("no delegate at index 0 " + at)
                continue
            }
            // View coordinates, so the content origin convention cannot smuggle the margin back.
            var pt = first.mapToItem(grid, 0, 0)
            if (pt.x + hairline < gap)
                failures.push("first frame x " + (pt.x + hairline) + " inside the gap " + at)
            if (pt.y + hairline < gap)
                failures.push("first frame y " + (pt.y + hairline) + " inside the gap " + at)
            // The scroll lane stays clear: the last tile of the first row ends short of it.
            var last = grid.itemAtIndex(expColumns - 1)
            if (last === null) {
                failures.push("no delegate at index " + (expColumns - 1) + " " + at)
            } else {
                var end = last.mapToItem(grid, last.width, 0)
                if (end.x > grid.width - padX + 1)
                    failures.push("last tile ends at " + end.x + ", the lane starts at " + (grid.width - padX) + " " + at)
            }
        }
        // A cursor move to the last row scrolls to the end through the real reveal, then the bottom reads one turn later.
        for (var s = 0; s < grids.length; s++) {
            grids[s].positionViewAtBeginning()
            grids[s].pane.cursorIndex = grids[s].count - 1
        }
        bottomTimer.start()
    }

    function measureBottom() {
        var failures = root.failures
        var gap = Flea.Theme.spacing.gap
        var hairline = Flea.Theme.spacing.hairline
        var grids = [narrow, middle, wide]
        for (var g = 0; g < grids.length; g++) {
            var grid = grids[g]
            var at = "at width " + grid.width
            var last = grid.count - 1
            // The cursor reached the last row through the real reveal in measure, so this read pins revealCursor's lift.
            var boundNew = grid.originY + grid.contentHeight + grid.bottomMargin - grid.height
            console.log("GRID_GAP LIFT " + at + " yReveal=" + grid.contentY + " contentH=" + grid.contentHeight + " boundNew=" + boundNew)
            var item = grid.itemAtIndex(last)
            if (item === null) {
                failures.push("no delegate at last index " + last + " " + at)
                continue
            }
            // View coordinates, so the frame bottom plus its hairline is the tile bottom here.
            var end = item.mapToItem(grid, 0, 0)
            var frameBottom = end.y + item.height - hairline
            if (frameBottom + hairline > grid.height - gap)
                failures.push("last tile bottom " + (frameBottom + hairline) + " past " + (grid.height - gap) + " " + at)
        }
        // A middle-row cursor reveals through the real path next, then its read waits one more turn.
        for (var s = 0; s < grids.length; s++) {
            grids[s].positionViewAtBeginning()
            grids[s].pane.cursorIndex = Math.floor(grids[s].count / 2)
        }
        midTimer.start()
    }

    function measureMid() {
        var failures = root.failures
        var grids = [narrow, middle, wide]
        for (var g = 0; g < grids.length; g++) {
            var grid = grids[g]
            var at = "at width " + grid.width
            var mid = Math.floor(grid.count / 2)
            var yRevealed = grid.contentY
            grid.positionViewAtIndex(mid, GridView.Contain)
            if (grid.contentY !== yRevealed)
                failures.push("middle-row reveal moved past Contain " + yRevealed + " to " + grid.contentY + " " + at)
            grid.keepLastRowClear(mid)
            if (grid.contentY !== yRevealed)
                failures.push("middle-row lift moved " + yRevealed + " to " + grid.contentY + " " + at)
        }
        var last = narrow.count - 1
        narrow.positionViewAtBeginning()
        narrow.visible = false
        narrow.pane.cursorIndex = last
        hideTimer.start()
    }

    // The show waits its own turn, so the hold must already be up while hidden.
    function measureHide() {
        var failures = root.failures
        if (narrow.visible !== false)
            failures.push("hide step left the view visible")
        if (!narrow.hiddenHeld)
            failures.push("hidden hold never engaged while hidden")
        narrow.visible = true
        restoreTimer.start()
    }

    function measureRestore() {
        var failures = root.failures
        var gap = Flea.Theme.spacing.gap
        var hairline = Flea.Theme.spacing.hairline
        if (narrow.hiddenHeld)
            failures.push("hidden-held restore still holds the view")
        if (root.restoreTicksSeen < 1)
            failures.push("restore path never ran while held")
        var item = narrow.itemAtIndex(narrow.count - 1)
        if (item === null) {
            failures.push("no delegate at last index after restore")
        } else {
            var end = item.mapToItem(narrow, 0, 0)
            var frameBottom = end.y + item.height - hairline
            if (frameBottom + hairline > narrow.height - gap)
                failures.push("restored last tile bottom " + (frameBottom + hairline) + " past " + (narrow.height - gap))
        }
        // Ctrl+wheel through the real zoomWheel: Qt 6.12's notch (pixels 15 beside angle 120, no phase) is one whole step.
        Flea.ViewState.changeSetting("preview.thumbSize", "medium")
        narrow.zoomTravel = 0
        narrow.zoomWheel({ phase: Qt.NoScrollPhase, pixelDelta: { x: 0, y: 15 }, angleDelta: { x: 0, y: 120 }, modifiers: Qt.ControlModifier })
        if (narrow.zoomTravel !== 0 || Flea.ViewState.thumbnailSize !== "large")
            failures.push("a Qt 6.12 notch took medium to " + Flea.ViewState.thumbnailSize + " with travel " + narrow.zoomTravel + ", want large")
        narrow.zoomWheel({ phase: Qt.ScrollUpdate, pixelDelta: { x: 0, y: 24 }, angleDelta: { x: 0, y: 120 }, modifiers: Qt.ControlModifier })
        if (Math.abs(narrow.zoomTravel - 24 / narrow.touchpadStep) > 1e-9)
            failures.push("a 24 px touchpad stroke left zoom travel " + narrow.zoomTravel + ", want " + 24 / narrow.touchpadStep)
        if (failures.length === 0)
            console.log("GRID_GAP PASS widths=500,800,1200 gap=" + gap + " lane=" + Flea.Theme.spacing.rowPaddingX + " columns=" + narrow.columns + "," + middle.columns + "," + wide.columns)
        for (var f = 0; f < failures.length; f++)
            console.log("GRID_GAP FAIL " + failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
