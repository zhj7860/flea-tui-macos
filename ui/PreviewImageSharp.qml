import QtQuick

// The sharper layer of a zoomed Quick Look picture: a raster's whole decode asked once, an SVG drawn again at each zoomed size.
Image {
    id: root

    // The fit picture this layer lies over: it takes that picture's file, rect and fill.
    property Image base: null
    // False at fit, where the layer holds no file and so no decode.
    property bool active: false
    // The decode size; 0x0 is the whole picture to Qt, which is what a raster asks for here.
    property size want: Qt.size(0, 0)
    // Set on the first frame and kept while a redraw loads, so the last frame holds; cleared when the layer is let go.
    property bool drawn: false

    x: root.base ? root.base.x : 0
    y: root.base ? root.base.y : 0
    width: root.base ? root.base.width : 0
    height: root.base ? root.base.height : 0
    visible: root.drawn
    source: root.active && root.base ? root.base.source : ""
    fillMode: root.base ? root.base.fillMode : Image.Stretch
    autoTransform: true
    asynchronous: true
    cache: false
    retainWhileLoading: true
    sourceSize: root.want
    onStatusChanged: {
        if (root.status === Image.Ready) root.drawn = true
        else if (root.status !== Image.Loading) root.drawn = false
    }
}
