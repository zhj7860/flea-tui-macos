import QtQuick
import "js/Format.js" as Format

// The moving layer over a still GIF frame, built by its host only once that frame is drawn; the host's Loader holds the still's rect and this fills it.
AnimatedImage {
    id: root

    property string path: ""
    // False while the host's picture is covered or off screen.
    property bool shown: true
    // The window is mapped and not minimised; a hidden window pauses on its current frame.
    readonly property bool exposed: Window.window !== null && Window.window.visible
        && Window.visibility !== Window.Hidden && Window.visibility !== Window.Minimized
    // True from the frame its own first frame is ready, which is when the host stops drawing the still.
    readonly property bool ready: root.status === Image.Ready && root.frameCount > 1

    anchors.fill: parent
    opacity: root.ready ? 1 : 0
    source: root.path.length > 0 ? Format.fileUri(root.path) : ""
    fillMode: Image.Stretch
    playing: root.visible && root.shown && root.exposed
    asynchronous: true
    cache: false
}
