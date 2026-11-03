import QtQuick
import QtQuick.Shapes

// The Omarchy spiral as the activity mark: a stroke-dash crawl along the brand path, never a
// rotation. This and EmptyState's FleaMark are the only two places the spiral appears; rows
// and menus never draw it, per the icon-language spec.
Item {
    id: root

    property color color: Theme.color.mutedFrame
    // The mark draws on the same 24 unit grid as every Glyph, scaled to the slot.
    readonly property real grid: 24
    readonly property real markScale: Math.min(root.width, root.height) / root.grid

    Shape {
        width: root.grid
        height: root.grid
        x: (root.width - root.grid * root.markScale) / 2
        y: (root.height - root.grid * root.markScale) / 2
        preferredRendererType: Shape.CurveRenderer
        transform: Scale { xScale: root.markScale; yScale: root.markScale }

        ShapePath {
            id: crawl
            strokeColor: root.color
            fillColor: "transparent"
            // A brand mark, not a cut glyph: the spiral keeps the brand's 2 and is exempt from Theme.strokeWidth on purpose.
            strokeWidth: 2
            capStyle: ShapePath.SquareCap
            joinStyle: ShapePath.MiterJoin
            strokeStyle: ShapePath.DashLine
            // The spiral's centreline is 114 grid units and dash units are strokeWidth multiples,
            // so 30+27=57 is exactly one period; the animation walks one period per cycle and the
            // loop point is therefore invisible.
            dashPattern: [30, 27]
            PathSvg { path: "M21 21H3V3h18v14H7V7h10v6h-6" }
        }
    }

    // Still for its first second on screen, so a load faster than that draws no motion; a hide puts it back to rest.
    readonly property int stillMs: 1000
    property bool crawling: false
    onVisibleChanged: if (!root.visible) { root.crawling = false; crawl.dashOffset = 0 }
    Timer {
        interval: root.stillMs
        running: root.visible && !root.crawling
        onTriggered: root.crawling = true
    }

    NumberAnimation {
        target: crawl
        property: "dashOffset"
        from: 0
        to: -57
        duration: 1600
        loops: Animation.Infinite
        // Item.visible reads effective visibility, so a hidden ancestor stops the crawl too.
        running: root.visible && root.crawling
    }
}
