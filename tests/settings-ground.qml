//@ pragma ShellId flea-settings-ground-test
import QtQuick
import QtTest
import Quickshell
import "flea" as Flea

// Settings keeps card-owned gestures while ground-owned gestures dismiss; the real pane stays disabled.
ShellRoot {
    id: root
    readonly property var pane: body.currentPane
    readonly property string fixture: Quickshell.env("FLEA_PATH")
    readonly property var cases: [
        {name: "left drag", button: Qt.LeftButton, move: true, closes: true},
        {name: "right drag", button: Qt.RightButton, move: true, closes: true},
        {name: "left click", button: Qt.LeftButton, move: false, closes: true},
        {name: "right click", button: Qt.RightButton, move: false, closes: true},
        {name: "card to ground left", button: Qt.LeftButton, move: true, card: true},
        {name: "card to ground right", button: Qt.RightButton, move: true, card: true},
        {name: "contents to ground left", button: Qt.LeftButton, move: true, contents: true},
        {name: "contents to ground right", button: Qt.RightButton, move: true, contents: true},
        {name: "card left click", button: Qt.LeftButton, card: true, inside: true},
        {name: "card right click", button: Qt.RightButton, card: true, inside: true},
        {name: "control left click", button: Qt.LeftButton, control: true, inside: true},
        {name: "ground-owned release over card", button: Qt.LeftButton, move: true, inside: true, closes: true},
        {name: "card to outside window", button: Qt.LeftButton, move: true, card: true, outside: true},
        {name: "ruler to ground", button: Qt.LeftButton, move: true, ruler: true},
        {name: "scroll to ground", button: Qt.LeftButton, move: true, scroll: true}
    ]
    property int caseIndex: 0
    property int checks: 0
    property int failures: 0
    property string stage: "settle"
    property double started: Date.now()
    property bool executing: false
    property bool finished: false
    property bool foldersFirstBefore: true
    property point from: Qt.point(0, 0)
    property point to: Qt.point(0, 0)
    property var scrollItem: null
    property real scrollBefore: 0
    property var rulerHandler: null
    readonly property var current: cases[caseIndex]

    function check(name, actual, expected) {
        checks++
        var equal = actual === expected
        if (!equal) failures++
        console.log("SETTINGS_GROUND " + (equal ? "ok " : "FAIL ") + current.name + " " + name
                    + ": got " + actual + ", expected " + expected)
    }
    function next(value) { stage = value; started = Date.now() }
    function findItem(item, property) {
        if (item[property] !== undefined) return item
        for (var i = 0; i < item.children.length; i++) {
            var found = findItem(item.children[i], property)
            if (found) return found
        }
        return null
    }
    function tapHandlerAt(item, point) {
        if (!item.contains(item.mapFromItem(body, point.x, point.y))) return null
        for (var r = 0; r < item.resources.length; r++)
            if (item.resources[r] instanceof TapHandler) return item.resources[r]
        for (var i = 0; i < item.children.length; i++) {
            var found = tapHandlerAt(item.children[i], point)
            if (found) return found
        }
        return null
    }
    function finish() {
        finished = true
        console.log("SETTINGS_GROUND DONE checks=" + checks + " failed=" + failures)
        body.quitBackends()
    }
    function advance() {
        if (executing || finished) return
        executing = true
        try { runStage() }
        catch (error) { check("harness error", String(error), "none"); finish() }
        executing = false
    }
    function runStage() {
        if (Date.now() - started > 5000) { check("stage " + stage + " completed", false, true); finish(); return }
        if (stage === "settle") {
            if (pane.listInFlight || pane.path !== fixture || pane.total !== 3 || !pane.visibleItemFor(2)) return
            pane.setCursor(0)
            var row = pane.visibleItemFor(2)
            var folder = pane.visibleItemFor(0)
            from = body.mapFromItem(row, 40, row.height / 2)
            to = current.move ? body.mapFromItem(folder, 40, folder.height / 2) : from
            pane.settingsPanel.open(pane)
            pane.settingsPanel.item.showSection(current.ruler ? "display" : current.scroll ? "menus" : "view")
            next("open")
        } else if (stage === "open") {
            if (Date.now() - started < 400) return
            var panel = pane.settingsPanel.item
            var card = panel.cardItem
            var title = body.mapFromItem(panel.titleItem, panel.titleItem.width / 2, panel.titleItem.height / 2)
            if (current.card) from = title
            if (current.contents || current.control) {
                var control = panel.rowItemForId("foldersFirst")
                from = body.mapFromItem(control, control.width / 2, control.height / 2)
                foldersFirstBefore = Flea.ViewState.state.foldersFirst !== false
            }
            if (current.ruler) {
                var ruler = findItem(panel.rowItemForId("textStop"), "tickWidth")
                check("the size ruler is active", ruler.active, true)
                from = body.mapFromItem(ruler, ruler.tickWidth / 2, ruler.height / 2)
                rulerHandler = tapHandlerAt(ruler, from)
                check("the real ruler handler was found", rulerHandler !== null, true)
            }
            if (current.scroll) {
                scrollItem = findItem(card, "compactHeight")
                scrollItem.contentY = 0
                scrollBefore = scrollItem.contentY
                check("the content can scroll", scrollItem.contentHeight > scrollItem.height + Flea.Theme.rowHeight, true)
                from = body.mapFromItem(scrollItem, scrollItem.width / 2, scrollItem.height * 0.75)
                to = Qt.point(from.x, Math.max(2, body.mapFromItem(card, 0, 0).y - 4))
            }
            if (current.inside) to = current.control ? from : title
            if (current.outside) to = Qt.point(-40, from.y)
            var inPanel = panel.contains(panel.mapFromItem(body, to.x, to.y))
            var inCard = card.contains(card.mapFromItem(body, to.x, to.y))
            check("release target has the intended bounds", inPanel && !inCard, !current.inside && !current.outside)
            check("press target has the intended bounds", card.contains(card.mapFromItem(body, from.x, from.y)),
                  !!current.card || !!current.contents || !!current.control || !!current.ruler || !!current.scroll)
            check("the pane is disabled", pane.enabled, false)
            driver.mouseMove(body, from.x, from.y, 1, Qt.NoButton, Qt.NoModifier)
            driver.mousePress(body, from.x, from.y, current.button, Qt.NoModifier, 1)
            next("held")
        } else if (stage === "held") {
            // A click must finish before TapHandler's long-press threshold, while a drag keeps R0's hold.
            if (Date.now() - started < (current.move ? 300 : 40)) return
            check("the press leaves Settings open", pane.settingsPanel.opened, true)
            if (current.ruler) check("the real ruler handler owns the press", rulerHandler !== null && rulerHandler.pressed, true)
            if (current.move) {
                for (var step = 1; step <= 8; step++)
                    driver.mouseMove(body, from.x + (to.x - from.x) * step / 8,
                                     from.y + (to.y - from.y) * step / 8, 20, current.button, Qt.NoModifier)
            }
            next("moved")
        } else if (stage === "moved") {
            if (Date.now() - started < (current.move ? 500 : 40)) return
            check("no file drag starts under Settings", pane.dragActive, false)
            if (current.scroll) check("the real content scrolled past the card edge", scrollItem.contentY > scrollBefore + Flea.Theme.rowHeight, true)
            driver.mouseRelease(body, to.x, to.y, current.button, Qt.NoModifier, 1)
            next("released")
        } else if (stage === "released") {
            if (Date.now() - started < 300) return
            check("release preserves the gesture's dismissal", pane.settingsPanel.opened,
                  !current.closes)
            check("release leaves the cursor alone", pane.cursorIndex, 0)
            check("release opens no pane menu", pane.contextMenu().opened, false)
            if (current.control) check("the control still activates", Flea.ViewState.state.foldersFirst !== false, !foldersFirstBefore)
            pane.settingsPanel.item.close()
            if (caseIndex + 1 === cases.length) finish()
            else { caseIndex++; next("settle") }
        }
    }

    FloatingWindow {
        id: window
        implicitWidth: 1400
        implicitHeight: 900
        Flea.WindowBody { id: body; host: window }
        Item { anchors.fill: parent; TestEvent { id: driver } }
    }
    Timer { interval: 20; repeat: true; running: !root.finished; onTriggered: root.advance() }
}
