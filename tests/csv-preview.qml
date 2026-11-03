//@ pragma ShellId flea-csv-preview-test

import QtQuick
import Quickshell
import "flea" as Flea
import "CsvRecords.js" as RecordChecks

// tests/csv-preview.sh's harness: CSV and TSV as a table in the preview column and in Quick Look, over the real backend. Every ask passes a spy first, so the raw flag is read off what the tables send.
ShellRoot {
    id: root

    readonly property string fixture: Quickshell.env("CSVPREV_DIR")
    readonly property int tickMs: 20
    readonly property int giveUpMs: 15000
    readonly property int jumpGiveUpMs: 60000
    // big.csv's first 120-character name is line 61 (row 60), past the first screen, so it arrives on a short scroll.
    readonly property int longLine: 61
    property int checks: 0
    property int failures: 0
    property int at: 0
    property var awaiting: null
    property string awaitLabel: ""
    property double waitStart: 0
    property int awaitTimeout: root.giveUpMs
    property bool finished: false
    // Every ask the tables sent, as the spy saw it, and the widths the Quick Look grid had on its first screen.
    property var asks: []
    property var widthsAtFirst: []
    property int tableFrames: 0
    property int partialFrames: 0
    property int plainToken: 0
    property var plainAnswer: null
    property double measureStart: 0
    property int measureAsks: 0
    property bool wheelSample: false
    property int wheelEmptyFrames: 0
    property int prematureReady: 0

    function log(line) { console.log("CSVPREV " + line) }
    function check(label, actual, expected) {
        root.checks += 1
        var ok = JSON.stringify(actual) === JSON.stringify(expected)
        if (!ok) root.failures += 1
        root.log((ok ? "PASS " : "FAIL ") + label + " got=" + JSON.stringify(actual) + " expected=" + JSON.stringify(expected))
    }
    function finish() {
        if (root.finished) return
        root.finished = true
        root.log("DONE " + root.checks + " checks, " + root.failures + " failed")
        quitter.start()
    }
    function wait(label, test, timeoutMs) {
        root.awaitLabel = label
        root.awaiting = test
        root.waitStart = Date.now()
        root.awaitTimeout = timeoutMs === undefined ? root.giveUpMs : timeoutMs
    }
    function tick() {
        if (root.finished) return
        if (root.awaiting !== null) {
            if (!root.awaiting()) {
                if (Date.now() - root.waitStart < root.awaitTimeout) return
                root.check(root.awaitLabel + " came in time", false, true)
            }
            root.awaiting = null
        }
        var step = root.steps[root.at]
        root.at += 1
        if (step === undefined) {
            root.finish()
            return
        }
        step()
    }
    function descendants(item) {
        var out = [item]
        for (var i = 0; i < out.length; i++) {
            var kids = out[i].children || []
            for (var j = 0; j < kids.length; j++) out.push(kids[j])
        }
        return out
    }
    // The drawn Text items that read exactly label, at any depth under item.
    function drawn(item, label) {
        return root.descendants(item).filter(function (n) { return n.visible === true && n.text === label })
    }
    function colTable() { return column.code }
    function qlTable() { return quick.body }
    function firstScreenOf(t) { return t !== null && t.firstScreen === true }
    // The drawn 120-character name, once the grid has built the row it sits on.
    function longDrawn(t) {
        return root.descendants(t).some(function (n) {
            if (!n.visible || typeof n.text !== "string" || n.text.length !== 120) return false
            var at = n.mapToItem(t.list, 0, 0)
            return at.y >= 0 && at.y < t.list.height && at.x < t.list.width && at.x + n.width > 0
        })
    }
    function inView(t, label) {
        return root.drawn(t, label).some(function (n) {
            var point = n.mapToItem(t.list, 0, 0)
            return point.y >= 0 && point.y < t.list.height
        })
    }

    // A frame that draws the header must already hold the whole first screen.
    function sample() {
        var tables = [root.colTable(), root.qlTable()]
        for (var i = 0; i < tables.length; i++) {
            var t = tables[i]
            if (t === null || !t.active || !t.visible || !t.table || t.table.header === null) continue
            root.tableFrames += 1
            if (!t.firstScreen) root.partialFrames += 1
        }
        if (root.wheelSample) {
            var q = root.qlTable()
            if (root.descendants(q.list).some(function (n) {
                if (n.rec !== null || n.index === undefined) return false
                var point = n.mapToItem(q.list, 0, 0)
                return point.y >= 0 && point.y < q.list.height
            })) root.wheelEmptyFrames += 1
        }
    }

    // The table the preview column and Quick Look both draw, asked through the spy.
    Flea.Backend {
        id: realBackend
    }
    QtObject {
        id: spy
        signal codeResult(var message)
        function askCode(slot, source, first, count) {
            var t = slot === "column" ? root.colTable() : root.qlTable()
            var rows = Math.max(1, Math.ceil(t.list.height / t.rowHeight))
            var top = t.list.contentHeight > 0 ? Math.max(0, t.list.indexAt(0, t.list.contentY + 1)) + 2 : 2
            root.asks.push({ slot: slot, source: source, first: first, count: count, rows: rows, top: top })
            return realBackend.askCode(slot, source, first, count)
        }
    }
    Connections {
        target: realBackend
        function onCodeResult(message) {
            spy.codeResult(message)
            var tables = [root.colTable(), root.qlTable()]
            for (var i = 0; i < tables.length; i++) {
                var t = tables[i]
                if (t === null || !t.table || !t.firstScreen) continue
                var last = Math.min(t.shown, t.firstTo)
                if (last > 0 && t.held[last] === undefined) root.prematureReady += 1
            }
        }
    }

    readonly property var steps: [
        function () {
            quick.backend = realBackend
            quick.path = root.fixture + "/plain.txt"
            quick.active = true
            root.wait("Quick Look's text first screen", function () { return quick.firstScreen })
        },
        function () {
            root.check("quicklook: a text pane builds no CsvTable", root.descendants(quick).filter(function (n) {
                return String(n).indexOf("CsvTable") === 0
            }).length, 0)
            quick.active = false
            quick.backend = spy
        },
        // The preview column: bench.csv as a table, asked raw, the header and body drawn, numbers on the right.
        function () {
            column.path = root.fixture + "/bench.csv"
            column.active = true
            root.wait("the column's first screen", function () { return root.firstScreenOf(root.colTable()) })
        },
        function () {
            var t = root.colTable()
            root.check("column: the path is a table", column.csv, true)
            root.check("column: the table is not drawn as the grid", t.look, false)
            root.check("column: the header cells", t.table.header, ["fixture", "files", "folders", "depth"])
            root.check("column: 24 body rows", t.bodyRows, 24)
            root.check("column: numbers right-aligned, the rest left", t.rights, [false, true, true, true])
            root.check("column: the first screen froze the widths", t.frozen, true)
            root.check("column: the drawn columns end inside the frame", t.contentEnd <= t.list.width - 2 * t.edge, true)
            var header = root.drawn(t, "fixture")
            root.check("column: the header is drawn bold", header.length > 0 && header[0].font.bold, true)
            root.check("column: the header has only the board's cell inset", header[0].mapToItem(column, 0, 0).x, t.columnEdge)
            var numbers = root.drawn(t, "1000")
            root.check("column: numeric cells are drawn right-aligned", numbers.length > 0 && numbers.every(function (n) { return n.horizontalAlignment === Text.AlignRight }), true)
            root.check("column: every ask was raw", root.asks.length > 0 && root.asks.every(function (a) { return a.source.raw === true }), true)
        },
        // A long first cell elides within the column's flexing first box.
        function () {
            column.path = root.fixture + "/long.csv"
            root.wait("the column's long first screen", function () { return root.firstScreenOf(root.colTable()) })
        },
        function () {
            var t = root.colTable()
            var first = root.drawn(t, t.table.byLine[2].cells[0])
            root.check("column: the long first cell is elided", first.length > 0 && first[0].truncated, true)
        },
        // The preview column with a wide file: the frame keeps the columns it holds and draws no more.
        function () {
            column.path = root.fixture + "/wide.csv"
            root.wait("the column's wide first screen", function () { return root.firstScreenOf(root.colTable()) })
        },
        function () {
            var t = root.colTable()
            root.check("column wide: 12 columns in the table", t.table.cols, 12)
            root.check("column wide: only the columns the frame holds are drawn", t.layout.length < 12, true)
            root.check("column wide: the drawn columns end inside the frame", t.contentEnd <= t.list.width - 2 * t.edge, true)
        },
        // The preview column with TSV: tabs split the cells and commas stay inside them.
        function () {
            column.path = root.fixture + "/fixture.tsv"
            root.wait("the column's TSV first screen", function () { return root.firstScreenOf(root.colTable()) })
        },
        function () {
            var t = root.colTable()
            root.check("column tsv: the delimiter is a tab", t.delim, "\t")
            root.check("column tsv: the header splits on tabs", t.table.header, ["a", "b", "c"])
            root.check("column tsv: a comma stays inside its cell", t.table.byLine[2].cells[1], "x,y")
        },
        // Quick Look: the same file as a grid, row numbers in the gutter, 24 rows in the bar.
        function () {
            quick.path = root.fixture + "/bench.csv"
            quick.active = true
            root.wait("Quick Look's first screen", function () { return root.firstScreenOf(root.qlTable()) })
        },
        function () {
            var t = root.qlTable()
            root.check("quicklook: the path is a table", quick.csv, true)
            root.check("quicklook: the bar reads 24 rows", quick.countText(), "24 rows")
            root.check("quicklook: the first body row is numbered 1", root.drawn(t, "1").length > 0, true)
            root.check("quicklook: 4 boxes for the 4 columns", t.layout.length, 4)
            root.check("quicklook: each box is its widest cell plus both paddings",
                       t.layout.every(function (p, c) { return p.w === t.widths[c] + 2 * t.edge }), true)
            root.check("quicklook: numbers right-aligned, the rest left", t.rights, [false, true, true, true])
            root.check("quicklook: the grid is at least the frame wide", t.list.contentWidth >= t.list.width, true)
            var bar = root.descendants(quick).filter(function (n) { return n.countLabel !== undefined })[0]
            var gridAt = t.mapToItem(quick, 0, 0)
            root.check("quicklook: the grid is flush below the shared bar", [gridAt.x, gridAt.y, t.width], [0, bar.height, quick.width])
            var numbers = root.drawn(t, "1")
            root.check("quicklook: a muted right-aligned row number is drawn", numbers.some(function (n) {
                return n.horizontalAlignment === Text.AlignRight && String(n.color) === String(Flea.Theme.color.muted)
            }), true)
            var gutters = root.descendants(t).filter(function (n) {
                return n.visible && typeof n.text === "string" && /^[0-9]+$/.test(n.text) && n.mapToItem(t.list, 0, 0).x === 0
            }).map(function (n) { return Number(n.text) }).sort(function (a, b) { return a - b })
            root.check("quicklook: row numbers 1 to 24 are drawn", gutters.join(","), Array.from({ length: 24 }, function (_, i) { return i + 1 }).join(","))
        },
        // Quick Look with a wide file: the grid scrolls sideways and the header stays at the top.
        function () {
            quick.path = root.fixture + "/wide.csv"
            root.wait("Quick Look's wide first screen", function () { return root.firstScreenOf(root.qlTable()) })
        },
        function () {
            var t = root.qlTable()
            root.check("wide: the grid scrolls sideways", t.list.contentWidth > t.list.width, true)
            root.check("wide: 12 boxes", t.layout.length, 12)
            t.list.contentX = 200
            var head = root.drawn(t, "c12")
            root.check("wide: the header stays at the top", head.length > 0 && head[0].mapToItem(t, 0, 0).y === t.headPadY, true)
            root.check("wide: the header moves with the grid",
                       head.length > 0 && head[0].mapToItem(t, 0, 0).x === t.layout[11].x + t.edge - 200, true)
            t.list.contentX = 0
        },
        // Quick Look with 49,999 rows: the widths the first screen put are kept when the grid scrolls to a long name.
        function () {
            quick.path = root.fixture + "/big.csv"
            root.wait("Quick Look's big first screen", function () { return root.firstScreenOf(root.qlTable()) })
        },
        function () {
            var t = root.qlTable()
            root.widthsAtFirst = t.widths.slice()
            root.check("big: the bar reads 49,999 rows", quick.countText(), "49,999 rows")
            root.check("big: the first screen froze the widths", t.frozen, true)
            root.wheelSample = true
            // A short scroll, the way a wheel moves, so the grid builds the rows it lands on.
            t.list.contentY = Math.floor(t.list.height / t.rowHeight) * t.rowHeight
            root.wait("big: line " + root.longLine + " held", function () { return t.covered(root.longLine, root.longLine + 1) })
        },
        function () {
            var t = root.qlTable()
            t.list.contentY = 40 * t.rowHeight
            root.wait("big: the long name drawn", function () { return root.longDrawn(t) })
        },
        function () {
            var t = root.qlTable()
            root.check("big: the scroll moved the grid", t.list.contentY > 0, true)
            root.check("big: the long name is held", t.table.byLine[root.longLine].cells[1].length, 120)
            root.check("big: the long name is drawn", root.longDrawn(t), true)
            root.check("big: the widths did not move on scroll", JSON.stringify(t.widths), JSON.stringify(root.widthsAtFirst))
            root.check("big: the drawn long cell is truncated", root.drawn(t, t.table.byLine[root.longLine].cells[1]).some(function (n) {
                var point = n.mapToItem(t.list, 0, 0)
                return n.truncated && point.y >= 0 && point.y < t.list.height
            }), true)
            root.wheelSample = false
            root.check("big: a one-screen wheel scroll never drew an empty row", root.wheelEmptyFrames, 0)
            t.list.contentY = 0
            t.fresh()
            root.wait("big: a fresh top screen for the jump measurement", function () {
                return t.firstScreen && t.list.count === t.bodyRows && root.inView(t, "f00001")
            })
        },
        function () {
            var t = root.qlTable()
            root.measureStart = Date.now()
            root.measureAsks = root.asks.length
            t.list.positionViewAtIndex(t.bodyRows - 1, ListView.End)
            root.wait("big: the last screen draws", function () { return root.inView(t, "f49999") }, root.jumpGiveUpMs)
        },
        function () {
            var t = root.qlTable()
            root.log("MEASURE big.csv top-to-last asks=" + (root.asks.length - root.measureAsks) + " wall_ms=" + (Date.now() - root.measureStart))
            root.check("big: one request draws the last screen", root.asks.length - root.measureAsks, 1)
            root.check("big: the last row draws in the wanted screen", root.inView(t, "f49999"), true)
            root.check("big: a far jump preserves the widths", t.widths, root.widthsAtFirst)
            quick.height = 12000
            root.measureAsks = root.asks.length
            t.fresh()
            root.wait("big: the first screen larger than lineCap", function () {
                return t.firstScreen && t.held[Math.min(t.shown, t.firstTo)] !== undefined
            })
        },
        function () {
            root.check("big: a tall first screen uses multiple capped replies", root.asks.length - root.measureAsks > 1, true)
            root.check("big: no reply reports ready before its first screen is held", root.prematureReady, 0)
            quick.height = 680
            quick.path = root.fixture + "/malformed.csv"
            root.measureStart = Date.now()
            root.measureAsks = root.asks.length
            root.wait("malformed: the first screen draws", function () {
                var q = root.qlTable()
                var rec = q.table.byLine[2]
                return q.firstScreen && rec !== undefined && root.inView(q, rec.cells[1].split("\n").join(" "))
            })
        },
        function () {
            var t = root.qlTable()
            root.log("MEASURE malformed.csv bytes=1MiB asks=" + (root.asks.length - root.measureAsks) + " first_screen_ms=" + (Date.now() - root.measureStart))
            root.check("malformed: one request draws the first screen", root.asks.length - root.measureAsks, 1)
            root.check("malformed: one aligned reply retains the record through EOF", Object.keys(t.held).length === t.total, true)
            var rec = t.table.byLine[2]
            root.check("malformed: the open quote at EOF is drawn", rec !== undefined && root.inView(t, rec.cells[1].split("\n").join(" ")), true)
        },
        // Quick Look with quoted newlines: the cell keeps its newline and draws it as a space on its line.
        function () {
            quick.path = root.fixture + "/quoted.csv"
            root.wait("Quick Look's quoted first screen", function () { return root.firstScreenOf(root.qlTable()) })
        },
        function () {
            var t = root.qlTable()
            root.check("quoted: the cell keeps its newline", t.table.byLine[2].cells[1], "two\nlines")
            root.check("quoted: the newline draws as a space", root.drawn(t, "two lines").length > 0, true)
            root.check("quoted: the continuation line starts no row", t.table.byLine[3], undefined)
            root.check("quoted: the bar counts two records", quick.countText(), "2 rows")
            root.check("quoted: two model rows", t.bodyRows, 2)
            RecordChecks.screen(root, t, "quoted", true)
        },
        function () {
            quick.path = root.fixture + "/jump.csv"
            root.wait("jump: first screen", function () { return root.firstScreenOf(root.qlTable()) })
        },
        function () {
            root.qlTable().list.positionViewAtIndex(399, ListView.Beginning)
            root.wait("jump: the wanted window held", function () { return root.qlTable().held[703] !== undefined })
        },
        function () {
            var t = root.qlTable()
            root.check("jump: a quoted continuation draws no fabricated row", t.table.byLine[680], undefined)
            root.check("jump: the record start before the window is known", t.table.byLine[401] !== undefined, true)
            root.check("jump: the first complete row after the quote is drawn", root.inView(t, "row702"), true)
            quick.path = root.fixture + "/open.csv"
            root.wait("open: the first-screen record drawn", function () {
                var q = root.qlTable()
                return q.firstScreen && q.table.byLine[2] !== undefined && root.drawn(q, "1").length > 0
            })
        },
        function () {
            var t = root.qlTable()
            root.check("open: the first screen fetched the closing quote", t.held[71] !== undefined, true)
            root.check("open: the complete record is drawn", t.table.byLine[2] !== undefined && root.drawn(t, t.table.byLine[2].cells[1].split("\n").join(" ")).length > 0, true)
            column.path = root.fixture + "/open.csv"
            root.wait("open: the column's complete first-screen record", function () { return root.colTable().table.byLine[2] !== undefined })
        },
        function () {
            root.check("open: the column fetched beyond its frame to close the record", root.colTable().held[71] !== undefined, true)
            plainCsv.active = true
            plainCode.active = true
            root.plainToken = realBackend.askCode("plain-count", { text: "a,b\n1,2\n", name: "plain.csv", raw: true }, 1, 400)
            root.wait("plain: backend total", function () { return root.plainAnswer !== null })
        },
        function () {
            root.check("plain: backend counts two lines for a terminal newline", root.plainAnswer.total, 2)
            root.check("plain: CSV matches the backend total", plainCsv.total, root.plainAnswer.total)
            root.check("plain: CodeLines matches the backend total", plainCode.total, root.plainAnswer.total)
            root.check("plain: one CSV body row", plainCsv.bodyRows, 1)
            root.check("plain: no phantom row is drawn", plainCsv.table.byLine[3], undefined)
            plainCsv.active = false
            plainCode.active = false
        },
        // Binary: the NUL file is not a table, and its frame is the binary one.
        function () {
            quick.path = root.fixture + "/nul.csv"
            root.wait("Quick Look's binary answer", function () { return quick.binary === true })
        },
        function () {
            root.check("binary: the table is not drawn", root.qlTable().visible, false)
        },
        // Large: the backend says the file is over 1 MiB, so the frame is too large and no table is drawn.
        function () {
            quick.path = root.fixture + "/over.csv"
            root.wait("Quick Look's large answer", function () { return quick.tooLarge === true })
        },
        function () {
            root.check("large: the table is not drawn", root.qlTable().visible, false)
        },
        // Empty: no header, no rows, and the bar reads 0 rows.
        function () {
            quick.path = root.fixture + "/empty.csv"
            root.wait("Quick Look's empty first screen", function () { return root.qlTable().settled })
        },
        function () {
            root.check("empty: no header is drawn", root.qlTable().table.header, null)
            root.check("empty: the bar reads 0 rows", quick.countText(), "0 rows")
        },
        // Every ask the tables sent in the run carried the raw flag.
        function () {
            root.check("every ask in the run was raw with its table delimiter", root.asks.length > 0 && root.asks.every(function (a) { return a.source.raw === true && (a.source.csv === "," || a.source.csv === "\t") }), true)
            var columns = root.asks.filter(function (a) { return a.slot === "column" })
            root.check("column: fills records through the open first-screen record", columns.length, 6)
            root.check("column: asks stay inside its screen", columns.every(function (a) { return a.first >= 1 && a.first + a.count - 1 <= a.rows + 1 }), true)
            var look = root.asks.filter(function (a) { return a.slot === "look" })
            root.check("quicklook: asks stay in view plus one screen on each side", look.every(function (a) {
                return a.first >= Math.max(1, a.top - a.rows) && a.first + a.count - 1 <= a.top + 2 * a.rows - 1 && a.count <= 400
            }), true)
            root.check("frames: a table was sampled", root.tableFrames > 0, true)
            root.check("frames: no partial first screen was drawn", root.partialFrames, 0)
        }
    ].concat(RecordChecks.steps(root, column, quick, realBackend))

    Timer {
        id: ticker
        interval: root.tickMs
        running: !root.finished
        repeat: true
        onTriggered: root.tick()
    }

    Flea.CsvTable {
        id: plainCsv
        width: 400
        height: 600
        fromText: true
        text: "a,b\n1,2\n"
        path: "plain.csv"
    }
    Flea.CodeLines {
        id: plainCode
        width: 400
        height: 600
        fromText: true
        text: plainCsv.text
    }
    Connections {
        target: realBackend
        function onCodeResult(message) {
            if (message.token === root.plainToken) root.plainAnswer = message
        }
    }
    // A run that never reaches its end fails, rather than hanging the suite.
    Timer {
        interval: 180000
        running: !root.finished
        onTriggered: {
            root.check("the suite ended in time", false, true)
            root.finish()
        }
    }
    Timer {
        id: quitter
        interval: 50
        onTriggered: Qt.exit(root.failures > 0 ? 1 : 0)
    }

    FloatingWindow {
        id: win
        visible: true
        width: 900
        height: 700

        Item {
            id: frameProbe
            anchors.fill: parent

            Flea.PreviewLines {
                id: column
                x: 0
                y: 0
                width: 400
                height: 600
                backend: spy
                built: true
                active: false
            }
            Flea.PreviewText {
                id: quick
                x: 420
                y: 0
                width: 460
                height: 680
                backend: spy
                active: false
            }
        }
    }

    Connections {
        target: frameProbe.Window.window
        function onAfterAnimating() { root.sample() }
    }
}
