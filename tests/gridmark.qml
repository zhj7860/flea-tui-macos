//@ pragma ShellId flea-gridmark-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Filter.js" as Filter

// A real ui/GridArea.qml draws List's match mark on each label's matched letters, read back as boxes, in every tile state.
ShellRoot {
    id: root

    property var failures: []
    property var restCounts: ({})
    property var restCaptions: ({})
    property int armedCount: -1
    property var wrapQuery: ""
    property var checked: []
    // Sized off the drawn line once the grid lays out, so it wraps after a blank and never elides.
    property string longName: "Annotated.txt"

    // Built by call: initializers run before onCompleted and would hand it the empty array.
    function fixtureRows() {
        var names = [root.longName, "apple.txt", "maps", "notes.txt", "piano.md", "zappa.mp3"]
        return names.map(function (n) { return { n: n, d: n === "maps", i: n === "maps" ? "inode-directory" : "text-x-generic", p: 420, s: 13, m: 1758835200, t: false, k: 0, v: 0 } })
    }

    Component {
        id: backendStub
        QtObject {
            function peek(path, size, hidden) {}
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
            property string path: "/probe"
            property var rows: []
            property string filterQuery: ""
            property bool filterTyping: false
            // The pane's own narrowing, so the rows and the query land in one turn as they do in ui/Pane.qml.
            readonly property var shown: Filter.shown(rows, held, filterQuery)
            readonly property int shownTotal: shown === null ? total : shown.length
            readonly property int total: rows.length
            property int held: 0
            property int cursorIndex: 3
            property int renamingIndex: -1
            property string renameError: ""
            property bool renamePending: false
            property bool paneFocused: true
            property bool dualMode: false
            property var clipboard: ({ paths: [], moving: false })
            property var selected: ({})
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property string searchMode: ""
            property string searchQuery: ""
            property QtObject swap: QtObject { property string answeredQuery: "" }
            property var selectionBand: null
            property var sidebar: null
            property int previewIndex: -1
            property bool storageKnown: true
            property string storageClass: ""
            property bool listInFlight: false
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
            function isSelected(index) { return selected[index] === true }
            function commitRename(newName) {}
        }
    }

    Component {
        id: statusStub
        QtObject { property var activities: [] }
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
    property var stubStatus: statusStub.createObject(root)
    property var stubPane: paneStub.createObject(root, { backend: root.stubBackend, rows: root.fixtureRows(), statusBar: root.stubStatus })

    FloatingWindow {
        implicitWidth: 900
        implicitHeight: 500
        color: Flea.Theme.color.background

        Flea.GridArea {
            id: grid
            width: 760
            height: 420
            anchors.centerIn: parent
            pane: root.stubPane
            menu: root.stubMenu
        }

        // The oracle: the run as ui/MatchText.qml would measure it, one plain Text per piece.
        Text { id: piece; visible: false; textFormat: Text.PlainText }
        // Qt's own width for each laid-out caption line, which a centred line is placed by.
        Text {
            id: lines
            visible: false
            property var widths: []
            textFormat: Text.PlainText
            wrapMode: Text.WrapAnywhere
            horizontalAlignment: Text.AlignHCenter
            lineHeightMode: Text.FixedHeight
            elide: Text.ElideRight
            onLineLaidOut: function (line) { lines.widths[line.number] = line.implicitWidth }
        }
    }

    Timer {
        id: step
        property var next: null
        interval: 600
        repeat: false
        onTriggered: step.next()
    }
    Component.onCompleted: { step.next = root.measureLayout; step.start() }

    function fail(text) { root.failures.push(text) }
    // Each step names itself, so a probe that stops part way says where.
    function then(fn) { step.next = function () { console.log("GRIDMARK STEP " + fn.name); fn() }; step.interval = 300; step.start() }

    function countUnder(item) {
        var n = 0, stack = [item]
        while (stack.length > 0) {
            var o = stack.pop()
            n += 1
            var kids = (o !== null && o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
            var res = (o !== null && o.resources !== undefined) ? o.resources : []
            for (var j = 0; j < res.length; j++) stack.push(res[j])
        }
        return n - 1
    }

    // Every drawn tile with a row, by its listing name.
    function drawn() {
        var out = {}
        for (var i = 0; i < grid.count; i++) {
            var d = grid.itemAtIndex(i)
            if (d !== null && d.visible && d.row) out[d.row.n] = d
        }
        return out
    }

    // Visible accent rectangles short of covering the caption: List's wash wherever the tile builds or places it; a tile-wide fill covers it.
    function washesOf(tile) {
        var cap = tile.captionItem, accent = Flea.Theme.color.accent, out = [], stack = [tile]
        while (stack.length > 0) {
            var o = stack.pop()
            var kids = o.children !== undefined ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
            if (o === tile || o.border === undefined || o.color === undefined || !o.visible || o.width <= 0) continue
            if (Math.abs(o.color.r - accent.r) > 0.002 || Math.abs(o.color.g - accent.g) > 0.002 || Math.abs(o.color.b - accent.b) > 0.002) continue
            var p = o.mapToItem(cap, 0, 0)
            if (p.x <= 0 && p.y <= 0 && p.x + o.width >= cap.width && p.y + o.height >= cap.height) continue
            out.push({ item: o, x: p.x, y: p.y, width: o.width, height: o.height })
        }
        return out.sort(function (a, b) { return a.y - b.y })
    }

    function effectiveAlpha(item, top) {
        var a = item.color.a
        for (var cur = item; cur !== null; cur = cur.parent) { a *= cur.opacity; if (cur === top) break }
        return a
    }

    function measured(cap, text) { piece.font = cap.font; piece.text = text; return piece.implicitWidth }

    // The run a List row would mark in the drawn caption, split at its breaks, placed the way Qt lays the line.
    function expected(tile, query) {
        var cap = tile.captionItem, parts = String(cap.text).split("\n")
        var at = parts.join("").toLowerCase().indexOf(query.toLowerCase())
        if (query.length === 0 || at < 0) return []
        lines.font = cap.font; lines.width = cap.width; lines.lineHeight = cap.lineHeight
        lines.maximumLineCount = cap.maximumLineCount; lines.widths = []; lines.text = cap.text; lines.forceLayout()
        var out = []
        for (var i = 0, pos = 0; i < parts.length; pos += parts[i].length, i++) {
            var from = Math.max(at, pos) - pos, to = Math.min(at + query.length, pos + parts[i].length) - pos
            if (from >= to) continue
            if (lines.widths[i] === undefined) root.fail("the line oracle reports no width for line " + i)
            // Qt lays a line's trailing blanks past the width it centres by, so the mark ends where that width does.
            var left = (cap.width - lines.widths[i]) / 2, x = left + root.measured(cap, parts[i].substring(0, from))
            var right = Math.min(x + root.measured(cap, parts[i].substring(from, to)), left + lines.widths[i])
            if (right - x > 0.01) out.push({ x: x, y: i * cap.lineHeight, width: right - x, height: piece.implicitHeight })
        }
        return out
    }

    // One tile's drawn mark against the oracle: the same boxes, List's ink, the cut dim multiplied in.
    function checkMark(label, tile, query, dim) {
        if (!tile) { root.fail(label + ": no tile draws the row it checks"); return }
        var want = root.expected(tile, query), got = root.washesOf(tile), name = tile.row ? tile.row.n : "?"
        if (got.length !== want.length) {
            root.fail(label + ": " + name + " draws " + got.length + " mark boxes, want " + want.length + " on " + JSON.stringify(query) + " in " + JSON.stringify(tile.captionItem.text))
            return
        }
        var ink = Flea.Theme.color.accent.a * Flea.Theme.washActive * dim
        for (var i = 0; i < want.length; i++) {
            var g = got[i], w = want[i]
            if (Math.abs(g.x - w.x) > 0.01 || Math.abs(g.y - w.y) > 0.01 || Math.abs(g.width - w.width) > 0.01 || Math.abs(g.height - w.height) > 0.01)
                root.fail(label + ": " + name + " box " + i + " is " + [g.x, g.y, g.width, g.height].join(",") + ", want " + [w.x, w.y, w.width, w.height].join(","))
            var a = root.effectiveAlpha(g.item, tile)
            if (Math.abs(a - ink) > 0.003)
                root.fail(label + ": " + name + " box " + i + " inks at alpha " + a + ", want " + ink)
        }
        if (root.checked.indexOf(label) < 0) root.checked.push(label)
    }

    // A row the step needs and no tile draws ends the probe here, with the names it missed.
    function need(ds, names) {
        var miss = names.filter(function (n) { return !ds[n] })
        if (miss.length > 0) { root.fail("no tile draws " + miss.join(", ")); root.report() }
        return miss.length === 0
    }

    function captionOf(tile) { var c = tile.captionItem; return [c.text, c.x, c.y, c.width, c.height].join("|") }

    // The long name fills the first line to a trailing blank after "no" and runs on in fewer cells than one line.
    function measureLayout() {
        var tile = root.drawn()["apple.txt"], per = tile ? tile.captionPerLine : -1
        if (per < 9) { root.fail("a caption line holds " + per + " cells, too few for the wrap fixture"); root.report(); return }
        root.longName = "Annotated-meeting-minutes-for-the-quarter".slice(0, per - 3) + "no " + "from-the-quarterly-review".slice(0, per - 6) + ".md"
        root.stubPane.rows = root.fixtureRows()
        root.then(root.measureRest)
    }

    function measureRest() {
        var ds = root.drawn(), names = Object.keys(ds)
        if (!root.need(ds, root.fixtureRows().map(function (r) { return r.n }))) return
        var counts = {}, caps = {}
        for (var i = 0; i < names.length; i++) {
            counts[names[i]] = root.countUnder(ds[names[i]])
            caps[names[i]] = root.captionOf(ds[names[i]])
            if (root.washesOf(ds[names[i]]).length !== 0) root.fail("rest: " + names[i] + " draws a mark with no query")
        }
        root.restCounts = counts
        root.restCaptions = caps
        var longCaption = String(ds[root.longName].captionItem.text)
        if (longCaption.indexOf("\n") < 0 || longCaption.indexOf("…") >= 0 || longCaption.split("\n")[0].slice(-1) !== " ")
            root.fail("the long name draws " + JSON.stringify(longCaption) + ", want two whole lines, the first ending in a blank")
        root.stubPane.filterTyping = true
        root.then(root.measureArmed)
    }

    // The strip is up and empty: the mark builds now, draws nothing, and moves no caption.
    function measureArmed() {
        var ds = root.drawn(), names = Object.keys(ds)
        for (var i = 0; i < names.length; i++) {
            var n = root.countUnder(ds[names[i]])
            if (root.armedCount < 0) root.armedCount = n - root.restCounts[names[i]]
            if (n - root.restCounts[names[i]] !== root.armedCount) root.fail("armed: " + names[i] + " builds " + (n - root.restCounts[names[i]]) + " over rest, others " + root.armedCount)
            if (root.washesOf(ds[names[i]]).length !== 0) root.fail("armed: " + names[i] + " draws a mark with no query")
            if (root.captionOf(ds[names[i]]) !== root.restCaptions[names[i]]) root.fail("armed: " + names[i] + " moved its caption to " + root.captionOf(ds[names[i]]))
        }
        root.stubPane.filterQuery = "no"
        // R0: every tile drawing a row carries its mark in the turn the narrowing lands, before any frame.
        var now = root.drawn(), keys = Object.keys(now)
        for (var k = 0; k < keys.length; k++) root.checkMark("same turn", now[keys[k]], "no", 1)
        root.then(root.measureKey)
    }

    function measureKey() {
        var ds = root.drawn(), names = Object.keys(ds).sort()
        if (!root.need(ds, [root.longName, "notes.txt", "piano.md"])) return
        if (names.join(",") !== [root.longName, "notes.txt", "piano.md"].sort().join(","))
            root.fail("no narrows to " + names.join(","))
        for (var i = 0; i < names.length; i++) {
            var t = ds[names[i]]
            if (root.countUnder(t) - root.restCounts[names[i]] !== root.armedCount) root.fail("the key built on " + names[i] + ": " + (root.countUnder(t) - root.restCounts[names[i]]) + " over rest, armed " + root.armedCount)
            if (names[i] !== "notes.txt" && t.cursor) root.fail(names[i] + " is the cursor, want notes.txt alone")
            if (root.captionOf(t) !== root.restCaptions[names[i]]) root.fail("the mark moved " + names[i] + "'s caption to " + root.captionOf(t))
            root.checkMark(t.cursor ? "cursor" : "rest", t, "no", 1)
        }
        root.stubPane.selected = { 4: true }
        ds[root.longName].hovered = true
        root.then(root.measureLifted)
    }

    function measureLifted() {
        var ds = root.drawn()
        if (!root.need(ds, ["piano.md", root.longName])) return
        root.checkMark("selected", ds["piano.md"], "no", 1)
        root.checkMark("hover", ds[root.longName], "no", 1)
        ds[root.longName].hovered = false
        root.stubPane.selected = {}
        root.stubPane.clipboard = { paths: ["/probe/piano.md"], moving: true }
        ds["notes.txt"].dropTarget = true
        root.then(root.measureCutDrop)
    }

    function measureCutDrop() {
        var ds = root.drawn(), cut = ds["piano.md"], drop = ds["notes.txt"]
        if (!root.need(ds, ["piano.md", "notes.txt"])) return
        if (cut.clipMark !== "scissors") root.fail("the cut fixture marks piano.md " + JSON.stringify(cut.clipMark))
        root.checkMark("cut", cut, "no", Flea.Theme.disabledOpacity)
        if (String(drop.captionItem.text).indexOf("\n") >= 0) root.fail("a drop target draws its caption on two lines")
        root.checkMark("drop", drop, "no", 1)
        drop.dropTarget = false
        root.stubPane.clipboard = { paths: [], moving: false }
        // The rewrap check needs both captions drawing their mark now, before their letters widen.
        if ([ds[root.longName], drop].some(function (t) { return root.washesOf(t).length === 0 })) root.fail("rewrap: a caption draws no mark box before its letters widen, so the rewrap check proves nothing")
        // Wider letters than the cells Flea broke the captions by make Qt lay them out again, as a wide-glyph name would.
        ds[root.longName].captionItem.font.letterSpacing = Flea.Theme.font.bodySmall
        drop.captionItem.font.letterSpacing = Flea.Theme.font.bodySmall
        root.then(root.measureRewrap)
    }

    // Captions Qt laid out again, one elided and one wrapped past Flea's breaks, draw no box rather than one off their letters.
    function measureRewrap() {
        var ds = root.drawn(), elided = ds[root.longName], wrapped = ds["notes.txt"]
        if (!root.need(ds, [root.longName, "notes.txt"])) return
        if (!elided.captionItem.truncated) root.fail("rewrap: wider letters leave " + JSON.stringify(elided.captionItem.text) + " whole")
        if (wrapped.captionItem.lineCount < 2 || wrapped.captionItem.truncated)
            root.fail("rewrap: wider letters lay notes.txt on " + wrapped.captionItem.lineCount + " lines, truncated " + wrapped.captionItem.truncated + ", want two whole ones")
        var tiles = [elided, wrapped]
        for (var i = 0; i < tiles.length; i++) {
            var n = root.washesOf(tiles[i]).length
            if (n !== 0) root.fail("rewrap: " + tiles[i].row.n + " laid out again draws " + n + " mark boxes")
            tiles[i].captionItem.font.letterSpacing = 0
        }
        root.checked.push("rewrap")
        root.then(root.measureWrapSetup)
    }

    // A query whose first match starts on the first line and ends on the second.
    function measureWrapSetup() {
        if (!root.need(root.drawn(), [root.longName])) return
        var tile = root.drawn()[root.longName]
        var parts = String(tile.captionItem.text).split("\n"), joined = parts.join("").toLowerCase()
        for (var a = 3; a >= 1 && root.wrapQuery === ""; a--) {
            for (var b = 2; b >= 1 && root.wrapQuery === ""; b--) {
                var q = parts[0].slice(-a) + parts[1].slice(0, b)
                if (joined.indexOf(q.toLowerCase()) === parts[0].length - a) root.wrapQuery = q
            }
        }
        if (root.wrapQuery === "") { root.fail("no query crosses the wrap of " + JSON.stringify(tile.captionItem.text)); root.report(); return }
        root.stubPane.filterQuery = root.wrapQuery
        root.checkMark("wrap same turn", root.drawn()[root.longName], root.wrapQuery, 1)
        root.then(root.measureWrap)
    }

    function measureWrap() {
        if (!root.need(root.drawn(), [root.longName])) return
        var tile = root.drawn()[root.longName]
        if (root.washesOf(tile).length !== 2) root.fail("a run across the wrap draws " + root.washesOf(tile).length + " boxes, want one per line")
        root.checkMark("wrap", tile, root.wrapQuery, 1)
        root.stubPane.filterQuery = ""
        root.stubPane.filterTyping = false
        root.stubPane.searchMode = "results"
        root.stubPane.searchQuery = "apz"
        root.stubPane.rows = ["sub/apex.txt", "maps/capital.txt", "a/p.txt", "sub/deep/happy.md"].map(function (n) { return { n: n, d: false, i: "text-x-generic", p: 420, s: 13, m: 1758835200, t: false, k: 0, v: 0 } })
        root.stubPane.swap.answeredQuery = "ap"
        root.then(root.measureSearch)
    }

    // A search marks its answered query on the path label, never the live text; a fuzzy row with no run draws none.
    function measureSearch() {
        var ds = root.drawn()
        if (!root.need(ds, ["sub/apex.txt", "maps/capital.txt", "a/p.txt", "sub/deep/happy.md"])) return
        root.checkMark("search", ds["sub/apex.txt"], "ap", 1)
        root.checkMark("search", ds["maps/capital.txt"], "ap", 1)
        root.checkMark("search", ds["sub/deep/happy.md"], "ap", 1)
        if (root.washesOf(ds["a/p.txt"]).length !== 0) root.fail("a fuzzy row with no run draws a mark")
        root.stubPane.swap.answeredQuery = ""
        root.then(root.measureClosed)
    }

    function measureClosed() {
        var ds = root.drawn(), names = Object.keys(ds)
        for (var i = 0; i < names.length; i++)
            if (root.washesOf(ds[names[i]]).length !== 0) root.fail("an empty answer still marks " + names[i])
        root.stubPane.searchMode = ""
        root.stubPane.searchQuery = ""
        root.stubPane.rows = root.fixtureRows()
        root.then(root.measureBack)
    }

    // The strip gone, every tile is back at its rest count and caption.
    function measureBack() {
        var ds = root.drawn(), names = Object.keys(ds)
        for (var i = 0; i < names.length; i++) {
            if (root.countUnder(ds[names[i]]) !== root.restCounts[names[i]]) root.fail("closed: " + names[i] + " holds " + root.countUnder(ds[names[i]]) + ", rest " + root.restCounts[names[i]])
            if (root.captionOf(ds[names[i]]) !== root.restCaptions[names[i]]) root.fail("closed: " + names[i] + " caption " + root.captionOf(ds[names[i]]))
        }
        root.report()
    }

    function report() {
        if (root.failures.length === 0)
            console.log("GRIDMARK PASS armed=+" + root.armedCount + " keybuilt=0 states=" + root.checked.join(",") + " wrap=" + JSON.stringify(root.wrapQuery))
        for (var f = 0; f < root.failures.length; f++)
            console.log("GRIDMARK FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
