//@ pragma ShellId flea-menu-refresh-scroll-test

import QtQuick
import Quickshell
import "flea" as Flea

// tests/menu-refresh-scroll.sh's harness: a provider refresh that rebuilds the rows of a scrolled menu keeps the flyout's row, else the cursor's, in view.
ShellRoot {
    id: shell

    property var failures: []
    property int ticks: 0
    property int phase: 0

    function log(line) { console.log("MENUREFRESH " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(name, cond, detail) {
        if (!cond) shell.failures.push(name + " got " + detail)
    }
    function findFirst(item, name) {
        var stack = [item]
        while (stack.length > 0) {
            var o = stack.pop()
            if (o !== item && String(o).indexOf(name) >= 0) return o
            var kids = (o && o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
        }
        return null
    }

    FloatingWindow {
        implicitWidth: 640
        implicitHeight: 480
        color: "#303030"

        Flea.ContextMenu {
            id: menu
            anchors.fill: parent
            rowIsFile: true
            workArea: Qt.rect(0, 0, 640, 300)
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: shell.advance()
    }

    function rowOf(key) {
        return menu.entries.findIndex(function (e) { return e.action === key })
    }
    // The Copy as row is read by its key, never by a stored index, and the cursor sits on a row that is not Copy as's.
    function inBand(name, main) {
        var at = menu.itemFor(shell.rowOf("copyAs")).mapToItem(main, 0, 0).y
        shell.check(name + "-in-band", at >= 0 && at + menu.itemFor(shell.rowOf("copyAs")).height <= main.height, "y=" + at + " contentY=" + main.contentY)
        return at
    }
    function decoyAbove() {
        for (var i = shell.rowOf("copyAs") - 1; i >= 0; i--)
            if (!menu.entries[i].separator && !menu.entries[i].disabled) return i
        return -1
    }
    function open(taildrop, peer) {
        menu.close()
        menu.taildropInstalled = taildrop
        menu.taildropPeers = taildrop ? [{ id: peer, label: peer }] : []
        menu.openAt(Qt.point(20, 20))
    }
    function answer(taildrop, peer) {
        menu.taildropInstalled = taildrop
        menu.taildropPeers = taildrop ? [{ id: peer, label: peer }] : []
        menu.providersSettled()
    }

    property var steps: [
        // A flyout on Copy as while the cursor rests on another row, a Taildrop row inserted above Copy as.
        function (main) { Flea.ViewState.state = { menu: { hidden: [] } }; shell.open(false, "") },
        function (main) {
            shell.before = shell.rowOf("copyAs")
            shell.check("copy-opens", menu.openSubmenuFor("copyAs") && menu.openSubmenuRow === shell.before, "no Copy as row")
            menu.cursor = shell.decoyAbove()
            shell.check("cursor-differs", menu.cursor !== menu.openSubmenuRow, String(menu.cursor))
        },
        function (main) { shell.check("flyout-scrolled", main.contentY > 0, String(main.contentY)); shell.answer(true, "p") },
        function (main) {
            shell.check("flyout-shifted", shell.rowOf("copyAs") > shell.before, shell.before + "/" + shell.rowOf("copyAs"))
            shell.check("flyout-row", menu.openSubmenuRow === shell.rowOf("copyAs"), String(menu.openSubmenuRow))
            var at = shell.inBand("flyout", main)
            // The flyout follows the row through heldOffset, so the two agree on where the row stands.
            var off = menu.itemFor(shell.rowOf("copyAs")).mapToItem(menu.frameItem, 0, 0).y - Flea.Theme.spacing.rowPaddingY
            shell.check("flyout-beside", menu.heldOffset === off, menu.heldOffset + "/" + off)
            shell.rowY = at
        },
        // No flyout, the cursor on Copy as, a Taildrop row inserted above it (the height changes).
        function (main) { shell.open(false, "") },
        function (main) { menu.cursor = shell.rowOf("copyAs"); shell.check("cursor-scrolled", main.contentY > 0, String(main.contentY)); shell.answer(true, "p") },
        function (main) { shell.check("height-cursor", menu.cursor === shell.rowOf("copyAs"), String(menu.cursor)); shell.inBand("height", main) },
        // No flyout, the cursor on Copy as, the peer renamed: rows rebuilt at the same height.
        function (main) { shell.open(true, "p") },
        function (main) {
            menu.cursor = shell.rowOf("copyAs")
            shell.check("equal-scrolled", main.contentY > 0, String(main.contentY))
            shell.old = menu.itemFor(menu.cursor)
            shell.answer(true, "q")
        },
        function (main) {
            shell.check("equal-rebuilt", menu.itemFor(shell.rowOf("copyAs")) !== shell.old, "same row object")
            shell.check("equal-cursor", menu.cursor === shell.rowOf("copyAs"), String(menu.cursor))
            shell.inBand("equal", main)
        }
    ]
    property int before: -1
    property var old: null
    property real rowY: 0

    // One step per tick so the Column lays out between steps, as it does between a click and the key that follows.
    function advance() {
        shell.ticks += 1
        var main = menu.frameItem ? shell.findFirst(menu.frameItem, "CardScroll") : null
        if (shell.phase < 0 || shell.ticks < 3) return
        shell.ticks = 0
        if (shell.phase < shell.steps.length) {
            shell.steps[shell.phase](main)
            shell.phase += 1
            return
        }
        if (shell.failures.length === 0)
            shell.log("PASS contentY=" + main.contentY + " rowY=" + shell.rowY)
        else
            for (var i = 0; i < shell.failures.length; i++)
                shell.log("FAIL " + shell.failures[i])
        shell.log("DONE failures=" + shell.failures.length)
        shell.phase = -1
        shell.quit()
    }
}
