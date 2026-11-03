//@ pragma ShellId flea-columnsfilter-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Filter.js" as Filter
import "flea/js/Focus.js" as Focus
import "flea/js/Nav.js" as Nav
import "columnsfilter-fixture.js" as Fixture
import "button-probe.js" as Probe

// Enter commits the filter, j/k walk the kept rows with the preview following, and Escape restores every row on the same file by name; every row is read back from the pane.
ShellRoot {
    id: root

    property var failures: []
    property int stage: 0
    property string parentBefore: ""
    property string escName: ""

    Component {
        id: backendStub
        QtObject {
            signal peeked(string path, bool hidden, int total, var rows, bool readFailed, int mode, bool hiddenLast, int first)
            signal metaResult(var message)
            signal codeResult(var message)
            signal changed(string path)
            signal shebang(string path, bool hasShebang, int id)
            property int dirDev: 0
            function peek(path, size, hidden) {}
            function askMeta(index, wantLines, wantMedia, wantArchive) { return 0 }
            function thumb(rows, cacheOnly) {}
            function thumbcancel(rows) {}
            function dirsize(rows) {}
            function dirsizecancel() {}
            function window(start, count) {}
        }
    }

    Component {
        id: paneStub
        QtObject {
            property string path: "/probe/studio"
            property string listingPath: "/probe/studio"
            property string viewMode: "columns"
            property string focusView: "list"
            property var rows: []
            property var shown: null
            property int shownTotal: 12
            property int total: 12
            property int held: 0
            property int cursorIndex: 4
            property int cursorSeq: 0
            property int renamingIndex: -1
            property var renameRequest: null
            property string renameError: ""
            property bool renamePending: false
            property bool paneFocused: true
            property bool dualMode: false
            property string filterQuery: ""
            property bool filterTyping: false
            property real filterKeyAt: 0
            property real filterNarrowedAt: 0
            property string searchMode: ""
            property string searchQuery: ""
            property QtObject swap: QtObject { property string answeredQuery: "" }
            property string recentMode: ""
            property var clipboard: ({ paths: [], moving: false })
            property var picked: ({})
            property var selection: null
            property int selectionVersion: 0
            property int selectionAnchor: 0
            property string keySequence: ""
            property string keySequenceIdentity: ""
            property real inputAt: 0
            property real rowsAt: 0
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property var kindNames: ["text-x-generic"]
            property bool showHidden: false
            property bool storageKnown: true
            property string storageClass: "local"
            property bool listInFlight: false
            property string listingState: "ready"
            property var trash: ({ opened: false })
            property var selectionBand: null
            property var sidebar: null
            property int previewIndex: -1
            property int trashArmedAt: 0
            property var pendingSort: null
            property var pendingBackground: []
            property string stateMessage: ""
            property int lockedMode: 0
            property string dropPath: ""
            property bool dragHolding: false
            property int visibleRows: 8
            property int firstSettleMs: 70
            property int settleMs: 120
            property int coalesceMs: 16
            property int refetchMargin: 25
            property int buffer: 150
            property int windowSize: 35
            property var backend: null
            property var statusBar: null
            property var listArea: ({ primeSettle: function () {} })
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) { var o = index - held; return (o >= 0 && o < rows.length) ? rows[o] : null }
            function isSelected(index) { return picked[index] === true }
            function selectedIndices() { var out = []; for (var k in picked) out.push(Number(k)); return out }
            function selectionCount() { return selectedIndices().length }
            function clearSelection() { picked = {}; selectionVersion += 1 }
            function thumbFor(index) { return "" }
            function showRow(view, context) {}
            function renameEditor() { return null }
            function cancelSlowClick() {}
            function act(action) { Focus.act(action, root.stubPane) }
            function open(path) {}
            function openFile(path) {}
            function focusRequested() {}
            function refresh() {
                shown = Filter.shown(rows, held, filterQuery)
                shownTotal = shown === null ? total : shown.length
            }
            function typeQuery(text) {
                Filter.start(root.stubPane)
                for (var i = 0; i < text.length; i++) {
                    Filter.typed(root.stubPane, text.charAt(i))
                    root.stubPane.refresh()
                }
                Filter.commit(root.stubPane)
            }
        }
    }

    Component {
        id: menuStub
        QtObject {
            function close() {}
            function openBackground(point) {}
        }
    }

    Component {
        id: statusStub
        QtObject { property var activities: [] }
    }

    property var stubBackend: backendStub.createObject(root)
    property var stubStatus: statusStub.createObject(root)
    property var stubPane: paneStub.createObject(root, { backend: root.stubBackend, rows: Fixture.buildRows(), statusBar: root.stubStatus })
    // The real IPC seam over the stub pane: filterStamps reports what the product reports.
    QtObject { id: windowStub; function centreOf(item) { return "" } function rectOf(item) { return "" } }
    Flea.Ipc { id: ipc; pane: root.stubPane; fleaWindow: windowStub }

    Component.onCompleted: {
        // Filter.prune's toggle and Marks.follow's read, closing over the stub pane.
        root.stubPane.selection = {
            toggle: function (i) { var p = root.stubPane.picked; if (p[i]) delete p[i]; else p[i] = true },
            follows: function () { return false },
            only: function (i) { var p = {}; p[i] = true; root.stubPane.picked = p }
        }
    }

    FloatingWindow {
        implicitWidth: 1500
        implicitHeight: 700
        color: Flea.Theme.color.background

        Flea.FilterStrip {
            id: strip
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            pane: root.stubPane
        }

        Flea.ColumnsArea {
            id: area
            anchors.top: strip.bottom
            anchors.left: parent.left
            anchors.right: parent.horizontalCenter
            anchors.rightMargin: -200
            anchors.bottom: parent.bottom
            pane: root.stubPane
            menu: menuStub.createObject(root)
        }

        Flea.ColumnRow { id: probeRow; opacity: 0; width: 400; row: Fixture.searchRow(); pane: Fixture.searchPane("final") }
        Flea.ColumnRow { id: cursorProbe; opacity: 0; width: 400; row: Fixture.searchRow(); pane: Fixture.searchPane("final") }

        Flea.GridArea {
            id: grid
            anchors.top: strip.bottom
            anchors.left: area.right
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            pane: root.stubPane
            menu: menuStub.createObject(root)
        }
    }

    Timer { interval: 800; running: true; repeat: false; onTriggered: root.measureRest() }
    Timer { id: commitTimer; interval: 600; repeat: false; onTriggered: root.measureCommit() }
    Timer { id: walkTimer; interval: 700; repeat: false; onTriggered: root.measureWalk() }
    Timer { id: previewTimer; interval: 700; repeat: false; onTriggered: root.measurePreview() }
    Timer { id: escapeTimer; interval: 800; repeat: false; onTriggered: root.measureEscape() }
    Timer { id: navPrepTimer; interval: 600; repeat: false; onTriggered: root.measureNavPrep() }
    Timer { id: navTimer; interval: 600; repeat: false; onTriggered: root.measureNav() }

    function fail(text) { root.failures.push(text) }
    // Every key takes the product route and the stub recomputes the pane's own shown behind it.
    function press(key, text) {
        Focus.handleKey({ key: key, text: text, modifiers: Qt.NoModifier }, root.stubPane, null)
        root.stubPane.refresh()
    }

    // At rest both views list the whole window and the List strip itself stands down.
    function measureRest() {
        // "a" alone in Columns stays keys.toml's [[text]] char="a" network binding, so the dropped "/" left it where it belongs.
        var aKey = Focus.lookup({ key: Qt.Key_A, text: "a", modifiers: Qt.NoModifier }, root.stubPane)
        if (aKey !== "addNetwork")
            root.fail("rest routes a to " + aKey + ", want addNetwork")
        if (Fixture.activeCount(area) !== 12)
            root.fail("rest lists " + Fixture.activeCount(area) + " active rows, want 12")
        if (grid.count !== 12)
            root.fail("rest lists " + grid.count + " grid tiles, want 12")
        if (strip.up !== false)
            root.fail("rest holds the strip up with no query")
        if (area.showParent !== true)
            root.fail("rest draws no parent column to hold still")
        if (root.failures.length > 0) { root.report(); return }
        Fixture.answerParentPeek(root.stubBackend, root.stubPane.windowSize)
        root.parentBefore = Fixture.parentNames(area)
        if (root.parentBefore === "")
            root.fail("rest answers no parent peek to hold still")
        root.stubPane.picked = { 4: true, 5: true }
        var restItems = Fixture.built(area.itemAtIndex(0))
        root.press(Qt.Key_Slash, "/")
        Fixture.armFailures(area.itemAtIndex(0), restItems).forEach(root.fail)
        root.press(Qt.Key_A, "a")
        root.press(Qt.Key_P, "p")
        if (root.stubPane.filterTyping !== true)
            root.fail("typing leaves the query line without the caret")
        if (root.failures.length > 0) { root.report(); return }
        root.stage = 1
        commitTimer.start()
    }

    // Enter keeps the narrowed rows and hands the keyboard back with the query standing; both views draw the matches through one strip.
    function measureCommit() {
        root.press(Qt.Key_Return, "")
        if (root.stubPane.filterTyping !== false)
            root.fail("enter keeps the query line typing")
        if (root.stubPane.filterQuery !== "ap")
            root.fail("enter drops query " + root.stubPane.filterQuery + ", want ap")
        if (root.stubPane.shownTotal !== 6)
            root.fail("enter keeps " + root.stubPane.shownTotal + " rows, want 6")
        if (Fixture.activeCount(area) !== 6)
            root.fail("enter lists " + Fixture.activeCount(area) + " active rows, want 6")
        if (grid.count !== 6)
            root.fail("enter lists " + grid.count + " grid tiles, want 6")
        var first = area.itemAtIndex(0)
        if (first === null || first.row === null || first.row.n !== "Apps")
            root.fail("enter draws no Apps delegate first")
        if (strip.up !== true || strip.height <= 0)
            root.fail("enter leaves the List strip down")
        if (Filter.summary(root.stubPane.shown, 12, 12) !== "6 of 12 shown")
            root.fail("enter sentences " + Filter.summary(root.stubPane.shown, 12, 12))
        Fixture.markFailures(first, probeRow, root.stubPane, Flea.Theme).forEach(root.fail)
        var colStamps = Fixture.stamps(ipc)
        if (colStamps.view !== "columns" || !(colStamps.keyAt > 0 && colStamps.keyAt <= colStamps.narrowedAt))
            root.fail("stamps name " + JSON.stringify(colStamps) + " in columns")
        root.stubPane.viewMode = "grid"
        var gridStamps = Fixture.stamps(ipc)
        if (gridStamps.view !== "grid" || !(gridStamps.keyAt > 0 && gridStamps.keyAt <= gridStamps.narrowedAt))
            root.fail("stamps name " + JSON.stringify(gridStamps) + " in grid")
        root.stubPane.viewMode = "columns"
        if (Fixture.parentNames(area) !== root.parentBefore)
            root.fail("enter moved the parent column")
        if (root.stubPane.cursorIndex !== 4)
            root.fail("enter moved a cursor it still shows")
        if (JSON.stringify(root.stubPane.selectedIndices()) !== "[4]")
            root.fail("enter keeps selection " + JSON.stringify(root.stubPane.selectedIndices()) + ", want [4]")
        if (root.failures.length > 0) { root.report(); return }
        root.stage = 2
        walkTimer.start()
    }

    // j and k after Enter walk the kept rows only, skipping the hidden row between two matches.
    function measureWalk() {
        root.press(Qt.Key_J, "j")
        if (root.stubPane.cursorIndex !== 6 || !Fixture.shownHas(root.stubPane, 6))
            root.fail("j lands cursor " + root.stubPane.cursorIndex + ", want shown 6")
        root.press(Qt.Key_K, "k")
        if (root.stubPane.cursorIndex !== 4 || !Fixture.shownHas(root.stubPane, 4))
            root.fail("k lands cursor " + root.stubPane.cursorIndex + ", want shown 4")
        if (root.failures.length > 0) { root.report(); return }
        root.stage = 3
        previewTimer.start()
    }

    // Once the settle lands the filtered preview shows the cursor's own row, then j steps to the Escape anchor.
    function measurePreview() {
        if (Fixture.preview(area).loadedIndex !== 4)
            root.fail("preview holds " + Fixture.preview(area).loadedIndex + ", want cursor 4")
        if (Fixture.preview(area).path !== "/probe/studio/caption.png")
            root.fail("preview paths " + Fixture.preview(area).path + ", want the caption")
        root.press(Qt.Key_J, "j")
        if (root.stubPane.cursorIndex !== 6 || !Fixture.shownHas(root.stubPane, 6))
            root.fail("j lands cursor " + root.stubPane.cursorIndex + ", want shown 6")
        if (root.failures.length > 0) { root.report(); return }
        root.stage = 4
        escapeTimer.start()
    }

    // Escape restores every row with the cursor on the same file by name: listing row 6 against shown 3, so an index restore reads wrong.
    function measureEscape() {
        if (Fixture.preview(area).loadedIndex !== 6)
            root.fail("preview holds " + Fixture.preview(area).loadedIndex + " past j, want cursor 6")
        if (Fixture.preview(area).path !== "/probe/studio/gap.md")
            root.fail("preview paths " + Fixture.preview(area).path + " past j, want the gap")
        root.escName = root.stubPane.rowFor(root.stubPane.cursorIndex).n
        root.press(Qt.Key_Escape, "")
        if (root.stubPane.filterQuery !== "")
            root.fail("esc keeps query " + root.stubPane.filterQuery)
        if (Fixture.activeCount(area) !== 12)
            root.fail("esc lists " + Fixture.activeCount(area) + " active rows, want 12")
        if (grid.count !== 12)
            root.fail("esc lists " + grid.count + " grid tiles, want 12")
        if (strip.up !== false)
            root.fail("esc leaves the strip up")
        if (root.stubPane.cursorIndex !== 6)
            root.fail("esc moves the cursor to " + root.stubPane.cursorIndex + ", want 6")
        if (root.stubPane.rowFor(root.stubPane.cursorIndex).n !== root.escName)
            root.fail("esc stands on " + root.stubPane.rowFor(root.stubPane.cursorIndex).n + ", want " + root.escName)
        if (root.failures.length > 0) { root.report(); return }
        root.stage = 5
        navPrepTimer.start()
    }

    // A navigation forgets the filter the way List does; the rows below stand in for the re-list landing behind it.
    function measureNavPrep() {
        root.stubPane.typeQuery("ap")
        if (Fixture.activeCount(area) !== 6) {
            root.fail("re-filter lists " + Fixture.activeCount(area) + " active rows, want 6")
            root.report()
            return
        }
        Nav.forget(root.stubPane)
        if (root.stubPane.filterQuery !== "")
            root.fail("a navigation keeps query " + root.stubPane.filterQuery)
        root.stubPane.rows = Fixture.buildRows()
        root.stubPane.total = 12
        root.stubPane.listingState = "ready"
        root.stubPane.refresh()
        root.stage = 6
        navTimer.start()
    }

    // After the navigation both views list the whole window again.
    function measureNav() {
        if (Fixture.activeCount(area) !== 12)
            root.fail("navigated lists " + Fixture.activeCount(area) + " active rows, want 12")
        if (grid.count !== 12)
            root.fail("navigated lists " + grid.count + " grid tiles, want 12")
        if (strip.up !== false)
            root.fail("navigated leaves the strip up")
        if (Fixture.parentNames(area) !== root.parentBefore)
            root.fail("navigated moved the parent column")
        root.press(Qt.Key_Slash, "/")
        root.press(Qt.Key_Z, "z")
        root.press(Qt.Key_Z, "z")
        root.press(Qt.Key_Z, "z")
        if (area.shownHasRow !== false || area.shownChildPath !== "")
            root.fail("nomatch holds " + area.shownChildPath + ", want empty")
        root.press(Qt.Key_Escape, "")
        root.stubBackend.peeked("/probe/studio/Apps", false, 0, [], false, 0, false, root.stubPane.windowSize)
        if (area.shownHasRow !== true || area.shownChildPath !== "/probe/studio/Apps")
            root.fail("esc holds " + area.shownChildPath + ", want the Apps column")
        root.press(Qt.Key_Slash, "/")
        root.press(Qt.Key_A, "a")
        root.press(Qt.Key_P, "p")
        root.press(Qt.Key_Z, "z")
        if (area.shownHasRow !== false)
            root.fail("apz holds a row")
        root.press(Qt.Key_Backspace, "")
        if (area.shownHasRow !== true || Fixture.activeCount(area) !== 6)
            root.fail("backspace holds " + Fixture.activeCount(area) + " rows, want 6 with a column")
        Fixture.hiddenFailures(area, root.stubPane, root.press).forEach(root.fail)
        // Last, because it swaps the palette: the sandbox accent equals its foreground, which hides a name drawn in cellInk.
        Flea.Theme.applyColors(Probe.COLOURED_THEME)
        Fixture.nameInkFailures(cursorProbe, probeRow, Flea.Theme).forEach(root.fail)
        if (root.failures.length > 0) { root.report(); return }
        console.log("COLUMNSFILTER PASS active=6-of-12 grid=6-of-12 strip=list esc=restored nav=forgotten parent=kept commit=enter-kept walk=j-k-kept preview=follows escape=name-kept stamps=columns-grid nomatch=empty-esc-restored-backspace-match hidden=no-marks")
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("COLUMNSFILTER FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
