//@ pragma ShellId flea-columnsdrawn-test

import QtQuick
import Quickshell
import "flea" as Flea

// Real ColumnsArea over a stub pane: the child slot of drawnNames names the folder under the cursor, so a folder holding only files draws no child and a cursor folder lists its peeked rows (tests/ui-captures-drops.sh waits on exactly this).
ShellRoot {
    id: root

    Component {
        id: backendStub
        QtObject {
            signal peeked(string path, bool hidden, int total, var rows, bool readFailed, int mode, bool hiddenLast, int first)
            signal metaResult(var message)
            property int dirDev: 0
            property int metaSeq: 0
            property var peekLog: []
            function peek(path, size, hidden) { peekLog.push(String(path)) }
            function askMeta(index, wantLines, wantMedia, wantArchive) { metaSeq += 1; return metaSeq }
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
            property var rows: []
            property var shown: null
            property int cursorIndex: 0
            property bool showHidden: false
            property int windowSize: 35
            property bool listInFlight: false
            property string listingState: "ready"
            property string searchMode: ""
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property var kindNames: ["text-x-generic", "image-x-generic"]
            property bool storageKnown: true
            property string storageClass: "local"
            property int firstSettleMs: 70
            property int settleMs: 120
            property int coalesceMs: 16
            property int refetchMargin: 25
            property int buffer: 150
            property var backend: null
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) { return (index >= 0 && index < rows.length) ? rows[index] : null }
            function isSelected(index) { return false }
            function selectedIndices() { return [] }
            function selectionCount() { return 0 }
            function thumbFor(index) { return "" }
            function open(path) {}
            function openFile(path) {}
            function focusRequested() {}
        }
    }

    Component {
        id: menuStub
        QtObject {
            function close() {}
            function openBackground(point) {}
        }
    }

    property var stubBackend: backendStub.createObject(root)
    property var stubPane: paneStub.createObject(root, { backend: root.stubBackend })
    property var failures: []

    // The area lives in a real window, so the swap's scheduled updates complete and every hold below is a frozen picture.
    FloatingWindow {
        implicitWidth: 1200
        implicitHeight: 600
        color: Flea.Theme.color.background

        Flea.ColumnsArea {
            id: area
            anchors.fill: parent
            pane: root.stubPane
            menu: menuStub.createObject(root)
        }
    }

    property var fileA: ({ n: "p1.txt", d: false, k: 0, p: 420, s: 13, m: 7, t: false, i: "text-x-generic" })
    property var fileB: ({ n: "p2.txt", d: false, k: 0, p: 420, s: 15, m: 8, t: false, i: "text-x-generic" })
    property var folderOuter: ({ n: "outer", d: true, k: 0, p: 493, s: 0, m: 9, t: false, i: "folder" })
    property var innerA: ({ n: "in1.txt", d: false, k: 0, p: 420, s: 11, m: 10, t: false, i: "text-x-generic" })
    property var innerB: ({ n: "in2.txt", d: false, k: 0, p: 420, s: 12, m: 11, t: false, i: "text-x-generic" })
    function fail(text) { root.failures.push(text) }
    function names(rows) { return rows.map(function (row) { return row.n }).join("|") }

    Timer { interval: 600; running: true; repeat: false; onTriggered: root.phaseFilesOnly() }
    Timer { id: folderTimer; interval: 400; repeat: false; onTriggered: root.phaseFolder() }

    // A folder holding only files, cursor on one of them: the file previews in the third column and no child column is drawn.
    function phaseFilesOnly() {
        root.stubPane.rows = [root.fileA, root.fileB]
        root.stubPane.cursorIndex = 0
        filesTimer.start()
    }
    Timer { id: filesTimer; interval: 400; repeat: false; onTriggered: root.phaseFilesChecked() }

    function phaseFilesChecked() {
        if (area.drawnNames("child") !== "")
            root.fail("a cursor on a file draws child names '" + area.drawnNames("child") + "', want none")
        if (root.failures.length > 0) { root.report(); return }
        // The cursor folder lists its peeked rows: the contents of outer are the child column, not the shown folder's own files.
        root.stubPane.rows = [root.folderOuter, root.fileA, root.fileB]
        root.stubPane.cursorIndex = 0
        root.stubBackend.peeked(root.stubPane.join(root.stubPane.path, "outer"), false, 2, [root.innerA, root.innerB], false, 0, false, root.stubPane.windowSize)
        folderTimer.start()
    }

    function phaseFolder() {
        if (area.drawnNames("child") !== "in1.txt|in2.txt")
            root.fail("a cursor on a folder draws child names '" + area.drawnNames("child") + "', want its peeked in1.txt|in2.txt")
        if (root.failures.length === 0)
            console.log("COLUMNSDRAWN PASS file-cursor=no-child folder-cursor=its-rows")
        root.report()
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("COLUMNSDRAWN FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
