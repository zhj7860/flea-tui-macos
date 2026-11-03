//@ pragma ShellId flea-keyreach-test
import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "flea/js/ChromeKeys.js" as ChromeKeys

// Tab walks list, rail, chrome bar and tab strip in the real WindowBody; each stop answers its keys, draws its own frame inside its host, and Right Arrow reaches a mounted row's eject mark.
ShellRoot {
    id: root
    readonly property string fixture: Quickshell.env("HOME") + "/fixture"
    readonly property var pane: body.currentPane
    readonly property var chrome: body.currentPane.chromeBar
    readonly property var strip: body.currentPane.tabStrip
    readonly property int hairline: Flea.Theme.spacing.hairline
    // The chrome controls with the first one disabled: no history yet, a parent above the fixture, not the grid.
    readonly property string listControls: "arrow-up,search,list,columns,grid,dual,sliders"
    readonly property int stallTicks: 200
    property int checks: 0
    property var failures: []
    property int index: 0
    property int ticks: 0
    property var plan: []
    // A key can run the event loop, so a tick that lands inside a step must not start it again.
    property bool stepping: false
    property var counts: ({ up: 0, back: 0, search: 0, filter: 0, sort: 0, views: [], settings: 0 })

    function check(cond, label) {
        root.checks++
        if (!cond) { root.failures.push(label); console.log("KEYREACH FAIL " + label) }
    }
    function same(got, want, label) { root.check(got === want, label + ": got " + got + ", want " + want) }
    function key(code, mods) { driver.keyClick(code, mods === undefined ? Qt.NoModifier : mods, -1) }
    function ready() { return !pane.listInFlight && pane.path === fixture && pane.listingState === "ready" }
    function view() { return pane.focusView + (pane.focusView === "chrome" ? ":" + chrome.focusedGlyph : pane.focusView === "strip" ? ":" + strip.focusedIndex : "") }
    function glyphs() { return ChromeKeys.controls(chrome).join(",") }
    // Presses Right or Left until the bar's keyboard focus is on glyph; false when it never gets there.
    function reach(glyph) {
        var live = ChromeKeys.controls(chrome)
        var from = live.indexOf(chrome.focusedGlyph), to = live.indexOf(glyph)
        if (to < 0) return false
        for (var i = from; i !== to; i += to > from ? 1 : -1) root.key(to > from ? Qt.Key_Right : Qt.Key_Left)
        return chrome.focusedGlyph === glyph
    }
    // A frame is whole inside its host and clear of every edge by at least a pixel, with a pixel to spare beside any ink the host names.
    function inside(tag, item, host, width, height) {
        var box = item.mapToItem(host, 0, 0, item.width, item.height)
        root.check(box.x >= 1 && box.y >= 1 && box.x + box.width <= width - 1 && box.y + box.height <= height - 1,
                   tag + " frame " + box.x + "," + box.y + " " + box.width + "x" + box.height + " is not inside " + width + "x" + height)
        return box
    }
    function foregroundFrame(tag, frame) {
        root.check(frame.visible && Qt.colorEqual(frame.border.color, Flea.Theme.color.foreground) && frame.border.width === root.hairline,
                   tag + " frame is not one foreground hairline")
    }
    function tabFrame(tag, i) {
        var tab = strip.itemAt(i)
        var box = root.inside(tag, tab.focusFrame, tab, tab.width, tab.height)
        root.foregroundFrame(tag, tab.focusFrame)
        // The accent edge fills the tab's bottom rows and the separator its right column.
        root.check(box.y + box.height <= tab.height - Flea.Theme.accentEdge - 1, tag + " frame touches the accent edge")
        root.check(box.x + box.width <= tab.width - 1 - 1, tag + " frame touches the separator")
    }
    function ringsOnBar() {
        var seen = 0
        var live = ChromeKeys.ORDER
        for (var i = 0; i < live.length; i++) {
            var mark = chrome.buttonFor(live[i])
            if (mark && mark.ringItem.visible) seen++
        }
        return seen
    }

    // The plan: a function that returns false waits for the next tick, anything else moves on.
    function build() {
        var p = []
        function act(label, fn) { p.push({ label: label, fn: function () { fn(); return true } }) }
        function wait(label, cond) { p.push({ label: label, fn: cond }) }
        function press(code, mods, expect, label) { act(label, function () { root.key(code, mods); root.same(root.view(), expect, label) }) }
        wait("the window lists the fixture", function () { return root.ready() && root.chrome !== null && root.pane.sidebar !== null })
        act("keyboard to the list", function () { pane.forceActiveFocus() })

        // One tab, a rail, the bar: three stops forward and three back.
        press(Qt.Key_Tab, Qt.NoModifier, "rail", "Tab from the list reaches the rail")
        press(Qt.Key_Tab, Qt.NoModifier, "chrome:arrow-up", "Tab reaches the bar on its first live control")
        press(Qt.Key_Tab, Qt.NoModifier, "list", "Tab skips a strip of one tab and returns to the list")
        press(Qt.Key_Backtab, Qt.ShiftModifier, "chrome:sliders", "Shift+Tab from the list reaches the bar on its last control")
        press(Qt.Key_Backtab, Qt.ShiftModifier, "rail", "Shift+Tab reaches the rail")
        press(Qt.Key_Backtab, Qt.ShiftModifier, "list", "Shift+Tab returns to the list")
        act("the bar's controls", function () { root.key(Qt.Key_Tab); root.key(Qt.Key_Tab); root.same(root.glyphs(), root.listControls, "live controls") })
        act("each control draws one foreground frame inside the bar", function () {
            var live = ChromeKeys.controls(chrome)
            for (var i = 0; i < live.length; i++) {
                root.check(root.reach(live[i]), live[i] + " was not reached by the keyboard")
                var ring = chrome.buttonFor(live[i]).ringItem
                root.check(ring.visible, live[i] + " ring is not visible")
                root.check(root.ringsOnBar() === 1, live[i] + " is not the only framed control")
                root.inside(live[i], ring, chrome, chrome.width, chrome.height - root.hairline)
                root.check(Qt.colorEqual(ring.border.color, Flea.Theme.color.foreground), live[i] + " frame is not foreground")
            }
        })
        act("Home, End and the ends of the bar", function () {
            root.key(Qt.Key_Home); root.same(root.view(), "chrome:arrow-up", "Home")
            root.key(Qt.Key_Left); root.same(root.view(), "chrome:arrow-up", "Left on the first control stays")
            root.key(Qt.Key_End); root.same(root.view(), "chrome:sliders", "End")
            root.key(Qt.Key_Right); root.same(root.view(), "chrome:sliders", "Right on the last control stays")
            root.key(Qt.Key_J); root.key(Qt.Key_Down); root.same(root.view(), "chrome:sliders", "every other key does nothing")
            root.key(Qt.Key_Home)
        })

        // Presses by keyboard.
        act("Up from the bar", function () { root.key(Qt.Key_Return) })
        wait("the parent is listed", function () { return !pane.listInFlight && pane.path !== root.fixture && pane.listingState === "ready" })
        act("the mark keeps the keyboard, back is live", function () { root.same(root.view(), "chrome:arrow-up", "Up keeps the keyboard on its mark"); root.key(Qt.Key_Home); root.same(root.view(), "chrome:arrow-left", "back is live") })
        act("Back from the bar", function () { root.key(Qt.Key_Enter) })
        wait("the fixture is listed again", function () { return root.ready() })
        act("Search hands the keyboard to the query line", function () { root.reach("search"); root.key(Qt.Key_Space) })
        wait("search is typing", function () { return pane.searchMode === "typing" })
        act("search closes", function () { root.same(pane.focusView, "list", "Search hands the keyboard to the pane"); root.key(Qt.Key_Escape) })
        wait("search is closed", function () { return pane.searchMode === "" && root.ready() })
        act("to the bar again", function () { pane.focusView = "list"; pane.forceActiveFocus(); root.key(Qt.Key_Tab); root.key(Qt.Key_Tab); root.reach("columns"); root.key(Qt.Key_Return) })
        wait("columns view", function () { return pane.viewMode === "columns" })
        act("columns keeps the keyboard", function () { root.same(root.view(), "chrome:columns", "a view mark keeps the keyboard"); root.reach("grid"); root.key(Qt.Key_Return) })
        wait("grid view", function () { return pane.viewMode === "grid" })
        act("the grid brings filter and sort in", function () {
            root.check(root.glyphs().indexOf("filter,sort") > 0 && root.glyphs().indexOf("search") < 0, "grid controls " + root.glyphs())
            root.reach("sort"); root.key(Qt.Key_Return)
        })
        act("sort asked, filter next", function () { root.check(root.counts.sort === 1, "Return on Sort did not reach the sort action"); root.same(root.view(), "chrome:sort", "Sort keeps the keyboard"); root.reach("filter"); root.key(Qt.Key_Return) })
        wait("filter is typing", function () { return pane.filterTyping })
        act("filter closes", function () { root.same(pane.focusView, "list", "Filter hands the keyboard to the pane"); root.key(Qt.Key_Escape) })
        wait("filter is closed", function () { return !pane.filterTyping })
        act("Settings opens", function () { pane.forceActiveFocus(); root.key(Qt.Key_Tab); root.key(Qt.Key_Tab); root.reach("sliders"); root.key(Qt.Key_Return) })
        wait("the panel is open", function () { return pane.settingsPanel.opened })
        act("the panel closes", function () { root.same(pane.focusView, "list", "Settings takes the keyboard"); pane.settingsPanel.item.close(); pane.forceActiveFocus() })
        act("Dual from the bar", function () { root.key(Qt.Key_Tab); root.key(Qt.Key_Tab); root.reach("dual"); root.key(Qt.Key_Return) })
        wait("dual view", function () { return body.dualMode })
        act("List from the bar", function () { root.same(root.view(), "chrome:dual", "Dual keeps the keyboard on its mark"); root.reach("list"); root.key(Qt.Key_Return) })
        wait("single view", function () { return !body.dualMode && pane.viewMode === "list" })
        act("Ctrl+4 is Dual", function () { pane.focusView = "list"; pane.forceActiveFocus(); root.key(Qt.Key_4, Qt.ControlModifier) })
        wait("dual by chord", function () { return body.dualMode })
        act("two lists, then the rail, the bar and the strip", function () {
            body.focusPane(0); pane.focusView = "list"; pane.forceActiveFocus()
            root.key(Qt.Key_Tab); root.same(body.focusSide + ":" + root.view(), "1:list", "Tab from the left list reaches the right one")
            root.key(Qt.Key_Tab); root.same(body.focusSide + ":" + root.view(), "0:rail", "Tab from the right list reaches the left pane's rail")
            root.key(Qt.Key_Tab); root.same(body.focusSide + ":" + root.view(), "0:chrome:" + ChromeKeys.controls(chrome)[0], "Tab from the rail reaches the bar")
            root.key(Qt.Key_Tab); root.same(body.focusSide + ":" + root.view(), "0:list", "a window of one tab goes on to the left list")
            root.key(Qt.Key_Backtab, Qt.ShiftModifier); root.same(body.focusSide + ":" + root.view(), "0:chrome:sliders", "Shift+Tab from the left list reaches the bar")
            root.key(Qt.Key_Backtab, Qt.ShiftModifier); root.same(body.focusSide + ":" + root.view(), "0:rail", "Shift+Tab goes on to the rail")
            root.key(Qt.Key_Backtab, Qt.ShiftModifier); root.same(body.focusSide + ":" + root.view(), "1:list", "Shift+Tab goes on to the right list")
            body.focusPane(1)
            var right = body.currentPane
            right.focusView = "chrome"
            body.focusPane(0)
            root.same(right.focusView, "list", "a click on the left pane gives the right pane's bar stop its list back")
            body.focusPane(1)
            right.focusView = "strip"
            body.focusPane(0)
            root.same(right.focusView, "list", "and its strip stop")
            root.key(Qt.Key_1, Qt.ControlModifier)
        })
        wait("single again", function () { return !body.dualMode })

        // Two tabs add the strip.
        act("a second tab", function () { pane.focusView = "list"; pane.forceActiveFocus(); pane.act("tabNew") })
        wait("the strip is open", function () { return strip.open && root.ready() })
        act("the strip is a stop", function () {
            root.key(Qt.Key_Tab); root.key(Qt.Key_Tab); root.key(Qt.Key_Tab)
            root.same(root.view(), "strip:" + strip.currentIndex, "Tab reaches the strip on the current tab")
            root.tabFrame("current tab", strip.currentIndex)
            root.key(Qt.Key_Right); root.same(root.view(), "strip:2", "Right reaches New tab")
            var add = strip.newTabFrame
            root.inside("New tab", add, add.parent, add.parent.width, add.parent.height)
            root.foregroundFrame("New tab", add)
            root.key(Qt.Key_Right); root.same(root.view(), "strip:2", "Right on New tab stays")
            root.key(Qt.Key_Home); root.same(root.view(), "strip:0", "Home reaches the first tab")
            root.tabFrame("first tab", 0)
            root.key(Qt.Key_Return)
        })
        wait("the first tab is current", function () { return strip.currentIndex === 0 && root.ready() })
        act("Return selected it and left the strip", function () {
            root.same(root.view(), "list", "Return on a tab returns to the list")
            root.key(Qt.Key_Backtab, Qt.ShiftModifier); root.same(root.view(), "strip:2", "Shift+Tab enters the strip on New tab")
            root.key(Qt.Key_Return)
        })
        wait("a third tab", function () { return strip.tabCount === 3 && root.ready() })
        act("New tab left the strip", function () { root.same(root.view(), "list", "Return on New tab returns to the list") })

        // No rail: the ring closes up.
        act("hide the rail", function () { pane.act("sidebar") })
        wait("the rail is gone", function () { return pane.sidebar === null })
        act("the ring without a rail", function () {
            pane.forceActiveFocus()
            root.key(Qt.Key_Tab); root.same(root.view(), "chrome:" + ChromeKeys.controls(chrome)[0], "Tab from the list reaches the bar")
            root.key(Qt.Key_Tab); root.same(root.view().indexOf("strip:"), 0, "then the strip")
            root.key(Qt.Key_Tab); root.same(root.view(), "list", "then the list")
            pane.act("sidebar")
        })
        wait("the rail is back", function () { return pane.sidebar !== null })

        // Right Arrow to a mounted share's eject mark.
        act("a mounted share", function () {
            var service = pane.networkService
            service._mountListing = "Mount(0): KeyReach NAS -> smb://keyreach.test/media/\n"
            service.rebuild()
        })
        wait("the rail lists it", function () { return root.shareIndex() >= 0 })
        act("Right reaches the mark", function () {
            pane.focusView = "rail"
            pane.sidebar.cursorIndex = root.shareIndex()
            root.key(Qt.Key_Right)
            root.check(pane.sidebar.markFocused, "Right on the share row did not reach its mark")
            var row = pane.sidebar.railItemFor(root.shareIndex())
            var frame = row.markFrameItem
            root.foregroundFrame("eject mark", frame)
            var box = frame.mapToItem(row, 0, 0, frame.width, frame.height)
            root.check(box.x >= 0 && box.y >= 0 && box.x + box.width <= row.width && box.y + box.height <= row.height, "the mark frame " + box.x + "," + box.y + " " + box.width + "x" + box.height + " leaves its " + row.width + "x" + row.height + " row")
            root.key(Qt.Key_Left)
            root.check(!pane.sidebar.markFocused, "Left did not return to the row")
            root.key(Qt.Key_Right)
            root.key(Qt.Key_Return)
        })
        wait("the release was asked", function () { return pane.networkService._pendingUnmountLabel === "KeyReach NAS" })
        act("the keyboard is back on the row", function () { root.check(!pane.sidebar.markFocused && pane.focusView === "rail", "the keyboard did not return to the row") })
        return p
    }
    function shareIndex() {
        var entries = pane.sidebar ? pane.sidebar.entries : []
        for (var i = 0; i < entries.length; i++) if (entries[i].label === "KeyReach NAS") return i
        return -1
    }
    function report() {
        stepper.running = false
        console.log("KEYREACH DONE checks=" + root.checks + " failed=" + root.failures.length)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    Connections {
        target: root.chrome
        function onSortRequested() { root.counts.sort += 1 }
    }

    Component.onCompleted: root.plan = root.build()

    FloatingWindow {
        id: window
        implicitWidth: 1000
        implicitHeight: 650
        Flea.WindowBody { id: body; host: window }
        Item { anchors.fill: parent; TestEvent { id: driver } }
    }

    Timer {
        id: stepper
        interval: 50
        running: true
        repeat: true
        onTriggered: {
            if (root.stepping) return
            root.stepping = true
            try {
                while (root.index < root.plan.length) {
                    var step = root.plan[root.index]
                    if (step.fn() === false) break
                    root.index++
                    root.ticks = 0
                }
            } finally { root.stepping = false }
            if (root.index >= root.plan.length) { root.report(); return }
            root.ticks++
            if (root.ticks > root.stallTicks) {
                root.failures.push("stalled: " + root.plan[root.index].label)
                console.log("KEYREACH FAIL stalled: " + root.plan[root.index].label + " view=" + root.view())
                root.report()
            }
        }
    }
}
