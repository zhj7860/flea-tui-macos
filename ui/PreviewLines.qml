import QtQuick
import Quickshell.Io
import qs.Commons
import "js/Csv.js" as Csv

// The first lines of a text file in the preview column's frame, coloured by the backend for code; a network or phone file is read here, under the size gate.
Item {
    id: root

    property string path: ""
    property bool active: false
    property int size: 0
    // Code gets the muted number gutter; plain text does not.
    property bool numbered: false
    // The backend that colours the lines; a bare stub leaves the file's own text drawn plain.
    property var backend: null

    // The same gate ui/PreviewText.qml uses: FileView reads the whole file, so a row over it is
    // refused on every class; truncating would still read all of it first, a 2 GB log over SMB.
    property int maxBytes: 1048576
    // True on network and phone storage, where the backend is never given the path.
    property bool truncate: false
    readonly property bool overSize: root.size > root.maxBytes
    // Over the gate by the listing's size, or by the backend's own count when the file grew since.
    readonly property bool tooLarge: root.overSize || root.answer === "large"
    // More than the frame can show is wasted work, so only as many lines as its height holds are ever built into rows.
    readonly property int maxLines: Math.max(1, Math.floor((root.height - 2 * Theme.spacing.gap) / Math.ceil(lineMetrics.lineSpacing)))

    // The caller reads the file when the backend must not open it, or when it cannot colour it.
    readonly property bool engine: root.backend !== null && typeof root.backend.askCode === "function"
    // A .csv or .tsv draws as a table; every other text or code file keeps the line view.
    readonly property bool csv: Csv.delimiter(root.path) !== ""
    readonly property bool fromFile: root.truncate || !root.engine
    readonly property string fileText: file.text()
    // The line view, built the first time a text or code file is previewed so a launch that never previews one loads none of it.
    readonly property var code: root.csv ? csvLoader.item : codeLoader.item
    readonly property var viewport: root.code ? root.code.viewport : null
    readonly property string answer: root.code ? root.code.answer : ""
    readonly property string shownText: root.fromFile ? root.fileText : root.lines.join("\n")
    readonly property var lines: root.code ? root.code.lines : []

    // Surfaced so the column can show the canvas's Error tile instead of an empty frame.
    property bool fileFailed: false
    readonly property bool readFailed: root.fileFailed || root.answer === "failed"
    // The sentence under the kind's mark when the file has nothing to draw, "" otherwise; the column adds it to the mark it already draws.
    readonly property string note: root.answer === "binary" ? "binary file" : ""
    // True when the reader has settled with nothing to draw (too large, binary or empty), so the column stands the kind's mark in.
    readonly property bool blank: root.tooLarge || root.answer === "binary"
        || (root.active && !root.readFailed && root.code !== null && root.code.settled && root.code.total === 0)
    readonly property bool loading: root.active && !root.readFailed && !root.tooLarge && root.answer === ""

    FileView {
        id: file
        path: (root.active && !root.overSize && root.fromFile) ? root.path : ""
        printErrors: false
        onLoadFailed: root.fileFailed = true
        onPathChanged: root.fileFailed = false
    }

    property bool built: false
    onActiveChanged: if (root.active) root.built = true
    Component.onCompleted: if (root.active) root.built = true

    Loader {
        id: csvLoader
        anchors.fill: parent
        active: root.built && root.csv
        source: "CsvTable.qml"
        onLoaded: {
            item.backend = Qt.binding(function () { return root.backend })
            item.path = Qt.binding(function () { return root.path })
            item.fromText = Qt.binding(function () { return root.fromFile })
            item.text = Qt.binding(function () { return root.fromFile && file.loaded ? root.fileText : null })
            item.active = Qt.binding(function () { return root.active && !root.overSize })
            item.limit = 0
            item.margin = 0
            item.pixelSize = Theme.font.caption
        }
    }

    Loader {
        id: codeLoader
        anchors.fill: parent
        anchors.margins: Theme.spacing.gap
        active: root.built && !root.csv
        source: "CodeLines.qml"
        onLoaded: {
            item.backend = Qt.binding(function () { return root.backend })
            item.path = Qt.binding(function () { return root.path })
            item.fromText = Qt.binding(function () { return root.fromFile })
            item.text = Qt.binding(function () { return root.fromFile && file.loaded ? root.fileText : null })
            item.active = Qt.binding(function () { return root.active && !root.overSize })
            item.numbered = Qt.binding(function () { return root.numbered })
            item.limit = 0
            item.scrolls = true
            item.margin = 0
            item.pixelSize = Theme.font.caption
        }
    }

    FontMetrics {
        id: lineMetrics
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
    }
}
