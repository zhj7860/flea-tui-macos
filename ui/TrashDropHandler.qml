import QtQuick
import "js/TrashDrop.js" as TrashDrop

// The rail loads this bridge on its first matching drag, keeping TrashDrop.js off the first frame.
FileDrag {
    id: root

    function accepts(marker, urls, path) { return TrashDrop.accepts(marker, urls, path, root.pane ? root.pane.backend : null) }
    function line(marker, urls, path) { return TrashDrop.line(marker, urls, path, root.pane ? root.pane.backend : null) }
    function drop(pane, marker, urls) { return TrashDrop.drop(pane, marker, urls) }
}
