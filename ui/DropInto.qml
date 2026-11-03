import QtQuick
import "." as Flea
import "js/Drag.js" as DragOps
import "js/DragOut.js" as DragOut
import "js/Swap.js" as Swap
import "js/Tabs.js" as Tabs

// A directory as a drop target, named by path: the listing's floor in ui/PaneWire.qml and each tab in
// ui/TabBar.qml. The rows keep their own DropAreas above the floor, so only what a row refuses lands
// here; ui/js/Drag.js dropInto decides the verb and sends the one transfer.
DropArea {
    id: root

    property var pane: null
    property string dest: ""
    // What the status line calls the destination; the path itself when empty.
    property string label: ""
    // The destination's filesystem when it is known, 0 when it is not, which makes the drop a copy.
    property int destDev: 0
    // A tab takes every drag that carries paths, because resting on it is navigation: a drop the
    // directory would refuse, its own rows lifted back onto it, is still refused by dropInto below.
    property bool switchesOnHover: false
    // The floor and the tab being opened set this while a listing is out. The area stays able to receive the drop.
    property bool refuseLoading: false
    property string enteredMarker: ""
    property var enteredUrls: []
    // The floor is the listing's own extent, so its pointer rows are the autoscroll band's rows.
    property bool scrolls: false

    keys: [DragOps.ROWS_MIME, DragOps.SHELF_MIME, "text/uri-list", "text/plain"]

    Flea.FileDrag {
        id: feedback
        pane: root.pane
    }

    function updateFeedback() {
        if (!root.containsDrag || !feedback.feedback) return
        if (DragOps.canDropInto(root.enteredMarker, root.enteredUrls, root.dest))
            feedback.showTarget(root.label || root.dest, root.destDev)
        else feedback.leaveTarget()
    }

    function scrollBand(drag) {
        if (root.scrolls) feedback.hoverMoved(drag.y, root.height)
    }

    function leaveFeedback() {
        feedback.leaveTarget()
        root.enteredMarker = ""
        root.enteredUrls = []
    }

    onDestChanged: root.updateFeedback()
    onDestDevChanged: root.updateFeedback()

    // One read of a drag for both handlers: the marker, the shelf paths, the plain text and the refusal they share.
    function readDrag(d) {
        var marker = d.getDataAsString(DragOps.ROWS_MIME)
        var shelf = d.getDataAsString(DragOps.SHELF_MIME)
        var plain = d.getDataAsString("text/plain")
        return { marker: marker, shelf: shelf, plain: plain,
                 refusal: DragOut.refusal(DragOut.sources(d.urls, plain, marker, shelf), root.dest, marker, shelf) }
    }

    onEntered: function (drag) {
        // xw6: a tab drag carries only the private tab type and is never a file drop:
        // the strip catcher owns it, and the hover switch must not fire for it either.
        if (drag.getDataAsString(Tabs.TAB_MIME) !== "") {
            drag.accepted = false
            return
        }
        var read = root.readDrag(drag)
        var carrying = DragOps.hasPaths(drag.urls) || (read.plain && DragOut.usePlain(read.marker, read.shelf))
        var allowed = DragOps.canDropInto(read.marker, drag.urls, root.dest, read.plain)
        if (!(root.switchesOnHover && carrying) && !allowed && read.refusal === "") {
            drag.accepted = false
            return
        }
        root.scrollBand(drag)
        root.enteredMarker = read.marker
        DragOut.keys.enter(read.marker, drag.getDataAsString(DragOut.keys.liftMime))
        var urls = []
        for (var i = 0; i < drag.urls.length; i++) urls.push(String(drag.urls[i]))
        root.enteredUrls = urls
        // A tab may accept navigation without accepting a drop; only an eligible destination is named.
        feedback.enterTarget(read.marker, drag.urls, allowed ? (root.label || root.dest) : "",
            allowed ? root.destDev : DragOps.markerDev(read.marker), read.shelf,
            drag.proposedAction)
    }
    onPositionChanged: function (drag) {
        root.scrollBand(drag)
        root.updateFeedback()
    }
    onExited: {
        if (root.scrolls) feedback.hoverEnded()
        DragOut.keys.leave()
        root.leaveFeedback()
    }
    onDropped: function (drop) {
        if (root.scrolls) feedback.hoverEnded()
        // Every way out of a drop, refusals included, ends the drag's keys.
        var ctrl = DragOut.keys.ctrl, shift = DragOut.keys.shift
        DragOut.keys.clear()
        if (drop.getDataAsString(Tabs.TAB_MIME) !== "") {
            root.leaveFeedback()
            return
        }
        if (root.refuseLoading) {
            if (root.pane) root.pane.message(Swap.LOADING, false)
            root.leaveFeedback()
            return
        }
        var read = root.readDrag(drop)
        if (read.refusal !== "" && root.pane) {
            root.pane.message(read.refusal, false)
            root.leaveFeedback()
            return
        }
        if (DragOps.dropInto(root.pane, read.marker, drop.urls, root.dest, root.destDev, read.shelf, read.plain, drop.proposedAction, ctrl, shift)) {
            // CopyAction: this transfer already moved or copied. MoveAction would make the source delete too.
            drop.accept(Qt.CopyAction)
        }
        root.leaveFeedback()
    }
}
