import QtQuick
import QtQuick.Shapes
import qs.Commons

// Filled outline of the brand's 2-unit stroke, with bounds equal to ink for glyph sizing; nothing is ever added to it.
Item {
  id: root

  property color color: "white"
  // The size token every OEM bar mark takes, never a literal and never iconSmall.
  property real iconSize: Style.font.icon
  // 0.8125 gives 13 px ink at a 16 px token for OEM ink-for-ink parity; measured-bounds bars scale this ink box to their icon size.
  readonly property real opticalScale: 0.8125
  implicitWidth: Math.round(root.iconSize * root.opticalScale)
  implicitHeight: root.implicitWidth

  readonly property real grid: 24
  // The outline's ink spans 2 to 22 inside the 24-unit grid.
  readonly property real inkOrigin: 2
  readonly property real inkExtent: 20
  readonly property real markScale: Math.min(root.width, root.height) / root.inkExtent

  Shape {
    width: root.grid
    height: root.grid
    preferredRendererType: Shape.CurveRenderer
    transform: [
      Scale { xScale: root.markScale; yScale: root.markScale },
      Translate { x: -root.inkOrigin * root.markScale; y: -root.inkOrigin * root.markScale }
    ]

    ShapePath {
      fillColor: root.color
      strokeColor: "transparent"
      strokeWidth: -1
      PathSvg { path: "M22 22H2V2h20v16H6V6h12v8h-8v-2h6V8H8v8h12V4H4v16h18z" }
    }
  }
}
