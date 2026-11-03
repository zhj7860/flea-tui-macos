import QtQuick
import QtQuick.Shapes

// One viewport texture follows the frame's inner arc; the tall page keeps its original decode.
Shape {
    id: root
    property Item target: null
    property real radius: 0
    property bool roundTop: true
    preferredRendererType: Shape.CurveRenderer

    ShaderEffectSource {
        id: texture
        sourceItem: root.target
        hideSource: true
        visible: false
    }
    ShapePath {
        strokeWidth: -1
        fillColor: "transparent"
        fillItem: texture
        PathRectangle {
            width: root.width
            height: root.height
            radius: root.radius
            topLeftRadius: root.roundTop ? root.radius : 0
            topRightRadius: root.roundTop ? root.radius : 0
        }
    }
}
