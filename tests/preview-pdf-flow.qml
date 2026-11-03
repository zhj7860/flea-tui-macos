//@ pragma ShellId flea-preview-pdf-flow

import QtQuick
import QtTest
import QtQuick.Pdf
import Quickshell
import "flea" as Flea

// A PDF in the Columns preview fills the frame's width, its pages follow one another under a scroll knob, and only the pages near the frame are built; tests/preview-pdf-flow.sh drives it.
ShellRoot {
    id: root

    readonly property string dir: Quickshell.env("FLOW_DIR")
    readonly property int winW: parseInt(Quickshell.env("FLOW_W"))
    readonly property int winH: parseInt(Quickshell.env("FLOW_H"))
    readonly property real gap: Flea.Theme.spacing.gap

    property int passed: 0
    property int failed: 0
    property int stepAt: -1
    property double since: 0
    property string stage: "boot"
    property int wheels: 0
    property int sinceWheel: 0
    property int lastWheel: 0
    property int blankFrames: 0
    property int sampled: 0
    property int peakImages: 0
    property int focusCalls: 0
    property int inset: 0
    property real bigWidth: 0

    function log(line) { console.log("FLOW " + line) }
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
            for (var i = 0; i < p.length; i++)
                backend.metaResult({ token: p[i].token, w: 0, h: 0, ms: 0, rate: 0, entries: 0, unpacked: 0, afailed: false, names: [],
                    lines: 0, partial: false, lfailed: false, target: "", targetdir: "", owner: "", orient: 1 })
        }
        function thumb(rows, cacheOnly) {}
        function thumbcancel(rows) {}
        function dirsize(rows) {}
        function dirsizecancel() {}
        function window(start, count) {}
        function pdfCopy(path, slot) { return 0 }
    }
    Timer { id: flushTimer; interval: 90; onTriggered: backend.flush() }

    readonly property var rowsList: [
        { n: "report.pdf", d: false, k: 0, p: 33188, s: 2400000, m: 1758835200, t: false, i: "x-office-document" },
        { n: "receipt.pdf", d: false, k: 0, p: 33188, s: 31000, m: 1758835201, t: false, i: "x-office-document" },
        { n: "slip.pdf", d: false, k: 0, p: 33188, s: 12000, m: 1758835202, t: false, i: "x-office-document" },
        { n: "big.pdf", d: false, k: 0, p: 33188, s: 90000, m: 1758835203, t: false, i: "x-office-document" }
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
        property var kindNames: ["PDF document"]
        property bool storageKnown: true
        property string storageClass: "local"
        property int firstSettleMs: 70
        property int settleMs: 120
        property int coalesceMs: 16
        property int refetchMargin: 25
        property int buffer: 150
        property int total: 4
        property int held: 0
        property var shown: null
        property int shownTotal: 4
        property int renamingIndex: -1
        property int selectionVersion: 0
        property var clipboard: null
        property var trash: ({ opened: false })
        property var listArea: ({ forceActiveFocus: function () { root.focusCalls += 1 } })
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
        Flea.ColumnsArea { id: area; anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; width: parent.width - root.inset; pane: pane; menu: menu }
        Flea.PdfViewer {
            id: look
            anchors.fill: parent
            visible: false
            path: root.dir + "/report.pdf"
            active: false
        }
        TestEvent { id: driver }
    }

    readonly property Item col: area.previewColumn

    function all(item, out) {
        for (var i = 0; i < item.children.length; i++) { out.push(item.children[i]); root.all(item.children[i], out) }
        return out
    }
    function find(item, test) { var list = root.all(item, []); for (var i = 0; i < list.length; i++) if (test(list[i])) return list[i]; return null }
    function pdf() { return root.find(root.col, function (it) { return it.continuous === true && it.pageSlot !== undefined }) }
    function bar() { return root.find(root.col, function (it) { return it.knobItem !== undefined && it.orientation === Qt.Vertical }) }
    function flick() { var p = root.pdf(); return p ? p.viewport : null }
    function images(item) { return root.all(item, []).filter(function (it) { return it.currentFrame !== undefined && it.document !== undefined }) }
    function slots() {
        var p = root.pdf()
        var out = []
        for (var i = 0; p && i < p.pageCount; i++) if (p.pageSlot(i)) out.push(p.pageSlot(i))
        return out
    }
    // Every page slot the stack holds, found by what a slot is rather than through the page lookup.
    function slotItems() { return root.all(root.pdf(), []).filter(function (it) { return it.rendering !== undefined && it.errored !== undefined }) }
    // The slots a frame of the flickable shows any part of.
    function inView() {
        var f = root.flick()
        return root.slots().filter(function (s) { return s.y + s.height > f.contentY && s.y < f.contentY + f.height })
    }
    function landed(slot) {
        var im = root.images(slot)
        return im.length === 1 && im[0].status === Image.Ready
    }

    // One sample a frame once the column has drawn the document: a page in view without its render is a blank frame.
    FrameAnimation {
        running: true
        onTriggered: {
            var c = root.col
            if (!c.row || c.row.n !== "report.pdf" || !c.pdfDrawn || !root.pdf()) return
            root.sampled += 1
            if (!root.flick() || !root.flick().visible) return
            var shown = root.inView()
            for (var i = 0; i < shown.length; i++) if (!root.landed(shown[i])) { root.blankFrames += 1; break }
            root.peakImages = Math.max(root.peakImages, root.images(c).length)
        }
    }

    function settled(name) {
        var c = root.col
        return c.row !== null && c.row.n === name && c.meta !== null && !c.busy && !c.pending && area.thirdReady
            && c.pdfPages > 0 && c.pdfDrawn && (!c.swap || (!c.swap.capturing && !c.swap.holding))
    }

    function stripItems() {
        return root.all(root.col, []).filter(function (it) {
            return ["chevron-left", "chevron-right", "minus", "plus", "maximize"].indexOf(it.glyph) >= 0
                || (it.text !== undefined && /^\d+ \/ \d+$/.test(String(it.text)))
        })
    }

    function report() {
        var f = root.flick()
        var p = root.pdf()
        var fr = root.col.frameItem
        var inner = fr.width - 2 * fr.border.width
        var s0 = p.pageSlot(0)
        var s1 = p.pageSlot(1)
        var total = 12 * Math.round(inner * 792 / 612) + 11 * root.gap
        root.check("the frame is a tall one over the facts line", root.col.tallRow && root.col.previewState === "pdf", true)
        root.near("page 1 is as wide as the frame inside its border", s0.width, inner)
        root.near("page 1 keeps the page's own proportion", s0.height, Math.round(inner * 792 / 612))
        root.check("page 1 starts at the frame's top", s0.y + "|" + f.contentY, "0|0")
        root.check("page 2 follows one gap under page 1", s1.y, s0.y + s0.height + root.gap)
        root.check("page 2's top is in view under page 1", s1.y < f.contentY + f.height, true)
        root.check("the content is as tall as the twelve pages and eleven gaps", f.contentHeight, total)
        root.check("the stack is as wide as the frame", f.contentWidth, f.width)
        root.check("no chevron, page chip or zoom mark is in the column", root.stripItems().length, 0)
        root.check("the line states the pages", root.col.factRows.length > 0 && root.factsLine().indexOf("12 pages") >= 0, true)
        root.check("page 1 is rendered at the first settled frame", root.landed(s0) && root.landed(s1), true)
        root.check("the column reads page 1 and 2 as landed", root.col.pdfLanded().indexOf(0) >= 0 && root.col.pdfLanded().indexOf(1) >= 0, true)
        var im = root.images(root.col)
        var visible = root.inView().length
        root.check("at rest at most the visible pages and two are built", im.length <= visible + 2, true)
        root.check("at rest the page 1 render is the frame's width in device pixels", im[0].sourceSize.width, Math.round(inner * Screen.devicePixelRatio))
        var b = root.bar()
        root.check("the knob is on the frame's lane", b !== null && b.overflow && b.visible, true)
        root.near("the knob is the visible share of the content", b.handleLength, Math.max(Flea.Theme.hitMin, b.trackLength * f.height / f.contentHeight))
        root.check("the content height was right before any render landed", root.firstHeight, total)
        root.log("COUNTS rest images=" + im.length + " visible=" + visible)
    }

    function factsLine() { return root.find(root.col, function (it) { return typeof it.tail === "string" && typeof it.kind === "string" && it.visible }).tail }

    function wheelOnce() {
        var fr = root.col.frameItem
        var at = fr.mapToItem(root.col, fr.width / 2, fr.height / 2)
        driver.mouseWheel(root.col, at.x, at.y, Qt.NoButton, Qt.NoModifier, 0, -120, 1)
        root.wheels += 1
    }

    function scrolled() {
        var f = root.flick()
        var b = root.bar()
        var im = root.images(root.col)
        var visible = root.inView().length
        root.check("a wheel reached page 6 or later", root.col.pdfPage() >= 5, true)
        root.check("the page under the frame's top is the one its offset names", root.col.pdfPage(), root.pdf().pageAt(f.contentY))
        root.check("after the scroll at most the visible pages and two are built", im.length <= visible + 2, true)
        root.check("the wheel left the listing the keyboard", root.focusCalls + "|" + root.col.activeFocus, "0|false")
        root.check("the knob shows while the view moves", b.shown, true)
        root.near("and sits where the view is", b.handleOffset, b.trackLength * f.contentY / f.contentHeight)
        root.check("no frame showed a page without its render", root.blankFrames, 0)
        root.log("COUNTS scrolled images=" + im.length + " visible=" + visible + " peak=" + root.peakImages + " blank=" + root.blankFrames + "/" + root.sampled + " wheels=" + root.wheels)
        root.check("the peak never passed the visible pages and two", root.peakImages <= 6, true)
    }

    property real firstHeight: -1
    Timer {
        // The first height the column's flickable has once the document is ready, read before the first render lands.
        interval: 1
        repeat: true
        running: true
        onTriggered: {
            var c = root.col
            if (root.firstHeight >= 0 || !c || !c.row || c.row.n !== "report.pdf" || c.pdfPages <= 0) return
            var f = root.flick()
            if (f) root.firstHeight = f.contentHeight
        }
    }

    function receipt() {
        var p = root.pdf()
        var f = root.flick()
        var b = root.bar()
        var fr = root.col.frameItem
        root.check("a one-page document is as wide as the frame", Math.abs(p.pageSlot(0).width - (fr.width - 2 * fr.border.width)) <= 1, true)
        root.check("and states one page", root.factsLine().indexOf("1 page") >= 0 && root.factsLine().indexOf("1 pages") < 0, true)
        root.check("and builds one page", root.images(root.col).length, 1)
        root.check("and has no strip", root.stripItems().length, 0)
        root.check("a row after a scrolled one opens at its top", f.contentY, 0)
        root.check("a tall single page taller than the frame has the knob", f.contentHeight > f.height && b.overflow, true)
    }

    // A document that does not open is handed to one slot's own image, whose render then fails and reports through onStatusChanged.
    PdfDocument { id: brokenDoc; source: "file://" + root.dir + "/broken.pdf" }
    function breakSlot(no) {
        var image = root.images(root.pdf().pageSlot(no))[0]
        image.document = brokenDoc
        image.sourceSize = Qt.size(image.sourceSize.width + 1, 0)
    }
    function slotErrored(no) {
        var slot = root.pdf() ? root.pdf().pageSlot(no) : null
        return slot !== null && slot.errored
    }
    function laterPage() {
        root.check("a later page whose render failed is left in its own slot", root.slotErrored(1), true)
        root.check("and does not fail the column", root.col.pdfFailed, false)
        root.check("the pane stays on the stack", root.col.previewState, "pdf")
        root.check("and the page before it still draws", root.landed(root.pdf().pageSlot(0)), true)
    }
    function topPage() {
        root.check("the page under the frame's top can fail after the first draw", root.slotErrored(0), true)
        root.check("and does not fail the drawn column", root.col.pdfFailed, false)
        root.check("the drawn pane stays on the stack", root.col.previewState, "pdf")
    }
    function laterUndrawnPage() {
        root.check("a later page can fail before the first draw", root.slotErrored(1), true)
        root.check("and does not fail the undrawn column", root.col.pdfFailed, false)
        root.check("the undrawn pane stays on the stack", root.col.previewState, "pdf")
    }
    function failedPage() {
        root.check("a first page whose render failed puts the pane in the failure state", root.col.pdfFailed && root.col.previewState === "error", true)
    }

    // A 500-page document: the slots and images stay with the frame, and the page sizes are read once per document, never per width.
    function big() {
        var p = root.pdf()
        var visible = root.inView().length
        root.bigWidth = p.width
        root.check("a 500-page document builds slots only near the frame", root.slotItems().length <= visible + 2, true)
        root.check("and images only near the frame", root.images(root.col).length <= visible + 2, true)
        root.check("and reads its 500 page sizes once", p.sizeReads, 500)
        root.log("COUNTS big slots=" + root.slotItems().length + " images=" + root.images(root.col).length + " visible=" + visible + " sizeReads=" + p.sizeReads)
        root.inset = 120
    }
    function bigNarrow() {
        var p = root.pdf()
        var visible = root.inView().length
        root.check("the frame is narrower", p.width < root.bigWidth, true)
        root.check("a narrower 500-page stack builds slots only near the frame", root.slotItems().length <= visible + 2, true)
        root.check("and images only near the frame", root.images(root.col).length <= visible + 2, true)
        root.check("and still has read its page sizes once", p.sizeReads, 500)
        root.log("COUNTS big narrow slots=" + root.slotItems().length + " images=" + root.images(root.col).length + " visible=" + visible + " sizeReads=" + p.sizeReads)
    }

    function slip() {
        var f = root.flick()
        var b = root.bar()
        root.check("a one-page document that fits the frame draws no knob", f.contentHeight <= f.height && !b.overflow && !b.visible, true)
    }

    function quickLook() {
        look.visible = true
        look.active = true
    }
    function quickLookChecks() {
        var inner = root.find(look, function (it) { return it.continuous === false && it.pageSlot !== undefined })
        root.check("Quick Look keeps the single page", inner !== null && root.images(look).length, 1)
        root.check("and its pager and zoom strip", look.buttonFor("chevron-right") !== null && look.buttonFor("plus") !== null, true)
        root.check("and no stack of pages", inner.stackHeight, 0)
    }

    function back() {
        root.check("a row opens at page 1's top", root.col.pdfPage() + "|" + root.flick().contentY, "0|0")
        root.check("and a failed page of the last document is not carried over", root.col.pdfFailed, false)
    }

    readonly property var plan: [
        { row: 0, run: function () { root.report() } },
        { row: 0, scroll: true, run: function () { root.scrolled() } },
        { row: 1, run: function () { root.receipt() } },
        { row: 2, run: function () { root.slip() } },
        { row: 3, run: function () { root.big() } },
        { row: 3, stay: true, narrowed: true, run: function () { root.bigNarrow() } },
        { row: 3, stay: true, run: function () { root.breakSlot(1) } },
        { row: 3, stay: true, wait: function () { return root.slotErrored(1) }, run: function () { root.laterPage() } },
        { row: 3, stay: true, run: function () { root.breakSlot(0) } },
        { row: 3, stay: true, wait: function () { return root.slotErrored(0) }, run: function () { root.topPage() } },
        { row: 3, stay: true, run: function () {
            root.check("the frame's top is on the page before the later failure", root.pdf().pageAt(root.pdf().viewTop), 0)
            root.pdf().shownPage = -1
            root.check("the column is put back before its first draw", root.col.pdfDrawn, false)
            root.breakSlot(1)
        } },
        { row: 3, stay: true, wait: function () { return root.slotErrored(1) }, run: function () { root.laterUndrawnPage() } },
        { row: 3, stay: true, run: function () {
            // Recreate the state before the first draw so the repeated render error tests initial failure.
            root.pdf().shownPage = -1
            root.breakSlot(0)
        } },
        { row: 3, stay: true, wait: function () { return root.slotErrored(0) }, run: function () { root.failedPage() } },
        { row: 0, run: function () { root.back() } },
        { row: 0, look: true, run: function () { root.quickLookChecks() } }
    ]

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

    Timer {
        id: stepper
        interval: 16
        repeat: true
        onTriggered: {
            if (Date.now() - root.since > 25000) { root.check("deadline in stage " + root.stage + " step " + root.stepAt, false, true); root.stop(); return }
            var step = root.stepAt >= 0 ? root.plan[root.stepAt] : null
            if (root.stage === "boot") { if (root.col.frameItem) root.advance() }
            else if (root.stage === "wait" && step.wait) {
                if (step.wait()) { step.run(); root.advance() }
            } else if (root.stage === "wait") {
                if (step.look) {
                    if (!look.visible) root.quickLook()
                    if (look.pageCount <= 0 || look.shownPage < 0) return
                } else if (!root.settled(root.rowsList[step.row].n) || !root.pdf() || (step.narrowed && root.pdf().width >= root.bigWidth)) return
                if (step.scroll) { root.stage = "scroll"; root.sinceWheel = 0; return }
                step.run()
                root.advance()
            } else if (root.stage === "scroll") {
                root.sinceWheel += 1
                if (root.col.pdfPage() < 5 && root.wheels < 80) {
                    if (root.sinceWheel % 4 === 0) { root.wheelOnce(); root.lastWheel = root.sinceWheel }
                    return
                }
                // The wheel's tail and the renders it asked for settle before the counts are read, inside the knob's hold.
                if (root.sinceWheel < root.lastWheel + 30) return
                step.run()
                root.advance()
            }
        }
    }

    function advance() {
        root.since = Date.now()
        root.stepAt += 1
        if (root.stepAt >= root.plan.length) { root.stop(); return }
        root.stage = "wait"
        if (!root.plan[root.stepAt].look && !root.plan[root.stepAt].stay) root.move(root.plan[root.stepAt].row)
    }

    Component.onCompleted: { root.since = Date.now(); stepper.start() }
}
