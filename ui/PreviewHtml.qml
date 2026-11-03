import QtQuick
import qs.Commons
import Quickshell.Io
import "." as Flea
import "js/Markdown.js" as Markdown
import "js/Format.js" as Format
import "js/PreviewKeys.js" as PreviewKeys
import "js/Scroll.js" as Scroll

// The helper's still image and the shipped code renderer share the frame and its scroll lane.
Item {
    id: root
    property bool active: false
    property string path: ""
    property int size: 0
    readonly property int byteCeiling: 1048576
    readonly property int settleMs: 160
    property int maxBytes: byteCeiling
    property bool truncate: false
    property real cornerRadius: Math.max(0, Style.cornerRadius - Theme.spacing.hairline)
    property bool compact: false
    property bool externalScrollBars: false
    property var backend: null
    property string slot: "column"
    property string view: "rendered"
    property bool wrap: false
    readonly property string shownView: root.view === "source" ? "source" : "rendered"
    readonly property bool sourceView: root.shownView === "source"
    readonly property bool overSize: root.size > root.maxBytes
    readonly property bool tooLarge: root.overSize || (root.sourceView && !!root.sourceCode && root.sourceCode.answer === "large")
    readonly property bool binary: root.sourceView && !!root.sourceCode && root.sourceCode.answer === "binary"
    readonly property int deviceWidth: Math.max(1, Math.round(root.width * Screen.devicePixelRatio))
    readonly property int deviceHeight: root.slot === "look" ? Math.max(1, Math.ceil(root.height * root.deviceWidth / Math.max(1, root.width))) : 0
    property int token: -1
    property bool pending: false
    property bool readFailed: false
    property bool hasDrawn: false
    property int imageToken: -1
    property int total: 0
    property string imageFile: ""
    property string pageTitle: ""
    property int renderedWidth: 0
    property real zoom: 1
    property bool sourceBuilt: false
    readonly property var sourceCode: sourceLoader.item
    readonly property var viewport: root.sourceView ? (root.sourceCode ? root.sourceCode.viewport : null) : page
    readonly property Item bodyItem: root.sourceView ? root.sourceCode : page
    readonly property bool failed: root.sourceView ? root.readFailed || (!!root.sourceCode && root.sourceCode.answer === "failed")
        : root.readFailed || picture.status === Image.Error
    readonly property bool contentReady: root.sourceView ? !!root.sourceCode && root.sourceCode.settled
        : !root.pending && picture.status === Image.Ready
    readonly property bool firstScreen: root.failed || root.tooLarge || root.binary
        || (root.sourceView ? !!root.sourceCode && root.sourceCode.firstScreen : root.contentReady)
    readonly property bool loading: root.active && !root.firstScreen && (root.sourceView || !root.hasDrawn)
    readonly property bool blank: root.tooLarge || root.binary
    readonly property string status: root.tooLarge ? "This file is too large to preview."
        : root.failed ? "This file could not be read." : root.firstScreen ? "ready" : "loading"
    readonly property string lineLabel: Markdown.countLine(root.sourceView && root.sourceCode ? root.sourceCode.total : root.total)
    readonly property real scrollY: root.viewport ? root.viewport.contentY : 0

    function captureState(window, owner, pane, column) {
        var bar = column ? null : pane.barGeometry()
        var frame = column ? owner.frameItem : owner.panesItem.parent
        var lane = scrollBars.item ? scrollBars.item.children[0] : null
        return JSON.stringify({ path: root.path, view: root.shownView, ready: root.firstScreen,
            visible: column ? owner.visible : owner.revealedOpen, state: root.status,
            lines: root.sourceView && root.sourceCode ? root.sourceCode.total : root.total,
            count: bar ? bar.lines.text : root.lineLabel, mark: bar ? bar.markName : "html", file: root.imageFile,
            width: root.renderedWidth, deviceWidth: root.deviceWidth, y: root.scrollY, zoom: root.zoom,
            facts: column ? owner.factsLine.kind + owner.factsLine.tail : "", frame: window.rectOf(frame),
            column: column, window: { width: window.width, height: window.height }, radius: frame.radius,
            hairline: frame.border.width, ringColor: String(frame.border.color), canvasColor: String(frame.color),
            viewportHeight: root.viewport ? root.viewport.height : 0, contentHeight: root.viewport ? root.viewport.contentHeight : 0,
            lane: lane ? { shown: lane.shown, visible: lane.visible, rect: window.rectOf(lane) } : null,
            close: bar ? { hovered: bar.close.hovered, pressed: bar.close.pressed, focused: bar.close.keyboardFocused,
                ring: bar.close.ringItem.visible, centre: window.centreOf(bar.close) } : null })
    }
    function cancel() {
        settle.stop()
        if (root.pending && root.backend && typeof root.backend.askHtml === "function")
            root.backend.askHtml(root.slot, "", root.deviceWidth, true)
        root.token = -1
        root.pending = false
    }
    function schedule() {
        if (!root.active || root.sourceView || root.tooLarge) { root.cancel(); return }
        settle.restart()
    }
    function ask() {
        if (!root.active || root.sourceView || root.tooLarge || root.width <= 0) return
        if (!root.backend || typeof root.backend.askHtml !== "function") { root.readFailed = true; return }
        root.readFailed = false
        root.pending = true
        root.token = root.backend.askHtml(root.slot, root.path, root.deviceWidth, false, root.deviceHeight)
    }
    function scrollBy(rows) {
        var v = root.viewport
        if (!v) return
        var bounds = Scroll.limitsY(v)
        v.contentY = Math.max(bounds.min, Math.min(bounds.max, v.contentY + rows * Theme.rowHeight))
    }
    function zoomBy(steps) { if (!root.sourceView) root.zoom = PreviewKeys.zoomStep(root.zoom, steps) }
    function zoomFit() { root.zoom = 1 }
    function endGap() { return root.viewport ? Math.max(0, root.viewport.contentHeight - root.viewport.height - root.viewport.contentY) : -1 }
    function keepTop(top) {
        var v = root.sourceView ? root.viewport : null
        if (!v) return
        v.forceLayout()
        v.positionViewAtIndex(top, ListView.Beginning)
    }
    onWrapChanged: if (root.sourceView && root.viewport) Qt.callLater(root.keepTop, Math.max(0, root.viewport.indexAt(0, root.viewport.contentY + 1)))

    onPathChanged: {
        root.cancel()
        root.hasDrawn = false
        root.imageFile = ""
        root.total = 0
        root.readFailed = false
        root.zoom = 1
        page.contentY = 0
        root.schedule()
    }
    onActiveChanged: root.schedule()
    onSourceViewChanged: {
        if (root.sourceView) root.sourceBuilt = true
        root.readFailed = false
        root.schedule()
    }
    onBackendChanged: root.schedule()
    onDeviceWidthChanged: root.schedule()
    onDeviceHeightChanged: root.schedule()
    onTooLargeChanged: root.schedule()
    Component.onCompleted: { root.sourceBuilt = root.sourceView; root.schedule() }
    Component.onDestruction: {
        root.cancel()
        if (root.sourceCode) root.sourceCode.active = false
    }
    // Repeated width changes only restart this settle; no helper runs while the frame is being resized.
    Timer { id: settle; interval: root.settleMs; onTriggered: root.ask() }
    Connections {
        target: root.backend
        function onHtmlResult(message) {
            if (!root.active || root.sourceView || message.slot !== root.slot || message.token !== root.token) return
            root.pending = false
            root.readFailed = message.state !== "ready"
            if (!root.readFailed) {
                root.total = message.total
                root.renderedWidth = message.width
                root.pageTitle = message.title || ""
                root.imageFile = message.file
                root.imageToken = message.token
            }
        }
    }

    Flickable {
        id: page
        anchors.fill: parent
        clip: true
        visible: !root.sourceView && !root.tooLarge && !root.failed
        contentWidth: Math.max(width, picture.width)
        contentHeight: picture.height
        boundsBehavior: Flickable.StopAtBounds
        property int currentIndex: -1
        function forceLayout() {}
        Image {
            id: picture
            width: page.width * root.zoom
            height: implicitWidth > 0 ? implicitHeight * width / implicitWidth : 0
            // The helper bounds the whole scrollable page; decoding only the viewport would discard its lower pixels.
            source: root.imageFile.length > 0 ? Format.fileUri(root.imageFile) + "#t" + root.imageToken : ""
            fillMode: Image.Stretch
            asynchronous: true
            cache: false
            retainWhileLoading: true
            onStatusChanged: if (status === Image.Ready) root.hasDrawn = true
        }
    }
    Loader {
        anchors.fill: page
        active: root.active && page.visible && root.cornerRadius > 0 && GraphicsInfo.api !== GraphicsInfo.Software
        source: "HtmlClip.qml"
        onLoaded: {
            item.target = page
            item.radius = Qt.binding(function () { return root.cornerRadius })
            item.roundTop = root.slot !== "look"
        }
    }
    FileView {
        id: sourceFile
        path: root.active && root.sourceView && root.truncate && !root.tooLarge ? root.path : ""
        printErrors: false
        onLoadFailed: root.readFailed = true
    }
    Loader {
        id: sourceLoader
        anchors.fill: parent
        anchors.margins: root.compact ? Theme.spacing.gap : Theme.spacing.rowPaddingX
        active: root.sourceBuilt
        visible: root.sourceView
        source: "CodeLines.qml"
        onLoaded: {
            item.backend = Qt.binding(function () { return root.backend })
            item.path = Qt.binding(function () { return root.path })
            item.fromText = Qt.binding(function () { return root.truncate })
            item.text = Qt.binding(function () { return root.truncate && sourceFile.loaded ? sourceFile.text() : null })
            item.slot = Qt.binding(function () { return root.slot })
            item.active = Qt.binding(function () { return root.active && root.sourceView && !root.overSize })
            item.numbered = true
            item.scrolls = true
            item.wrap = Qt.binding(function () { return root.wrap })
            item.pixelSize = Qt.binding(function () { return root.compact ? Theme.font.caption : Theme.font.body })
        }
    }
    Flea.FastScrollHandler { flickable: root.viewport; visible: !root.externalScrollBars }
    Loader {
        id: scrollBars
        anchors.fill: parent
        property var targetView: root.viewport
        active: !root.externalScrollBars && root.viewport !== null
        sourceComponent: Flea.ViewportScrollBars { flickable: parent.targetView }
    }
    Flea.LoadingState { anchors.fill: parent; visible: root.loading }
    Flea.CodeRefusal { anchors.fill: parent; visible: !root.compact; binary: root.binary; failed: root.failed; tooLarge: root.tooLarge; markName: "html" }
}
