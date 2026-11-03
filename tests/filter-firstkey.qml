//@ pragma ShellId flea-filter-firstkey-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Filter.js" as Filter

// Per filter key and strip open, a real ui/List.qml over a stub pane counts delegates built synchronously, marks drawn that frame, backend calls, and the time to the next afterAnimating.
ShellRoot {
    id: root

    property var failures: []
    property var phases: []
    property var backendCalls: []
    property var showRowCalls: []
    property var listRef: null
    property var cycleSync: []
    property var cycleMade: []
    property var cycleGone: []
    property var keyLive: null
    property var missingMarks: []
    property var applyMs: []
    property var shownMs: []

    function buildRows() {
        var rows = []
        for (var i = 0; i < 300; i++) {
            var n = (i % 2 === 0 ? "ke-" : "xa-") + ("00" + i).slice(-3) + ".txt"
            rows.push({ n: n, d: false, i: "text-x-generic", p: 33188, s: 100 + i, m: 1758835200, t: false, k: 0 })
        }
        return rows
    }

    Component {
        id: backendStub
        QtObject {
            function peek(path, size, hidden) {}
            function thumb(rows, cacheOnly) { root.backendCalls.push("thumb:" + rows.length) }
            function thumbcancel(rows) { root.backendCalls.push("thumbcancel:" + rows.length) }
            function dirsize(rows) { root.backendCalls.push("dirsize:" + rows.length) }
            function dirsizecancel() { root.backendCalls.push("dirsizecancel") }
            function window(start, count) { root.backendCalls.push("window:" + start + ":" + count) }
        }
    }

    Component {
        id: paneStub
        QtObject {
            property string path: "/probe"
            property var rows: []
            property var shown: null
            property int shownTotal: 300
            property int total: 300
            property int held: 0
            property int cursorIndex: 0
            property int cursorSeq: 0
            property int renamingIndex: -1
            property bool paneFocused: true
            property bool dualMode: false
            property var clipboard: ({ paths: [], moving: false })
            property var selection: ({})
            property int selectionVersion: 0
            property var thumbState: ({ file: {}, order: [] })
            // One size still asked, so every filter key reaches List.qml's dirsizecancel through the stub.
            property var dirSizeState: ({ file: { "/probe/ke-000.txt": null }, order: ["/probe/ke-000.txt"] })
            property var kindNames: []
            property string searchMode: ""
            property string searchQuery: ""
            property string recentMode: ""
            property string filterQuery: ""
            property bool filterTyping: false
            property real filterKeyAt: 0
            property real filterNarrowedAt: 0
            property var selectionBand: null
            property int previewIndex: -1
            property bool storageKnown: true
            property string storageClass: ""
            property bool listInFlight: false
            property string listingState: "ready"
            property int visibleRows: 8
            property int cacheRows: 0
            property int firstSettleMs: 70
            property int settleMs: 120
            property int coalesceMs: 16
            property int refetchMargin: 25
            property int buffer: 150
            property int windowSize: 35
            property var backend: null
            property var statusBar: null
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) { var o = index - held; return (o >= 0 && o < rows.length) ? rows[o] : null }
            function isSelected(index) { return false }
            function selectedIndices() { return [] }
            function thumbFor(index) { return "" }
            function commitRename(newName) {}
            function showRow(view, context) {
                root.showRowCalls.push(view)
                if (root.listRef) root.listRef.showCursor(view, context)
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

    property var stubBackend: backendStub.createObject(root)
    property var stubMenu: menuStub.createObject(root)
    property var stubPane: paneStub.createObject(root, { backend: root.stubBackend, rows: root.buildRows() })

    FloatingWindow {
        id: win
        implicitWidth: 900
        implicitHeight: 600
        color: Flea.Theme.color.background

        Flea.List {
            id: list
            width: 700
            height: 400
            anchors.centerIn: parent
            pane: root.stubPane
            menu: root.stubMenu
        }
    }


    // The product's own bindings, not the stub's constants: shown recomputes off the query.
    Component.onCompleted: {
        root.listRef = list
        root.stubPane.shown = Qt.binding(function () { return Filter.shown(root.stubPane.rows, root.stubPane.held, root.stubPane.filterQuery) })
        root.stubPane.shownTotal = Qt.binding(function () { return root.stubPane.shown === null ? root.stubPane.total : root.stubPane.shown.length })
        root.stubPane.visibleRows = Qt.binding(function () { return Math.max(1, Math.ceil(list.height / Flea.Theme.fileRowHeight)) })
    }

    function countUnder(item) {
        var n = 0
        var stack = [item]
        while (stack.length > 0) {
            var o = stack.pop()
            n += 1
            var kids = (o !== null && o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
        }
        return n - 1
    }

    // Marked MatchTexts whose wash Loader holds no item in this same turn: a deferred mark.
    function countMissingMarks() {
        var missing = 0
        var stack = [list]
        while (stack.length > 0) {
            var o = stack.pop()
            if (o !== null && o !== undefined && o.marked === true) {
                var kids = o.children !== undefined ? o.children : []
                for (var i = 0; i < kids.length; i++) {
                    var c = kids[i]
                    if (c !== null && c !== undefined && c.item !== undefined && c.active !== undefined && c.item === null)
                        missing += 1
                }
            }
            var all = (o !== null && o !== undefined && o.children !== undefined) ? o.children : []
            for (var j = 0; j < all.length; j++) stack.push(all[j])
        }
        return missing
    }

    // Every live object under the list in one walk, so tagging and counting share no duplicated traversal.
    function liveList() {
        var out = []
        var stack = [list]
        while (stack.length > 0) {
            var o = stack.pop()
            if (o !== null && o !== undefined) out.push(o)
            var kids = (o !== null && o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
        }
        return out
    }

    // Remembers every live object by identity, so a key that destroys N delegates and creates N still shows as made plus gone.
    function snapLive() {
        var seen = new Map()
        var items = root.liveList()
        for (var i = 0; i < items.length; i++) seen.set(items[i], true)
        root.keyLive = seen
    }
    function countMadeGone() {
        var now = new Map()
        var made = 0
        var items = root.liveList()
        for (var i = 0; i < items.length; i++) {
            now.set(items[i], true)
            if (!root.keyLive.has(items[i])) made += 1
        }
        var gone = 0
        root.keyLive.forEach(function (flag, object) { if (!now.has(object)) gone += 1 })
        root.cycleMade.push(made)
        root.cycleGone.push(gone)
    }

    property int lastObjects: -1
    property int lastBackend: 0

    function snap(label) {
        var objects = root.countUnder(list)
        var built = root.lastObjects < 0 ? 0 : objects - root.lastObjects
        var calls = root.backendCalls.slice(root.lastBackend)
        var line = label + " objects=" + objects + " built=" + built
            + " backend=[" + calls.join(",") + "] contentY=" + Math.round(list.contentY)
            + " cursor=" + root.stubPane.cursorIndex + " shown=" + (root.stubPane.shown === null ? "null" : root.stubPane.shown.length)
            + " showRows=[" + root.showRowCalls.join(",") + "]"
        root.phases.push(line)
        console.log("FIRSTKEY " + line)
        root.lastObjects = objects
        root.lastBackend = root.backendCalls.length
        root.showRowCalls = []
        return built
    }

    // One open/type cycle: the strip frame, then three keys, each snapped same-turn.
    property int cycle: 0
    property var keys: ["k", "e", "y"]
    property int keyIdx: 0
    property int restObjects: -1
    property int key1SettledObjects: -1

    Timer { interval: 800; running: true; repeat: false; onTriggered: root.openCycle() }
    Timer { id: slashTimer; interval: 500; repeat: false; onTriggered: root.afterSlash() }
    Timer { id: keyTimer; interval: 500; repeat: false; onTriggered: root.afterKey() }

    function openCycle() {
        if (root.cycle === 0)
            root.snap("rest")
        else
            root.snap("rest-c" + root.cycle)
        root.restObjects = root.lastObjects
        Filter.close(root.stubPane)
        Filter.start(root.stubPane)
        root.snap(root.cycle === 0 ? "slash" : "slash-c" + root.cycle)
        root.keyIdx = 0
        slashTimer.start()
    }

    function afterSlash() {
        root.snap(root.cycle === 0 ? "slashsettled" : "slashsettled-c" + root.cycle)
        root.typeKey()
    }

    function typeKey() {
        var p = root.stubPane
        root.snapLive()
        var t0 = Date.now()
        Filter.shown(p.rows, p.held, p.filterQuery + root.keys[root.keyIdx])
        root.shownMs.push(Date.now() - t0)
        t0 = Date.now()
        Filter.typed(p, root.keys[root.keyIdx])
        root.applyMs.push(Date.now() - t0)
        var tag = "key" + (root.keyIdx + 1) + (root.cycle === 0 ? "" : "-c" + root.cycle)
        var built = root.snap(tag + "sync")
        root.cycleSync.push(built)
        root.missingMarks.push(root.countMissingMarks())
        root.keyIdx += 1
        keyTimer.start()
    }

    function afterKey() {
        var doneTag = "key" + root.keyIdx + (root.cycle === 0 ? "" : "-c" + root.cycle)
        root.snap(doneTag + "settled")
        root.countMadeGone()
        if (root.keyIdx === 1)
            root.key1SettledObjects = root.lastObjects
        if (root.keyIdx < root.keys.length) {
            root.typeKey()
            return
        }
        root.cycle += 1
        if (root.cycle < 4) {
            root.openCycle()
            return
        }
        root.report()
    }

    function report() {
        console.log("FIRSTKEY applyms=" + JSON.stringify(root.applyMs) + " shownms=" + JSON.stringify(root.shownMs))
        console.log("FIRSTKEY syncbuilt=" + JSON.stringify(root.cycleSync))
        console.log("FIRSTKEY madegone=" + JSON.stringify(root.cycleMade) + " " + JSON.stringify(root.cycleGone))
        console.log("FIRSTKEY missingmarks=" + JSON.stringify(root.missingMarks))
        // RED: the first key of every cycle must build nothing synchronously, with every mark drawn in that same frame.
        var fails = []
        for (var c = 0; c < root.cycleSync.length; c++) {
            if (c % 3 === 0 && root.cycleSync[c] !== 0)
                fails.push("cycle " + (c / 3) + " first key built " + root.cycleSync[c] + " objects synchronously, want 0")
            if (c % 3 === 0 && root.cycleMade[c] + root.cycleGone[c] !== 0)
                fails.push("cycle " + (c / 3) + " first key made " + root.cycleMade[c] + " and lost " + root.cycleGone[c] + " delegates, want 0 and 0")
        }
        for (var m = 0; m < root.missingMarks.length; m++) {
            if (root.missingMarks[m] !== 0)
                fails.push("keystroke " + m + " left " + root.missingMarks[m] + " marks undrawn same-frame")
        }
        root.failures = fails
        if (fails.length === 0)
            console.log("FIRSTKEY PASS sync=0 marks=sameframe")
        for (var f = 0; f < fails.length; f++)
            console.log("FIRSTKEY FAIL " + fails[f])
        console.log("FIRSTKEY DONE phases=" + root.phases.length + " failures=" + fails.length)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
