//@ pragma ShellId flea-preview-scroll-test
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "flea" as Flea
import "flea/js/Scroll.js" as Scroll

ShellRoot {
    id: root
    readonly property string fixture: Quickshell.env("PREVIEW_SCROLL_DIR")
    readonly property string shots: Quickshell.env("PREVIEW_SCROLL_OUT")
    property var pane: null
    property var keys: null
    property int checks: 0
    property int failures: 0
    property int at: 0
    property var waiting: null
    property double started: Date.now()
    property bool finished: false
    property bool ticking: false
    property real beforeY: 0
    property real expectedY: 0
    property var beforeFocus: null
    property int beforeCursor: 0
    property int beforeObjects: 0
    property var beforeDelegates: []
    property int requestedLines: 0
    property int beforeRequested: 0
    property int beforeCreated: 0
    property int beforeDestroyed: 0
    readonly property int rewrittenLines: 200
    property real savedCode: 0
    property real savedMarkdown: 0
    property real savedCsv: 0
    property string restoring: ""
    property real restoreY: 0
    property int restoreFrames: 0
    property int badFrames: 0
    property bool watchScroll: false
    property bool captured: false
    property bool htmlActive: false
    property bool htmlSampling: false
    property int htmlFrames: 0
    property var htmlFirstFrame: null
    readonly property int htmlSavedY: 217
    readonly property int htmlMovedY: 341
    readonly property var ops: ["open", "listing-ready", "seams", "html-restore", "html-move", "html-source", "html-source-ready", "html-finish", "supersede-scroll", "supersede-page", "supersede-return", "cancel-scroll", "cancel-return", "cancel-page", "cancel-reset", "capture-code-rest", "code-click", "code-wheel", "forward", "capture-code-paged", "back", "code-save", "code-next", "code-return",
        "code-memory", "code-end", "forward-end", "code-top", "back-top", "short", "short-check", "markdown",
        "capture-markdown-rest", "markdown-click", "markdown-wheel", "forward", "capture-markdown-paged", "back", "markdown-save", "markdown-next", "markdown-return", "markdown-memory",
        "markdown-end", "forward-end", "markdown-top", "back-top", "csv", "csv-seams", "capture-csv-rest", "csv-wheel", "forward", "capture-csv-paged", "back", "csv-save",
        "csv-code", "csv-markdown", "csv-return", "csv-memory", "capture-csv-restored", "tsv", "tsv-check", "image", "image-check", "code-again", "rewrite", "rewrite-check",
        "empty", "empty-check", "large", "large-check", "capacity", "list", "list-check", "done"]

    function check(label, actual, expected) {
        root.checks++
        var ok = JSON.stringify(actual) === JSON.stringify(expected)
        if (!ok) root.failures++
        console.log("PVSCROLL " + (ok ? "PASS " : "FAIL ") + label + " got=" + JSON.stringify(actual) + " expected=" + JSON.stringify(expected))
    }
    function near(label, actual, expected) { root.check(label + " actual=" + actual + " expected=" + expected, Math.abs(actual - expected) <= 1, true) }
    function descendants(item) {
        var out = item ? [item] : []
        for (var i = 0; i < out.length; i++) {
            var kids = out[i].children || []
            for (var k = 0; k < kids.length; k++) out.push(kids[k])
        }
        return out
    }
    function col() { return root.pane ? root.pane.previewColumnItem : null }
    function view() { return root.memory() ? root.memory().viewport : null }
    function memory() { return root.descendants(root.col()).filter(function (n) { return n.objectName === "previewScroll" })[0] }
    function code() { return root.col() ? root.col().linesItem.code : null }
    function name() { return root.col() ? root.col().path.split("/").pop() : "" }
    function listingObjects() { return root.descendants(root.pane.listArea.activeColumn().viewport).length }
    function listingDelegates() {
        return root.descendants(root.pane.listArea.activeColumn().viewport).filter(function (item) { return item.markRow !== undefined && item.index !== undefined })
    }
    function bar() {
        return root.descendants(root.col()).filter(function (n) { return n.flickable === root.view() && n.vertical === true && n.knobItem !== undefined })[0]
    }
    function ready(file) {
        var c = root.col()
        return c && root.name() === file && c.swap.ready && !c.swap.holding && !c.swap.capturing && !c.textLoading
    }
    function key(text) { root.keys.keyClickChar(text, text === text.toUpperCase() ? Qt.ShiftModifier : Qt.NoModifier, -1) }
    function waitFile(file) { root.waiting = function () { return root.ready(file) } }
    function moveTo(index, file) { root.pane.setCursor(index); root.waitFile(file) }
    function snapshot() {
        root.pane.listArea.activeColumn().viewport.forceLayout()
        root.beforeY = root.view().contentY
        root.beforeFocus = win.contentItem.Window.window.activeFocusItem
        root.beforeCursor = root.pane.cursorIndex
        root.beforeObjects = root.listingObjects()
        root.beforeDelegates = root.listingDelegates()
        root.beforeRequested = root.requestedLines
        root.beforeCreated = root.pane.listArea.activeColumn().prebuild.createdCount
        root.beforeDestroyed = root.pane.listArea.activeColumn().prebuild.destroyedCount
        root.watchScroll = true
    }
    function stable() {
        root.check("listing keeps keyboard focus", win.contentItem.Window.window.activeFocusItem === root.beforeFocus, true)
        root.check("listing cursor is unchanged", root.pane.cursorIndex, root.beforeCursor)
        root.check("scroll builds no listing objects", root.listingObjects(), root.beforeObjects)
        var delegates = root.listingDelegates()
        root.check("listing keeps every delegate object", root.beforeDelegates.length > 0 && delegates.length === root.beforeDelegates.length
            && root.beforeDelegates.every(function (item) { return delegates.indexOf(item) >= 0 }), true)
        root.check("listing constructs and destroys no delegates", [root.pane.listArea.activeColumn().prebuild.createdCount,
            root.pane.listArea.activeColumn().prebuild.destroyedCount], [root.beforeCreated, root.beforeDestroyed])
        if (!root.col().isMarkdownRow) {
            var requested = root.requestedLines - root.beforeRequested
            root.check("code asks no more than a newly visible screen", requested <= Math.ceil(root.view().height / root.code().rowHeight) + 1, true)
        }
        root.watchScroll = false
    }
    function page(letter) {
        root.snapshot()
        var bounds = Scroll.limitsY(root.view())
        root.expectedY = Math.max(bounds.min, Math.min(bounds.max, root.beforeY + (letter === "F" ? 1 : -1) * root.view().height))
        root.key(letter)
        root.waiting = function () {
            if (root.col().textLoading) return false
            root.near(letter + " moves one viewport height with clamps", root.view().contentY, root.expectedY)
            root.stable()
            return true
        }
    }
    function textState(label) {
        var state = JSON.parse(previewReader.previewTextState(true))
        root.check(label + " IPC reports ready text and its body", [state.path, state.ready, state.y, state.height, state.total],
            [root.col().path, true, root.view().contentY, root.view().height, root.code().total])
        root.check(label + " IPC reports absent wrap as null", state.wrap, null)
    }
    function csvPosition() {
        var v = root.view()
        var index = v.indexAt(0, v.contentY + 1)
        var item = v.itemAtIndex(index)
        return { y: v.contentY, origin: v.originY, index: index, offset: item ? item.y - v.contentY : null }
    }
    function sample() {
        if (root.htmlSampling) {
            var viewport = htmlDocument.viewport
            if (root.htmlFrames === 0)
                root.htmlFirstFrame = [coldFrame.visible, coldScroll.pendingRestore, coldScroll.loading,
                    viewport.contentY, coldScroll.drawnY]
            root.htmlFrames++
            if (coldFrame.visible && viewport.contentY !== root.expectedY)
                root.check("HTML live frame keeps its restored offset", viewport.contentY, root.expectedY)
        }
        var c = root.col(), v = root.view()
        if (!c || c.swap.holding || c.swap.capturing) return
        if (root.restoring && root.name() === root.restoring) {
            root.restoreFrames++
            var restoredCode = root.code()
            if (!v || Math.abs(v.contentY - root.restoreY) > 1
                    || (!c.isMarkdownRow && (!restoredCode || !restoredCode.firstScreen))) root.badFrames++
        }
        if (!v) return
        if (root.watchScroll && !c.isMarkdownRow && root.code() && !root.code().firstScreen) {
            root.badFrames++
            console.log("PVSCROLL MISSING " + root.ops[root.at] + " y=" + v.contentY + " needed=" + JSON.stringify(root.code().needed()))
        }
    }
    function run(op) {
        if (op === "open") {
            Flea.ViewState.changeKey("view", "columns")
            root.pane = paneComponent.createObject(win.contentItem)
            root.keys = Qt.createQmlObject("import QtTest; TestEvent {}", root.pane.listArea)
            root.pane.open(root.fixture)
            root.waitFile("00-long.rs")
        } else if (op === "listing-ready") {
            root.waiting = function () {
                var prebuild = root.pane.listArea.activeColumn().prebuild
                return prebuild.want === 0 && !prebuild.timer.running
            }
        } else if (op === "seams") {
            root.check("column exposes viewport and pageBy", !!root.view() && typeof root.col().pageBy === "function", true)
            if (!root.view() || typeof root.col().pageBy !== "function") { root.finish(); return }
            root.check("code model contains all 132 lines", root.view().count, 132)
            var b = root.bar()
            root.check("long code has one shared vertical bar", root.descendants(root.col()).filter(function (n) { return n.flickable === root.view() && n.vertical === true }).length, 1)
            root.check("long code overflows", !!b && b.overflow, true)
            root.near("knob shows visible share", b.handleLength, b.trackLength * root.view().height / root.view().contentHeight)
            root.check("knob stays hidden at rest", b.shown, false)
            root.check("first Markdown without its Loader stays loading", coldScroll.loading, true)
        } else if (op === "html-restore") {
            firstMarkdown.isMarkdownRow = false
            firstMarkdown.isHtmlRow = true
            firstMarkdown.markdown = htmlDocument
            firstMarkdown.path = root.fixture + "/saved.html"
            firstMarkdown.row = { n: "saved.html", d: false, s: 100, m: 7 }
            firstMarkdown.swap = htmlSwap
            coldScroll.store(firstMarkdown.path, coldScroll.subject, { y: root.htmlSavedY })
            coldScroll.follow()
            root.htmlActive = true
            root.expectedY = root.htmlSavedY
            root.htmlFrames = 0
            root.htmlSampling = true
            htmlDocument.renderedReady = true
            root.waiting = function () {
                if (root.htmlFrames < 1) return false
                root.check("rendered HTML restores without a code item", [coldScroll.html === htmlDocument, coldScroll.code], [true, null])
                root.check("rendered HTML first live frame holds the saved offset", root.htmlFirstFrame,
                    [true, false, false, root.htmlSavedY, root.htmlSavedY])
                root.htmlSampling = false
                return true
            }
        } else if (op === "html-move") {
            firstMarkdown.linesItem.code = inactiveCode
            renderedPage.contentY = root.htmlMovedY
            root.check("rendered HTML scroll ignores the inactive cold code reader", [htmlSwap.holds, coldScroll.scrollPending], [0, false])
            root.check("rendered HTML remembers its new drawn offset", [coldScroll.drawnY, coldScroll.places[firstMarkdown.path].place.y],
                [root.htmlMovedY, root.htmlMovedY])
        } else if (op === "html-source") {
            htmlDocument.sourceView = true
            coldScroll.follow()
            root.waiting = function () {
                root.check("HTML Source uses its own code reader and viewport", [coldScroll.code === htmlSourceCode, coldScroll.viewport === sourceViewport], [true, true])
                root.check("HTML Source waits for its cold code window", [coldScroll.pendingRestore, coldScroll.loading, sourceViewport.contentY],
                    [true, true, root.htmlMovedY])
                return true
            }
        } else if (op === "html-source-ready") {
            root.expectedY = root.htmlMovedY
            root.htmlFrames = 0
            root.htmlSampling = true
            htmlSourceCode.firstScreen = true
            root.waiting = function () {
                if (root.htmlFrames < 1) return false
                root.check("HTML Source first live frame waits for code and holds the offset", root.htmlFirstFrame,
                    [true, false, false, root.htmlMovedY, root.htmlMovedY])
                root.htmlSampling = false
                return true
            }
        } else if (op === "html-finish") {
            root.htmlActive = false
        } else if (op === "supersede-scroll" || op === "cancel-scroll") {
            root.col().pageBy(1)
            root.check("cold page starts a pending capture", [root.memory().scrollPending, root.col().swap.capturing], [true, true])
            if (op === "cancel-scroll") {
                root.col().swap.cancel()
                root.check("cancel clears pending scroll without its callback", root.memory().scrollPending, false)
            }
            root.key("j")
            root.waitFile("01-other.rs")
        } else if (op === "supersede-page" || op === "cancel-page") root.page("F")
        else if (op === "supersede-return" || op === "cancel-return") {
            root.key("k")
            root.waitFile("00-long.rs")
        } else if (op === "cancel-reset") {
            root.waiting = function () {
                if (root.col().textLoading) return false
                if (root.view().contentY <= Scroll.limitsY(root.view()).min) return true
                root.col().pageBy(-1)
                return false
            }
        } else if (op.startsWith("capture-")) {
            root.captured = false
            root.pane.grabToImage(function (result) {
                root.check("capture saves " + op, result.saveToFile(root.shots + "/" + op + ".png"), true)
                root.captured = true
            })
            root.waiting = function () { return root.captured }
        } else if (op.endsWith("-click")) {
            root.snapshot()
            var clickPoint = root.col().frameItem.mapToItem(root.pane, root.col().frameItem.width / 2, root.col().frameItem.height / 2)
            driver.mouseClick(root.pane, clickPoint.x, clickPoint.y, Qt.LeftButton, Qt.NoModifier, 1)
            root.stable()
        } else if (op.endsWith("-wheel")) {
            root.snapshot()
            var point = root.col().frameItem.mapToItem(root.pane, root.col().frameItem.width / 2, root.col().frameItem.height / 2)
            driver.mouseWheel(root.pane, point.x, point.y, Qt.NoButton, Qt.NoModifier, 0, -120, 1)
            root.waiting = function () {
                if (root.view().contentY <= root.beforeY || root.col().textLoading) return false
                root.check("wheel scrolls the preview", root.view().contentY > root.beforeY, true)
                root.check("shared knob appears during use", root.bar().shown, true)
                root.stable()
                return true
            }
        } else if (op === "forward" || op === "forward-end") root.page("F")
        else if (op === "back" || op === "back-top") root.page("B")
        else if (op.endsWith("-end") || op.endsWith("-top")) {
            var end = op.endsWith("-end")
            root.waiting = function () {
                var bounds = Scroll.limitsY(root.view()), target = end ? bounds.max : bounds.min
                if (Math.abs(root.view().contentY - target) <= 1 && !root.col().textLoading) return true
                if (!root.col().textLoading) root.key(end ? "F" : "B")
                return false
            }
        } else if (op === "code-save" || op === "markdown-save" || op === "csv-save") {
            root.page("F")
            var saveReady = root.waiting
            root.waiting = function () {
                if (!saveReady()) return false
                root.check("saved place is below the top", root.view().contentY > Scroll.limitsY(root.view()).min, true)
                if (op === "code-save") root.savedCode = root.view().contentY
                else if (op === "markdown-save") root.savedMarkdown = root.view().contentY
                else root.savedCsv = root.view().contentY
                if (op === "csv-save") console.log("PVSCROLL CSV SAVED " + JSON.stringify(root.csvPosition()))
                return true
            }
        } else if (op === "code-next" || op === "markdown-next") {
            root.key("j")
            root.waitFile(op === "code-next" ? "01-other.rs" : "04-other.md")
        } else if (op === "code-return" || op === "markdown-return" || op === "csv-return") {
            root.restoring = op === "code-return" ? "00-long.rs" : op === "markdown-return" ? "03-long.md" : "08-long.csv"
            root.restoreY = op === "code-return" ? root.savedCode : op === "markdown-return" ? root.savedMarkdown : root.savedCsv
            root.restoreFrames = 0
            if (op === "csv-return") root.moveTo(8, root.restoring)
            else { root.key("k"); root.waitFile(root.restoring) }
        } else if (op === "code-memory" || op === "markdown-memory" || op === "csv-memory") {
            if (op === "csv-memory") console.log("PVSCROLL CSV RETURN " + JSON.stringify(root.csvPosition()))
            root.near("file returns to its saved position", root.view().contentY, root.restoreY)
            root.check("return sampled its first live frame", root.restoreFrames > 0, true)
            root.check("no live frame at top or with missing code", root.badFrames, 0)
            root.restoring = ""
            if (op === "csv-memory") root.textState("CSV restored")
        } else if (op === "csv") {
            root.pane.setCursor(8)
            root.waiting = function () { return root.ready("08-long.csv") && root.code() && root.code().settled }
        } else if (op === "csv-seams") {
            root.check("CSV exposes its body as viewport", !!root.view() && root.view() === root.code().list, true)
            if (!root.view()) { root.finish(); return }
            root.check("CSV keeps all 132 body rows", root.view().count, 132)
            root.textState("CSV")
        } else if (op === "csv-code") root.moveTo(0, "00-long.rs")
        else if (op === "csv-markdown") root.moveTo(3, "03-long.md")
        else if (op === "tsv") root.moveTo(9, "09-long.tsv")
        else if (op === "tsv-check") {
            root.check("TSV exposes all body rows", root.view().count, 132)
            root.textState("TSV")
        } else if (op === "short") root.moveTo(2, "02-short.txt")
        else if (op === "short-check") {
            root.check("short file has ten lines", root.view().count, 10)
            root.check("short file draws no knob", root.bar().overflow, false)
            root.page("F")
        } else if (op === "markdown") root.moveTo(3, "03-long.md")
        else if (op === "image") root.moveTo(5, "05-image.png")
        else if (op === "image-check") {
            root.check("image exposes no scrolling viewport", root.view(), null)
            var cursor = root.pane.cursorIndex
            root.key("F"); root.key("B")
            root.check("paging image leaves cursor alone", root.pane.cursorIndex, cursor)
        } else if (op === "code-again") root.moveTo(0, "00-long.rs")
        else if (op === "rewrite") {
            root.page("F")
            var pageReady = root.waiting
            root.waiting = function () {
                if (!pageReady()) return false
                root.savedCode = root.view().contentY
                root.check("rewrite starts with a saved nonzero position", root.savedCode > Scroll.limitsY(root.view()).min, true)
                rewrite.setText("fn rewritten() {}\n".repeat(root.rewrittenLines))
                return true
            }
        } else if (op === "rewrite-check") {
            root.waiting = function () {
                if (!root.ready("00-long.rs") || root.code().total !== root.rewrittenLines) return false
                root.check("rewritten file still overflows without clamping the saved position", Scroll.limitsY(root.view()).max >= root.savedCode && root.savedCode > Scroll.limitsY(root.view()).min, true)
                root.near("changed file starts at top", root.view().contentY, Scroll.limitsY(root.view()).min)
                return true
            }
        } else if (op === "capacity") {
            var m = root.memory()
            for (var i = 0; i < 257; i++) m.store("/fixture/" + i, "same", { y: i })
            root.check("session memory is bounded to 256 paths", m.order.length, 256)
            root.check("oldest path is evicted", m.places["/fixture/0"] === undefined, true)
            root.check("latest path is retained", m.places["/fixture/256"].place.y, 256)
        } else if (op === "empty") root.moveTo(6, "06-empty.txt")
        else if (op === "empty-check") {
            root.check("empty text settles without a restore wait", [root.view().count, root.col().textLoading], [0, false])
        } else if (op === "large") root.moveTo(7, "07-large.md")
        else if (op === "large-check") {
            root.check("oversize Markdown settles without reading", [root.col().markdown.tooLarge, root.col().textLoading], [true, false])
        } else if (op === "list") {
            root.keys.keyClick(Qt.Key_1, Qt.ControlModifier, -1)
            root.waiting = function () { return root.pane.viewMode === "list" }
        } else if (op === "list-check") {
            var before = root.pane.cursorIndex
            root.key("F"); root.key("B")
            root.check("paging List view leaves cursor alone", root.pane.cursorIndex, before)
        } else if (op === "done") root.finish()
    }
    function finish() {
        if (root.finished) return
        root.finished = true
        console.log("PVSCROLL DONE " + root.checks + " checks, " + root.failures + " failed")
        quitter.start()
    }
    function tick() {
        if (Date.now() - root.started > 20000) {
            var c = root.col(), m = root.memory()
            console.log("PVSCROLL STATE " + JSON.stringify({ file: root.name(), loading: c.textLoading,
                pending: m.pendingRestore, ready: m.contentReady, wanted: m.wanted, places: m.places,
                y: root.view() ? root.view().contentY : null,
                markdown: c.markdown ? { loading: c.markdown.loading, ready: c.markdown.contentReady, count: c.markdown.viewport.count } : null }))
            root.check(root.ops[root.at] + " finishes", "timeout", "done"); root.finish(); return
        }
        if (root.waiting !== null) {
            if (!root.waiting()) return
            root.waiting = null
            root.at++
            root.started = Date.now()
            return
        }
        if (root.at >= root.ops.length) { root.finish(); return }
        root.run(root.ops[root.at])
        if (root.waiting === null) { root.at++; root.started = Date.now() }
    }
    FloatingWindow {
        id: win
        implicitWidth: 1200
        implicitHeight: 760
        color: Flea.Theme.color.background
        TestEvent { id: driver }
        Item { id: frameProbe }
    }
    Rectangle {
        id: coldFrame
        parent: win.contentItem
        width: 240
        height: 100
        z: 100
        color: Flea.Theme.color.background
        visible: root.htmlActive && !coldScroll.loading
    }
    Flickable {
        id: renderedPage
        parent: coldFrame
        anchors.fill: parent
        visible: !htmlDocument.sourceView
        contentWidth: width
        contentHeight: 1200
        clip: true
        property int currentIndex: -1
        function forceLayout() {}
        Text { width: parent.width; height: 1200; text: "Rendered HTML\n".repeat(60); color: Flea.Theme.color.foreground }
    }
    ListView {
        id: sourceViewport
        parent: coldFrame
        anchors.fill: parent
        visible: htmlDocument.sourceView
        model: 100
        clip: true
        delegate: Text { required property int index; width: ListView.view.width; height: 20; text: "Source " + index; color: Flea.Theme.color.foreground }
    }
    QtObject {
        id: htmlSourceCode
        property bool settled: true
        property bool firstScreen: false
        readonly property var viewport: sourceViewport
    }
    QtObject {
        id: inactiveCode
        property bool settled: false
        property bool firstScreen: false
    }
    QtObject {
        id: htmlDocument
        property bool sourceView: false
        property bool renderedReady: false
        readonly property var sourceCode: htmlDocument.sourceView ? htmlSourceCode : null
        readonly property var viewport: htmlDocument.sourceView ? sourceViewport : renderedPage
        readonly property bool contentReady: htmlDocument.sourceView ? htmlSourceCode.settled : htmlDocument.renderedReady
        readonly property bool loading: htmlDocument.sourceView ? !htmlSourceCode.firstScreen : !htmlDocument.renderedReady
    }
    QtObject {
        id: htmlSwap
        property int holds: 0
        property bool capturing: false
        property bool holding: false
        property string key: ""
        function hold(callback, key, wheel) { htmlSwap.holds++; htmlSwap.key = key; htmlSwap.capturing = true }
        function start(ready) {}
    }
    QtObject {
        id: firstMarkdown
        property Item frameItem: coldFrame
        property bool isMarkdownRow: true
        property bool isHtmlRow: false
        readonly property bool isDocumentRow: firstMarkdown.isMarkdownRow || firstMarkdown.isHtmlRow
        property var markdown: null
        property var swap: null
        property var row: ({ n: "03-long.md", d: false, s: 0, m: 0 })
        property string path: root.fixture + "/03-long.md"
        property QtObject linesItem: QtObject {
            property bool visible: false
            property var code: null
            property var viewport: null
            property bool loading: false
        }
    }
    Flea.PreviewScroll { id: coldScroll; column: firstMarkdown }
    Flea.IpcPreviewState { id: previewReader; pane: root.pane }
    Connections {
        target: frameProbe.Window.window
        function onAfterAnimating() { root.sample() }
    }
    Flea.Backend {
        id: realBackend
        function askCode(slot, source, first, count) {
            realBackend.codeToken += 1
            var request = Object.assign({ c: "code", token: realBackend.codeToken, slot: slot, first: first, count: count }, source)
            root.requestedLines += request.count
            realBackend.send(request)
            return realBackend.codeToken
        }
    }
    FileView { id: rewrite; path: root.fixture + "/00-long.rs"; printErrors: false; blockWrites: true }
    Component { id: paneComponent; Flea.Pane { width: 1200; height: 760; backend: realBackend } }
    Timer { id: quitter; interval: 100; onTriggered: Qt.exit(root.failures > 0 ? 1 : 0) }
    Timer {
        interval: 40
        running: !root.finished
        repeat: true
        onTriggered: {
            if (root.ticking) return
            root.ticking = true
            root.tick()
            root.ticking = false
        }
    }
}
