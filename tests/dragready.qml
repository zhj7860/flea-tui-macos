import QtQuick
import "js/sourcefixture.js" as Source

// Grid lift readiness: every tile builds its lift path in the landing turn, while only views keeping per-row drop areas arm the DropArea (ui/RowDrag.qml), which holds no Loader.
Item {
    id: root
    property int checked: 0
    property int failed: 0
    function check(label, actual, expected) {
        root.checked++
        if (actual !== expected) {
            root.failed++
            console.log("FAIL " + label + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
        }
    }
    // ui/<file> built from its own text beside ui/js, because ui/qmldir's singletons need Quickshell.
    function built(parent, properties) {
        var text = Source.source("ui/RowDrag.qml")
        var body = text.search(/^[A-Z]\w* \{/m)
        var imports = text.substring(0, body).replace(/import "js\//g, "import \"")
        var wrapper = Qt.createQmlObject(imports + "QtObject { property Component made: Component { " + text.substring(body) + " } }",
                                         parent, Qt.resolvedUrl("../ui/js/RowDrag.qml"))
        return wrapper.made.createObject(parent, properties)
    }
    // The row's DropArea, wherever it sits under the item.
    function dropAreaIn(item) {
        var kids = item.children || []
        for (var j = 0; j < kids.length; j++) {
            if (kids[j] && kids[j].keys !== undefined && kids[j].drag !== undefined) return kids[j]
            var deeper = root.dropAreaIn(kids[j])
            if (deeper) return deeper
        }
        return null
    }
    // The lift handler builds with the row: RowDrag declares its DragHandler directly (no Loader in RowDrag, pinned below) and the grid delegate holds RowDrag outside any Loader.
    function liftBuiltIn() {
        var drag = Source.source("ui/RowDrag.qml")
        if (drag.indexOf("DragHandler {") < 0) return false
        var area = Source.source("ui/GridArea.qml")
        var delegateAt = area.indexOf("delegate: Flea.GridTile {")
        var rowDragAt = area.indexOf("Flea.RowDrag {", delegateAt)
        if (delegateAt < 0 || rowDragAt < 0) return false
        var between = area.substring(delegateAt, rowDragAt)
        var loader = between.lastIndexOf("Loader {")
        if (loader >= 0 && between.indexOf("}", loader) < 0) return false
        return true
    }
    Component { id: paneStub; QtObject {
        property bool listInFlight: false
        property bool renamePending: false
        property int renamingIndex: -1
        property string path: "/p"
        function join(b, n) { return b + "/" + n }
        function message(t) {}
    } }
    Component { id: sessionStub; QtObject {
        property var pane: null
        property var dragRows: []
        property real dragListing: 0
        property int dropIndex: -1
        property string dropDest: ""
        property int dropDestDev: 0
        property bool dragCopy: false
        property bool dragShift: false
        property bool dragLink: false
        property var dragMime: ({})
        function liftBegan(i, c) {}
        function liftReleased() {}
        function liftMoved(c) {}
        function enterTarget(m, u, n, d, s, p) {}
        function showTarget(n, d) {}
        function leaveTarget() {}
        function hoverEnded() {}
        function verbAt(m, r) { return "" }
    } }
    property var sampleRow: ({ n: "omarchy", d: true, i: "folder", p: 493, s: 0, m: 1758835200, t: false, k: 0, v: 0 })
    Component.onCompleted: {
        var pane = paneStub.createObject(root)
        var session = sessionStub.createObject(root, { pane: pane })
        var full = null, slim = null
        try {
            full = root.built(root, { session: session, listingIndex: 2, row: root.sampleRow })
            slim = root.built(root, { session: session, listingIndex: 2, row: root.sampleRow, dropsLocal: false })
        } catch (e) {
            console.log("dragready: build failed " + e)
            Qt.quit()
            return
        }
        root.check("lift handler builds with the tile", root.liftBuiltIn(), true)
        root.check("slim tile keeps its lift gate", slim.enabled, true)
        // Both tiles share one session, so one pane and one dropScope: only dropsLocal tells their areas apart.
        var fullArea = root.dropAreaIn(full), slimArea = root.dropAreaIn(slim)
        root.check("local tile builds its drop area", fullArea !== null, true)
        root.check("shared-area tile builds its drop area too", slimArea !== null, true)
        root.check("local tile arms its drop area", fullArea !== null && fullArea.enabled, true)
        root.check("shared-area tile leaves its own inert", slimArea !== null && slimArea.enabled === false, true)
        root.check("no Loader stands in front of the area", Source.source("ui/RowDrag.qml").indexOf("Loader {") < 0, true)
        root.check("drop API answers", typeof full.enterAt === "function" && typeof full.leaveAt === "function"
                  && typeof full.moveAt === "function" && typeof full.dropAt === "function", true)
        console.log("dragready: " + root.checked + " checks, " + root.failed + " failed")
        Qt.quit()
    }
}
