import QtQuick
import QtQuick.Shapes
import "js/LangMarkPaths.js" as LangMarkPaths

// A language logo on the file page: stroked page plus filled logo in the same ink.
Item {
    id: root

    property string slug: ""
    property color color: "transparent"
    // Shared 24-unit grid with ui/js/Icons.js.
    readonly property real grid: 24
    // Caller ceiling; without one it draws nothing (fails loud).
    property real maxSize
    // "scale" would shadow Item.scale, as in ui/Glyph.qml.
    readonly property real markSize: Math.min(root.maxSize, root.width, root.height)
    readonly property real gridScale: root.markSize / root.grid
    // Board's two-unit stroke on the shared grid.
    property real strokeWidth: 2
    // Caller caps; false is the Omarchy cut.
    property bool roundCaps: false

    // File page with the corner cut for the logo box (x 1..15, y 9..23).
    readonly property string page: "M4 7V2h10l6 6v14H17 M14 2v6h6"

    // Grid-sized Shape re-centered in the slot (Scale origin is 0,0).
    Shape {
        width: root.grid
        height: root.grid
        x: (root.width - root.markSize) / 2
        y: (root.height - root.markSize) / 2
        preferredRendererType: Shape.CurveRenderer
        transform: Scale { xScale: root.gridScale; yScale: root.gridScale }

        ShapePath {
            strokeColor: root.color
            fillColor: "transparent"
            strokeWidth: root.strokeWidth
            capStyle: root.roundCaps ? ShapePath.RoundCap : ShapePath.SquareCap
            joinStyle: root.roundCaps ? ShapePath.RoundJoin : ShapePath.MiterJoin
            PathSvg { path: root.page }
        }

        // Filled logo baked via translate(1 9) scale(14/24); see ui/js/LangMarkPaths.js.
        ShapePath {
            strokeColor: "transparent"
            fillColor: root.color
            PathSvg { path: LangMarkPaths.pathFor(root.slug) }
        }
    }
}
