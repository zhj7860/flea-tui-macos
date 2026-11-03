pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import "js/Csv.js" as Csv
import "." as Flea

// CSV or TSV as a sticky table, with raw line windows aligned to whole records by the backend.
Item {
    id: root

    property var backend: null
    property string slot: "column"
    property string path: ""
    // true sends the bytes in `text` (null until the caller has read them) instead of the path.
    property bool fromText: false
    property var text: null
    property bool active: false
    // Quick Look's grid: row numbers, each column its widest cell plus the row padding, and both axes scroll.
    property bool look: false
    property int limit: 0
    // Screens asked past the view on each side.
    property int margin: 1
    property int pixelSize: Theme.font.caption
    readonly property int lineCap: 400 // The most lines one ask names (docs/protocol.md "code"); a longer window is asked in parts.

    readonly property string delim: Csv.delimiter(root.path)
    readonly property bool engine: root.backend !== null && typeof root.backend.askCode === "function"
    // The board draws its table at caption 12; its pixel values scale with the caption, as the board sizes in Theme.qml do.
    readonly property real boardScale: root.pixelSize / 12
    // Board: the column's rows sit 12 px in from the frame on each side.
    readonly property int columnEdge: Math.round(12 * root.boardScale)
    // Board: 6 px between the column's cells.
    readonly property int columnGap: Math.round(6 * root.boardScale)
    // Board: Quick Look's row numbers fill a 42 px column.
    readonly property int numberWidth: Math.round(42 * root.boardScale)
    // Board: 3 px above and below each column row and its header.
    readonly property int columnPadY: Math.round(3 * root.boardScale)
    // Board: 6 px above and below each Quick Look row.
    readonly property int gridPadY: Math.round(6 * root.boardScale)
    // Board: 8 px above and below the Quick Look header.
    readonly property int gridHeadPadY: Math.round(8 * root.boardScale)
    readonly property int edge: root.look ? Theme.spacing.rowPaddingX : root.columnEdge
    readonly property int bodyPadY: root.look ? root.gridPadY : root.columnPadY
    readonly property int headPadY: root.look ? root.gridHeadPadY : root.columnPadY
    // The table rule of ui/PreviewMarkdown.qml, drawn under the header.
    readonly property real ruleOpacity: 0.12
    readonly property real rowHeight: bodyMetrics.height + 2 * root.bodyPadY
    readonly property real headHeight: headMetrics.height + 2 * root.headPadY + Theme.spacing.hairline

    // "" until the first screen is answered, then styled, plain, binary, large or failed.
    property string answer: ""
    property int total: 0
    property int records: 0
    // The held physical lines, each {t: text}, with record: ordinal at every reply start; stamp counts changes to it.
    property var held: ({})
    property int stamp: 0
    // The token of the ask in flight, 0 when none: an answer for any other token is dropped.
    property int token: 0
    property bool retiring: false
    // The last record of the first screen, so the first screen is known whole before the table is drawn.
    property int firstTo: 0
    // The table as held: the header cells, the body rows and the column count.
    property var table: ({ header: null, rows: [], byLine: ({}), byRecord: ({}), cols: 0, open: [] })
    // Widths and alignments are measured on the first screen and only extended after it, so no column moves under the reader.
    property bool frozen: false
    property var heads: []
    property var widths: []
    property var rights: []

    readonly property bool settled: root.answer === "styled" || root.answer === "plain"
    readonly property int shown: root.limit > 0 ? Math.min(root.records, root.limit) : root.records
    readonly property bool firstReady: root.settled && root.covered(1, Math.min(root.shown, root.firstTo))
        && Csv.ready(root.table, Math.min(root.shown, root.firstTo))
    readonly property bool firstScreen: root.firstReady && (root.look
        || (root.covered(root.needed().from, root.needed().to) && Csv.ready(root.table, root.needed().to)))
    visible: root.firstReady
    // The scroll view the wheel, the bars and the Quick Look reader read.
    readonly property var list: view
    readonly property alias viewport: view
    // One delegate per data record; continuation lines never take a row or a number.
    readonly property int bodyRows: Csv.dataRows(root.shown)
    // The plain text of the lines drawn, for the readers that check what is on screen.
    readonly property var lines: {
        root.stamp
        var out = []
        var tail = root.table.byRecord[root.shown]
        var last = root.limit > 0 && root.shown > 1 ? (tail ? tail.line + tail.span - 1 : 0) : root.total
        for (var i = 1; i <= last; i++)
            out.push(root.held[i] ? root.held[i].t : "")
        return out
    }
    readonly property var layout: root.look ? Csv.grid(root.widths, root.rights, root.numberWidth, Theme.spacing.rowPaddingX)
                                            : Csv.fit(root.widths, root.heads, root.rights, root.columnGap, view.width - 2 * root.edge)
    readonly property real contentEnd: root.layout.length > 0 ? root.layout[root.layout.length - 1].x + root.layout[root.layout.length - 1].w : 0
    // Quick Look's grid is at least the frame wide and as wide as its boxes; a column keeps the frame's width.
    readonly property real gridWidth: root.look ? Math.max(view.width, root.contentEnd) : view.width

    FontMetrics {
        id: bodyMetrics
        font.family: Theme.font.family
        font.pixelSize: root.pixelSize
    }
    FontMetrics {
        id: headMetrics
        font.family: Theme.font.family
        font.pixelSize: root.pixelSize
        font.bold: true
    }
    // Digits in a numeric cell draw with tabular figures, so they are measured the same way.
    FontMetrics {
        id: figureMetrics
        font.family: Theme.font.family
        font.pixelSize: root.pixelSize
        font.features: ({ "tnum": 1 })
    }

    // The width of column c: its widest header or body cell, the header in bold.
    function naturalWidth(grid, c) {
        var px = headMetrics.advanceWidth(String(grid[0][c] || ""))
        for (var r = 1; r < grid.length; r++) {
            var cell = String(grid[r][c] || "")
            px = Math.max(px, (Csv.isNumber(cell) ? figureMetrics : bodyMetrics).advanceWidth(cell))
        }
        return Math.ceil(px)
    }

    // Re-reads the held table, and measures each column it has not measured yet; nothing is measured again once the first screen is whole.
    function refresh(parsed) {
        var t = parsed || Csv.table(root.held, root.total, root.delim)
        root.table = t
        if (t.header === null || (root.frozen && root.widths.length >= t.cols))
            return
        var measured = root.frozen ? t.rows : t.rows.filter(function (rec) { return rec.record <= root.firstTo })
        var grid = [t.header].concat(measured.map(function (rec) { return rec.cells }))
        var align = Csv.numericColumns(grid, t.cols)
        var heads = root.frozen ? root.heads.slice() : []
        var widths = root.frozen ? root.widths.slice() : []
        var rights = root.frozen ? root.rights.slice() : []
        for (var c = widths.length; c < t.cols; c++) {
            heads.push(Math.ceil(headMetrics.advanceWidth(String(t.header[c] || ""))))
            widths.push(root.naturalWidth(grid, c))
            rights.push(align[c])
        }
        if (!root.frozen && root.covered(1, Math.min(root.shown, root.firstTo)) && Csv.ready(t, Math.min(root.shown, root.firstTo)))
            root.frozen = true
        root.heads = heads
        root.widths = widths
        root.rights = rights
    }

    // The record ordinals the view needs, with the margin, file and limit bounds; ordinal 1 is the header.
    function needed() {
        var rows = Math.max(1, Math.ceil(view.height / Math.max(1, root.rowHeight)))
        // ListView rounds fractional row heights, so its delegate index names the record even on a far jump.
        var top = view.contentHeight > 0 ? Math.max(0, view.indexAt(0, view.contentY + 1)) + 2 : 2
        var to = top + rows * (1 + root.margin) - 1
        if (root.limit > 0)
            to = Math.min(to, root.limit)
        if (root.settled)
            to = Math.min(to, root.records)
        var from = root.rowAt(1) ? Math.max(2, top - rows * root.margin) : 1
        return { from: from, to: to }
    }

    function rowAt(n) {
        return root.stamp >= 0 ? (n === 1 ? root.table.header : root.table.byRecord[n]) : undefined
    }

    function covered(from, to) {
        for (var i = from; i <= to; i++)
            if (!root.rowAt(i))
                return false
        return true
    }

    function reset() {
        root.held = {}
        root.stamp += 1
        root.total = 0
        root.records = 0
        root.answer = ""
        root.token = 0
        root.firstTo = 0
        root.frozen = false
        root.heads = []
        root.widths = []
        root.rights = []
        root.table = { header: null, rows: [], byLine: ({}), byRecord: ({}), cols: 0, open: [] }
    }

    // Starts a view of a new file or text; the first ask waits for the end of the turn so one change of several properties asks once.
    function fresh() {
        root.reset()
        if (!root.active)
            return
        if (!root.engine && root.fromText && root.text !== null)
            root.answerPlain()
        else
            Qt.callLater(root.ask)
    }

    // Lines of the caller's own text, drawn plain when no backend can ask for them.
    function answerPlain() {
        var rows = Csv.plainLines(root.text)
        var held = {}
        for (var i = 0; i < rows.length; i++)
            held[i + 1] = { t: rows[i] }
        root.held = held
        root.total = rows.length
        var parsed = Csv.table(held, root.total, root.delim)
        root.records = parsed.rows.length + (parsed.header !== null ? 1 : 0)
        root.answer = "plain"
        root.firstTo = root.needed().to
        root.refresh(parsed)
        root.stamp += 1
    }

    function ask() {
        if (root.retiring || !root.active || !root.engine || view.height <= 0)
            return
        if (root.answer === "binary" || root.answer === "large" || root.answer === "failed")
            return
        if (root.fromText && root.text === null)
            return
        if (root.fromText && root.text.length === 0) {
            root.answerPlain()
            return
        }
        if (!root.fromText && root.path.length === 0)
            return
        if (root.token !== 0)
            return
        var want = root.needed()
        if (want.to < want.from || (root.settled && root.covered(want.from, want.to)))
            return
        var from = want.from
        while (from <= want.to && root.rowAt(from))
            from += 1
        if (root.firstTo === 0)
            root.firstTo = want.to
        // raw sends the lines plain: a table is never coloured as code.
        var source = root.fromText ? { text: root.text, name: root.path.split("/").pop(), lang: "", raw: true, csv: root.delim, record: from } : { path: root.path, raw: true, csv: root.delim, record: from }
        root.token = root.backend.askCode(root.slot, source, from, Math.min(root.lineCap, want.to - from + 1))
    }

    function answered(message) {
        if (root.token === 0 || message.token !== root.token)
            return
        root.token = 0
        if (!root.settled || message.state === "binary" || message.state === "large" || message.state === "failed")
            root.answer = message.state
        root.total = message.total || 0
        root.records = message.records || 0
        var rows = message.lines || []
        for (var i = 0; i < rows.length; i++)
            root.held[message.first + i] = { t: rows[i].length > 0 ? rows[i][1] : "" }
        if (rows.length > 0)
            root.held[message.first].record = message.firstRecord
        root.refresh()
        root.stamp += 1
        // Binary, large and failed are the file's whole answer: nothing more is asked of it until the view starts a new one.
        if (root.settled)
            Qt.callLater(root.ask)
    }

    onPathChanged: root.fresh()
    onTextChanged: root.fresh()
    onFromTextChanged: root.fresh()
    onActiveChanged: root.fresh()
    Component.onDestruction: root.retiring = true
    onLimitChanged: Qt.callLater(root.ask)

    Connections {
        target: root.engine ? root.backend : null
        function onCodeResult(message) { root.answered(message) }
    }

    // The header, sticky above the rows; in Quick Look it moves sideways with the grid and stays at the top.
    Item {
        id: head
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.headHeight
        visible: root.table.header !== null
        clip: true

        Item {
            x: root.look ? -view.contentX : 0
            width: root.gridWidth
            height: parent.height

            Repeater {
                model: root.table.header !== null ? root.layout.length : 0
                delegate: Text {
                    required property int index
                    // A reset clears the layout before old delegates are destroyed.
                    readonly property var place: root.layout[index] || { x: 0, w: 0, right: false }
                    x: root.look ? place.x + Theme.spacing.rowPaddingX : root.edge + place.x
                    width: root.look ? Math.max(0, place.w - 2 * Theme.spacing.rowPaddingX) : place.w
                    y: root.headPadY
                    text: Csv.oneLine(root.table.header !== null ? root.table.header[index] || "" : "")
                    horizontalAlignment: place.right ? Text.AlignRight : Text.AlignLeft
                    elide: Text.ElideRight
                    color: Theme.color.foregroundBright
                    font.family: Theme.font.family
                    font.pixelSize: root.pixelSize
                    font.bold: true
                    textFormat: Text.PlainText
                }
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: Theme.spacing.hairline
            color: Theme.color.foreground
            opacity: root.ruleOpacity
        }
    }

    ListView {
        id: view
        anchors.top: head.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        interactive: true
        flickableDirection: Flickable.HorizontalAndVerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        model: root.bodyRows
        contentWidth: root.gridWidth
        onContentYChanged: Qt.callLater(root.ask)
        onHeightChanged: Qt.callLater(root.ask)

        delegate: Item {
            id: row
            required property int index
            // A held record occupies exactly one delegate at its ordinal.
            readonly property var rec: root.table.byRecord[index + 2] || null
            width: root.gridWidth
            height: root.rowHeight

            Text {
                visible: root.look && row.rec !== null
                x: 0
                width: root.numberWidth - Theme.spacing.rowPaddingX
                y: root.bodyPadY
                text: row.rec !== null ? String(Csv.rowNumber(row.rec.record)) : ""
                horizontalAlignment: Text.AlignRight
                color: Theme.color.muted
                font.family: Theme.font.family
                font.pixelSize: root.pixelSize
                font.features: ({ "tnum": 1 })
                textFormat: Text.PlainText
            }

            Repeater {
                model: row.rec !== null ? root.layout.length : 0
                delegate: Text {
                    required property int index
                    // A reset may clear the record before its old cells are destroyed.
                    readonly property var place: root.layout[index] || { x: 0, w: 0, right: false }
                    readonly property string cell: Csv.oneLine(row.rec !== null ? row.rec.cells[index] || "" : "")
                    x: root.look ? place.x + Theme.spacing.rowPaddingX : root.edge + place.x
                    width: root.look ? Math.max(0, place.w - 2 * Theme.spacing.rowPaddingX) : place.w
                    y: root.bodyPadY
                    text: cell
                    horizontalAlignment: place.right ? Text.AlignRight : Text.AlignLeft
                    elide: Text.ElideRight
                    color: Theme.color.foreground
                    font.family: Theme.font.family
                    font.pixelSize: root.pixelSize
                    font.features: Csv.isNumber(cell) ? ({ "tnum": 1 }) : ({})
                    textFormat: Text.PlainText
                }
            }
        }
    }

    Flea.FastScrollHandler {
        visible: root.look
        flickable: view
    }

    Flea.ViewportScrollBars {
        visible: root.look
        flickable: view
    }
}
