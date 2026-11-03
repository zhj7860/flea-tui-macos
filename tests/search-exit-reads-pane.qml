import QtQuick
import "flea" as Flea
import "flea/js/Filter.js" as Filter

// The exit-hold pane: walk rows under the strip, then the folder they land as, with only the surface the real List and GridArea read; the sent arrays are what the probe asserts through.
QtObject {
    id: pane
    property string mode: "list"
    readonly property string viewMode: "list"
    property var columnsArea: null
    property int selectedAt: -1
    property string path: "/probe"
    property var listArea: null
    property var rows: []
    property var shown: null
    property int shownTotal: 0
    property int total: 0
    property int held: 0
    property int cursorIndex: 0
    property int cursorSeq: 0
    property int renamingIndex: -1
    property string renameError: ""
    property var renameRequest: null
    readonly property bool renamePending: renameRequest !== null
    property bool paneFocused: true
    property bool dualMode: false
    property var clipboard: ({ paths: [], moving: false })
    property var thumbState: ({ file: {}, order: [] })
    property var dirSizeState: ({ file: {}, order: [] })
    property var kindNames: ["JPEG image"]
    property string searchMode: "typing"
    property string searchQuery: "nor"
    property QtObject swap: QtObject { property string answeredQuery: "nor" }
    property bool searchLeaving: true
    property string recentMode: ""
    property string filterQuery: ""
    property var selectionBand: null
    property int previewIndex: -1
    property bool storageKnown: true
    property string storageClass: ""
    property bool listInFlight: true
    property string listingState: "ready"
    property int visibleRows: listArea ? Math.ceil(listArea.height / Flea.Theme.fileRowHeight) : 0
    property int cacheRows: 0
    property int firstSettleMs: 70
    property int settleMs: 120
    property int coalesceMs: 16
    property int refetchMargin: 0
    property int buffer: 0
    property int windowSize: 25
    property var sentThumb: []
    property var sentDir: []
    property var sentWindow: []
    property var sentCancel: []
    property var backend: QtObject {
        function thumb(rows, cacheOnly) { sentThumb.push(rows.length) }
        function thumbcancel(rows) { sentCancel.push(rows.length) }
        function dirsize(rows) { sentDir.push(rows.length) }
        function dirsizecancel() {}
        function window(start, count) { sentWindow.push(start + ":" + count) }
    }
    property var menu: QtObject {
        function close() {}
    }
    property var sidebar: null
    property var statusBar: null
    function join(base, name) { return String(base) + "/" + String(name) }
    function rowFor(index) {
        var offset = index - held
        return offset < 0 || offset >= rows.length ? null : rows[offset]
    }
    function isSelected(index) { return false }
    function setCursor(index, context) { cursorIndex = index }
    function selectOnly(index, context) { selectedAt = index; setCursor(index, context) }
    function showRow(view, context) { listArea.positionViewAtIndex(view, ListView.Contain) }
    function pressSlowClick() {}
    function cancelSlowClick() {}
    function armSlowClick(index, modifiers, dragging, wasSole) {}
    function slowClickWasSole(index) { return false }
    // Twenty-five image rows of forty, the held walk window: a scroll over it asks thumbs, sizes and a window unless the hold refuses.
    function standWalk() {
        var out = []
        for (var i = 0; i < 25; i++)
            out.push({ n: "sub/photo-" + i + ".jpg", d: i % 4 === 0, i: "image-jpeg", p: 33188, s: 80000, m: 1758835200, t: true, k: 0 })
        rows = out
        shownTotal = 40
        total = 40
    }
    // Ten of twenty-five, so the landed folder still owes its window past what it holds.
    function landFolder() {
        var out = []
        for (var j = 0; j < 10; j++)
            out.push({ n: "photo-" + j + ".jpg", d: j % 4 === 0, i: "image-jpeg", p: 33188, s: 80000, m: 1758835200, t: true, k: 0 })
        rows = out
        shownTotal = 25
        total = 25
        searchMode = ""
        searchQuery = ""
        swap.answeredQuery = ""
        searchLeaving = false
        listInFlight = false
        listingState = "ready"
        sentThumb = []
        sentDir = []
        sentWindow = []
        sentCancel = []
    }
}
