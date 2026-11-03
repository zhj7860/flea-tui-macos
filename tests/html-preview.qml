import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Icons.js" as Icons

ShellRoot {
    id: root
    property int phase: 0
    readonly property real probeRadius: 12
    property int failures: 0
    property int checks: 0
    property var keys: null
    property double started: Date.now()
    property double calmAt: 0
    property bool finished: false
    property bool ticking: false
    property bool capturePending: false
    property int replies: 0
    property bool heldResize: false
    property bool lostResize: false
    property bool rSent17: false
    property int beforeResize: 0
    property real beforePage: 0
    property int cursorBefore: -1
    property int midBefore: 0
    property int topBefore: 0
    function pane() { return body.item ? body.item.currentPane : null }
    function look() { return root.pane() ? root.pane().preview : null }
    function doc() { return root.look() && root.look().markdownShown ? root.look().markdownShown.document : null }
    function column() { return root.pane() ? root.pane().previewColumnItem : null }
    function check(name, got, want) {
        root.checks++
        var pass = JSON.stringify(got) === JSON.stringify(want)
        if (!pass) root.failures++
        console.warn("HTML_PREVIEW " + (pass ? "PASS " : "FAIL ") + name + " got=" + JSON.stringify(got) + " want=" + JSON.stringify(want))
    }
    function calm(ok) {
        if (!ok) { root.calmAt = 0; return false }
        if (!root.calmAt) root.calmAt = Date.now()
        return Date.now() - root.calmAt > 300
    }
    function next() { root.phase++; root.started = Date.now(); root.calmAt = 0 }
    function key(text) { root.keys.keyClickChar(text, Qt.NoModifier, -1) }
    function press(key) { root.keys.keyClick(key, Qt.NoModifier, -1) }
    function indexOf(name) {
        for (var i = 0; i < root.pane().total; i++)
            if (root.pane().rowFor(i).n === name) return i
        return -1
    }
    function open(name) {
        root.pane().setCursor(root.indexOf(name))
        root.pane().listArea.forceActiveFocus()
        root.press(Qt.Key_Space)
    }
    function shot(item, name, after) {
        var output = Quickshell.env("FLEA_CI_SUITE_LOGS") || Quickshell.env("HTML_ROOT")
        root.capturePending = true
        item.grabToImage(function (image) {
            root.check(name + " image saved", image.saveToFile(output + "/" + name + ".png"), true)
            if (typeof after === "function") after()
            root.capturePending = false
        })
    }
    function cornerShot(frame, name, column, after) {
        frame.radius = root.probeRadius
        var doc = column ? root.column().markdown : root.doc()
        doc.cornerRadius = frame.radius - frame.border.width
        root.capturePending = true
        cornerWait.action = function () {
            console.warn("HTML_CORNER_STATE " + JSON.stringify({ name: name, column: column,
                frame: "0 0 " + frame.width + " " + frame.height, window: { width: frame.width, height: frame.height },
                radius: frame.radius, hairline: frame.border.width, ringColor: String(frame.border.color), pageColor: "#ffffff",
                graphicsApi: doc.GraphicsInfo.api, accelerated: doc.GraphicsInfo.api !== GraphicsInfo.Software && doc.GraphicsInfo.api !== GraphicsInfo.Unknown }))
            root.shot(frame, name, after)
        }
        cornerWait.restart()
    }
    function finish() {
        if (root.finished) return
        root.finished = true
        console.warn("HTML_PREVIEW DONE " + root.checks + " checks, " + root.failures + " failed")
        quit.start()
    }
    function tick() {
        var p = root.pane(), l = root.look(), d = root.doc(), c = root.column()
        if (Date.now() - root.started > 25000) {
            root.check("phase " + root.phase + " completes (look=" + (l ? l.status : "none") + ", column=" + (c ? c.previewState : "none")
                + ", widths=" + (d ? d.renderedWidth + "/" + d.deviceWidth : "none") + ", window=" + window.width + "/" + window.implicitWidth
                + ", replies=" + root.replies + "/" + root.beforeResize + ")", "timeout", "done")
            root.finish()
            return
        }
        switch (root.phase) {
        case 0:
            if (!p || p.listInFlight || !p.storageKnown || p.total < 4) return
            root.check("listing builds no Quick Look or HTML surface", [l, root.replies], [null, 0])
            root.check("neither document kind stores its view", [Flea.ViewState.preview.htmlView, Flea.ViewState.preview.markdownView], [undefined, undefined])
            root.keys = Qt.createQmlObject("import QtTest; TestEvent {}", p.listArea)
            root.open("index.html")
            root.next()
            break
        case 1:
            if (!root.calm(l && l.active && d && d.contentReady && l.openState().landed)) return
            var g = l.markdownShown.barGeometry()
            root.check("HTML draws the page image and the shared bar", [l.isHtml, l.isCodeText, d.shownView, d.imageFile.length > 0, g.markName, g.name.text, g.lines.text, g.segment !== null],
                [true, false, "rendered", true, "html", "index.html", "61 lines", false])
            root.check("rendered frame uses device width", d.renderedWidth, d.deviceWidth)
            root.check("the HTML mark uses the approved shield path", Icons.pathFor("html"), "M4 2h16l-1.5 17L12 22l-6.5-3z M15.5 6.5h-7V11h7v5L12 17.5 8.5 16")
            root.cornerShot(l.panesItem.parent, "html-quicklook", false, function () {
                root.cursorBefore = p.cursorIndex
                root.key("j")
                root.key("+")
                root.next()
            })
            break
        case 2:
            if (!root.calm(d && d.scrollY > 0 && d.zoom > 1)) return
            root.check("j scrolls rendered HTML without moving the cursor", p.cursorIndex, root.cursorBefore)
            root.check("plus zooms on the preview ladder", d.zoom, 1.25)
            root.shot(l.panesItem.parent, "html-scrolled-zoomed", function () {
                root.key("0")
                root.key("k")
                root.beforeResize = root.replies
                viewportHost.width = 1220
                viewportHost.width = 1260
                viewportHost.width = 1240
                root.next()
            })
            break
        case 3:
            if (d && d.pending && d.imageFile.length > 0 && !d.sourceView) {
                root.heldResize = true
                if (d.loading || !d.bodyItem.visible) root.lostResize = true
            }
            if (!root.calm(d && d.contentReady && d.renderedWidth === d.deviceWidth && root.replies > root.beforeResize)) return
            root.check("a resize keeps the drawn page until the new render lands", [root.heldResize, root.lostResize], [true, false])
            root.check("resize burst renders only the settled width", root.replies - root.beforeResize, 1)
            root.check("zero restores fit", d.zoom, 1)
            root.key("r")
            root.next()
            break
        case 4:
            if (!root.calm(d && d.shownView === "source" && d.firstScreen)) return
            root.check("r draws the shipped code renderer with all 61 lines", [d.sourceCode.total, d.sourceCode.numbered, l.markdownShown.barGeometry().lines.text], [61, true, "61 lines"])
            root.shot(l.panesItem, "html-source", function () {
                root.press(Qt.Key_Space)
                p.chooseView("columns")
                root.next()
            })
            break
        case 5:
            if (!root.calm(c && c.visible && c.isHtmlRow && c.markdown && c.markdown.firstScreen && !c.textLoading)) return
            root.check("column renders HTML after Quick Look Source closes", [c.markdown.shownView, c.markdown.imageFile.length > 0, c.tallRow], ["rendered", true, true])
            root.check("column frame fills to the name and facts", c.frameItem.height > c.frameItem.width * 10 / 16, true)
            root.beforePage = c.markdown.viewport.contentY
            p.listArea.forceActiveFocus()
            root.key("F")
            root.next()
            break
        case 6:
            if (!root.calm(c && !c.textLoading && c.markdown.viewport.contentY > root.beforePage)) return
            root.check("F pages rendered HTML with the cursor unchanged", p.cursorIndex, root.cursorBefore)
            root.key("B")
            root.open("notes.md")
            root.next()
            break
        case 7:
            if (!root.calm(l && l.isMarkdown && l.markdownShown && l.markdownShown.firstScreen)) return
            root.check("Markdown remains rendered after HTML chose Source", l.markdownShown.shownView, "rendered")
            root.shot(l.panesItem.parent, "markdown-corners-look", function () { root.phase = 32 })
            break
        case 32:
            if (!root.calm(c && c.isMarkdownRow && c.markdown && c.markdown.contentReady)) return
            c.frameItem.radius = root.probeRadius
            root.shot(c.frameItem, "markdown-corners-column", function () {
                root.key("r")
                root.phase = 8
                root.started = Date.now()
                root.calmAt = 0
            })
            break
        case 8:
            if (!root.calm(l.markdownShown.shownView === "source" && l.markdownShown.firstScreen)) return
            root.press(Qt.Key_Space)
            root.open("index.html")
            root.next()
            break
        case 9:
            if (!root.calm(d && !d.sourceView && d.contentReady)) return
            root.check("HTML opens rendered after Markdown Source closes", d.shownView, "rendered")
            root.key("r")
            root.next()
            break
        case 10:
            if (!root.calm(d && d.sourceView && d.firstScreen)) return
            root.check("HTML r changes only the open Quick Look", d.shownView, "source")
            root.press(Qt.Key_Escape)
            root.open("index.html")
            root.phase = 31
            root.started = Date.now()
            root.calmAt = 0
            break
        case 11:
            if (!root.calm(c && c.markdown && !c.markdown.sourceView && c.markdown.contentReady && !c.textLoading)) return
            root.check("column draws rendered HTML independently", [c.markdown.shownView, c.markdown.total], ["rendered", 61])
            root.shot(c, "html-column")
            root.next()
            break
        case 12:
            if (!root.calm(true)) return
            p.selection.only(root.indexOf("notes.md"))
            p.selection.toggle(root.indexOf("index.html"))
            p.selectionVersion++
            root.next()
            break
        case 13:
            if (!root.calm(c && c.selectionCount === 2)) return
            root.check("HTML never paints over the multi-selection summary", [c.previewState, c.markdown === null], ["multi", true])
            p.clearSelection()
            p.setCursor(root.indexOf("long.html"))
            root.next()
            break
        case 14:
            if (!root.calm(c && c.markdown && c.markdown.total === 800 && c.markdown.contentReady && !c.textLoading)) return
            root.midBefore = c.swap.describe().midFrames
            root.beforePage = c.markdown.viewport.contentY
            root.key("F")
            root.next()
            break
        case 15:
            if (!root.calm(c && !c.textLoading && c.markdown.firstScreen && c.markdown.viewport.contentY > root.beforePage)) return
            root.beforePage = c.markdown.viewport.contentY
            root.key("F")
            root.next()
            break
        case 16:
            if (!root.calm(c && !c.textLoading && c.markdown.firstScreen && c.markdown.viewport.contentY > root.beforePage)) return
            root.check("paging rendered HTML draws no unfinished frame", c.swap.describe().midFrames - root.midBefore, 0)
            root.open("long.html")
            root.next()
            break
        case 17:
            if (!root.rSent17 && d && !d.sourceView && d.contentReady && l.openState().landed) { root.rSent17 = true; root.key("r"); return }
            if (!root.calm(d && d.sourceView && d.firstScreen && l.openState().landed)) return
            root.check("long HTML Source keeps its gutter and whole-file count", [d.sourceCode.total, d.sourceCode.numbered], [800, true])
            d.viewport.positionViewAtIndex(40, ListView.Beginning)
            root.next()
            break
        case 18:
            if (!root.calm(d && d.firstScreen)) return
            root.topBefore = d.viewport.indexAt(0, d.viewport.contentY + 1)
            root.key("w")
            root.next()
            break
        case 19:
            if (!root.calm(d && d.wrap && d.firstScreen)) return
            root.check("HTML Source wrap preserves the first visible line", d.viewport.indexAt(0, d.viewport.contentY + 1), root.topBefore)
            root.key("w")
            root.next()
            break
        case 20:
            if (!root.calm(d && !d.wrap && d.firstScreen)) return
            root.check("HTML Source unwrap preserves the first visible line", d.viewport.indexAt(0, d.viewport.contentY + 1), root.topBefore)
            root.press(Qt.Key_Space)
            root.open("board.html")
            root.next()
            break
        case 21:
            if (!root.calm(d && !d.sourceView && d.contentReady && l.openState().landed)) return
            root.check("the board specimen has the whole-file bar count", l.markdownShown.barGeometry().lines.text, "61 lines")
            root.check("F9 short HTML page covers the viewport bottom edge", d.viewport.contentHeight >= d.viewport.height - 0.5, true)
            root.shot(l.panesItem, "html-board-quicklook", function () {
                root.press(Qt.Key_Space)
                root.next()
            })
            break
        case 22:
            if (!root.calm(c && c.markdown && !c.markdown.sourceView && c.markdown.contentReady && !c.textLoading)) return
            root.check("the board specimen has the exact compact facts", c.factsLine.kind + c.factsLine.tail, "HTML document · 1.6 kB · 61 lines")
            root.cornerShot(c.frameItem, "html-board-column", true)
            root.next()
            break
        case 23:
            if (!root.calm(true)) return
            root.finish()
            break
        case 31:
            if (!root.calm(d && !d.sourceView && d.contentReady)) return
            root.check("closing Source forgets the flip", d.shownView, "rendered")
            root.press(Qt.Key_Space)
            root.phase = 11
            root.started = Date.now()
            root.calmAt = 0
            break
        }
    }
    FloatingWindow {
        id: window
        implicitWidth: 1200
        implicitHeight: 760
        Item {
            id: viewportHost
            width: window.width
            height: window.height
            Loader {
                id: body
                anchors.fill: parent
                source: "file://" + Quickshell.env("HTML_UI") + "/WindowBody.qml"
                onLoaded: item.host = window
            }
        }
    }
    Timer { id: cornerWait; interval: 150; property var action: null; onTriggered: action() }
    Connections {
        target: root.doc() || null
        function onPendingChanged() {
            var d = root.doc()
            if (root.phase !== 3 || !d || !d.pending || !d.imageFile.length || d.sourceView) return
            root.heldResize = true
            if (d.loading || !d.bodyItem.visible) root.lostResize = true
        }
    }
    Connections {
        target: root.pane() ? root.pane().backend : null
        function onHtmlResult(message) { if (message.slot === "look" && message.state === "ready") root.replies++ }
    }
    Timer { id: quit; interval: 100; onTriggered: Qt.exit(root.failures > 0 ? 1 : 0) }
    Timer {
        interval: 20
        running: true
        repeat: true
        onTriggered: {
            if (root.finished || root.ticking || root.capturePending) return
            root.ticking = true
            try { root.tick() } finally { root.ticking = false }
        }
    }
}
