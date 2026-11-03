import QtQuick
import qs.Commons

// The Tailscale mark, reproduced from the official artwork rather than recut. Decided on the
// reproduction after both recuts were rendered beside the original at the sizes this actually draws
// at: a stroked mark spends most of a small glyph on outline, and a one-weight language cannot carry
// the mark's own emphasis. It sits where FleaMark sits, outside the cut and outside Glyph.qml.
Item {
    id: root

    // The type scale, not the slot, and clamped so a reproduction can never out-size the cut glyph
    // beside it. A smaller caller slot still wins, the way Glyph's own min() lets it.
    property real iconSize: Theme.markSize
    property color color: "transparent"

    // The official file's own box and geometry: circles of radius 18 at 30.5, 84.5 and 138.5.
    readonly property real grid: 169
    readonly property real dotRadius: 18
    readonly property var centres: [30.5, 84.5, 138.5]
    // The official draws the middle row plus the bottom centre solid and the rest at 0.4; the two
    // opacities are the mark, because the brand toolkit says the gray dots adapt in opacity.
    readonly property real mutedOpacity: 0.4
    readonly property real drawn: Math.min(Theme.markSize, root.iconSize)
    readonly property real unit: root.drawn / root.grid

    implicitWidth: root.drawn
    implicitHeight: root.drawn
    width: root.drawn
    height: root.drawn

    Repeater {
        model: 9

        delegate: Rectangle {
            required property int index
            readonly property int row: Math.floor(index / 3)
            readonly property int col: index % 3
            // Row 1 is the middle row, and column 1 of row 2 is the bottom centre.
            readonly property bool solid: row === 1 || (row === 2 && col === 1)

            width: 2 * root.dotRadius * root.unit
            height: width
            radius: width / 2
            x: root.centres[col] * root.unit - width / 2
            y: root.centres[row] * root.unit - height / 2
            color: root.color
            opacity: solid ? 1.0 : root.mutedOpacity
        }
    }
}
