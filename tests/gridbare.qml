//@ pragma ShellId flea-gridbare-test

import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "flea/js/Selection.js" as Selection

// A real Grid in a real window, driven by pointer events: a tile takes a press, tap, drag or menu only on its icon box or painted caption, and the rest of a cell is the listing's own ground.
ShellRoot {
    id: root

    property var failures: []
    property int gestures: 0
    readonly property int rowCount: 40
    // One short name and one long enough to wrap in GridNames, so the painted caption box is measured at two widths.
    readonly property string shortName: "a.md"
    readonly property string longName: "screenshot-2026-08-30-final-review-for-gm-after-the-bench-v3.png"
    readonly property int shortIndex: 5
    readonly property int longIndex: 6
    // A tile with a column on each side, so a press at its right edge stays inside the viewport.
    readonly property int plainIndex: 7

    function buildRows() {
        var rows = []
        for (var i = 0; i < root.rowCount; i++) {
            var n = i === root.shortIndex ? root.shortName : i === root.longIndex ? root.longName : "item" + (i < 10 ? "0" + i : i) + ".txt"
            rows.push({ n: n, d: false, i: "text-x-generic", p: 420, s: 13, m: 1758835200, t: false, k: 0, v: 0 })
        }
        return rows
    }

    Component {
        id: backendStub
        QtObject {
            property int heldListing: 1
            property int dirDev: 1
            function peek(path, size, hidden) {}
            function thumb(rows, cacheOnly) {}
            function thumbcancel(rows) {}
            function dirsize(rows) {}
            function dirsizecancel() {}
            function window(start, count) {}
            function send(message) {}
        }
    }

    Component {
        id: paneStub
        QtObject {
            property string path: "/probe"
            property var rows: []
            property var shown: null
            property int shownTotal: 40
            property int total: 40
            property int held: 0
            property int cursorIndex: 0
            property int renamingIndex: -1
            // Holds a rename open while the probe presses, as a focused editor does; the offscreen window gives it no focus to hold.
            property int renamePin: -1
            // Counts each time the pin had to restore the rename, so a press that ends it shows.
            property int pinSnaps: 0
            onRenamingIndexChanged: if (renamePin >= 0 && renamingIndex !== renamePin) { pinSnaps++; renamingIndex = renamePin }
            property string renameError: ""
            property bool renamePending: false
            property var renameRequest: null
            property bool paneFocused: true
            property bool dualMode: false
            property bool singleClick: false
            property var clipboard: null
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property string searchMode: ""
            property string searchQuery: ""
            property string filterQuery: ""
            property bool filterTyping: false
            property var swap: ({ searchWarm: false, answeredQuery: "" })
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
            property var pathsPending: null
            property var clipPending: null
            property bool awaitingPaths: false
            property bool dragHolding: false
            property bool pointerHeld: false
            property var selection: Selection.create()
            property int selectionVersion: 0
            property int selectionAnchor: -1
            property string focusView: "grid"
            property var listArea: null
            signal focusRequested()
            // What the product's handlers did, read back by the probe.
            property var selectedOnly: []
            property var toggled: []
            property int opens: 0
            property int tileMenus: 0
            property int slowClicks: 0
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) { var o = index - held; return (o >= 0 && o < rows.length) ? rows[o] : null }
            function isSelected(index) { selectionVersion; return selection.has(index) }
            function selectedIndices() {
                var picked = []
                for (var i = 0; i < total; i++) if (selection.has(i)) picked.push(i)
                return picked
            }
            function clearSelection() { selection.clear(); selectionVersion++ }
            function selectOnly(index, keep) { selectedOnly.push(index); selection.only(index, keep === true); selectionVersion++ }
            function toggleSelectAt(index) { toggled.push(index); selection.toggle(index); selectionVersion++ }
            function extendSelectionTo(index) {}
            function setCursor(index, context) {}
            function commitOpenRename() {}
            function act(verb) { if (verb === "open") opens += 1 }
            function slowClickWasSole(index) { return false }
            function armSlowClick(index, modifiers, dragging, wasSole) { slowClicks += 1 }
            function pressSlowClick() {}
            function cancelSlowClick() {}
            function message(text, alert) {}
            function commitRename(newName) {}
        }
    }

    Component {
        id: menuStub
        QtObject {
            property int backgrounds: 0
            property int tiles: 0
            function close() {}
            function openBackground(point) { backgrounds += 1 }
            function openAt(point) { tiles += 1 }
        }
    }

    property var stubBackend: backendStub.createObject(root)
    property var stubMenu: menuStub.createObject(root)
    property var stubPane: paneStub.createObject(root, { backend: root.stubBackend, rows: root.buildRows() })

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

        TestEvent { id: driver }
    }

    // List and Columns keep SelectionBand's own row test, driven through a scrolled list: a press on a row is refused, one on the ground below the rows owns the band.
    FloatingWindow {
        implicitWidth: 300
        implicitHeight: 200
        color: Flea.Theme.color.background

        ListView {
            id: plainList
            width: 300
            height: 200
            model: 6
            delegate: Item { width: 300; height: 20 }
            footer: Item { width: 300; height: 200 }
            Flea.SelectionBand { id: plainBand; parent: plainList; pane: root.stubPane; flickable: plainList }
        }
    }

    Timer { interval: 900; running: true; repeat: false; onTriggered: root.run() }

    function fail(text) { root.failures.push(text) }
    function expect(label, got, want) {
        if (got !== want) root.fail(label + ": got " + got + ", want " + want)
    }

    function tile(index) { return grid.itemAtIndex(index) }
    function at(index, x, y) { return root.tile(index).mapToItem(grid, x, y) }

    // The lift's DragHandler, found through the RowDrag a tile holds.
    function liftOf(index) {
        var kids = root.tile(index).children
        for (var k = 0; k < kids.length; k++) {
            if (kids[k].session === undefined) continue
            for (var d = 0; d < kids[k].data.length; d++)
                if (kids[k].data[d].centroid !== undefined) return kids[k].data[d]
        }
        return null
    }

    function press(index, x, y, button) { var p = root.at(index, x, y); driver.mousePress(grid, p.x, p.y, button, Qt.NoModifier, 1) }
    function release(index, x, y, button) { var p = root.at(index, x, y); driver.mouseRelease(grid, p.x, p.y, button, Qt.NoModifier, 1) }
    function drag(index, x, y, dx, dy) {
        var p = root.at(index, x, y)
        driver.mouseMove(grid, p.x + dx / 2, p.y + dy / 2, 1, Qt.LeftButton, Qt.NoModifier)
        driver.mouseMove(grid, p.x + dx, p.y + dy, 1, Qt.LeftButton, Qt.NoModifier)
    }
    function doubleClick(index, x, y) { var p = root.at(index, x, y); driver.mouseDoubleClickSequence(grid, p.x, p.y, Qt.LeftButton, Qt.NoModifier, 1) }
    function click(index, x, y, button) { root.press(index, x, y, button); root.release(index, x, y, button) }

    function reset() {
        var pane = root.stubPane
        pane.selection = Selection.create()
        pane.selectionVersion++
        pane.selectedOnly = []
        pane.toggled = []
        pane.opens = 0
        pane.pathsPending = null
        root.stubMenu.backgrounds = 0
        root.stubMenu.tiles = 0
    }

    // One point of one tile: onTile says whether the tile owns it, and every gesture must agree.
    function probe(label, index, x, y, onTile, bandOpen) {
        var pane = root.stubPane, menu = root.stubMenu, lift = root.liftOf(index)
        var seen = root.at(index, x, y)
        root.expect(label + " lies in the viewport", seen.y >= 0 && seen.y + 30 < grid.height && seen.x >= 0 && seen.x + 40 < grid.width, true)
        root.gestures += 4

        root.reset()
        root.click(index, x, y, Qt.LeftButton)
        root.expect(label + " click selects the tile", pane.selectedOnly.length > 0, onTile)
        root.expect(label + " click leaves no band owner", pane.selectionBand, null)

        // The platform's synthetic double click reaches the tile as two taps, so the open itself is the native case's.
        root.reset()
        root.doubleClick(index, x, y)
        root.expect(label + " double click selects the tile", pane.selectedOnly.length > 0, onTile)
        root.expect(label + " double click on bare ground opens nothing", onTile ? 0 : pane.opens, 0)

        root.reset()
        root.click(index, x, y, Qt.RightButton)
        root.expect(label + " right click raises the tile menu", menu.tiles, onTile ? 1 : 0)
        root.expect(label + " right click raises the background menu", menu.backgrounds, onTile ? 0 : 1)

        root.reset()
        root.press(index, x, y, Qt.LeftButton)
        root.expect(label + " press makes the band the owner", pane.selectionBand !== null, !onTile && bandOpen)
        root.drag(index, x, y, 40, 30)
        root.expect(label + " drag lifts the tile", lift.active, onTile)
        root.expect(label + " drag sweeps a band", pane.selectionBand !== null && pane.selectionBand.bandActive, !onTile && bandOpen)
        driver.mouseRelease(grid, root.at(index, x, y).x + 40, root.at(index, x, y).y + 30, Qt.LeftButton, Qt.NoModifier, 1)
        root.expect(label + " release frees the band", pane.selectionBand, null)
    }

    // A margin of a plain tile: its left edge, its right edge, its top edge and the gap between icon and caption.
    function plainPoints(index, tag) {
        var t = root.tile(index), icon = t.thumbItem, label = t.captionItem
        var iconBox = icon.mapToItem(t, 0, 0), labelBox = label.mapToItem(t, 0, 0), middle = iconBox.y + icon.height / 2
        return [
            [tag + " icon centre", index, iconBox.x + icon.width / 2, middle, true],
            [tag + " icon top left corner", index, iconBox.x + 1, iconBox.y + 1, true],
            [tag + " left edge", index, 2, middle, false],
            [tag + " right edge", index, t.width - 3, middle, false],
            [tag + " top edge", index, t.width / 2, 2, false],
            [tag + " beside the icon", index, iconBox.x - 3, middle, false],
            [tag + " between icon and caption", index, t.width / 2, (iconBox.y + icon.height + labelBox.y) / 2, false]
        ]
    }

    // A band from the margin between two middle tiles sweeps the four tiles it crosses, from the pressed point.
    function sweep(tag, inside) {
        var c = grid.columns
        var a = root.tile(c + 1), b = root.tile(2 * c + 2)
        var start = a.mapToItem(grid, a.width - 3, a.height / 2)
        var stop = b.mapToItem(grid, b.width / 2, b.height / 2)
        var four = [c + 1, c + 2, 2 * c + 1, 2 * c + 2].join(",")
        root.expect(tag + " sweep stays in the viewport", start.y >= 0 && (!inside || stop.y < grid.height), true)
        root.reset()
        driver.mousePress(grid, start.x, start.y, Qt.LeftButton, Qt.NoModifier, 1)
        driver.mouseMove(grid, (start.x + stop.x) / 2, (start.y + stop.y) / 2, 1, Qt.LeftButton, Qt.NoModifier)
        driver.mouseMove(grid, stop.x, stop.y, 1, Qt.LeftButton, Qt.NoModifier)
        root.expect(tag + " band from a margin selects four tiles", root.stubPane.selectedIndices().join(","), four)
        driver.mouseRelease(grid, stop.x, stop.y, Qt.LeftButton, Qt.NoModifier, 1)
        root.expect(tag + " band keeps four tiles on release", root.stubPane.selectedIndices().join(","), four)
        root.reset()
    }

    function hover(index, x, y) { var p = root.at(index, x, y); driver.mouseMove(grid, p.x, p.y, 1, Qt.NoButton, Qt.NoModifier) }

    // Hover lights a tile on its icon box and painted caption only; a pointer on the bare margin of its cell lights nothing, and moving off the margin onto the icon lights it.
    function hoverProbe(index, tag) {
        var t = root.tile(index), icon = t.thumbItem, text = t.captionItem
        var iconBox = icon.mapToItem(t, 0, 0), box = text.mapToItem(t, 0, 0)
        var painted = Math.min(text.width, text.contentWidth)
        var iconAt = [iconBox.x + icon.width / 2, iconBox.y + icon.height / 2]
        var captionAt = [box.x + text.width / 2, box.y + 3]
        var marginAt = [iconBox.x - 3, iconBox.y + icon.height / 2]
        root.expect(tag + " is not the cursor", t.cursor, false)
        root.expect(tag + " caption paints a width", painted > 0, true)
        root.gestures += 4
        root.hover(index, marginAt[0], marginAt[1])
        root.expect(tag + " margin is not hovered", t.hovered, false)
        root.hover(index, iconAt[0], iconAt[1])
        root.expect(tag + " icon box is hovered after the margin", t.hovered, true)
        root.hover(index, marginAt[0], marginAt[1])
        root.expect(tag + " margin is not hovered after the icon", t.hovered, false)
        root.hover(index, captionAt[0], captionAt[1])
        root.expect(tag + " caption is hovered", t.hovered, true)
        root.hover(index, 2, 2)
        root.expect(tag + " corner is not hovered after the caption", t.hovered, false)
    }

    // A tile that renames keeps every press on its editor row, the text field and the cell beside it: no band, no background menu, and its own handlers stay off.
    function renameProbe(index) {
        var pane = root.stubPane, menu = root.stubMenu, t = root.tile(index)
        var box = t.captionItem.mapToItem(t, 0, 0), y = t.renameY + 4
        var points = [["editor centre", box.x + t.captionItem.width / 2], ["cell margin beside the editor", 2]]
        pane.cursorIndex = index
        pane.renamePin = index
        pane.renamingIndex = index
        root.expect("the renaming tile is drawn as editing", t.editing, true)
        root.expect("the editor row is below the icon box", t.thumbItem.mapFromItem(t, 0, y).y >= t.thumbItem.height, true)
        // The editor's begin check runs on the first event this unfocused window processes and the pin restores it, so one hover settles that before the count starts.
        var rest = root.at(index, t.width / 2, 4)
        driver.mouseMove(grid, rest.x, rest.y, 1, Qt.NoButton, Qt.NoModifier)
        pane.pinSnaps = 0
        for (var k = 0; k < points.length; k++) {
            var label = "renaming " + points[k][0], x = points[k][1]
            root.gestures += 2
            root.reset()
            root.click(index, x, y, Qt.RightButton)
            root.expect(label + " right click raises no background menu", menu.backgrounds, 0)
            root.expect(label + " right click raises no tile menu", menu.tiles, 0)
            root.reset()
            root.press(index, x, y, Qt.LeftButton)
            root.expect(label + " press starts no band", pane.selectionBand, null)
            root.release(index, x, y, Qt.LeftButton)
            root.expect(label + " press selects nothing", pane.selectedOnly.length, 0)
            root.expect(label + " clicks and presses leave the rename open", pane.pinSnaps, 0)
        }
        pane.renamePin = -1
        pane.renamingIndex = -1
        pane.cursorIndex = 0
        root.reset()
    }

    // A real press on a scrolled list: a row refuses the band, the ground below the rows owns it.
    function listPresses() {
        plainList.contentY = 100
        root.expect("the list is scrolled past its first rows", plainList.contentY, 100)
        root.reset()
        root.stubPane.selectionBand = null
        driver.mousePress(plainList, 10, 10, Qt.LeftButton, Qt.NoModifier, 1)
        root.expect("a press on a scrolled list row starts no band", root.stubPane.selectionBand, null)
        driver.mouseRelease(plainList, 10, 10, Qt.LeftButton, Qt.NoModifier, 1)
        driver.mousePress(plainList, 10, 100, Qt.LeftButton, Qt.NoModifier, 1)
        root.expect("a press on the ground below scrolled list rows starts the band", root.stubPane.selectionBand, plainBand)
        driver.mouseRelease(plainList, 10, 100, Qt.LeftButton, Qt.NoModifier, 1)
        root.expect("release frees the list band", root.stubPane.selectionBand, null)
        root.gestures += 2
    }

    function run() {
        root.stubPane.listArea = grid
        var short = root.tile(root.shortIndex), long = root.tile(root.longIndex), plain = root.tile(root.plainIndex)
        if (!short || !long || !plain || grid.count !== root.rowCount) {
            root.fail("the grid built " + grid.count + " rows and no tiles 5, 6 and 7")
            root.report()
            return
        }
        var points = root.plainPoints(root.plainIndex, "plain")
        var names = [[short, root.shortIndex, "short caption"], [long, root.longIndex, "wrapped caption"]]
        for (var n = 0; n < names.length; n++) {
            var t = names[n][0], index = names[n][1], name = names[n][2]
            var text = t.captionItem, box = text.mapToItem(t, 0, 0)
            var painted = Math.min(text.width, text.contentWidth)
            var left = box.x + (text.width - painted) / 2
            var top = box.y + Math.min(text.height, text.contentHeight)
            points.push([name + " paints " + Math.round(painted) + " of " + Math.round(text.width) + " px", index, left + painted / 2, box.y + 3, true])
            points.push([name + " first painted pixel", index, left + 1, box.y + 3, true])
            points.push([name + " left of the painted text", index, left - 3, box.y + 3, false])
            points.push([name + " right of the painted text", index, left + painted + 2, box.y + 3, false])
            if (top < box.y + text.height)
                points.push([name + " below the painted lines", index, left + painted / 2, top + 2, false])
        }
        root.expect("the caption widths differ", Math.round(short.captionItem.contentWidth) < Math.round(long.captionItem.contentWidth), true)
        for (var p = 0; p < points.length; p++)
            root.probe(points[p][0], points[p][1], points[p][2], points[p][3], points[p][4], true)
        // While a listing loads the band stays out, and the tile's own handlers still answer only on the tile.
        root.stubPane.listingState = "loading"
        for (p = 0; p < points.length; p++)
            root.probe("loading " + points[p][0], points[p][1], points[p][2], points[p][3], points[p][4], false)
        root.stubPane.listingState = "ready"

        var c = grid.columns
        root.expect("the grid has middle columns", c >= 4, true)
        root.sweep("unscrolled", false)
        root.hoverProbe(root.plainIndex, "plain")

        // Scrolled past a tile row, viewport and content coordinates differ: a tile's icon still owns its menu, a margin still owns the band and the background menu.
        grid.contentY = Math.round(grid.cellHeight * 1.25)
        grid.forceLayout()
        root.expect("the grid is scrolled past a tile row", grid.contentY > grid.cellHeight, true)
        var scrolled = root.plainPoints(2 * c + 2, "scrolled plain")
        for (p = 0; p < scrolled.length; p++)
            root.probe(scrolled[p][0], scrolled[p][1], scrolled[p][2], scrolled[p][3], scrolled[p][4], true)
        root.sweep("scrolled", true)
        root.hoverProbe(2 * c + 2, "scrolled plain")
        root.renameProbe(2 * c + 2)
        root.listPresses()
        root.report()
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("GRIDBARE FAIL " + root.failures[f])
        if (root.failures.length === 0)
            console.log("GRIDBARE PASS gestures=" + root.gestures + " icon=hit caption=short,wrapped margin=band hover=icon,caption")
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
