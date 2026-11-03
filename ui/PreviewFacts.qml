import QtQuick
import "." as Flea

// What the preview column states under the name: a tall kind's one compact line, or the table of every fact.
Item {
    id: root

    property bool compact: false
    // ui/js/Facts.js compactLine: the Kind and the tail of the one line.
    property var line: ({ kind: "", tail: "" })
    property var rows: []

    height: root.compact ? factsLine.height : factsTable.height

    Flea.PreviewFactsLine {
        id: factsLine
        width: root.width
        visible: root.compact
        kind: root.line.kind
        tail: root.line.tail
    }

    // An empty model while the line shows, so the hidden table builds no row.
    Flea.FactsTable {
        id: factsTable
        width: root.width
        visible: !root.compact
        rows: root.compact ? [] : root.rows
    }
}
