//@ pragma ShellId flea-tagrows-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Tags.js" as TagsLib

// Tag slots on the real delegates: an untagged row builds nothing, a tagged one mounts one slot, and a delegate that gets another row reuses it.
ShellRoot {
    id: root

    property var failures: []
    property var plain: ({ n: "plain.txt", i: "text-x-generic", p: 420, d: false, s: 13, m: 1758835200, t: false, k: 0, v: 0, shown: true })
    property var tagged: ({ n: "tagged.txt", i: "text-x-generic", p: 420, d: false, s: 13, m: 1758835200, t: false, k: 0, v: 0, tg: ["Red", "Blue"], shown: true })
    property var triple: ({ n: "tagged.txt", i: "text-x-generic", p: 420, d: false, s: 13, m: 1758835200, t: false, k: 0, v: 0, tg: ["Green", "Gray", "Purple"], shown: true })
    property var seven: ({ n: "seven.txt", i: "text-x-generic", p: 420, d: false, s: 13, m: 1758835200, t: false, k: 0, v: 0, tg: ["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Gray"], shown: true })
    property var palette: ({ Red: "#ff0000", Orange: "#ff8800", Yellow: "#ffff00", Green: "#00ff00", Blue: "#0000ff", Purple: "#aa00ff", Gray: "#888888" })
    property var picked: []
    property var triples: []
    property int phase: 0
    property var shape: ({})

    Column {
        id: colHost
        Repeater {
            id: colRep
            model: [root.plain, root.tagged]
            delegate: Flea.ColumnRow {
                required property var modelData
                width: 280
                row: modelData
                showSize: true
                nameBudget: 40
            }
        }
    }

    Column {
        id: gridHost
        y: 100
        Repeater {
            id: gridRep
            model: [root.plain, root.tagged]
            delegate: Flea.GridTile {
                required property var modelData
                width: 160
                height: 120
                row: modelData
                clipMark: ""
            }
        }
    }

    Column {
        id: listHost
        y: 400
        Repeater {
            id: listRep
            model: [root.plain, root.tagged]
            delegate: Flea.Row {
                required property var modelData
                width: 800
                row: modelData
                kindNames: []
                hiddenCols: []
                clipMark: ""
            }
        }
    }

    Column {
        id: menuHost
        y: 500
        Flea.MenuRow { id: plainMenuRow; width: 240; entry: ({ label: "Copy", glyph: "copy", action: "copy", hint: "y" }) }
        Flea.MenuRow {
            id: tagMenuRow
            width: 240
            entry: ({ label: "Red", glyph: "tag", action: "tags", hint: "1", id: "Red", tagRow: { swatch: "Red", fallback: false, state: "applied", digit: "1" } })
        }
    }

    Item { id: railHost; y: 600; width: 260; height: 200 }

    // ui/TagState.qml over a stub pane and backend (tests/tagrows-state.qml, copied in as TagStateProbe.qml).
    TagStateProbe { id: tagProbe; onFailure: function (message) { root.fail(message) } }

    // Seven tags on each delegate kind, measured against the slot or cell they must stay inside.
    Column {
        id: sevenHost
        y: 820
        Flea.Row { id: sevenRow; width: 800; row: root.seven; kindNames: []; hiddenCols: []; clipMark: "" }
        Flea.ColumnRow { id: sevenColumn; width: 280; row: root.seven; showSize: true; nameBudget: 40 }
        Flea.GridTile { id: sevenTile; width: 90; height: 120; row: root.seven; clipMark: "" }
    }

    // The production Tags flyout through the real menu; a binding loop in its fit lands in the log the suite refuses.
    Flea.ContextMenu {
        id: tagsMenu
        width: 800
        height: 600
        workArea: Qt.rect(0, 0, 800, 600)
    }

    // Opens the Tags flyout, then the Sort flyout, through the real menu's own open path; the log gate proves neither fit loops.
    function measureFlyoutFit() {
        var states = TagsLib.statesFor([["Red"], ["Red", "Blue"]])
        tagsMenu.setEntries([
            { label: "Tags", action: "tags", glyph: "tag", submenu: TagsLib.tagEntries(states, Flea.Theme.tag.fallback) },
            { label: "Sort by", action: "sort", submenu: [{ label: "Name" }, { label: "Size" }, { label: "Date" }, { label: "Kind" }] }
        ])
        tagsMenu.openSubmenu(0)
        root.check(tagsMenu.submenuOpen, "flyout: the Tags flyout never opened")
        root.check(tagsMenu.submenuEntries.length === 9, "flyout: the Tags flyout lists " + tagsMenu.submenuEntries.length + " rows, not 9")
        tagsMenu.openSubmenu(1)
        root.check(tagsMenu.submenuEntries.length === 4, "flyout: the Sort flyout lists " + tagsMenu.submenuEntries.length + " rows, not 4")
    }

    QtObject {
        id: railStub
        property var navigationPane: QtObject { property var tagState: QtObject { property var inUse: ({ Red: true, Blue: true }) } }
        property var placesState: ({ showTags: true })
        property var placesEntries: [1, 2, 3, 4, 5, 6, 7]
        property int cursorIndex: -1
        property int litIndex: -1
        readonly property int highlightedIndex: cursorDrawn ? cursorIndex : litIndex
        property bool cursorDrawn: true
        property bool focused: true
        function activate(index) { root.picked.push(index) }
    }

    function fail(message) { failures.push(message) }
    function attempt(step) {
        try { step() } catch (e) { root.fail("threw " + e + " at line " + e.lineNumber) }
    }
    function check(ok, message) { if (!ok) root.fail(message) }

    function count(item) {
        var n = 0
        var stack = [item]
        while (stack.length > 0) {
            var o = stack.pop()
            n += 1
            var kids = (o !== null && o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
            var res = (o !== null && o.resources !== undefined) ? o.resources : []
            for (var j = 0; j < res.length; j++) stack.push(res[j])
        }
        return n
    }

    function swatches(slot) {
        return slot.children.filter(function (c) { return c.width === 14 && c.height === 14 })
    }

    function walk(item, match) {
        var found = []
        var stack = [item]
        while (stack.length > 0) {
            var o = stack.pop()
            if (match(o)) found.push(o)
            var kids = (o !== null && o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
        }
        return found
    }

    function textNamed(item, text) {
        var all = root.walk(item, function (o) { return o.text === text && o.visible })
        return all.length > 0 ? all[0] : null
    }

    // The two delegates of one kind: the first is untagged, the second carries Red and Blue.
    function kind(label, bare, tagged, own) {
        root.check(bare.tagItem === null, label + ": an untagged row holds a tag object")
        root.check(tagged.tagItem !== null, label + ": a tagged row mounted no slot from its first row")
        if (tagged.tagItem === null) return
        var slot = tagged.tagItem
        root.check(slot.tags.length === 2 && root.swatches(slot).length === 2, label + ": the slot does not hold two swatches")
        root.check(slot.width === 31, label + ": two swatches at 14 px and 3 px gaps are 31 wide, not " + slot.width)
        root.check(root.count(tagged) - root.count(bare) === root.count(slot), label + ": a tagged row builds more than its slot over an untagged one")
        root.check(slot.parent === tagged, label + ": the slot is not a child of its row")
        own(slot)
        var kept = slot
        tagged.row = root.triple
        root.check(tagged.tagItem === kept, label + ": a new row built a second slot")
        root.check(kept.tags.length === 3 && root.swatches(kept).length === 3, label + ": three tags do not draw three swatches")
        root.triples.push(kept)
        bare.row = root.tagged
        root.check(bare.tagItem !== null && bare.tagItem.tags.length === 2, label + ": an untagged delegate handed a tagged row mounts no slot")
        bare.row = root.plain
        root.check(bare.tagItem.tags.length === 0 && !bare.tagItem.visible && root.swatches(bare.tagItem).length === 0, label + ": a delegate handed back an untagged row keeps its swatches")
    }

    function measureShape() {
        var gap = Flea.Theme.spacing.gap
        root.kind("columns row", colRep.itemAt(0), colRep.itemAt(1), function (slot) {
            var row = colRep.itemAt(1)
            var name = row.nameItem()
            root.check(Math.abs(slot.x - (name.x + name.contentWidth + gap)) <= 1, "columns row: the swatches do not follow the name text, x=" + slot.x)
            root.check(slot.x + slot.width <= row.width, "columns row: the swatches leave the row")
            root.check(Math.abs((slot.y + slot.height / 2) - (name.y + name.height / 2)) <= 1, "columns row: the swatches are not centred on the name line")
        })
        root.kind("grid tile", gridRep.itemAt(0), gridRep.itemAt(1), function (slot) {
            var tile = gridRep.itemAt(1)
            var label = root.textNamed(tile, "tagged.txt")
            root.check(label !== null, "grid tile: no caption found to place the swatches under")
            if (label === null) return
            root.check(Math.abs((slot.x + slot.width / 2) - tile.width / 2) <= 1, "grid tile: the swatches are not centred under the name, x=" + slot.x)
            root.check(slot.y >= label.y + label.height - 1, "grid tile: the swatches sit over the caption")
            root.shape.gridBottom = slot.y + slot.height
            root.shape.gridHeight = tile.height
        })
        root.kind("list row", listRep.itemAt(0), listRep.itemAt(1), function (slot) {
            var row = listRep.itemAt(1)
            var mode = row.cell("mode")
            var size = row.cell("size")
            root.check(Math.abs(slot.x - (mode.x + mode.width + gap)) <= 1, "list row: the slot does not start where Mode ends, x=" + slot.x)
            root.check(slot.x + Flea.Theme.tagSlotWidth <= size.x + 1, "list row: the 88 px slot runs into Size, slot=" + slot.x + " size=" + size.x)
            root.check(Math.abs((slot.y + slot.height / 2) - (mode.y + mode.height / 2)) <= 1, "list row: the swatches are not centred on the row")
        })
        // A row with no tag but a stood slot still reserves the 88 px, so the name column does not move.
        root.check(listRep.itemAt(0).nameRight() === listRep.itemAt(1).nameRight(), "list row: the name ends at different places with and without tags")
    }

    // The 88 px slot holds five whole swatches, so seven tags draw five and never reach Size; a tile never leaves its cell.
    function measureSeven() {
        var room = Flea.Theme.tagSlotWidth
        var slot = sevenRow.tagItem
        root.check(slot !== null, "seven tags: the list row mounted no slot")
        if (slot !== null) {
            var size = sevenRow.cell("size")
            root.check(slot.width <= room, "seven tags: the list slot is " + slot.width + " wide, past the reserved " + room)
            root.check(slot.x + slot.width <= size.x, "seven tags: the list swatches run into Size, slot ends " + (slot.x + slot.width) + " size=" + size.x)
            root.check(root.swatches(slot).length === 5, "seven tags: the list slot draws " + root.swatches(slot).length + " swatches, not the 5 that fit")
        }
        var cslot = sevenColumn.tagItem
        root.check(cslot !== null, "seven tags: the columns row mounted no slot")
        if (cslot !== null) {
            var name = sevenColumn.nameItem()
            root.check(cslot.width <= room, "seven tags: the columns slot is " + cslot.width + " wide, past the reserved " + room)
            root.check(cslot.x + cslot.width <= name.x + name.width + Flea.Theme.spacing.gap + room, "seven tags: the columns swatches run past the reserved slot")
        }
        var tslot = sevenTile.tagItem
        root.check(tslot !== null, "seven tags: the grid tile mounted no slot")
        if (tslot !== null)
            root.check(tslot.x >= 0 && tslot.x + tslot.width <= sevenTile.width, "seven tags: the tile swatches leave the " + sevenTile.width + " px cell, x=" + tslot.x + " width=" + tslot.width)
    }

    function measureMenu() {
        root.check(plainMenuRow.tagItem === null, "menu row: a plain row mounted a tag part")
        root.check(tagMenuRow.tagItem !== null, "menu row: a tag row mounted no tag part")
        if (tagMenuRow.tagItem === null) return
        var part = tagMenuRow.tagItem
        var hint = root.textNamed(tagMenuRow, "1")
        root.check(part.width === 14 && part.height === 14, "menu row: the rule-14 box is not 14 x 14")
        root.check(hint !== null && part.x + part.width <= hint.x + 1, "menu row: the box is not before the digit hint")
        root.check(part.visible, "menu row: the tag part is hidden on a tag row")
        var kept = part
        tagMenuRow.entry = ({ label: "Blue", glyph: "tag", action: "tags", hint: "5", id: "Blue", tagRow: { swatch: "Blue", fallback: false, state: "mixed", digit: "5" } })
        root.check(tagMenuRow.tagItem === kept, "menu row: a second tag entry built a second part")
        tagMenuRow.entry = ({ label: "Copy", glyph: "copy", action: "copy", hint: "y" })
        root.check(!kept.visible, "menu row: a tag part stays drawn once its row carries a plain entry")
        tagMenuRow.entry = ({ label: "Red", glyph: "tag", action: "tags", hint: "1", id: "Red", tagRow: { swatch: "Red", fallback: false, state: "applied", digit: "1" } })
    }

    function measureRail() {
        var section = Qt.createComponent("flea/TagRailSection.qml").createObject(railHost, { sidebar: railStub })
        root.check(section !== null, "rail: the TAGS section did not build")
        if (section === null) return
        root.check(section.entries.length === 2 && section.base === 5, "rail: the section lists " + section.entries.length + " rows from base " + section.base)
        var first = section.itemAt(0)
        var second = section.itemAt(1)
        root.check(first !== null && second !== null && section.itemAt(2) === null, "rail: the section does not hold one row per tag in use")
        if (first === null) return
        first.activated(first.index)
        root.check(root.picked.length === 1 && root.picked[0] === 5, "rail: a tag row activates at its place among the entries, not " + root.picked)
        var marks = root.walk(first, function (o) { return o.width === 14 && o.height === 14 })
        root.check(marks.length === 1, "rail: a tag row draws " + marks.length + " swatches in its mark slot: " + root.walk(first, function (o) { return true }).map(function (o) { return String(o).split("(")[0] + ":" + o.width + "x" + o.height }).join(","))
        root.railSection = section
    }

    property var railSection: null

    // Show tags off hides the TAGS rows live and on shows them again; the section stays built, so this pins visibility, not a rebuild.
    function measureRailShowTags() {
        var section = root.railSection
        root.check(section !== null, "rail showTags: the TAGS section was never built")
        if (section === null) return
        root.check(section.visible, "rail showTags: the TAGS section is not visible with Show tags on")
        railStub.placesState = ({ showTags: false })
        root.check(!section.visible, "rail showTags: switching Show tags off leaves the TAGS rows drawn")
        railStub.placesState = ({ showTags: true })
        root.check(section.visible, "rail showTags: switching Show tags back on leaves the TAGS rows hidden")
    }

    // The rail moving to no pane, or to a pane with no tag state, lists no TAGS rows instead of throwing.
    function measureRailNoPane() {
        var section = root.railSection
        if (section === null) return
        var kept = railStub.navigationPane
        railStub.navigationPane = null
        root.check(section.entries.length === 0, "rail no pane: the section lists " + section.entries.length + " rows with no pane")
        root.check(!section.visible && section.height === 0, "rail no pane: an empty TAGS heading stays drawn or reserved, height " + section.height)
        railStub.navigationPane = ({ tagState: null })
        root.check(section.entries.length === 0, "rail no pane: the section lists " + section.entries.length + " rows for a pane with no tag state")
        root.check(!section.visible && section.height === 0, "rail no tag state: an empty TAGS heading stays drawn or reserved, height " + section.height)
        railStub.navigationPane = kept
        root.check(section.entries.length === 2, "rail no pane: the section lists " + section.entries.length + " rows once the tagged pane returns")
        root.check(section.visible && section.height > 0, "rail no pane: the TAGS section stays hidden once the tagged pane returns")
    }

    function colours() {
        var cells = root.swatches(colRep.itemAt(1).tagItem)
        root.check(cells.length === 2, "colours: the columns row holds " + cells.length + " swatches")
        root.check(cells.length === 2 && String(cells[0].color) === "#ff0000" && String(cells[1].color) === "#0000ff", "colours: the swatches do not take Theme.tag.colors")
        var marks = root.walk(root.railSection.itemAt(0), function (o) { return o.width === 14 && o.height === 14 })
        root.check(marks.length === 1 && String(marks[0].color) === "#ff0000", "colours: the rail swatch does not take Theme.tag.menuColors")
        var box = root.walk(tagMenuRow, function (o) { return o.width === 14 && o.height === 14 && String(o.color) === "#ff0000" })
        root.check(box.length === 1, "colours: the flyout row draws " + box.length + " red swatches")
    }

    function digits() {
        var slot = colRep.itemAt(1).tagItem
        var cells = root.swatches(slot)
        root.check(cells[0].border.width === 2 && cells[0].color.a === 0, "fallback: a swatch is not an outlined square")
        var one = root.walk(cells[0], function (o) { return o.text === "1" && o.visible })
        var five = root.walk(cells[1], function (o) { return o.text === "5" && o.visible })
        root.check(one.length === 1 && five.length === 1, "fallback: the swatches do not carry their digits")
        var plainSlot = root.walk(gridRep.itemAt(1).tagItem, function (o) { return o.text !== undefined && o.visible && o.text !== "" })
        root.check(plainSlot.length === 2, "fallback: a tile draws " + plainSlot.length + " digits for two tags")
    }

    Timer {
        interval: 800
        running: true
        repeat: false
        onTriggered: {
            root.attempt(root.measureShape)
            root.attempt(root.measureSeven)
            root.attempt(root.measureMenu)
            root.attempt(root.measureRail)
            root.attempt(root.measureRailShowTags)
            root.attempt(root.measureRailNoPane)
            root.attempt(tagProbe.measureAnswers)
            root.attempt(tagProbe.measureRead)
            root.attempt(tagProbe.measureWalk)
            root.attempt(root.measureFlyoutFit)
            Flea.Theme.tag = { colors: root.palette, menuColors: root.palette, fallback: false }
            step.start()
        }
    }

    function reused() {
        for (var i = 0; i < root.triples.length; i++) {
            var kept = root.triples[i]
            root.check(kept.width === 48, "a reused slot with three tags is " + kept.width + " wide, not 48")
            kept.parent.row = root.plain
            root.check(kept.tags.length === 0 && !kept.visible && root.swatches(kept).length === 0, "a reused slot handed an untagged row keeps its swatches")
            kept.parent.row = root.tagged
        }
    }

    function settled() {
        for (var i = 0; i < root.triples.length; i++)
            root.check(root.triples[i].width === 31, "a reused slot with two tags is " + root.triples[i].width + " wide, not 31")
        root.colours()
    }

    Timer {
        id: step
        interval: 300
        repeat: false
        onTriggered: {
            if (root.phase === 0) {
                root.attempt(root.reused)
            } else if (root.phase === 1) {
                root.attempt(root.settled)
                Flea.Theme.tag = { colors: root.palette, menuColors: root.palette, fallback: true }
            } else {
                root.attempt(root.digits)
                root.report()
                return
            }
            root.phase += 1
            step.start()
        }
    }

    function report() {
        if (failures.length === 0)
            console.log("TAGROWS PASS grid=" + root.shape.gridBottom + "/" + root.shape.gridHeight)
        for (var f = 0; f < failures.length; f++)
            console.log("TAGROWS FAIL " + failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
