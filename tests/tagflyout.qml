//@ pragma ShellId flea-tagflyout-test
import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "flea/js/Tags.js" as Tags

// tests/tagflyout.sh: the real pane over the real backend toggles tags from an open flyout, which stays open with its cursor and redraws each box in place, over rows inside the held window and past it.
ShellRoot {
    id: root
    readonly property var pane: body.currentPane
    readonly property var menu: pane ? pane.contextMenu() : null
    readonly property string fixture: Quickshell.env("FLEA_PATH")
    readonly property int fixtureRows: 2
    readonly property int pollMs: 20
    readonly property int stepLimitMs: 8000
    // Ticks a finished step rests, so a late close or a late answer shows before its check.
    readonly property int restTicks: 10
    readonly property int blueRow: 4
    readonly property int maxKeys: 12

    property var steps: []
    property int stepIndex: -1
    property int rest: 0
    property bool acted: false
    property bool finished: false
    property double started: Date.now()
    property int landed: 0
    property int landedBefore: 0
    property int windows: 0
    property int windowsBefore: 0
    property var refusals: []
    // The tags each settags request named, in the order the pane sent them.
    property var sentTags: []
    property int pendingSeen: 0
    // Every error sentence the pane raised, so a refused tag activate shows.
    property var errors: []
    // What TagState held a turn after the last settagged answer, once its own handler had run.
    property var afterWrite: null
    property bool readyAtOpen: true
    property bool readHeld: false
    property int checks: 0
    property int failures: 0

    function log(line) { console.log("TAGFLYOUT " + line) }
    function check(name, ok) {
        checks += 1
        if (ok) return
        failures += 1
        log("FAIL " + name)
    }
    function finish() {
        finished = true
        log((failures === 0 ? "PASS " : "FAIL ") + checks + " checks")
        log("DONE failures=" + failures)
        body.quitBackends()
    }
    function leaf(id) {
        var rows = menu.submenuEntries
        for (var i = 0; i < rows.length; i++)
            if (rows[i].id === id) return rows[i]
        return null
    }
    function state(id) { var row = leaf(id); return row && row.tagRow ? row.tagRow.state : "missing" }
    function indexOfLeaf(id) {
        var rows = menu.submenuEntries
        for (var i = 0; i < rows.length; i++)
            if (rows[i].id === id) return i
        return -1
    }
    function flyoutStands() { return menu.opened && menu.submenuOpen }
    function allAbsent() {
        for (var i = 0; i < Tags.NAMES.length; i++)
            if (state(Tags.NAMES[i]) !== Tags.ABSENT) return false
        return true
    }
    function moveTo(id) {
        var target = indexOfLeaf(id)
        for (var n = 0; n < maxKeys && menu.submenuCursor !== target; n++)
            driver.keyClick(menu.submenuCursor < target ? Qt.Key_Down : Qt.Key_Up, Qt.NoModifier, -1)
    }
    // A write over rows past the held window is settled once its forced re-read has also answered.
    function reReadLanded() { return toggleLanded() && pane.tags().asking === null }
    // One toggle lands when its settagged answer has come back and the held window has answered after it.
    function toggleLanded() { return landed > landedBefore && windows > windowsBefore }
    function toggled() { landedBefore = landed; windowsBefore = windows; afterWrite = null }
    function noteWrite() { var held = pane.tagState; afterWrite = held === null ? null : { asked: held.asked !== null, asking: held.asking !== null } }

    function build() {
        return [
            { name: "open the flyout over two files, one carrying Blue",
              act: function () {
                  pane.selectOnly(0)
                  pane.toggleSelectAt(1)
                  pane.listArea.forceActiveFocus()
                  driver.keyClickChar("T", Qt.ShiftModifier, -1)
              },
              ready: function () { return flyoutStands() },
              verify: function () {
                  check("two files selected", pane.selectedIndices().length === 2)
                  check("Blue reads mixed over one of two files", state("Blue") === Tags.MIXED)
                  check("Red reads empty", state("Red") === Tags.ABSENT)
              } },
            { name: "digit 5 applies the mixed Blue and leaves the flyout up",
              act: function () {
                  moveTo("Blue")
                  toggled()
                  driver.keyClickChar("5", Qt.NoModifier, -1)
              },
              ready: toggleLanded,
              verify: function () {
                  check("5: the menu stays open", menu.opened)
                  check("5: the flyout stays open", menu.submenuOpen && menu.openSubmenuRow >= 0 && menu.entries[menu.openSubmenuRow].action === "tags")
                  check("5: Blue reads applied on its own row", state("Blue") === Tags.APPLIED && indexOfLeaf("Blue") === blueRow)
                  check("5: the cursor stays on Blue", menu.submenuCursor === blueRow)
                  check("5: nothing was refused", refusals.length === 0)
              } },
            { name: "digit 1 applies Red with no refusal",
              act: function () { toggled(); driver.keyClickChar("1", Qt.NoModifier, -1) },
              ready: toggleLanded,
              verify: function () {
                  check("1: the flyout stays open", flyoutStands())
                  check("1: Red reads applied", state("Red") === Tags.APPLIED)
                  check("1: Blue still reads applied", state("Blue") === Tags.APPLIED)
                  check("1: the cursor stays on Blue", menu.submenuCursor === blueRow)
                  check("1: the second choice was not refused as moved", refusals.length === 0)
              } },
            { name: "a click on the Red row removes it",
              act: function () {
                  var row = menu.submenuItemFor(indexOfLeaf("Red"))
                  toggled()
                  driver.mouseClick(row, row.width / 2, row.height / 2, Qt.LeftButton, Qt.NoModifier, -1)
              },
              ready: toggleLanded,
              verify: function () {
                  check("click: the flyout stays open", flyoutStands())
                  check("click: Red reads empty", state("Red") === Tags.ABSENT)
                  check("click: Blue still reads applied", state("Blue") === Tags.APPLIED)
                  check("click: nothing was refused", refusals.length === 0)
              } },
            { name: "keypad Enter applies Purple",
              act: function () { moveTo("Purple"); toggled(); driver.keyClick(Qt.Key_Enter, Qt.KeypadModifier, -1) },
              ready: toggleLanded,
              verify: function () {
                  check("Enter: the flyout stays open", flyoutStands())
                  check("Enter: Purple reads applied", state("Purple") === Tags.APPLIED)
                  check("Enter: the cursor stays on Purple", menu.submenuCursor === indexOfLeaf("Purple"))
              } },
            { name: "Return on Remove all tags empties every box",
              act: function () { moveTo(Tags.CLEAR_ID); toggled(); driver.keyClick(Qt.Key_Return, Qt.NoModifier, -1) },
              ready: toggleLanded,
              verify: function () {
                  check("Remove all: the flyout stays open", flyoutStands())
                  check("Remove all: every box reads empty", allAbsent())
                  check("Remove all: the cursor stays on its row", menu.submenuCursor === indexOfLeaf(Tags.CLEAR_ID))
                  check("Remove all: nothing was refused", refusals.length === 0)
              } },
            { name: "Escape closes the flyout and keeps the menu",
              act: function () { driver.keyClick(Qt.Key_Escape, Qt.NoModifier, -1) },
              verify: function () {
                  check("Escape: the flyout closed", !menu.submenuOpen)
                  check("Escape: the menu stays open", menu.opened)
              } },
            { name: "a second Escape closes the menu",
              act: function () { driver.keyClick(Qt.Key_Escape, Qt.NoModifier, -1) },
              verify: function () {
                  check("Escape: the menu closed", !menu.opened)
                  check("Escape: focus returned to the listing", pane.listArea.activeFocus)
              } },
            { name: "T then digit 2 then a click on the ground closes everything",
              act: function () {
                  pane.listArea.forceActiveFocus()
                  driver.keyClickChar("T", Qt.ShiftModifier, -1)
              },
              ready: function () { return flyoutStands() },
              verify: function () { check("T reopens the flyout", flyoutStands()) } },
            { name: "digit 2 applies Orange",
              act: function () { toggled(); driver.keyClickChar("2", Qt.NoModifier, -1) },
              ready: toggleLanded,
              verify: function () {
                  check("2: Orange reads applied", state("Orange") === Tags.APPLIED)
                  check("2: the flyout stays open", flyoutStands())
              } },
            { name: "a click on the ground closes the whole menu",
              act: function () {
                  var frame = menu.frameItem
                  var farX = frame.x > 20 ? 2 : menu.width - 2
                  var farY = frame.y > 20 ? 2 : menu.height - 2
                  driver.mouseClick(menu, farX, farY, Qt.LeftButton, Qt.NoModifier, -1)
              },
              verify: function () {
                  check("ground: the menu closed", !menu.opened)
                  check("ground: the flyout closed", !menu.submenuOpen)
                  check("ground: focus returned to the listing", pane.listArea.activeFocus)
              } },
            { name: "two choices made before the menu snapshot answers both apply, in order",
              act: function () {
                  pane.selectOnly(0)
                  pane.toggleSelectAt(1)
                  pane.listArea.forceActiveFocus()
                  // Direct calls, because a TestEvent key spins the event loop and lets the snapshot answer between presses.
                  pane.tags().openMenu()
                  readyAtOpen = pane.menuActions.ready
                  toggled()
                  sentTags = []
                  errors = []
                  menu.chooseSub("Yellow")
                  menu.chooseSub("Green")
              },
              // A refused choice never lands, so an error ends the wait for the busy check to name.
              ready: function () { return errors.length > 0 || (landed >= landedBefore + 2 && windows > windowsBefore) },
              verify: function () {
                  check("3 and 4: both choices landed before the snapshot answered", !readyAtOpen)
                  check("3 and 4: the flyout stays open", flyoutStands())
                  check("3 and 4: Yellow was sent before Green", sentTags.join() === "Yellow,Green")
                  check("3 and 4: Yellow reads applied", state("Yellow") === Tags.APPLIED)
                  check("3 and 4: Green reads applied", state("Green") === Tags.APPLIED)
                  check("3 and 4: nothing was refused", refusals.length === 0)
                  check("3 and 4: no activate met a busy menu worker", errors.length === 0)
                  menu.close()
              } },
            { name: "three choices made before the menu snapshot answers all apply, in order",
              act: function () {
                  pane.selectOnly(0)
                  pane.toggleSelectAt(1)
                  pane.listArea.forceActiveFocus()
                  pane.tags().openMenu()
                  readyAtOpen = pane.menuActions.ready
                  toggled()
                  sentTags = []
                  errors = []
                  menu.chooseSub("Blue")
                  menu.chooseSub("Purple")
                  menu.chooseSub("Gray")
              },
              // A refused choice never lands, so an error ends the wait for the busy check to name.
              ready: function () { return errors.length > 0 || (landed >= landedBefore + 3 && windows > windowsBefore) },
              verify: function () {
                  check("3 choices: all landed before the snapshot answered", !readyAtOpen)
                  check("3 choices: they were sent in the order chosen", sentTags.join() === "Blue,Purple,Gray")
                  check("3 choices: Blue reads applied", state("Blue") === Tags.APPLIED)
                  check("3 choices: Purple reads applied", state("Purple") === Tags.APPLIED)
                  check("3 choices: Gray reads applied", state("Gray") === Tags.APPLIED)
                  check("3 choices: no activate met a busy menu worker", errors.length === 0)
                  menu.close()
              } },
            { name: "pick the first row and the last, which the held window does not hold together",
              act: function () {
                  pane.selectOnly(0)
                  pane.toggleSelectAt(pane.total - 1)
                  pane.listArea.forceActiveFocus()
              },
              ready: function () { return !pane.listInFlight && pane.selectedIndices().length === 2 },
              verify: function () {
                  check("past the window: one picked row is outside the held rows", pane.tags().filesFor(pane.selectedIndices()) === null)
              } },
            { name: "T over the picked rows reads their tags from the backend",
              act: function () { driver.keyClickChar("T", Qt.ShiftModifier, -1) },
              ready: function () { return flyoutStands() && pane.tags().asked !== null },
              verify: function () {
                  check("past the window: Yellow reads mixed, carried by the first row alone", state("Yellow") === Tags.MIXED)
                  check("past the window: Red reads empty", state("Red") === Tags.ABSENT)
              } },
            { name: "digit 1 over the picked rows keeps the read up and asks again",
              act: function () { toggled(); driver.keyClickChar("1", Qt.NoModifier, -1) },
              ready: reReadLanded,
              verify: function () {
                  check("past the window: the read was kept through the write", afterWrite !== null && afterWrite.asked)
                  check("past the window: a fresh read was asked at once", afterWrite !== null && afterWrite.asking)
                  check("past the window: Red reads applied from the fresh read", state("Red") === Tags.APPLIED)
                  check("past the window: the flyout stays open", flyoutStands())
                  menu.close()
              } },
            { name: "Copy as still closes on a choice",
              act: function () {
                  pane.listArea.forceActiveFocus()
                  driver.keyClickChar("c", Qt.NoModifier, -1)
              },
              ready: function () { return flyoutStands() && menu.loneFlyoutAction === "copyAs" },
              verify: function () {
                  check("c opens the Copy as flyout", flyoutStands())
                  menu.chooseSub("copyName")
                  check("Copy as: a choice closes the menu", !menu.opened)
                  check("Copy as: a choice closes the flyout", !menu.submenuOpen)
              } },
            { name: "T over the picked rows again",
              act: function () {
                  pane.listArea.forceActiveFocus()
                  driver.keyClickChar("T", Qt.ShiftModifier, -1)
              },
              ready: function () { return flyoutStands() && pane.tags().asked !== null },
              verify: function () { check("T reopens the flyout over the picked rows", flyoutStands()) } },
            { name: "a failed backend read drops the kept read",
              act: function () { readHeld = pane.tags().asked !== null; pane.backend.failed("read", "", "the read stopped", 0) },
              verify: function () {
                  check("failure: a read was held before it", readHeld)
                  check("failure: the kept read is gone", pane.tags().asked === null)
                  check("failure: the read still out is gone", pane.tags().asking === null)
                  check("failure: no change stays pending", pane.tags().pending.length === 0)
              } }
        ]
    }

    function enter(index) {
        stepIndex = index
        started = Date.now()
        rest = 0
        acted = false
    }
    function advance() {
        if (finished) return
        try { run() }
        catch (error) { check("harness error " + String(error), false); finish() }
    }
    function run() {
        if (stepIndex < 0) {
            if (Date.now() - started > stepLimitMs) { check("fixture listed", false); finish(); return }
            if (pane.listInFlight || pane.path !== fixture || pane.total < fixtureRows || !pane.visibleItemFor(fixtureRows - 1)) return
            steps = build()
            enter(0)
            return
        }
        var step = steps[stepIndex]
        if (!acted) {
            acted = true
            step.act()
            return
        }
        var ready = step.ready === undefined || step.ready()
        if (!ready) {
            if (Date.now() - started > stepLimitMs) {
                check("step never finished: " + step.name, false)
                finish()
            }
            return
        }
        if (rest++ < restTicks) return
        step.verify()
        if (stepIndex + 1 >= steps.length) finish()
        else enter(stepIndex + 1)
    }

    Connections {
        target: root.pane ? root.pane.backend : null
        function onSettagged(message) { root.landed += 1; Qt.callLater(root.noteWrite) }
    }
    Connections {
        target: root.pane ? root.pane.tagState : null
        function onPendingChanged() {
            var held = root.pane.tagState.pending
            if (held.length > root.pendingSeen) root.sentTags = root.sentTags.concat([held[held.length - 1].tag])
            root.pendingSeen = held.length
        }
    }
    Connections {
        target: root.pane
        function onRowsChanged() { root.windows += 1 }
        function onMessage(text, isError) { if (isError) root.errors = root.errors.concat([text]) }
    }
    Connections {
        target: root.menu
        function onRefused(reason) { root.refusals = root.refusals.concat([reason]); root.log("INFO refused: " + reason) }
    }

    FloatingWindow {
        id: window
        implicitWidth: 1000
        implicitHeight: 800
        Flea.WindowBody { id: body; host: window }
        Item { anchors.fill: parent; TestEvent { id: driver } }
    }
    Timer { interval: root.pollMs; repeat: true; running: !root.finished; onTriggered: root.advance() }
}
