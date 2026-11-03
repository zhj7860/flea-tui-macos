//@ pragma ShellId flea-settings-tail-test
import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Settings.js" as Settings
import "qml-probe.js" as QmlProbe

// tests/settings-tail.sh's harness: Settings > Menus walked by keyboard to its last row reveals the pane to its end, so no lower-edge fade lies over that row; then every section with a heading after a row is swept across host heights, so a heading never lies under a fade that shows only padding.
ShellRoot {
    id: shell

    property int checks: 0
    property var failures: []
    property int ticks: 0
    property int step: -1
    property bool done: false
    // Ticks the panel settles before the walk starts, and the bound a step waits for its layout.
    readonly property int settleTicks: 3
    readonly property int stepTickBound: 20
    // A window short enough that Menus is taller than its pane at every text size.
    readonly property int windowWidth: 900
    readonly property int windowHeight: 420
    // The pane's host grows and shrinks by this much, as the card's clamp does when the window changes under an open panel.
    readonly property int resizeBy: 40
    property int hostHeight: shell.windowHeight
    // After the walk reaches the last row, each height in turn is applied and the tail is read again.
    property var heights: [shell.windowHeight - shell.resizeBy, shell.windowHeight + shell.resizeBy, shell.windowHeight]
    property int heightIndex: -1
    // The pane's own tolerance: a fade shows only more than one hairline of content below.
    readonly property real endTolerance: 0.5
    // The fade is a cut, so the row after the cursor must have ink under it: at least this share of the fade's height of that ink is drawn above the pane's edge.
    readonly property real minCutShare: 0.5

    // About starts the update check, which spawns the flea binary this harness does not have, so it is not shown.
    readonly property string updateCheckSection: "about"
    // After the walk, the sweep takes each section in turn and, at every host height in a span, puts the cursor on each row that a heading follows.
    property var sweepSections: []
    property int sweepIndex: -1
    property bool sweeping: false
    property int sweptHeights: 0
    property int sweptTargets: 0

    function log(line) { QmlProbe.log("SETTAIL", line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(name, actual, expected) { QmlProbe.checkQuiet(shell, name, actual, expected) }
    function report() {
        QmlProbe.reportCard(shell, ticker)
        shell.quit()
    }

    FloatingWindow {
        implicitWidth: shell.windowWidth
        implicitHeight: shell.windowHeight
        color: "#303030"
        Item {
            width: parent.width
            height: shell.hostHeight
            Flea.SettingsPanel { id: panel; anchors.fill: parent }
        }
    }

    function findType(item, name) {
        var stack = [item]
        while (stack.length > 0) {
            var o = stack.pop()
            if (o !== item && String(o).indexOf(name) === 0) return o
            var kids = o && o.children !== undefined ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
        }
        return null
    }
    // The lower-edge fade is the one gradient the pane lays over its own content.
    function fadeOf(pane) {
        for (var i = 0; i < pane.children.length; i++)
            if (pane.children[i].gradient) return pane.children[i]
        return null
    }

    Timer {
        id: ticker
        interval: 100
        repeat: true
        running: true
        onTriggered: shell.advance()
    }

    // The pane's section columns in model order (the Repeater is among its content item's children and carries no built).
    function sectionItems(pane) {
        var out = []
        for (var i = 0; i < pane.contentItem.children.length; i++)
            if (pane.contentItem.children[i].built !== undefined) out.push(pane.contentItem.children[i])
        return out
    }

    // Sections whose rows are built: the first open builds View and the open section only, the idle walk builds the rest.
    function builtSections(pane) {
        var n = 0
        var items = shell.sectionItems(pane)
        for (var i = 0; i < items.length; i++)
            if (items[i].built === true) n++
        return n
    }

    // The pane's idle walk, read through the pane's own alias for it.
    function walkOf(pane) { return pane.walk }

    // A section the walk has not reached, other than About (which starts the update check) and the Columns subpage.
    function unreached(pane) {
        var items = shell.sectionItems(pane)
        for (var i = items.length - 1; i >= 0; i--)
            if (!items[i].built && items[i].modelData.id !== shell.updateCheckSection && items[i].modelData.id !== "columns") return items[i]
        return null
    }

    // The pane builds lazily and a section shown before the walk reaches it builds on that show: the walk is held while one such section is shown, and its rows must be there at once.
    function checkLazyBuild() {
        var pane = shell.findType(panel, "SettingsPane")
        var walk = shell.walkOf(pane)
        shell.check("the pane's idle walk is found", !!walk, true)
        if (!walk) return
        // The walk restarts only if the pane had it running, so the later all-built check cannot pass from this test's own start.
        var wasRunning = walk.running
        walk.stop()
        // View is the open section, so the walk's own k builds are the only others: k <= walk.next at any tick.
        var built = shell.builtSections(pane)
        shell.check("the pane builds View and only what the walk has reached before the walk is under way", built >= 1 && built <= 1 + walk.next, true)
        var target = shell.unreached(pane)
        shell.check("a section the walk has not reached exists to be shown", !!target, true)
        if (target) {
            var id = target.modelData.id
            // A column shows only while the panel does, and a closed panel's sections stay as they were.
            panel.open(null)
            panel.showSection(id)
            shell.check("section " + id + " builds when it is shown with the walk held", target.built, true)
            shell.check("section " + id + " shows every row at once", panel.rows.length > 0 && pane.current.rows.count === panel.rows.length, true)
        }
        if (wasRunning) walk.start()
    }

    // After the walk: the Columns subpage opens over the same section columns, none recreated, and every section then shows every row at once.
    function checkSubpage(pane) {
        var before = shell.sectionItems(pane)
        panel.showSection("columns")
        var after = shell.sectionItems(pane)
        var same = after.length === before.length
        for (var i = 0; same && i < before.length; i++) same = after[i] === before[i]
        shell.check("opening the Columns subpage keeps every section column", same, true)
        shell.check("the Columns subpage shows every row at once", panel.rows.length > 0 && pane.current.rows.count === panel.rows.length, true)
        var empty = []
        for (var s = 0; s < Settings.SECTIONS.length; s++) {
            var id = Settings.SECTIONS[s].id
            if (id === shell.updateCheckSection) continue
            panel.showSection(id)
            if (panel.rows.length === 0 || pane.current.rows.count !== panel.rows.length) empty.push(id)
        }
        shell.check("every section shown after the Columns subpage has its rows at once", empty, [])
    }

    // The row item the cursor is on, in the pane's content, against the pane's own window.
    function cursorInside(pane) {
        var item = pane.rowItem(panel.cursor)
        return !!item && item.y >= pane.contentY - shell.endTolerance && item.y + item.height <= pane.contentY + pane.height + shell.endTolerance
    }

    // A drawn fade is clear of the cursor row: the row's bottom, in the pane's own coordinates, sits above the fade's top.
    function fadeClear(pane, fade) {
        var item = pane.rowItem(panel.cursor)
        return !fade.visible || (!!item && item.y + item.height - pane.contentY <= fade.y + shell.endTolerance)
    }

    // The row after the cursor row, when a fade is drawn: its first ink starts inside the pane, under the fade, and at least a cut's depth above the pane's edge.
    function cutShows(pane, fade) {
        var next = pane.rowItem(panel.cursor + 1)
        if (!fade.visible || !next) return true
        var depth = pane.height - (next.y + pane.inkTop(next) - pane.contentY)
        return depth >= Math.round(fade.height * shell.minCutShare)
    }

    function checkTail(pane, fade, tag) {
        var below = pane.contentHeight - pane.contentY - pane.height
        shell.check(tag + ": the pane is revealed to its end, not past it", Math.abs(below) <= shell.endTolerance, true)
        shell.check(tag + ": no lower-edge fade lies over it", fade.visible, false)
        shell.check(tag + ": the cursor row is inside the pane", shell.cursorInside(pane), true)
    }

    // The cursor rows a heading follows, in the section the panel shows: the cursor stops there and the heading's own ink is the first thing a cut can show.
    function headingTargets(rows) {
        var out = []
        for (var i = 0; i + 1 < rows.length; i++)
            if (Settings.focusable(rows[i]) && rows[i + 1].kind === "group") out.push(i)
        return out
    }

    // Host heights from a row plus a heading below the walk's height to the same above it, so every offset of a heading against the fade's edge is met at 1 px.
    function sweepHeights(pane) {
        var rowHeight = Infinity
        var headingHeight = 0
        for (var i = 0; i < panel.rows.length; i++) {
            var item = pane.rowItem(i)
            if (!item) continue
            if (panel.rows[i].kind === "group") headingHeight = Math.max(headingHeight, item.height)
            else rowHeight = Math.min(rowHeight, item.height)
        }
        var span = rowHeight + headingHeight
        var out = []
        for (var h = shell.windowHeight - span; h <= shell.windowHeight + span; h++) out.push(h)
        return out
    }

    // One section: at each height the pane is rewound and the cursor put on each target; a height whose reveal leaves a fade over the cursor row, or over padding, is named once.
    function sweepSection(id) {
        panel.showSection(id)
        var pane = shell.findType(panel, "SettingsPane")
        var fade = shell.fadeOf(pane)
        var targets = shell.headingTargets(panel.rows)
        var heights = shell.sweepHeights(pane)
        var inside = []
        var clear = []
        var cuts = []
        var follows = []
        var previous = -1
        for (var k = 0; k < heights.length; k++) {
            shell.hostHeight = heights[k]
            panel.showSection(id)
            if (previous >= 0 && pane.height !== previous + 1) follows.push(heights[k])
            previous = pane.height
            for (var t = 0; t < targets.length; t++) {
                panel.cursor = targets[t]
                panel.showCursor()
                if (!shell.cursorInside(pane)) inside.push(heights[k] + "/" + targets[t])
                if (!shell.fadeClear(pane, fade)) clear.push(heights[k] + "/" + targets[t])
                if (!shell.cutShows(pane, fade)) cuts.push(heights[k] + "/" + targets[t])
                shell.sweptTargets++
            }
            shell.sweptHeights++
        }
        shell.check("sweep " + id + ": the pane height follows the host one px at a time", follows, [])
        shell.check("sweep " + id + ": the cursor row is inside the pane (height/row)", inside, [])
        shell.check("sweep " + id + ": no fade lies over the cursor row (height/row)", clear, [])
        shell.check("sweep " + id + ": a cut of the heading after the cursor row shows under the fade (height/row)", cuts, [])
    }

    // The sections that have a cursor row followed by a heading, found once the walk is over.
    function startSweep() {
        var found = []
        for (var i = 0; i < Settings.SECTIONS.length; i++) {
            var id = Settings.SECTIONS[i].id
            if (id !== shell.updateCheckSection && shell.headingTargets(Settings.rows(id, panel.settingsState)).length > 0) found.push(id)
        }
        shell.sweepSections = found
        var pane = shell.findType(panel, "SettingsPane")
        shell.check("the idle walk has built every section and the Columns subpage", shell.builtSections(pane), Settings.SECTIONS.length + 1)
        shell.checkSubpage(pane)
        shell.check("the sweep covers Menus and another section", found.indexOf("menus") >= 0 && found.length >= 2, true)
        shell.sweeping = true
        shell.sweepIndex = 0
    }

    function advanceSweep() {
        if (shell.sweepIndex >= shell.sweepSections.length) {
            shell.log("swept " + shell.sweepSections.join(",") + ": " + shell.sweptHeights + " heights, " + shell.sweptTargets + " cursor rows")
            shell.report()
            return
        }
        shell.sweepSection(shell.sweepSections[shell.sweepIndex])
        shell.sweepIndex++
    }

    function advance() {
        if (shell.done) return
        shell.ticks++
        if (shell.sweeping) { shell.advanceSweep(); return }
        if (shell.step < 0) {
            // The panel is built at once here, as its Loader builds it at the first open; the checks read the walk's own state, not the tick.
            if (shell.ticks === 1) shell.checkLazyBuild()
            if (shell.ticks < shell.settleTicks) return
            panel.open(null)
            panel.showSection("menus")
            shell.step = 0
            shell.ticks = 0
            return
        }
        // One tick after each move lets the pane lay out and the reveal land before it is read.
        var pane = shell.findType(panel, "SettingsPane")
        var fade = shell.fadeOf(pane)
        if (shell.step === 0) shell.check("the pane scrolls at this window height", pane.contentHeight > pane.height, true)
        shell.check("step " + shell.step + ": the cursor row is inside the pane", shell.cursorInside(pane), true)
        shell.check("step " + shell.step + ": no fade lies over the cursor row", shell.fadeClear(pane, fade), true)
        shell.check("step " + shell.step + ": what follows the cursor row shows under the fade", shell.cutShows(pane, fade), true)
        var before = panel.cursor
        panel.moveCursor(1)
        if (panel.cursor === before) {
            // The keyboard cannot go further: this is the last row, nothing follows it.
            shell.checkTail(pane, fade, "the last row at host height " + shell.hostHeight)
            if (shell.heightIndex + 1 >= shell.heights.length) { shell.startSweep(); return }
            shell.heightIndex++
            shell.hostHeight = shell.heights[shell.heightIndex]
            shell.ticks = 0
            return
        }
        shell.step++
        shell.ticks = 0
    }
}
