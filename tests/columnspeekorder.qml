//@ pragma ShellId flea-columnspeekorder-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/FolderSorts.js" as FolderSorts

// A shown column re-asks when its folder's remembered order changes with the path unchanged, and drops a reply sorted under the order it had before.
ShellRoot {
    id: root

    Component {
        id: backendStub
        QtObject {
            signal peeked(string path, bool hidden, int total, var rows, bool readFailed, int mode, bool hiddenLast, int first, var dev, var writable, string by, bool desc)
            signal metaResult(var message)
            property var peekLog: []
            // The order the real Backend.peek sends, read from the same state at the same moment.
            function peek(path, first, hidden, hiddenLast, keep) {
                var order = FolderSorts.peekOrder(Flea.ViewState.state.folderSorts, path, Flea.ViewState.state.rememberSort, keep)
                peekLog.push({ path: String(path), by: order.by || "", desc: order.desc === true })
            }
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
            property string path: "/x/y"
            property var rows: []
            property int cursorIndex: 0
            property bool showHidden: false
            property int windowSize: 35
            property bool listInFlight: false
            property string listingState: "ready"
            property string searchMode: ""
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property var kindNames: ["text-x-generic"]
            property bool storageKnown: true
            property string storageClass: "local"
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

    FloatingWindow {
        implicitWidth: 1200
        implicitHeight: 600
        color: Flea.Theme.color.background

        Flea.ColumnsArea {
            id: area
            width: 1100
            height: 600
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            pane: root.stubPane
            menu: menuStub.createObject(root)
        }
    }

    function fail(text) { root.failures.push(text) }

    // The asks for path in the log, each as "by/desc", for instance "size/1", or "/0" for name order.
    function asks(path) {
        var out = []
        root.stubBackend.peekLog.forEach(function (one) { if (one.path === path) out.push(one.by + "/" + (one.desc ? "1" : "0")) })
        return out
    }

    function drawn(path) { return area.rowsFor(path).map(function (row) { return row.n }).join("|") }

    function reply(path, names, by, desc) {
        var rows = names.map(function (name) { return { n: name, d: false, i: "text-x-generic" } })
        root.stubBackend.peeked(path, false, rows.length, rows, false, 0, false, root.stubPane.windowSize, 0, true, by, desc)
    }

    // Each write is what another window's sort, or the Settings switch, leaves in the shared state.
    function writeState(change) {
        var next = {}
        var now = Flea.ViewState.state || {}
        for (var k in now) next[k] = now[k]
        for (var c in change) next[c] = change[c]
        Flea.ViewState.state = next
    }

    Timer {
        interval: 700
        running: true
        repeat: false
        onTriggered: root.phaseRace()
    }
    Timer { id: landTimer; interval: 250; repeat: false; onTriggered: root.phaseLand() }
    Timer { id: rememberTimer; interval: 250; repeat: false; onTriggered: root.phaseRemember() }
    Timer { id: quietTimer; interval: 250; repeat: false; onTriggered: root.phaseQuiet() }

    // The parent column's first ask goes out in name order and stays out while /x turns to size order.
    function phaseRace() {
        if (root.asks("/x").join(",") !== "/0")
            root.fail("the first ask of /x is [" + root.asks("/x").join(",") + "], want one name-order ask")
        if (root.failures.length > 0) { root.report(); return }
        root.writeState({ folderSorts: { "/x": { key: "size", reverse: true } }, rememberSort: true })
        landTimer.start()
    }

    // The order change re-asks /x, the name-order reply landing after it is dropped, and the size-order reply is drawn.
    function phaseLand() {
        if (root.asks("/x").indexOf("size/1") < 0)
            root.fail("/x turned to size order with the path unchanged and its column asked [" + root.asks("/x").join(",") + "], want a size/1 ask")
        root.reply("/x", ["a", "b"], "", false)
        if (root.drawn("/x") === "a|b")
            root.fail("a name-order reply that lands after /x turned to size order is drawn as /x")
        root.reply("/x", ["b", "a"], "size", true)
        if (root.drawn("/x") !== "b|a")
            root.fail("the size-order reply of /x is not drawn, the column shows [" + root.drawn("/x") + "]")
        root.stubBackend.peekLog = []
        root.writeState({ rememberSort: false })
        rememberTimer.start()
    }

    // Turning remembering off re-asks /x in name order, and the size-order rows stay drawn until that reply lands.
    function phaseRemember() {
        var asked = root.asks("/x")
        if (asked.indexOf("/0") < 0)
            root.fail("turning folder sort memory off left /x in its remembered order, the column asked [" + asked.join(",") + "], want a name-order ask")
        else if (root.drawn("/x") !== "b|a")
            root.fail("/x shows [" + root.drawn("/x") + "] while its name-order re-ask is out, want the size-order rows held")
        root.reply("/x", ["a", "b"], "", false)
        if (root.drawn("/x") !== "a|b")
            root.fail("the name-order reply of /x is not drawn, the column shows [" + root.drawn("/x") + "]")
        root.stubBackend.peekLog = []
        root.writeState({ rememberSort: true, folderSorts: { "/elsewhere": { key: "size", reverse: false }, "/x/y": { key: "mtime", reverse: true } } })
        quietTimer.start()
    }

    // A sort written for a folder no column shows, or for the listed folder itself, asks no peek.
    function phaseQuiet() {
        var log = root.stubBackend.peekLog.map(function (one) { return one.path + " " + one.by })
        if (log.length !== 0)
            root.fail("a sort written for folders no column shows asked [" + log.join(",") + "], want nothing")
        if (root.failures.length === 0)
            console.log("COLUMNSPEEKORDER PASS reorder=reask stale=dropped held=rows remember=reask quiet=none")
        root.report()
    }

    function report() {
        for (var f = 0; f < root.failures.length; f++)
            console.log("COLUMNSPEEKORDER FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
