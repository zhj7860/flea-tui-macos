import QtQuick
import "js/DragOut.js" as DragOut

// The two timers a drag rests on, built with the first hovered row and kept for the window's life.
Item {
    id: root
    required property var session
    // The autoscroll step's own interval, one row per tick.
    readonly property int scrollMs: 100

    // Resting on a folder opens it when the setting is on; any move restarts the rest.
    Timer {
        id: openTimer
        interval: DragOut.OPEN_MS
        repeat: false
        onTriggered: {
            if (ViewState.openFoldersWhileDragging && root.session.hoverPath.length > 0 && root.session.pane)
                root.session.pane.open(root.session.hoverPath)
        }
    }

    // Resting in the top or bottom band scrolls the view a row at a time, with the setting on or off.
    Timer {
        id: scrollTimer
        interval: root.scrollMs
        repeat: true
        running: root.session.scrollDir !== 0
        onTriggered: {
            var view = root.session.pane ? root.session.pane.listArea : null
            if (!view || view.contentY === undefined)
                return
            var step = view.cellHeightPx !== undefined ? view.cellHeightPx : Theme.fileRowHeight
            view.contentY = Math.max(0, Math.min(view.contentHeight - view.height, view.contentY + root.session.scrollDir * step))
        }
    }

    function rest() { openTimer.restart() }
    function stopRest() { openTimer.stop() }
}
