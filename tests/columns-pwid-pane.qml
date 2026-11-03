import QtQuick

// The pane tests/columns-pwid.qml hands the real ui/ColumnsArea.qml: the properties and calls the Columns view reads, with no backend behind them.
QtObject {
    property string path: "/probe/studio/deep/er"
    property var rows: []
    property var shown: null
    property int cursorIndex: 0
    property int shownTotal: 0
    property int total: 0
    property int held: 0
    property int renamingIndex: -1
    property var trash: ({ opened: false })
    property var clipboard: ({ paths: [], moving: false })
    property int previewIndex: -1
    property string pendingSelect: ""
    property bool pendingMenu: false
    property var selectionBand: null
    property string focusView: "list"
    property bool showHidden: false
    property int windowSize: 35
    property bool listInFlight: false
    property string listingState: "ready"
    property string searchMode: ""
    property var thumbState: ({ file: {}, order: [] })
    property var dirSizeState: ({ file: {}, order: [] })
    property var kindNames: ["text-x-generic", "image-x-generic"]
    property bool storageKnown: true
    property string storageClass: "local"
    property int firstSettleMs: 70
    property int settleMs: 120
    property int coalesceMs: 16
    property int refetchMargin: 25
    property int buffer: 150
    property var backend: null
    function join(base, name) { return String(base) + "/" + String(name) }
    function rowFor(index) { return (index >= 0 && index < rows.length) ? rows[index] : null }
    function isSelected(index) { return false }
    function selectedIndices() { return [] }
    function selectionCount() { return 0 }
    function thumbFor(index) { return "" }
    function open(path) {}
    function openFile(path) {}
    function focusRequested() {}
}
