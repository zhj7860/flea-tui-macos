//@ pragma ShellId flea-columns-pwid-test
import QtQuick
import Quickshell
import Quickshell.Io
import QtTest
import "flea" as Flea
import "columns-pwid-legs.js" as Grab

// tests/columns-pwid.sh's harness: the real ui/ColumnsArea.qml over a stub pane and the real ViewState, a stub writer that logs each patch, and a pointer driven on the preview column's edge.
ShellRoot {
    id: shell

    property int checks: 0
    property var failures: []
    property int step: 0
    property int waited: 0
    property bool done: false
    property var edgeHome: ({})
    // Where the run starts: "drag" from no stored width, "restore" with the width a previous run saved.
    readonly property string phase: Quickshell.env("PWID_PHASE")
    readonly property int stored: Number(Quickshell.env("PWID_STORED"))
    readonly property int areaWidth: 1200
    readonly property int areaHeight: 600
    readonly property real hair: Flea.Theme.spacing.hairline

    // What the first frame drew with the preview column up, kept from the window's frameSwapped.
    property var firstFrame: null

    function log(line) { console.log("PWID " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(name, actual, expected) {
        shell.checks++
        if (JSON.stringify(actual) === JSON.stringify(expected)) return
        shell.failures.push(name)
        shell.log("FAIL " + name + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }

    FileView {
        id: savesFile
        path: Quickshell.env("PWID_SAVES")
        printErrors: false
        blockLoading: true
    }
    // One line per patch the stub writer was asked to store.
    function saves() {
        savesFile.reload()
        savesFile.waitForJob()
        return String(savesFile.text()).split("\n").filter(function (line) { return line.length > 0 })
    }

    Component {
        id: backendStub
        QtObject {
            signal peeked(string path, bool hidden, int total, var rows, bool readFailed, int mode, bool hiddenLast, int first)
            signal metaResult(var message)
            property int dirDev: 0
            property int metaSeq: 0
            function peek(path, size, hidden) {}
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
        PwidPane {}
    }

    Component {
        id: menuStub
        QtObject {
            function close() {}
            function openBackground(point) {}
        }
    }

    property var fileA: ({ n: "a.txt", d: false, k: 0, p: 420, s: 13, m: 7, t: false, i: "text-x-generic" })
    property var folderSub: ({ n: "sub", d: true, k: 0, p: 493, s: 0, m: 9, t: false, i: "folder" })
    property var kidRow: ({ n: "kid.txt", d: false, k: 0, p: 420, s: 1, m: 10, t: false, i: "text-x-generic" })

    property var stubBackend: backendStub.createObject(shell)
    property var stubPane: paneStub.createObject(shell, { backend: shell.stubBackend, rows: [shell.fileA, shell.folderSub] })

    FloatingWindow {
        implicitWidth: shell.areaWidth
        implicitHeight: shell.areaHeight
        color: Flea.Theme.color.background

        Flea.ColumnsArea {
            id: area
            anchors.fill: parent
            pane: shell.stubPane
            menu: menuStub.createObject(shell)
        }
        TestEvent { id: driver }
    }

    // The QQuickWindow under the Quickshell window, which is where frameSwapped comes from.
    Connections {
        target: area.Window.window
        function onFrameSwapped() {
            if (shell.firstFrame === null && area.thirdShown && shell.laid().length === 3)
                shell.firstFrame = { widths: shell.widths(), tiled: shell.tiles(shell.rects()) }
        }
    }

    function isColumnPane(o) {
        return o !== null && o.drawsEmpty !== undefined && o.lockedMode !== undefined
            && o.liftedName !== undefined && typeof o.itemAtIndex === "function"
    }
    function visibleUp(o) {
        for (var cur = o; cur !== null; cur = cur.parent) if (cur.visible === false) return false
        return true
    }
    // Every item under one, children and the item a Loader holds.
    function walk(item, each) {
        var stack = [item]
        while (stack.length > 0) {
            var o = stack.pop()
            each(o)
            var kids = (o !== null && o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
        }
    }
    function countObjects() {
        var n = 0
        shell.walk(area, function (o) { n++ })
        return n
    }
    // The shown columns left to right as [x, width], the third column last; x is the running sum of the widths, because a Row places its children on the next polish and a width binding lands at once.
    function laid() {
        var out = []
        var third = area.previewColumn.parent
        shell.walk(area, function (o) {
            if (shell.isColumnPane(o) && o.parent !== third && shell.visibleUp(o) && o.width > 0)
                out.push([o.mapToItem(area, 0, 0).x, o.width])
        })
        out.sort(function (a, b) { return a[0] - b[0] })
        out.push([third.mapToItem(area, 0, 0).x, third.width])
        return out
    }
    function rects() {
        var at = 0
        return shell.laid().map(function (r) { var x = at; at += r[1]; return [x, r[1]] })
    }
    // True once the Row has placed every column where the widths say.
    function placed() {
        var mapped = shell.laid(), sums = shell.rects()
        for (var i = 0; i < sums.length; i++) if (Math.round(mapped[i][0]) !== sums[i][0]) return false
        return true
    }
    function widths() { return shell.rects().map(function (r) { return r[1] }) }
    // The rects tile the area: no gap, no overlap, no column left empty.
    function tiles(rs) {
        var at = 0
        for (var i = 0; i < rs.length; i++) {
            if (rs[i][0] !== at || rs[i][1] < 1) return false
            at += rs[i][1]
        }
        return at === shell.areaWidth
    }
    function edgeItem() {
        var found = null
        shell.walk(area, function (o) { if (o.objectName === "previewEdge") found = o })
        return found
    }
    // The preview column's left edge: where the third column begins.
    function edgeX() { var r = shell.rects(); return r[r.length - 1][0] }
    function marks() {
        var out = []
        var edge = shell.edgeItem()
        if (edge === null) return out
        shell.walk(edge, function (o) {
            if (o.name === "move-horizontal" && o.gridScale !== undefined) out.push(o)
        })
        return out
    }
    function lines() {
        var out = []
        var edge = shell.edgeItem()
        if (edge === null) return out
        shell.walk(edge, function (o) {
            if (o.color !== undefined && o.radius !== undefined && String(o.color) === String(Flea.Theme.color.accent) && o.width === shell.hair)
                out.push(o)
        })
        return out
    }
    function resting(name) {
        shell.check(name + ": no accent line on the edge", shell.lines().length, 0)
        shell.check(name + ": no mark by the edge", shell.marks().length, 0)
    }
    // The press zone under the edge: the MouseArea ui/ResizeHandle.qml puts over the hairline.
    function zoneItem() {
        var found = null
        var edge = shell.edgeItem()
        if (edge === null) return null
        shell.walk(edge, function (o) { if (o.hoverEnabled !== undefined && o.cursorShape === Qt.SplitHCursor) found = o })
        return found
    }
    // The saves after the first `from`, so a leg names only what it wrote.
    function savedAfter(from) { return shell.savedWidths().slice(from) }
    function pointer(x, y) { driver.mouseMove(area, x, y, 0, Qt.NoButton, Qt.NoModifier) }
    function dragTo(x, y) { driver.mouseMove(area, x, y, 0, Qt.LeftButton, Qt.NoModifier) }

    function answerPeek(rows) {
        var row = shell.stubPane.rowFor(shell.stubPane.cursorIndex)
        var path = shell.stubPane.join(shell.stubPane.path, row.n)
        shell.stubBackend.peeked(path, false, rows.length, rows, false, 0, false, shell.stubPane.windowSize)
    }

    // The meta reply for the file load in flight, so the file shows in the last column again.
    function answerMeta() {
        var token = area.previewColumn.pendingToken
        if (!token) return false
        shell.stubBackend.metaResult({ token: token, w: 0, h: 0, ms: 0, rate: 0, entries: 0,
            unpacked: 0, afailed: false, names: [], lines: 3, partial: false, lfailed: false,
            target: "", targetdir: "", owner: "", orient: 1 })
        return true
    }

    // The patch each save logged: `{"preview":{"width":N}}`.
    function savedWidths() {
        return shell.saves().map(function (line) { var m = /"width":(\d+)/.exec(line); return m ? Number(m[1]) : -1 })
    }

    // Phase A, in order. Each entry runs one tick after the last, so the area settles between them.
    property var script: [
        function () {
            shell.check("setup: a file under the cursor shows the preview column", area.thirdShown, true)
            shell.check("rest: every rect is today's third of 1200", shell.widths(), [400, 400, 400])
            shell.check("rest: the rects tile the area", shell.tiles(shell.rects()), true)
            shell.check("rest: the edge zone exists", shell.edgeItem() !== null, true)
            shell.resting("rest")
            shell.check("rest: nothing was saved", shell.saves().length, 0)
            shell.pointer(100, 300)
        },
        function () {
            shell.resting("pointer elsewhere")
            shell.pointer(shell.edgeX(), 300)
        },
        function () {
            var x = shell.edgeX()
            shell.check("hover: one accent line", shell.lines().length, 1)
            shell.check("hover: one mark", shell.marks().length, 1)
            if (shell.lines().length === 1) {
                var line = shell.lines()[0]
                var at = line.mapToItem(area, 0, 0)
                shell.check("hover: the line is 1 px wide on the edge, full height", [at.x, at.y, line.width, line.height], [x - 1, 0, shell.hair, shell.areaHeight])
            }
            if (shell.marks().length === 1) {
                var mark = shell.marks()[0]
                var spot = mark.mapToItem(area, 0, 0)
                shell.check("hover: the mark is 16 px, 12 px left of the edge, top at mid height", [spot.x, spot.y, mark.markSize], [x - 12, shell.areaHeight / 2, 16])
                shell.check("hover: the mark inks in the foreground", String(mark.color), String(Flea.Theme.color.foreground))
            }
            shell.pointer(100, 300)
        },
        function () {
            shell.resting("pointer left")
            shell.pointer(800, 300)
        },
        // A drag of 20 moves: the edge holds until the pointer passes the drag threshold, then follows every move; nothing is built or dropped, nothing is saved until release.
        function () {
            driver.mousePress(area, 800, 300, Qt.LeftButton, Qt.NoModifier, 0)
            shell.edgeHome.count = shell.countObjects()
            shell.edgeHome.last = shell.edgeX()
            shell.edgeHome.good = true
            for (var i = 1; i <= 20; i++) {
                shell.dragTo(800 - 6 * i, 300)
                var edge = shell.edgeX()
                var want = 6 * i > Qt.styleHints.startDragDistance ? 800 - 6 * i : 800
                if (edge !== want) { shell.edgeHome.good = false; shell.log("move " + i + " put the edge at " + edge) }
                if (!shell.tiles(shell.rects())) { shell.edgeHome.good = false; shell.log("move " + i + " left a gap, an overlap or an empty column") }
            }
        },
        function () {
            shell.check("drag: the edge held under the threshold, followed past it, and every frame tiled", shell.edgeHome.good, true)
            shell.check("drag: mid-drag widths are whole pixels", shell.widths(), [340, 340, 520])
            shell.check("drag: no delegate was built or dropped in 20 moves", shell.countObjects(), shell.edgeHome.count)
            shell.check("drag: nothing is written while the pointer is down", shell.saves().length, 0)
            driver.mouseRelease(area, 680, 300, Qt.LeftButton, Qt.NoModifier, 0)
        },
        function () {
            shell.check("release: exactly one write, the whole percent", shell.savedWidths(), [43])
            shell.check("release: the stored percent lays the rects out", shell.widths(), [342, 342, 516])
            shell.check("release: the row placed every column where its width says", shell.placed(), true)
            // Far left: the last column stops where each ancestor keeps 300 px.
            driver.mousePress(area, 684, 300, Qt.LeftButton, Qt.NoModifier, 0)
            shell.dragTo(300, 300)
            shell.dragTo(0, 300)
            shell.check("clamp: far left leaves each ancestor 300 px", shell.widths(), [300, 300, 600])
            driver.mouseRelease(area, 0, 300, Qt.LeftButton, Qt.NoModifier, 0)
        },
        function () {
            shell.check("clamp: far left writes 50", shell.savedWidths(), [43, 50])
            // Far right: the last column stops at 300 px.
            driver.mousePress(area, 600, 300, Qt.LeftButton, Qt.NoModifier, 0)
            shell.dragTo(900, 300)
            shell.dragTo(1190, 300)
            shell.check("clamp: far right leaves the last column 300 px", shell.widths(), [450, 450, 300])
            driver.mouseRelease(area, 1190, 300, Qt.LeftButton, Qt.NoModifier, 0)
        },
        function () {
            shell.check("clamp: far right writes 25", shell.savedWidths(), [43, 50, 25])
            shell.pointer(100, 300)
            shell.stubPane.cursorIndex = 1
        },
        function () { shell.answerPeek([shell.kidRow]) },
        function () {
            shell.check("j: the folder shows in the last column", area.shownIsDir, true)
            shell.check("j: file to folder leaves every edge where it was", shell.widths(), [450, 450, 300])
            shell.pointer(900, 300)
        },
        function () {
            shell.check("j: the handle is live over a folder's contents", [shell.lines().length, shell.marks().length], [1, 1])
            shell.stubPane.cursorIndex = 0
        },
        function () { return shell.answerMeta() ? "" : "again" },
        function () {
            shell.check("k: the file shows in the last column again", area.shownIsDir, false)
            shell.check("k: folder back to file leaves every edge where it was", shell.widths(), [450, 450, 300])
            driver.mouseDoubleClickSequence(area, 900, 300, Qt.LeftButton, Qt.NoModifier, 0)
        },
        function () {
            shell.check("double click: every rect is today's third again", shell.widths(), [400, 400, 400])
            shell.check("double click: the row placed every column where its width says", shell.placed(), true)
            shell.check("double click: it writes 0", shell.savedWidths(), [43, 50, 25, 0])
            shell.pointer(100, 300)
        },
        // The click, jitter, lost grab, hidden edge and jittering double click legs: tests/columns-pwid-legs.js.
        ...Grab.legs(shell, driver, area),
        // The last width this run leaves behind is the one the restore run reads back.
        function () { shell.pointer(800, 300) },
        function () {
            driver.mousePress(area, 800, 300, Qt.LeftButton, Qt.NoModifier, 0)
            shell.dragTo(750, 300)
            shell.dragTo(700, 300)
            driver.mouseRelease(area, 700, 300, Qt.LeftButton, Qt.NoModifier, 0)
        },
        function () {
            shell.check("last drag writes 42", shell.savedAfter(shell.edgeHome.base), [42])
            shell.pointer(100, 300)
        }
    ]

    // Phase B: a relaunch with the stored width in ui.json draws it on the first frame that shows the preview column, with no line at rest.
    property var restore: [
        function () {
            var want = Math.round(shell.areaWidth * shell.stored / 100)
            var column = Math.floor((shell.areaWidth - want) / 2)
            shell.check("relaunch: the stored percent is read", Flea.ViewState.previewWidth, shell.stored)
            shell.check("relaunch: a frame drew the preview column", shell.firstFrame !== null, true)
            if (shell.firstFrame !== null) {
                shell.check("relaunch: the first frame already has the stored width", shell.firstFrame.widths, [column, column, shell.areaWidth - 2 * column])
                shell.check("relaunch: the first frame tiles the area", shell.firstFrame.tiled, true)
            }
            shell.check("relaunch: the width lays the rects out", shell.widths(), [column, column, shell.areaWidth - 2 * column])
            shell.check("relaunch: the rects tile the area", shell.tiles(shell.rects()), true)
            shell.resting("relaunch")
            shell.check("relaunch: nothing was written", shell.saves().length, 0)
        }
    ]

    Timer {
        interval: 120
        running: true
        repeat: true
        onTriggered: {
            if (shell.done) return
            var list = shell.phase === "restore" ? shell.restore : shell.script
            if (shell.step >= list.length) {
                shell.done = true
                if (shell.failures.length === 0) shell.log("PASS " + shell.checks + " checks")
                shell.log("DONE failures=" + shell.failures.length)
                shell.quit()
                return
            }
            // A step answers "again" while the thing it waits for has not arrived, up to 30 ticks.
            if (list[shell.step]() === "again" && shell.waited < 30) { shell.waited++; return }
            shell.waited = 0
            shell.step++
        }
    }
}
