//@ pragma ShellId flea-preview-tall

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Focus.js" as Focus
import "flea/js/Keymap.js" as Keymap

// A tall kind's frame fills the Columns preview from its top down to the name, over one compact facts line that `i` swaps for the table; tests/preview-tall.sh drives it.
ShellRoot {
    id: root

    readonly property string dir: Quickshell.env("TALL_DIR")
    readonly property int winW: parseInt(Quickshell.env("TALL_W"))
    readonly property int winH: parseInt(Quickshell.env("TALL_H"))
    readonly property bool relaunch: Quickshell.env("TALL_PHASE") === "relaunch"
    readonly property real gap: Flea.Theme.spacing.gap
    readonly property real margin: Flea.Theme.spacing.rowPaddingX

    property int passed: 0
    property int failed: 0
    property var rec: null
    property var nameY: ({})
    property int stepAt: -1
    property double since: 0
    property string stage: "boot"

    function log(line) { console.log("TALL " + line) }
    function check(name, got, want) {
        if (got === want) { root.passed += 1; root.log("PASS " + name + " got=" + got) }
        else { root.failed += 1; root.log("FAIL " + name + " got=" + got + " want=" + want) }
    }
    function near(name, got, want) { root.check(name, Math.abs(got - want) <= 1, true) }

    QtObject {
        id: backend
        signal peeked(string path, bool hidden, int total, var rows, bool readFailed, int mode, bool hiddenLast, int first)
        signal metaResult(var message)
        property int dirDev: 0
        property int seq: 0
        property var pending: []
        function peek(path, size, hidden) {}
        function askMeta(index, wantLines, wantMedia, wantArchive) {
            seq += 1
            pending.push({ token: seq, index: index })
            flushTimer.restart()
            return seq
        }
        function flush() {
            var p = pending
            pending = []
            for (var i = 0; i < p.length; i++) {
                var r = root.rowsList[p[i].index]
                backend.metaResult({ token: p[i].token, w: r.w || 0, h: r.h || 0, ms: 0, rate: 0, entries: r.entries || 0,
                    unpacked: r.entries ? 3400000 : 0, afailed: false, names: r.names || [], lines: r.lines || 0, partial: false,
                    lfailed: false, target: "", targetdir: "", owner: "", orient: 1 })
            }
        }
        function thumb(rows, cacheOnly) {}
        function thumbcancel(rows) {}
        function dirsize(rows) {}
        function dirsizecancel() {}
        function window(start, count) {}
    }

    // The reply lands a few frames after the row shows, as a real backend's does, so a frame shape that follows the load state would show.
    Timer { id: flushTimer; interval: 90; onTriggered: backend.flush() }

    function memberNames() {
        var out = []
        for (var i = 0; i < 40; i++) out.push({ n: "src/member-" + i + ".txt", d: false })
        return out
    }

    readonly property var rowsList: [
        { n: "icons.rs", d: false, k: 0, p: 33188, s: 4100, m: 1758835200, t: false, i: "text-x-generic", lines: 132 },
        { n: "notes.md", d: false, k: 1, p: 33188, s: 6200, m: 1758835201, t: false, i: "text-x-generic", lines: 48 },
        { n: "plain.txt", d: false, k: 2, p: 33188, s: 900, m: 1758835202, t: false, i: "text-x-generic", lines: 20 },
        { n: "backup.zip", d: false, k: 3, p: 33188, s: 9000, m: 1758835203, t: false, i: "package-x-generic", entries: 214, names: root.memberNames() },
        { n: "shot.png", d: false, k: 4, p: 33188, s: 5200, m: 1758835204, t: false, i: "image-x-generic", w: 1920, h: 1080 },
        { n: "phone.png", d: false, k: 4, p: 33188, s: 5200, m: 1758835205, t: false, i: "image-x-generic", w: 1170, h: 2532 },
        { n: "long.rs", d: false, k: 5, p: 33188, s: 4100, m: 1758835206, t: false, i: "text-x-generic", lines: 132 }
    ]

    QtObject {
        id: pane
        property string path: root.dir
        property string viewMode: "columns"
        property string focusView: "list"
        property var preview: null
        property var previewColumnItem: area.previewColumn
        property var rows: root.rowsList
        property int cursorIndex: 0
        property bool showHidden: false
        property int windowSize: 35
        property bool listInFlight: false
        property string listingState: "ready"
        property string searchMode: ""
        property string filterQuery: ""
        property bool filterTyping: false
        property string dropPath: ""
        property var statusBar: null
        property var thumbState: ({ file: {}, order: [] })
        property var dirSizeState: ({ file: {}, order: [] })
        property var kindNames: ["Rust source code", "Markdown document", "Plain text", "Zip archive", "PNG image", "Rust source code in the 2024 edition of the language"]
        property bool storageKnown: true
        property string storageClass: "local"
        property int firstSettleMs: 70
        property int settleMs: 120
        property int coalesceMs: 16
        property int refetchMargin: 25
        property int buffer: 150
        property int total: 7
        property int held: 0
        property var shown: null
        property int shownTotal: 7
        property int renamingIndex: -1
        property int selectionVersion: 0
        property var clipboard: null
        property var trash: ({ opened: false })
        property var listArea: ({ forceActiveFocus: function () {} })
        readonly property int previewIndex: area.previewIndex
        property var backend: backend
        function join(base, name) { return String(base) + "/" + String(name) }
        function rowFor(index) { return (index >= 0 && index < rows.length) ? rows[index] : null }
        function isSelected(index) { return selectionVersion < 0 }
        function selectedIndices() { return [cursorIndex] }
        function selectionCount() { return 1 }
        function thumbFor(index) { return "" }
        function open(path) {}
        function openFile(path) {}
        function focusRequested() {}
    }

    QtObject { id: menu; function close() {} function openBackground(point) {} }

    FloatingWindow {
        implicitWidth: root.winW
        implicitHeight: root.winH
        color: Flea.Theme.color.background
        Flea.ColumnsArea { id: area; anchors.fill: parent; pane: pane; menu: menu }
        Item { id: scratch; visible: false }
    }

    readonly property Item col: area.previewColumn

    function all(item, out) {
        for (var i = 0; i < item.children.length; i++) { out.push(item.children[i]); root.all(item.children[i], out) }
        return out
    }
    function find(test) { var list = root.all(root.col, []); for (var i = 0; i < list.length; i++) if (test(list[i])) return list[i]; return null }
    function factsBlock() { return root.find(function (it) { return it.compact !== undefined && it.line !== undefined }) }
    function factsLine() { return root.find(function (it) { return typeof it.tail === "string" && typeof it.kind === "string" }) }
    function table() { return root.find(function (it) { return it.labelWidth !== undefined && it.rows !== undefined }) }
    function nameItem() {
        return root.find(function (it) { return it.text === root.col.row.n && it.font && it.font.pixelSize === Flea.Theme.font.body })
    }
    function top(item) { return item.mapToItem(root.col, 0, 0).y }
    function members(item) { return root.all(item, []).length + 1 }

    // One sample a frame: the frame's height from the first frame that shows a row must never change while that row settles.
    FrameAnimation {
        running: true
        onTriggered: {
            var row = root.col.row
            if (!row) { root.rec = null; return }
            var h = root.col.frameItem.height
            if (root.rec === null || root.rec.name !== row.n) root.rec = { name: row.n, last: h, changes: 0 }
            else if (h !== root.rec.last) { root.rec.changes += 1; root.rec.last = h }
        }
    }

    function tallGeometry(label, tail) {
        var fr = root.col.frameItem
        var nameTop = root.top(root.nameItem())
        var line = root.factsLine()
        root.check(label + " frame top is the column top plus the margin", root.top(fr), root.margin)
        root.check(label + " frame bottom is the name top less one gap", root.top(fr) + fr.height + root.gap, nameTop)
        root.check(label + " the facts line sits one gap under the name", nameTop + root.nameItem().height + root.gap, root.top(line))
        root.check(label + " the facts line ends at the column bottom margin", root.top(line) + line.height + root.margin, root.col.height)
        root.check(label + " the line reads " + tail, line.kind + line.tail, tail)
        root.check(label + " the table is not shown", root.table().visible || root.table().rows.length > 0, false)
        root.check(label + " the frame height never changed while the row settled", root.rec.changes, 0)
        if (root.nameY.base === undefined) root.nameY.base = nameTop
        root.check(label + " the name keeps one place across kinds", nameTop, root.nameY.base)
    }

    // The code lines are CodeLines' rows, each a StyledText body in its own delegate, one row per line.
    function lineFit() {
        var lines = root.col.linesItem
        var built = root.all(lines, []).filter(function (it) { return it.textFormat === Text.StyledText })
        var drawn = built.filter(function (it) { return it.visible && it.mapToItem(lines.viewport, 0, 0).y >= 0 && it.mapToItem(lines.viewport, 0, 0).y < lines.viewport.height })
        var row = lines.viewport ? lines.viewport.itemAtIndex(0) : null
        var fits = row ? Math.ceil(lines.viewport.height / row.height) : -1
        root.check("code draws as many lines as fit the frame", drawn.length, Math.min(132, fits))
        root.check("and builds no more line items than fit (" + built.length + " built, " + fits + " fit)", built.length <= fits, true)
        root.check("and fills the frame past fourteen lines", drawn.length > 14, true)
    }

    // Narrow: the Kind elides alone and the tail is whole; wide: nothing elides.
    function elision(label, overflows) {
        var line = root.factsLine()
        var texts = line.children.filter(function (it) { return it.text !== undefined })
        var overflow = texts[0].implicitWidth + texts[1].implicitWidth > line.width
        root.log("WIDTHS " + label + " line=" + line.width + " kind=" + texts[0].implicitWidth + " tail=" + texts[1].implicitWidth)
        root.check(label + " the line " + (overflows ? "overflows" : "fits") + " its width", overflow, overflows)
        root.check(label + " the tail is whole", texts[1].width >= texts[1].implicitWidth - 1 && !texts[1].truncated && texts[1].x + texts[1].width <= line.width + 1, true)
        root.check(label + " the Kind elides exactly when the line overflows", texts[0].truncated, overflow)
    }

    function classes() {
        var out = []
        for (var i = 0; i < 4; i++) {
            Keymap.setPreset(Keymap.PRESETS[i])
            out.push(Focus.lookup({ key: Qt.Key_I, text: "i", modifiers: Qt.NoModifier }, pane))
        }
        Keymap.setPreset("default")
        root.check("i is factsToggle in the listing context of all four presets", out.join("|"), "factsToggle|factsToggle|factsToggle|factsToggle")
        root.check("and means nothing while the preview column or a viewer has the keys", Keymap.lookup(Qt.Key_I, "i", Qt.NoModifier, "preview") + Keymap.lookup(Qt.Key_I, "i", Qt.NoModifier, "pdf"), "")
    }

    // The block holds the line and an empty table, which is no more objects than the table int drew alone for this row.
    function objectCount(label) {
        var block = root.factsBlock()
        var rows = root.col.factRows
        var made = tableMaker.createObject(scratch, { rows: rows })
        var intCount = root.members(made)
        made.destroy()
        root.log("OBJECTS " + label + " block=" + root.members(block) + " table=" + intCount)
        root.check(label + " the facts block builds within one object of the table it replaces", root.members(block) <= intCount + 1, true)
    }
    Component { id: tableMaker; Flea.FactsTable { width: 300 } }

    function pressI() {
        var action = Focus.lookup({ key: Qt.Key_I, text: "i", modifiers: Qt.NoModifier }, pane)
        Focus.act(action, pane)
    }
    function settled(name) {
        var c = root.col
        return c.row !== null && c.row.n === name && c.meta !== null && !c.busy && !c.pending && area.thirdReady
            && !c.textLoading && (!c.swap || (!c.swap.capturing && !c.swap.holding))
    }

    readonly property var firstPlan: [
        { row: 0, run: function () {
            root.classes()
            root.tallGeometry("icons.rs", "Rust source code \u00b7 4.1 kB \u00b7 132 lines")
            root.elision("icons.rs", false)
            root.lineFit()
            root.objectCount("icons.rs")
        } },
        { row: 1, run: function () { root.tallGeometry("notes.md", "Markdown document \u00b7 6.2 kB \u00b7 48 lines") } },
        { row: 2, run: function () { root.tallGeometry("plain.txt", "Plain text \u00b7 900 B \u00b7 20 lines") } },
        { row: 3, run: function () {
            root.tallGeometry("backup.zip", "Zip archive \u00b7 9.0 kB \u00b7 214 entries")
            var arch = root.col.archiveItem
            var named = root.all(arch, []).filter(function (it) { return it.name === "folder" || it.name === "file" }).length
            root.check("the archive lists as many names as its frame holds", named, Math.min(40, arch.shown))
            root.check("and a tall frame holds more than fourteen", arch.shown > 14, true)
        } },
        { row: 6, run: function () {
            root.tallGeometry("long.rs", "Rust source code in the 2024 edition of the language \u00b7 4.1 kB \u00b7 132 lines")
            root.elision("long.rs", true)
        } },
        { row: 4, run: function () { root.roundFrame("landscape png") } },
        { row: 5, run: function () { root.roundFrame("portrait png") } },
        { row: 0, write: true, run: function () { root.fullMode() },
          after: function () { root.check("the swap resized the frame in one frame", root.rec.changes, 1); root.fullPlaces() } }
    ]
    readonly property var relaunchPlan: [
        { row: 0, write: true, run: function () { root.relaunchRun() }, after: function () {} }
    ]
    readonly property var plan: root.relaunch ? root.relaunchPlan : root.firstPlan

    // Every other kind keeps the 16 by 10 frame and the table.
    function roundFrame(label) {
        var fr = root.col.frameItem
        root.near(label + " keeps the 16 by 10 frame", fr.height, Math.round(fr.width * 10 / 16))
        root.check(label + " keeps the table", root.table().visible && root.table().rows.length >= 4, true)
        root.check(label + " draws no compact line", root.factsLine().visible, false)
    }

    // i swaps the line for the table pinned at the bottom, the frame shorter by exactly its height, and writes previewFacts.
    function fullMode() {
        var fr = root.col.frameItem
        var lineH = root.factsLine().height
        var compactH = fr.height
        root.pressI()
        root.check("i writes the mode", Flea.ViewState.previewFacts, "full")
        var t = root.table()
        root.check("the table replaces the line", t.visible && !root.factsLine().visible, true)
        root.check("the frame is shorter by exactly the table less the line", compactH - fr.height, t.height - lineH)
    }

    // The Column lays out on the next polish, so the places are read once the write has landed.
    function fullPlaces() {
        var fr = root.col.frameItem
        var t = root.table()
        root.check("the table is pinned at the column bottom", root.top(t) + t.height + root.margin, root.col.height)
        root.check("the frame still ends one gap above the name", root.top(fr) + fr.height + root.gap, root.top(root.nameItem()))
        root.check("the table sits one gap under the name", root.top(root.nameItem()) + root.nameItem().height + root.gap, root.top(t))
        pane.previewColumnItem = null
        root.pressI()
        root.check("i does nothing without the column on screen", Flea.ViewState.previewFacts, "full")
        pane.previewColumnItem = area.previewColumn
    }

    function relaunchRun() {
        var t = root.table()
        var fr = root.col.frameItem
        root.check("a relaunch reads the full mode", Flea.ViewState.previewFacts, "full")
        root.check("and draws the table from the first row", t.visible && t.rows.length > 0 && !root.factsLine().visible, true)
        root.check("with the frame ending above the name", root.top(fr) + fr.height + root.gap, root.top(root.nameItem()))
        root.pressI()
        root.check("i returns to the compact line", Flea.ViewState.previewFacts + "|" + root.factsLine().visible, "compact|true")
    }

    function move(r) {
        pane.cursorIndex = r
        area.activeColumn().showCursor(r)
        area.restartCoalesce()
        pane.selectionVersion += 1
    }

    function stop() {
        stepper.stop()
        root.log("QMLTALLY passed=" + root.passed + " failed=" + root.failed)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    // wait: the row has settled; write: the state file has the change.
    Timer {
        id: stepper
        interval: 16
        repeat: true
        onTriggered: {
            if (Date.now() - root.since > 20000) { root.check("deadline in stage " + root.stage + " step " + root.stepAt, false, true); root.stop(); return }
            var step = root.stepAt >= 0 ? root.plan[root.stepAt] : null
            if (root.stage === "boot") { if (root.col.frameItem) root.advance() }
            else if (root.stage === "wait") {
                if (!root.settled(root.rowsList[step.row].n)) return
                step.run()
                if (step.write) root.stage = "write"
                else root.advance()
            } else if (root.stage === "write" && JSON.stringify(Flea.ViewState.unsaved) === "{}") {
                step.after()
                root.advance()
            }
        }
    }

    function advance() {
        root.since = Date.now()
        root.stepAt += 1
        if (root.stepAt >= root.plan.length) { root.stop(); return }
        root.stage = "wait"
        root.move(root.plan[root.stepAt].row)
    }

    Component.onCompleted: { root.since = Date.now(); stepper.start() }
}
