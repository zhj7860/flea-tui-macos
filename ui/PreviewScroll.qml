import QtQuick
import "." as Flea
import "js/Scroll.js" as Scroll

// The column's scroll route and bounded session memory; no position is written to settings.
Item {
    id: root
    objectName: "previewScroll"
    required property var column
    parent: root.column.frameItem
    anchors.fill: parent

    readonly property var code: root.html && root.html.sourceView ? root.html.sourceCode : root.column.linesItem.code
    readonly property var markdown: root.column.isMarkdownRow ? root.column.markdown : null
    readonly property var html: root.column.isHtmlRow ? root.column.markdown : null
    readonly property var viewport: root.column.linesItem.visible ? root.column.linesItem.viewport
        : root.markdown ? root.markdown.viewport : root.html ? root.html.viewport : null
    readonly property string subject: root.column.row && root.column.path.length > 0
        ? JSON.stringify([root.column.path, root.column.row.s, root.column.row.m]) : ""
    readonly property bool contentReady: root.html ? root.html.contentReady : root.markdown ? root.markdown.contentReady : !!root.code && root.code.settled
    readonly property bool loading: root.scrollPending || (root.column.isDocumentRow ? !root.column.markdown || root.column.markdown.loading || (root.contentReady && root.pendingRestore)
        : root.column.linesItem.loading || (!!root.code && root.code.settled && (!root.code.firstScreen || root.pendingRestore))
        )
    property var places: ({})
    property var order: []
    readonly property int capacity: 256
    property string identity: ""
    property string filePath: ""
    property var wanted: ({ y: 0 })
    property bool pendingRestore: false
    property bool applying: false
    property string scrollKey: ""
    readonly property bool scrollPending: root.scrollKey.length > 0 && !!root.column.swap
        && root.column.swap.capturing && root.column.swap.key === root.scrollKey
    property real drawnY: 0

    function store(path, fingerprint, place) {
        var at = root.order.indexOf(path)
        if (at >= 0) root.order.splice(at, 1)
        root.order.push(path)
        root.places[path] = { fingerprint: fingerprint, place: place }
        while (root.order.length > root.capacity)
            delete root.places[root.order.shift()]
    }

    function remember() {
        var v = root.viewport
        if (!v || root.applying || root.pendingRestore || !root.contentReady
                || !root.identity || !root.column.row || root.column.path !== root.filePath
                || root.identity !== JSON.stringify([root.column.path, root.column.row.s, root.column.row.m]))
            return
        var place = { y: v.contentY - Scroll.limitsY(v).min }
        if (root.markdown) {
            var item = root.markdown.topBlockItem()
            place.index = item ? item.blockIndex : -1
            place.offset = item ? v.contentY - item.y : 0
        }
        root.store(root.filePath, root.identity, place)
    }

    function follow() {
        root.pendingRestore = root.subject.length > 0
        root.scrollKey = ""
        root.identity = root.subject
        root.filePath = root.identity ? root.column.path : ""
        var saved = root.places[root.filePath]
        root.wanted = saved && saved.fingerprint === root.identity ? saved.place : { y: 0 }
        Qt.callLater(root.restore)
    }

    // Layout and the saved place land before the preview hold releases its first live frame.
    function restore() {
        var v = root.viewport
        if (!root.pendingRestore || root.applying || !v || !root.contentReady)
            return
        root.applying = true
        v.forceLayout()
        if (root.markdown && root.wanted.index !== undefined) {
            root.markdown.savedY = Scroll.limitsY(v).min + root.wanted.y
            root.markdown.savedIndex = root.wanted.index
            root.markdown.savedOffset = root.wanted.offset
            root.markdown.keepScroll = true
            root.markdown.restoreScroll()
        } else {
            var bounds = Scroll.limitsY(v)
            v.currentIndex = -1
            v.contentY = Math.max(bounds.min, Math.min(bounds.max, bounds.min + root.wanted.y))
        }
        v.forceLayout()
        if (!root.markdown && !(root.html && !root.html.sourceView) && (!root.code || !root.code.firstScreen)) {
            root.applying = false
            return
        }
        root.pendingRestore = false
        root.applying = false
        root.drawnY = v.contentY
        root.remember()
    }

    // A cold code window moves under the existing preview hold, so no frame draws missing lines.
    function moved() {
        var v = root.viewport
        if (!v || root.applying || root.pendingRestore || !root.contentReady)
            return
        root.applying = true
        v.forceLayout()
        root.applying = false
        if (!root.markdown && !(root.html && !root.html.sourceView) && root.code && !root.code.firstScreen && root.column.swap
                && !root.column.swap.holding && !root.column.swap.capturing) {
            var target = v.contentY
            var identity = root.identity
            var key = "scroll:" + identity
            root.scrollKey = key
            root.applying = true
            v.contentY = root.drawnY
            root.applying = false
            root.column.swap.hold(function () {
                if (root.scrollKey !== key) return
                if (root.identity === identity) {
                    root.applying = true
                    v.contentY = target
                    v.forceLayout()
                    root.applying = false
                    root.remember()
                    root.column.swap.start(false)
                }
                root.scrollKey = ""
            }, key, true)
            return
        }
        if (root.markdown || (root.html && !root.html.sourceView) || (root.code && root.code.firstScreen))
            root.drawnY = v.contentY
        root.remember()
    }

    function pageBy(direction) {
        var v = root.viewport
        if (!v || !root.column.visible || root.column.overlayOpen || root.column.manualHold
                || root.column.pending || root.column.selectionCount > 1 || root.pendingRestore || root.scrollPending)
            return
        var bounds = Scroll.limitsY(v)
        v.cancelFlick()
        Scroll.stopTail(v)
        v.contentY = Math.max(bounds.min, Math.min(bounds.max, v.contentY + direction * v.height))
        v.forceLayout()
        root.remember()
    }

    function scrollPage(direction, viewport) {
        viewport.contentY = Math.max(0, Math.min(viewport.contentHeight - viewport.height,
            viewport.contentY + direction * Flea.Theme.rowHeight))
    }

    onSubjectChanged: root.follow()
    onContentReadyChanged: Qt.callLater(root.restore)
    onViewportChanged: {
        if (root.viewport) bars.targetView = root.viewport
        Qt.callLater(root.restore)
    }
    Connections {
        target: root.code
        function onFirstScreenChanged() {
            if (root.pendingRestore) Qt.callLater(root.restore)
            if (root.code.firstScreen && root.viewport && !root.pendingRestore)
                root.drawnY = root.viewport.contentY
            else
                root.moved()
        }
    }
    Connections {
        target: root.viewport
        // ListView has count; the rendered page's Flickable supplies only geometry and scrolling signals.
        ignoreUnknownSignals: true
        function onCountChanged() { Qt.callLater(root.restore) }
        function onContentHeightChanged() { Qt.callLater(root.restore) }
        function onOriginYChanged() { Qt.callLater(root.restore) }
        function onContentYChanged() { root.moved() }
    }
    Flea.FastScrollHandler {
        id: wheel
        flickable: root.html ? root.viewport : root.column.linesItem.viewport
        visible: (root.html !== null || root.column.linesItem.visible) && flickable !== null
        onWheel: function (event) {
            if (root.scrollPending) event.accepted = true
        }
    }
    Loader {
        id: bars
        anchors.fill: parent
        property var targetView: null
        active: root.viewport !== null && targetView !== null
        sourceComponent: Flea.ViewportScrollBars { flickable: bars.targetView }
    }
}
