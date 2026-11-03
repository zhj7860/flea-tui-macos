//@ pragma ShellId flea-columnsfilter-edge-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Focus.js" as Focus
import "flea/js/Filter.js" as Filter
import "columnsfilter-fixture.js" as Fixture

// The third column across a filter key that hides the cursor's folder never lands an empty column while a match remains.
ShellRoot {
    id: root

    property var failures: []
    property var log: []
    property int stage: 0
    readonly property string base: "/probe/studio"

    Component {
        id: backendStub
        QtObject {
            signal peeked(string path, bool hidden, int total, var rows, bool readFailed, int mode, bool hiddenLast, int first)
            signal metaResult(var message)
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
            // A binding, as in ui/Pane.qml: Filter.apply writes the query before it moves the cursor, so one pass stands it on a hidden row.
            readonly property var shown: Filter.shown(rows, held, filterQuery)
            readonly property int shownTotal: shown === null ? total : shown.length
            property int total: 12
            property int held: 0
            property int cursorIndex: 1
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
        }
    }

    Component { id: menuStub; QtObject { function close() {} function openBackground(point) {} } }
    Component { id: statusStub; QtObject { property var activities: [] } }

    property var stubBackend: backendStub.createObject(root)
    property var stubPane: paneStub.createObject(root, { backend: root.stubBackend, rows: Fixture.buildRows(), statusBar: statusStub.createObject(root) })

    Component.onCompleted: {
        root.stubPane.selection = {
            toggle: function (i) { var p = root.stubPane.picked; if (p[i]) delete p[i]; else p[i] = true },
            follows: function () { return false },
            only: function (i) { var p = {}; p[i] = true; root.stubPane.picked = p }
        }
    }

    FloatingWindow {
        implicitWidth: 1100
        implicitHeight: 600
        color: Flea.Theme.color.background

        Flea.ColumnsArea {
            id: area
            anchors.fill: parent
            pane: root.stubPane
            menu: menuStub.createObject(root)
        }
    }

    // Every change of what the third column draws, in order, so a pass that landed and was replaced in the same turn still shows.
    function note() { root.log.push((area.shownHasRow ? "row" : "empty") + ":" + (area.shownIsDir ? "dir" : "file") + ":" + area.shownChildPath) }
    Connections {
        target: area
        function onShownHasRowChanged() { root.note() }
        function onShownIsDirChanged() { root.note() }
        function onShownChildPathChanged() { root.note() }
    }

    Timer { id: step; interval: 700; running: true; repeat: false; onTriggered: root.advance() }

    function fail(text) { root.failures.push("stage " + root.stage + " " + text) }
    function press(key, text) { Focus.handleKey({ key: key, text: text, modifiers: Qt.NoModifier }, root.stubPane, null) }
    function answer(name, rows) { root.stubBackend.peeked(root.base + "/" + name, false, rows.length, rows, false, 0, false, root.stubPane.windowSize) }
    function take() { return { n: "take1.mov", d: false, i: "text-x-generic", p: 420, s: 1, m: 1, t: false, k: 0 } }
    function swap() { return area.swapState() }
    function blanks() { return root.log.filter(function (one) { return one.indexOf("empty:") === 0 }) }
    function expectShown(hasRow, isDir, path, what) {
        if (area.shownHasRow !== hasRow || area.shownIsDir !== isDir || area.shownChildPath !== path)
            root.fail(what + " draws " + area.shownHasRow + "," + area.shownIsDir + "," + area.shownChildPath + ", want " + hasRow + "," + isDir + "," + path)
    }
    function expectIdle(what) { if (root.swap().capturing || root.swap().holding) root.fail(what + " leaves the third column held") }
    function expectNoBlank(what) { if (root.blanks().length > 0) root.fail(what + " drew an empty third column: " + root.log.join(" ")) }
    function next(ms) { root.stage += 1; step.interval = ms; step.start() }

    function advance() {
        switch (root.stage) {
        case 0:
            // Rest: the cursor on the Clips folder, its rows answered and drawn.
            root.answer("Clips", [root.take()])
            root.expectShown(true, true, root.base + "/Clips", "rest")
            return root.failures.length > 0 ? root.report() : root.next(400)
        case 1:
            // "t" hides every folder and keeps balsam.txt first: the preview takes its hold over the Clips picture.
            root.expectIdle("rest")
            root.log = []
            root.press(Qt.Key_Slash, "/")
            root.press(Qt.Key_T, "t")
            if (root.stubPane.cursorIndex !== 3) root.fail("t lands cursor " + root.stubPane.cursorIndex + ", want 3")
            root.expectNoBlank("t")
            return root.next(700)
        case 2:
            root.expectNoBlank("t, after the hold")
            root.expectShown(true, false, "", "t, after the hold")
            root.expectIdle("t, after the hold")
            root.press(Qt.Key_Escape, "")
            root.stubPane.cursorIndex = 1
            return root.failures.length > 0 ? root.report() : root.next(700)
        case 3:
            // "a" hides Clips and keeps the unanswered Apps folder first: Clips stays up until Apps answers.
            root.expectShown(true, true, root.base + "/Clips", "back on Clips")
            root.expectIdle("back on Clips")
            root.log = []
            root.press(Qt.Key_Slash, "/")
            root.press(Qt.Key_A, "a")
            if (root.stubPane.cursorIndex !== 0) root.fail("a lands cursor " + root.stubPane.cursorIndex + ", want 0")
            root.expectNoBlank("a")
            root.answer("Apps", [root.take()])
            root.expectShown(true, true, root.base + "/Apps", "a, Apps answered")
            root.expectNoBlank("a, Apps answered")
            return root.failures.length > 0 ? root.report() : root.next(400)
        case 4:
            // A query matching nothing has no row to move to, so the column empties at once.
            root.press(Qt.Key_Z, "z")
            root.expectShown(false, false, "", "az")
            root.press(Qt.Key_Escape, "")
            return root.next(400)
        case 5:
            // A listing refresh that hides the cursor's folder while matches remain moves no cursor, so the column empties.
            root.expectShown(true, true, root.base + "/Apps", "esc")
            root.press(Qt.Key_Slash, "/")
            root.press(Qt.Key_A, "a")
            root.press(Qt.Key_P, "p")
            var renamed = Fixture.buildRows()
            renamed[0] = { n: "Bins", d: true, i: "folder", p: 493, s: 0, m: 1, t: false, k: 0 }
            root.stubPane.rows = renamed
            return root.next(300)
        case 6:
            root.expectShown(false, false, "", "refresh")
            root.expectIdle("refresh")
            root.press(Qt.Key_Escape, "")
            root.stubPane.rows = Fixture.buildRows()
            root.stubPane.cursorIndex = 3
            return root.failures.length > 0 ? root.report() : root.next(700)
        case 7:
            // A search answer with no rows nulls the cursor row under an unmoved index; the column drops the file it showed.
            root.expectShown(true, false, "", "on balsam.txt")
            root.stubPane.rows = []
            return root.next(300)
        case 8:
            root.expectShown(false, false, "", "zero-row answer")
            root.expectIdle("zero-row answer")
            root.stubPane.rows = Fixture.buildRows()
            return root.failures.length > 0 ? root.report() : root.next(300)
        case 9:
            // Rows coming back under the unmoved index show the file again.
            root.expectShown(true, false, "", "rows back")
            return root.pass()
        }
    }

    function pass() {
        if (root.failures.length > 0) return root.report()
        console.log("COLUMNSFILTEREDGE PASS file-match=held-no-empty folder-match=held-until-answered nomatch=empty refresh=empty zero-rows=empty rows-back=shown")
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("COLUMNSFILTEREDGE FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
