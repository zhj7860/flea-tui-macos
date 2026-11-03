import QtQuick
import "." as Flea

// The wheel and the two knobs of a zoomed picture; the Loader that builds this sits on the Flickable they drive.
Item {
    id: root

    readonly property Item viewport: root.parent ? root.parent.parent : null
    anchors.fill: parent

    Flea.FastScrollHandler { flickable: root.viewport }
    Flea.ViewportScrollBars { flickable: root.viewport }
}
