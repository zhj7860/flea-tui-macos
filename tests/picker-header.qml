//@ pragma ShellId flea-picker-header-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Picker.js" as Picker

// The real picker window: grid draws no header, tiles start one gap under the strip; a view round trip keeps the sort and cursor.
ShellRoot {
    id: root

    property var failures: []
    property int stage: 0
    property double stageSince: 0
    property var winShell: null
    property var win: null
    property bool reported: false
    // A cursor row other than 0, which a reset to the top would also produce.
    readonly property int cursorProbe: 3
    readonly property string probeSort: "size"
    readonly property int waitMs: 5000
    readonly property int probeTimeoutMs: 30000
    // Pixel slack for a mapped coordinate, which Qt reports as a real.
    readonly property real geometryTolerance: 0.5
    // The strip is laid out on whole pixels and the board's own centring rounds, so a probe allows one.
    readonly property real inlineTolerance: 1
    // Picker040's strip height at base size 14.
    readonly property int boardStripHeight: 27
    // Float noise only: the centring check compares against the whole pixel the board's anchors give.
    readonly property real centreEpsilon: 0.01
    // Far wider than any window: 40 directories of 14 characters.
    readonly property string longParents: "/" + new Array(41).join("directory-name/")
    readonly property string longLeaf: new Array(60).join("a-very-long-file-name-")

    function fail(text) { root.failures.push(text) }
    function late() { return Date.now() - root.stageSince > root.waitMs }
    function go(stage) { root.stage = stage; root.stageSince = Date.now() }

    // The first item under item whose QML type name starts with name, found without an id.
    function findType(item, name) {
        if (String(item).indexOf(name + "_QMLTYPE") === 0) return item
        for (var i = 0; i < item.children.length; i++) {
            var hit = root.findType(item.children[i], name)
            if (hit) return hit
        }
        return null
    }
    function under(item, ancestor) {
        for (var at = item; at; at = at.parent) if (at === ancestor) return true
        return false
    }
    // The first item under item with this object name, found without reading user text.
    function findName(item, name) {
        if (item.objectName === name) return item
        for (var i = 0; i < item.children.length; i++) {
            var hit = root.findName(item.children[i], name)
            if (hit) return hit
        }
        return null
    }
    function header() { return root.findType(root.win.contentItem, "PickerHeader") }
    // A 10 ms probe can read new text before Row's next polish; measure only after its pending layout.
    function pathStrip(chrome) {
        var strip = root.findName(chrome, "pickerStrip")
        if (strip) strip.forceLayout()
        return strip
    }

    // The strip's recipe from Picker040 at base size 14: board height, the path one gap after Back and Up, the leaf inline after its parents, centred above the rule.
    function checkGeometry(tag, chrome, strip) {
        var where = root.findName(chrome, "pickerWhere")
        var back = root.findName(chrome, "pickerBack")
        var parents = strip.children[0], leaf = strip.children[1]
        if (!where || !back) return false
        if (where.height !== root.boardStripHeight) root.fail(tag + ": the strip is " + where.height + " px tall, want the board's " + root.boardStripHeight)
        if (where.height !== Flea.Theme.chromeHeight) root.fail(tag + ": the strip is " + where.height + " px tall, want the chrome height " + Flea.Theme.chromeHeight)
        var start = strip.mapToItem(where, 0, 0).x
        var want = Flea.Theme.spacing.rowPaddingX + 2 * back.width + 2 * Flea.Theme.spacing.gap
        if (Math.abs(start - want) > root.inlineTolerance) root.fail(tag + ": the path starts at x " + start + ", want " + want + " after Back and Up")
        // Where the parents' drawn text ends, not where their box does: a box wider than its text is the leaf drawn apart. An elided run fills its box.
        var seam = parents.visible ? parents.x + (parents.truncated ? parents.width : parents.contentWidth) : 0
        if (Math.abs(leaf.x - seam) > root.inlineTolerance)
            root.fail(tag + ": the leaf is at x " + leaf.x + ", want " + seam + " right after its parents' text")
        // Qt centres on the parent's rounded half less the strip's rounded half, then adds the offset unrounded.
        var top = strip.mapToItem(where, 0, 0).y
        var wantTop = Math.round(where.height / 2) - Math.round(strip.height / 2) - Flea.Theme.spacing.hairline / 2
        if (Math.abs(top - wantTop) > root.centreEpsilon) root.fail(tag + ": the path top is at y " + top + ", want " + wantTop + " in the band above the rule")
        return true
    }
    // The path strip lights only its leaf over /winprobe; false while the strip is unbuilt.
    function checkStrip(tag) {
        var chrome = root.findType(root.win.contentItem, "PickerChrome")
        if (!chrome) return false
        var strip = root.pathStrip(chrome)
        if (!strip || strip.width <= 0 || !strip.visible) return false
        if (strip.children.length < 2) return false
        var parents = strip.children[0], leaf = strip.children[1]
        if (leaf.width <= 0 || leaf.text.length === 0) return false
        if (strip.display !== parents.text + leaf.text)
            root.fail(tag + ": the strip draws " + parents.text + leaf.text + ", want " + strip.display)
        if (parents.text !== "/") root.fail(tag + ": parents " + parents.text + ", want /")
        if (leaf.text !== "winprobe") root.fail(tag + ": leaf " + leaf.text + ", want winprobe")
        // A short path is one run at the strip's left: its text ends well short of the right edge.
        if (leaf.x + leaf.width > strip.width / 2) root.fail(tag + ": the short path ends at x " + (leaf.x + leaf.width) + " of a " + strip.width + " strip, want it at the left")
        if (!Qt.colorEqual(parents.color, Flea.Theme.color.muted))
            root.fail(tag + ": parents ink " + parents.color + ", want muted")
        if (!Qt.colorEqual(leaf.color, Flea.Theme.color.foreground))
            root.fail(tag + ": leaf ink " + leaf.color + ", want foreground")
        if (!root.checkGeometry(tag, chrome, strip)) return false
        var up = root.findName(chrome, "pickerUp")
        var back = root.findName(chrome, "pickerBack")
        var list = root.findName(chrome, "pickerListView")
        var grid = root.findName(chrome, "pickerGridView")
        if (!up || !back || !list || !grid) return false
        if (!up.enabled) root.fail(tag + ": Up is disabled over /winprobe, want live")
        else if (!Qt.colorEqual(up.markItem.color, Flea.Theme.color.foreground))
            root.fail(tag + ": live Up ink " + up.markItem.color + ", want foreground")
        if (back.enabled) root.fail(tag + ": Back is live with an empty history, want disabled")
        else {
            if (!Qt.colorEqual(back.markItem.color, Flea.Theme.color.mutedFrame))
                root.fail(tag + ": dead Back ink " + back.markItem.color + ", want muted")
            if (Math.abs(back.markItem.opacity - Flea.Theme.disabledOpacity) > 0.001)
                root.fail(tag + ": dead Back opacity " + back.markItem.opacity + ", want " + Flea.Theme.disabledOpacity)
        }
        if (list.lit) root.fail(tag + ": the list mark is lit in grid mode, want unlit")
        else if (!Qt.colorEqual(list.markItem.color, Flea.Theme.color.mutedFrame))
            root.fail(tag + ": unlit list ink " + list.markItem.color + ", want muted")
        if (!grid.lit) root.fail(tag + ": the grid mark is unlit in grid mode, want lit")
        else if (!Qt.colorEqual(grid.markItem.color, Flea.Theme.color.foreground))
            root.fail(tag + ": lit grid ink " + grid.markItem.color + ", want foreground")
        return true
    }
    // A deeper path keeps the same split: parents hold the directories, the leaf the last name.
    function checkDeep(tag) {
        var chrome = root.findType(root.win.contentItem, "PickerChrome")
        if (!chrome) return false
        var strip = root.pathStrip(chrome)
        if (!strip || strip.width <= 0 || !strip.visible) return false
        if (strip.children.length < 2) return false
        if (strip.display !== "/a/b/winprobe") return false
        var parents = strip.children[0], leaf = strip.children[1]
        if (parents.text !== "/a/b/") root.fail(tag + ": parents " + parents.text + ", want /a/b/")
        if (leaf.text !== "winprobe") root.fail(tag + ": leaf " + leaf.text + ", want winprobe")
        if (!Qt.colorEqual(parents.color, Flea.Theme.color.muted))
            root.fail(tag + ": parents ink " + parents.color + ", want muted")
        if (!Qt.colorEqual(leaf.color, Flea.Theme.color.foreground))
            root.fail(tag + ": leaf ink " + leaf.color + ", want foreground")
        return root.checkGeometry(tag, chrome, strip)
    }
    // Parents too long for the strip elide from the left and the leaf stays whole: the pair fills the strip, ends at its right edge.
    function checkLongParents(tag) {
        var chrome = root.findType(root.win.contentItem, "PickerChrome")
        if (!chrome) return false
        var strip = root.pathStrip(chrome)
        if (!strip || strip.width <= 0 || !strip.visible || strip.children.length < 2) return false
        if (strip.display !== root.longParents + "winprobe") return false
        var parents = strip.children[0], leaf = strip.children[1]
        if (leaf.text !== "winprobe") root.fail(tag + ": leaf " + leaf.text + ", want winprobe")
        if (leaf.truncated || Math.abs(leaf.width - leaf.implicitWidth) > root.inlineTolerance)
            root.fail(tag + ": the leaf is cut to " + leaf.width + " of " + leaf.implicitWidth + ", want it whole")
        if (!parents.truncated) root.fail(tag + ": the parents are not elided in a strip narrower than they are")
        if (parents.elide !== Text.ElideLeft) root.fail(tag + ": the parents elide " + parents.elide + ", want from the left")
        if (Math.abs(parents.width + leaf.width - strip.width) > root.inlineTolerance)
            root.fail(tag + ": parents " + parents.width + " plus leaf " + leaf.width + " fill " + (parents.width + leaf.width) + " of " + strip.width)
        if (Math.abs(leaf.x + leaf.width - strip.width) > root.inlineTolerance)
            root.fail(tag + ": the leaf ends at " + (leaf.x + leaf.width) + ", want the strip's right edge " + strip.width)
        return root.checkGeometry(tag, chrome, strip)
    }
    // A leaf wider than the strip takes all of it and gives the parents none.
    function checkLongLeaf(tag) {
        var chrome = root.findType(root.win.contentItem, "PickerChrome")
        if (!chrome) return false
        var strip = root.pathStrip(chrome)
        if (!strip || strip.width <= 0 || !strip.visible || strip.children.length < 2) return false
        if (strip.display !== "/a/" + root.longLeaf) return false
        var parents = strip.children[0], leaf = strip.children[1]
        if (leaf.text !== root.longLeaf) root.fail(tag + ": the leaf text was changed")
        if (!leaf.truncated || Math.abs(leaf.width - strip.width) > root.inlineTolerance)
            root.fail(tag + ": the leaf is " + leaf.width + " wide of a " + strip.width + " strip, want it to take all of it, cut")
        if (leaf.elide !== Text.ElideMiddle) root.fail(tag + ": the leaf elides " + leaf.elide + ", want from the middle")
        if (parents.width > root.inlineTolerance) root.fail(tag + ": the parents keep " + parents.width + " px, want none")
        return true
    }
    // With a history, Back is live and rests in the foreground like the main chrome.
    function checkBackLit(tag) {
        var chrome = root.findType(root.win.contentItem, "PickerChrome")
        var back = chrome ? root.findName(chrome, "pickerBack") : null
        if (!back || root.win.history.length === 0) return false
        if (!back.enabled) root.fail(tag + ": Back is dead with a history of " + root.win.history.length)
        else if (!Qt.colorEqual(back.markItem.color, Flea.Theme.color.foreground))
            root.fail(tag + ": live Back ink " + back.markItem.color + ", want foreground")
        if (back.markItem.opacity !== 1) root.fail(tag + ": live Back opacity " + back.markItem.opacity + ", want 1")
        return true
    }
    // Recent is one lit word with no parents; false while the strip still shows a path.
    function checkRecent(tag) {
        var chrome = root.findType(root.win.contentItem, "PickerChrome")
        if (!chrome) return false
        var strip = root.pathStrip(chrome)
        if (!strip || strip.width <= 0 || !strip.visible) return false
        if (strip.children.length < 2) return false
        if (strip.display !== Picker.RECENT_LABEL) return false
        var parents = strip.children[0], leaf = strip.children[1]
        if (parents.text !== "") root.fail(tag + ": parents " + parents.text + ", want empty")
        if (parents.visible) root.fail(tag + ": parents are shown in Recent, want hidden")
        if (leaf.text !== Picker.RECENT_LABEL) root.fail(tag + ": leaf " + leaf.text + ", want " + Picker.RECENT_LABEL)
        if (!Qt.colorEqual(leaf.color, Flea.Theme.color.foreground))
            root.fail(tag + ": leaf ink " + leaf.color + ", want foreground")
        return true
    }

    // Grid mode: no header, tile 0 one gap under the path strip, Tab reaches the grid; false while tile 0 is unbuilt.
    function checkGrid(tag) {
        var head = root.header()
        var chrome = root.findType(root.win.contentItem, "PickerChrome")
        var rail = root.findType(root.win.contentItem, "PickerPlaces").focusItem
        var gview = root.win.viewItem()
        // The cursor may have scrolled the grid, so measure tile 0 at the start.
        gview.contentY = gview.originY - gview.topMargin
        var tile = gview.itemAtIndex(0)
        if (!tile) return false
        if (head.visible) root.fail(tag + ": grid mode draws the column header")
        if (head.height !== 0) root.fail(tag + ": grid mode header takes height " + head.height + ", want 0")
        var tileTop = tile.mapToItem(root.win.contentItem, 0, 0).y
        var want = chrome.mapToItem(root.win.contentItem, 0, chrome.height).y + Flea.Theme.spacing.gap
        if (Math.abs(tileTop - want) > root.geometryTolerance)
            root.fail(tag + ": first tile top " + tileTop + ", want " + want + " (path strip bottom plus gap)")
        // Tab walks the picker's own chain from its first control, never a header control, and reaches the grid within one lap.
        var window = root.win.contentItem.Window.window
        var chain = chrome.focusItems().concat([rail, gview])
            .filter(function(item) { return item.visible && item.enabled && item.activeFocusOnTab })
        var reached = false
        chain[0].forceActiveFocus(Qt.TabFocusReason)
        if (root.under(window.activeFocusItem, gview)) root.fail(tag + ": the Tab walk began inside the grid")
        for (var step = 0; step < chain.length && !reached; step++) {
            var from = window.activeFocusItem
            // A rail row holds focus inside the rail, whose own Tab handler is the one that steps.
            if (root.under(from, rail)) from = rail
            root.win.stepFocus(from, false)
            var at = window.activeFocusItem
            if (at && root.under(at, head)) { root.fail(tag + ": Tab landed on the hidden header"); break }
            reached = at && root.under(at, gview)
        }
        if (!reached) root.fail(tag + ": Tab never reached the grid")
        return true
    }
    // List mode: the header at its implicit height, the rows starting directly under it; false while the cursor row is unbuilt.
    function checkList(tag) {
        var head = root.header()
        if (!root.win.viewItem().itemAtIndex(root.win.cursorIndex)) return false
        if (!head.visible) root.fail(tag + ": list mode lost the column header")
        if (head.implicitHeight <= 0 || Math.abs(head.height - head.implicitHeight) > root.geometryTolerance)
            root.fail(tag + ": list header height " + head.height + ", want implicit " + head.implicitHeight)
        // The list's own top is its first row's slot, whichever row the cursor scrolled to.
        var rowsTop = root.win.viewItem().mapToItem(root.win.contentItem, 0, 0).y
        var headBottom = head.mapToItem(root.win.contentItem, 0, head.height).y
        if (Math.abs(rowsTop - headBottom) > root.geometryTolerance)
            root.fail(tag + ": rows start at " + rowsTop + ", want the header bottom " + headBottom)
        return true
    }
    // The sort the header click set and the cursor set in grid, which a view switch must leave as they were.
    function checkKept(tag) {
        var head = root.header()
        if (head.sortBy !== root.probeSort || head.sortDesc !== false)
            root.fail(tag + ": the sort mark became " + head.sortBy + "/" + head.sortDesc + ", want " + root.probeSort + "/false")
        if (head.title("Size", "size") !== "Size \u25b4") root.fail(tag + ": the header draws " + head.title("Size", "size") + " for the sort")
        if (root.win.cursorIndex !== root.cursorProbe)
            root.fail(tag + ": the cursor moved to " + root.win.cursorIndex + ", want " + root.cursorProbe)
    }

    Timer {
        id: ticker
        interval: 10
        repeat: true
        running: true
        onTriggered: root.step()
    }
    Timer { interval: root.probeTimeoutMs; running: true; onTriggered: { root.fail("probe timed out in stage " + root.stage); root.report() } }

    function step() {
        if (root.failures.length > 0) { root.report(); return }
        switch (root.stage) {
        case 0: {
            var comp = Qt.createComponent("flea/PickerWindow.qml")
            if (comp.status !== Component.Ready) { root.fail("PickerWindow does not compile: " + comp.errorString()); return }
            root.winShell = comp.createObject(root)
            if (!root.winShell) { root.fail("PickerWindow did not instantiate: " + comp.errorString()); return }
            root.win = root.winShell.pickerWin
            root.go(1)
            return
        }
        case 1: {
            // The window launches in grid, from the state file the suite seeds.
            if (root.win.viewMode !== "grid" || root.win.total === 0 || root.win.rows.length === 0) {
                if (root.late()) root.fail("the window never listed in grid mode")
                return
            }
            if (!root.checkGrid("grid")) { if (root.late()) root.fail("grid: tile 0 never built"); return }
            if (!root.checkStrip("strip")) { if (root.late()) root.fail("strip: the path strip never built"); return }
            root.win.setView("list")
            root.go(2)
            return
        }
        case 2: {
            if (root.win.viewMode !== "list") { root.fail("setView list never switched view"); return }
            if (!root.checkList("list")) { if (root.late()) root.fail("list: the cursor row never built"); return }
            // The header's own click path: it asks the window for the order, which re-lists.
            root.header().sortRequested(root.probeSort)
            root.go(5)
            return
        }
        case 5: {
            if (root.win.pendingListings !== 0 || root.win.total === 0 || root.win.rows.length === 0) {
                if (root.late()) root.fail("the sorted listing never arrived")
                return
            }
            root.win.setView("grid")
            root.go(3)
            return
        }
        case 3: {
            if (root.win.viewMode !== "grid") { root.fail("setView grid never switched view"); return }
            root.win.cursorIndex = root.cursorProbe
            if (!root.checkGrid("grid")) { if (root.late()) root.fail("grid: tile 0 never built"); return }
            root.checkKept("grid")
            root.win.setView("list")
            root.go(4)
            return
        }
        case 4: {
            if (root.win.viewMode !== "list") { root.fail("round trip never returned to list"); return }
            if (!root.checkList("round trip list")) { if (root.late()) root.fail("round trip list: the cursor row never built"); return }
            root.checkKept("round trip list")
            root.win.setView("grid")
            root.go(6)
            return
        }
        case 6: {
            if (root.win.viewMode !== "grid") { root.fail("second setView grid never switched view"); return }
            if (!root.checkGrid("round trip grid")) { if (root.late()) root.fail("round trip grid: tile 0 never built"); return }
            root.checkKept("round trip grid")
            root.win.setView("list")
            root.go(7)
            return
        }
        case 7: {
            if (root.win.viewMode !== "list") { root.fail("second round trip never returned to list"); return }
            if (!root.checkList("second round trip list")) { if (root.late()) root.fail("second round trip list: the cursor row never built"); return }
            root.checkKept("second round trip list")
            root.win.openWithoutHistory("/a/b/winprobe")
            root.go(8)
            return
        }
        case 8: {
            if (!root.checkDeep("deep")) { if (root.late()) root.fail("deep: the strip never showed /a/b/winprobe"); return }
            root.win.openWithoutHistory(root.longParents + "winprobe")
            root.go(10)
            return
        }
        case 10: {
            if (!root.checkLongParents("long parents")) { if (root.late()) root.fail("long parents: the strip never showed the long path"); return }
            root.win.openWithoutHistory("/a/" + root.longLeaf)
            root.go(11)
            return
        }
        case 11: {
            if (!root.checkLongLeaf("long leaf")) { if (root.late()) root.fail("long leaf: the strip never showed the long name"); return }
            root.win.open("/a/b")
            root.go(12)
            return
        }
        case 12: {
            if (!root.checkBackLit("history")) { if (root.late()) root.fail("history: Back never had a history"); return }
            root.win.openWithoutHistory(Picker.RECENT)
            root.go(9)
            return
        }
        case 9: {
            if (!root.checkRecent("recent")) { if (root.late()) root.fail("recent: the strip never showed Recent"); return }
            root.report()
            return
        }
        }
    }

    function report() {
        // One report: the repeat timer is stopped and a late timeout cannot print a second verdict.
        if (root.reported) return
        root.reported = true
        ticker.stop()
        if (root.failures.length === 0) {
            console.log("PICKERHEADER PASS grid header hidden, tiles under the strip, list header restored")
        } else {
            for (var i = 0; i < root.failures.length; i++)
                console.log("PICKERHEADER FAIL " + root.failures[i])
        }
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
