import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Drag.js" as DragOps
import "flea/js/Messages.js" as Messages

// A peek column row lifts its own path, with the column's device and writability in the marker and no listing rows, and takes drops only on a folder row; a column with no peek source lifts nothing.
ShellRoot {
    id: root

    property int checks: 0
    property int failures: 0
    readonly property var names: ["a#b.txt", "50%.txt", "two words.txt", "-dash.txt", "new\nline.txt"]
    // The pane a peek column belongs to: joins paths, records each collide request, and can hold a listing in flight.
    readonly property QtObject paneStub: QtObject {
        property bool listInFlight: false
        property var asked: []
        property string said: ""
        // The backend's device answers by path, which a peek row with no device of its own reads at the drop.
        readonly property QtObject backend: QtObject {
            property var pathDevs: ({})
            property var dropAsked: []
            function askDropDevs(token, paths) { dropAsked = dropAsked.concat([token + ":" + paths.join(",")]) }
        }
        // The columns area as RowDrag.enter reaches it: the drawn columns' own dropAsks in one request, as ui/ColumnsArea.qml's askDropDevs does.
        readonly property QtObject columnsArea: QtObject {
            property var columns: []
            function askDropDevs(token) {
                var paths = []
                for (var i = 0; i < columns.length; i++) paths = paths.concat(columns[i].dropAsks())
                root.paneStub.backend.askDropDevs(token, paths)
            }
        }
        readonly property var collide: ({ ask: function (req) { root.paneStub.asked = root.paneStub.asked.concat([req]); return true } })
        // Drag.js dropInto asks through pane.asks(), as a product pane builds its collide card on first use.
        function asks() { return root.paneStub.collide }
        function join(a, b) { return a + "/" + b }
        function message(line, ok) { root.paneStub.said = line }
    }

    function check(label, actual, expected) {
        root.checks += 1
        if (JSON.stringify(actual) === JSON.stringify(expected)) return
        root.failures += 1
        console.log("COLUMNSPEEKDRAG FAIL " + label + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }

    function source(writable) { return { pane: root.paneStub, dir: "/fx/sub", v: 42, w: writable } }

    function rowsOf(column) {
        var out = []
        for (var i = 0; i < root.names.length; i++) {
            var cell = column.viewport.itemAtIndex(i)
            for (var c = 0; cell && c < cell.children.length; c++)
                if (cell.children[c].session !== undefined) out.push(cell.children[c])
        }
        return out
    }

    // Sample output: [true, ""] for a call that answered true and threw nothing.
    function attempt(call) {
        try { return [call(), ""] } catch (e) { return [null, String(e)] }
    }

    function dropAreaOf(rowDrag) {
        for (var c = 0; c < rowDrag.children.length; c++)
            if (rowDrag.children[c].keys !== undefined) return rowDrag.children[c]
        return null
    }

    Flea.FileDrag { id: lone; pane: null; peekSource: root.source(true) }
    Flea.FileDrag { id: locked; pane: null; peekSource: root.source(false) }

    FloatingWindow {
        implicitWidth: 1600
        implicitHeight: 400
        Flea.ColumnPane {
            id: peekColumn
            x: 0; width: 400; height: 400
            rows: root.names.map(function (n) { return { n: n, d: false, i: "text-x-generic" } })
            peekSource: root.source(true)
        }
        Flea.ColumnPane {
            id: bareColumn
            x: 400; width: 400; height: 400
            rows: root.names.map(function (n) { return { n: n, d: false, i: "text-x-generic" } })
        }
        Flea.ColumnPane {
            id: folderColumn
            x: 800; width: 400; height: 400
            rows: [{ n: "inbox", d: true, i: "folder" }]
            peekSource: root.source(true)
        }
        // A peek column of a file, a folder with a device, a folder with none, and far below the viewport a folder with none.
        Flea.ColumnPane {
            id: askColumn
            x: 1200; width: 400; height: 400
            rows: [{ n: "a.txt", d: false, i: "text-x-generic" }, { n: "big", d: true, v: 5 }, { n: "deep", d: true, i: "folder" }]
                .concat(root.names.map(function (n, at) { return { n: "pad" + at, d: false, i: "text-x-generic" } }))
                .concat(Array.from({ length: 80 }, function (_, at) { return { n: "far" + at, d: at === 79, i: "folder" } }))
            peekSource: root.source(true)
        }
    }

    Timer {
        interval: 600
        running: true
        onTriggered: {
            for (var i = 0; i < root.names.length; i++) {
                var name = root.names[i]
                var mime = lone.peekMime({ n: name, d: false }, false, false)
                var marker = mime[DragOps.ROWS_MIME]
                root.check(name + " plain path", mime["text/plain"], "/fx/sub/" + name)
                root.check(name + " uri", mime["text/uri-list"], "file:///fx/sub/" + encodeURIComponent(name) + "\r\n")
                root.check(name + " marker source, device, deletable", [DragOps.markerSource(marker), DragOps.markerDev(marker), DragOps.markerDeletable(marker)], ["/fx/sub", 42, true])
                root.check(name + " marker carries no rows", marker.split("\n")[1], "")
                root.check(name + " no index drop", DragOps.canDropByIndex(marker, "/fx/sub", [], 0), false)
            }
            root.check("a read-only column copies", DragOps.markerDeletable(locked.peekMime({ n: "x", d: false }, false, false)[DragOps.ROWS_MIME]), false)
            root.check("shift rides the marker", DragOps.markerShift(lone.peekMime({ n: "x", d: false }, false, true)[DragOps.ROWS_MIME]), true)
            var peekRows = root.rowsOf(peekColumn)
            root.check("every peek row realised", peekRows.length, root.names.length)
            for (var p = 0; p < peekRows.length; p++)
                root.check("peek row " + p + " lifts and takes no drop", [peekRows[p].enabled, root.dropAreaOf(peekRows[p]).enabled], [true, false])
            var folderRows = root.rowsOf(folderColumn)
            root.check("a peek folder row lifts and takes a drop", folderRows.length === 1
                ? [folderRows[0].enabled, root.dropAreaOf(folderRows[0]).enabled, folderRows[0].targetDir] : [], [true, true, "/fx/sub"])
            var folder = folderRows.length === 1 ? folderRows[0] : null
            var outside = ["file:///elsewhere/x.txt"]
            root.check("an outside uri-list enters the peek folder row", root.attempt(function () { return folder.enter("", outside, "", "", Qt.CopyAction, "") })
                .concat([folder ? folder.session.dropIndex : null]), [true, "", 0])
            root.check("its drop reaches the pane's collide with the folder as destination", root.attempt(function () { return folder.dropped("", outside, "", "", Qt.CopyAction) })
                .concat([root.paneStub.asked, root.paneStub.said]), [true, "", [{ c: "transfer", op: "copy", paths: ["/elsewhere/x.txt"], dest: "/fx/sub/inbox" }], ""])
            root.paneStub.listInFlight = true
            root.check("a listing in flight closes the peek folder row's drop", folder ? root.dropAreaOf(folder).enabled : null, false)
            root.paneStub.listInFlight = false
            root.check("the landed listing opens it again", folder ? root.dropAreaOf(folder).enabled : null, true)
            // A peek row is {n,d,i} with no v: its drop verb reads the backend's answer for its own path, and an unanswered or other-device path copies.
            root.paneStub.columnsArea.columns = [folderColumn, peekColumn, askColumn, bareColumn]
            var own = DragOps.markerPayload([], false, "/fx/other", 42, true, false)
            var carried = ["file:///fx/other/p1.txt"]
            var seen = function () { return [folder.session.dragCopy, folder.session.dropDestDev, folder.destDev] }
            root.check("a peek folder row carries no device of its own", folder.row.v, undefined)
            root.paneStub.backend.dropAsked = []
            root.check("an own drop enters it", root.attempt(function () { return folder.enter(own, carried, "", "", Qt.MoveAction, "t1") }), [true, ""])
            root.check("the drag asks the visible peek folder rows that name no device, in the drawn columns only",
                       root.paneStub.backend.dropAsked, ["t1:/fx/sub/inbox,/fx/sub/deep"])
            root.check("unanswered, the drop copies", seen(), [true, 0, 0])
            Messages.route(root.paneStub.backend, { t: "devs", devs: { "/fx/sub/inbox": 42 } })
            root.check("the answer landing under the pointer moves it", seen(), [false, 42, 42])
            folder.leaveRow()
            root.check("a later enter on the answered row moves", [root.attempt(function () { return folder.enter(own, carried, "", "", Qt.MoveAction, "") })[0]].concat(seen()), [true, false, 42, 42])
            folder.leaveRow()
            Messages.route(root.paneStub.backend, { t: "devs", devs: { "/fx/sub/inbox": 43 } })
            root.check("a folder under another device copies", [root.attempt(function () { return folder.enter(own, carried, "", "", Qt.MoveAction, "") })[0]].concat(seen()), [true, true, 43, 43])
            folder.leaveRow()
            // A row that names its own device drops on it, whatever the backend answers for its path: the backend says 42, the source's device, which would move, and the row says 5.
            var bigRows = root.rowsOf(askColumn).filter(function (r) { return r.row && r.row.n === "big" })
            var big = bigRows.length === 1 ? bigRows[0] : null
            root.paneStub.backend.pathDevs = { "/fx/sub/big": 42 }
            var seenBig = function () { return [big.session.dragCopy, big.session.dropDestDev, big.destDev] }
            root.check("a folder row with a device of its own is realised", big ? big.row.v : null, 5)
            root.check("its own device wins over the backend's answer for its path", big ? [root.attempt(function () { return big.enter(own, carried, "", "", Qt.MoveAction, "") })[0]].concat(seenBig()) : [], [true, true, 5, 5])
            if (big) big.leaveRow()
            root.paneStub.backend.pathDevs = {}
            root.paneStub.columnsArea.columns = []
            var bareRows = root.rowsOf(bareColumn)
            root.check("every bare row realised", bareRows.length, root.names.length)
            for (var b = 0; b < bareRows.length; b++)
                root.check("a column with no source lifts nothing " + b, bareRows[b].enabled, false)
            console.log("COLUMNSPEEKDRAG DONE checks=" + root.checks + " failed=" + root.failures)
            Quickshell.execDetached(["kill", String(Quickshell.processId)])
        }
    }
}
