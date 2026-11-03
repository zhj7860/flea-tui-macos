import QtQuick
import QtQuick.Shapes
import qs.Commons

// The Dropbox mark, reproduced from the official artwork rather than recut, the same ruling that
// brought TailscaleMark back. Five diamond tiles, monochrome and palette-tinted, no brand colour.
// Outside the cut and outside Glyph.qml, where FleaMark sits.
Item {
    id: root

    // The type scale, not the slot, and clamped so a reproduction can never out-size the cut glyph
    // beside it. A smaller caller slot still wins, the way Glyph's own min() lets it.
    property real iconSize: Theme.markSize
    property color color: "transparent"

    // The mark is wider than it is tall, so the box is too: scaling a wide mark into a square slot is
    // the AdGuard lesson, it renders smaller than its neighbours.
    readonly property real boxRatio: 1.18
    // Tile centres and size as fractions of the box, taken off the official artwork.
    readonly property var tileX: [0.25, 0.75, 0.25, 0.75, 0.50]
    readonly property var tileY: [0.188, 0.188, 0.564, 0.564, 0.812]
    readonly property real tileW: 0.50
    readonly property real tileH: 0.376

    readonly property real drawn: Math.min(Theme.markSize, root.iconSize)

    implicitWidth: root.drawn * root.boxRatio
    implicitHeight: root.drawn
    width: root.drawn * root.boxRatio
    height: root.drawn

    // All five tiles in one path string: a ShapePath is not an Item, so a Repeater cannot make them.
    readonly property string tiles: {
        var hw = root.tileW * root.width / 2
        var hh = root.tileH * root.height / 2
        var out = ""
        for (var i = 0; i < root.tileX.length; i++) {
            var cx = root.tileX[i] * root.width
            var cy = root.tileY[i] * root.height
            out += "M " + cx + " " + (cy - hh)
                 + " L " + (cx + hw) + " " + cy
                 + " L " + cx + " " + (cy + hh)
                 + " L " + (cx - hw) + " " + cy + " Z "
        }
        return out
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: root.color
            strokeColor: "transparent"
            strokeWidth: 0

            PathSvg { path: root.tiles }
        }
    }
}
