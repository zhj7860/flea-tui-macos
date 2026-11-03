import QtQuick
import "js/Drag.js" as DragOps
import "js/DragOut.js" as DragOut
import "js/DropDev.js" as DropDev
import "js/Tabs.js" as Tabs
import "js/Search.js" as Search

// Delegate input and drop eligibility share a view-owned FileDrag; no platform object lives in this row.
Item {
    id: root

    required property var session
    required property int listingIndex
    required property var row
    readonly property var pane: root.session.pane
    // A peek column's session names the directory it shows and the pane whose collide sends its drops; null is the pane's own listing.
    readonly property var dropScope: root.pane === null && root.session.peekSource ? root.session.peekSource : null
    readonly property var targetPane: root.dropScope ? root.dropScope.pane : root.pane
    readonly property string targetDir: root.dropScope ? root.dropScope.dir : (root.pane ? Search.baseOf(root.pane) : "")

    // A listing row names its own device; a peek or carried column row names none, so the backend's answer for its path stands in, and an unanswered path is 0, which copies.
    readonly property int destDev: !root.row ? 0 : root.row.v ? root.row.v
        : (root.row.d === true && root.targetPane && root.targetPane.backend
            ? DropDev.devFor(root.targetPane.backend.pathDevs, root.targetPane.join(root.targetDir, root.row.n)) : 0)
    // The answer landing while this folder is hovered re-says its line once, in the right verb.
    onDestDevChanged: if (root.lit()) {
        root.session.dropDestDev = root.destDev
        root.session.showTarget(root.row.n, root.destDev)
    }

    // The drop destination this delegate last recorded on the session, kept so leaving clears only its own record.
    property string recorded: ""
    // False where the view answers drops from one shared area, so the row's own area stays disabled.
    property bool dropsLocal: true

    anchors.fill: parent
    // A peek column's row lifts through the session's peekSource; which drops it takes is the DropArea's call alone.
    enabled: !!root.row && (root.pane !== null ? !root.pane.listInFlight && root.listingIndex >= 0
        : root.session.peekSource !== null)

    DragHandler {
        id: lift
        enabled: root.pane === null || (!root.pane.renamePending && root.pane.renamingIndex !== root.listingIndex)
        target: null
        // Preserve List's grab contract: the Flickable must not take the row drag after its threshold.
        grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.CanTakeOverFromHandlersOfDifferentType | PointerHandler.ApprovesTakeOverByHandlersOfSameType
        onActiveChanged: {
            if (active && root.pane !== null) root.session.liftBegan(root.listingIndex, lift.centroid)
            else if (active) root.session.liftPeek(root.row, lift.centroid)
            else root.session.liftReleased()
        }
        onCentroidChanged: if (active) root.session.liftMoved(lift.centroid)
    }

    // The row's own area answers where dropsLocal holds; a view with one shared area leaves this one inert. No Loader stands in front of it: a Loader would add an object to every list row for a grid tile's saving.
    DropArea {
        anchors.fill: parent
        // A peek row takes drops only as a folder, through its dropScope; without one it would aim the drop at the pane's own folder.
        enabled: root.dropsLocal && (root.pane !== null || (root.dropScope !== null && !!root.row && root.row.d === true && root.targetPane !== null && !root.targetPane.listInFlight))
        keys: [DragOps.ROWS_MIME, "text/uri-list", "text/plain"]
        onEntered: function (drag) { root.enterAt(drag, drag) }
        onPositionChanged: function (drag) { root.moveAt(drag) }
        onExited: root.leaveRow()
        onDropped: function (drop) { root.dropAt(drop) }
    }

    // A drop area's entrance, at a point in this row's own coordinates: the per-row area passes its drag, a shared one the mapped point.
    function enterAt(drag, at) {
        // xw6: a tab drag carries only the private tab type and is never a file drop.
        if (drag.getDataAsString(Tabs.TAB_MIME) !== "") {
            drag.accepted = false
            return
        }
        drag.accepted = root.enter(drag.getDataAsString(DragOps.ROWS_MIME), drag.urls,
                                   drag.getDataAsString(DragOps.SHELF_MIME),
                                   drag.getDataAsString("text/plain"), drag.proposedAction,
                                   drag.getDataAsString(DragOut.keys.liftMime))
        root.hoverAt(at)
    }

    function moveAt(at) {
        if (root.lit()) {
            root.session.showTarget(root.row.n, root.destDev)
            root.hoverAt(at)
        }
    }

    function leaveAt() { root.leaveRow() }

    function dropAt(drop) {
        if (drop.getDataAsString(Tabs.TAB_MIME) !== "")
            return
        var marker = drop.getDataAsString(DragOps.ROWS_MIME)
        var shelf = drop.getDataAsString(DragOps.SHELF_MIME)
        var plain = drop.getDataAsString("text/plain")
        if (root.refuseDrop(marker, drop.urls, shelf, plain)) return
        if (root.dropped(marker, drop.urls, shelf, plain, drop.proposedAction)) {
            drop.accept(Qt.CopyAction)
        }
        root.session.hoverEnded()
    }

    // The pointer leaves this delegate: the destination it recorded goes, even when a swap reused the delegate on another row, and a destination another row recorded since stays.
    function leaveRow() {
        if (root.recorded.length > 0 && root.session.dropDest === root.recorded) {
            root.session.dropIndex = -1
            root.session.dropDest = ""
            root.session.dropDestDev = 0
            root.session.leaveTarget()
        }
        root.recorded = ""
        if (root.session.dragRows.length === 0) {
            root.session.dragCopy = false
            root.session.dragLink = false
        }
        root.session.hoverEnded()
        DragOut.keys.leave()
    }

    // One reset for every finished gesture, refused or dropped: the drag's keys end and the row goes dark again.
    function clearTarget() {
        DragOut.keys.clear()
        root.session.dropIndex = -1
        root.session.dropDest = ""
        root.session.dropDestDev = 0
        root.session.dragCopy = false
        root.session.dragLink = false
        root.session.leaveTarget()
    }

    // Testable entrance: a refused folder row stays dark and names its refusal, never lighting "move here" for a drop that cannot land.
    function enter(marker, urls, shelf, plain, proposed, lift) {
        if (!(root.row && root.row.d === true)) return false
        var dest = root.targetPane.join(root.targetDir, root.row.n)
        var line = ""
        var ok = false
        if (DragOps.hasPaths(urls) || (plain && !marker)) {
            line = DragOut.refusal(DragOut.sources(urls, plain, marker, ""), dest, marker, "")
            ok = line === "" && DragOps.canDropInto(marker, urls, dest, plain)
        } else if (root.dropScope === null) {
            ok = DragOps.canDropByIndex(marker, root.targetDir, root.session.dragRows, root.listingIndex)
        }
        if (!ok) {
            if (line) root.targetPane.message(line, false)
            return false
        }
        root.session.dropIndex = root.listingIndex
        // The drop's own address: the swap may rebuild this delegate on another row before the release.
        root.session.dropDest = dest
        root.session.dropDestDev = root.destDev
        root.recorded = dest
        if (root.targetPane.columnsArea) root.targetPane.columnsArea.askDropDevs(lift)
        DragOut.keys.enter(marker, lift)
        root.session.enterTarget(marker, urls, root.row.n, root.destDev, shelf, proposed)
        return true
    }

    // Lit means this delegate still shows the hovered folder: after a swap the index may name another row.
    function lit() {
        return root.session.dropIndex === root.listingIndex && !!root.row
                && root.session.dropDest === root.targetPane.join(root.targetDir, root.row.n)
    }

    // Where a drop lands: the recorded hovered folder, else this row's own folder, since a swap may have reused the delegate.
    function landing() {
        if (root.session.dropDest.length > 0) return { dest: root.session.dropDest, dev: root.session.dropDestDev }
        var folder = root.row && root.row.d === true
        return { dest: folder ? root.targetPane.join(root.targetDir, root.row.n) : "", dev: folder ? root.destDev : 0 }
    }

    // Testable refusal: says the sentence and darkens exactly like dropped(), so a refused
    // drop never leaves the row lit (Qt sends dropped, not exited, after the drop).
    function refuseDrop(marker, urls, shelf, plain) {
        var dest = root.landing().dest
        if (!dest) return ""
        var line = DragOut.refusal(DragOut.sources(urls, plain, marker, shelf), dest, marker, shelf)
        if (!line) return ""
        root.targetPane.message(line, false)
        root.clearTarget()
        return line
    }

    // The drop apart from its platform event, which tests/js/collide.js cannot build: answers whether it was taken.
    function dropped(marker, urls, shelf, plain, proposed) {
        var accepted = false
        var at = root.landing()
        if (at.dest.length > 0) {
            if (DragOps.hasPaths(urls) || (plain && !marker && !shelf))
                accepted = DragOps.dropInto(root.targetPane, marker, urls, at.dest, at.dev, shelf, plain, proposed, DragOut.keys.ctrl, DragOut.keys.shift)
            else if (root.dropScope === null
                     && DragOps.canDropByIndex(marker, root.targetDir, root.session.dragRows, root.listingIndex))
                accepted = DragOps.dropByIndex(root.targetPane, root.session.dragRows, root.listingIndex,
                    root.session.verbAt(marker, root.row, DragOut.keys.ctrl, DragOut.keys.shift), root.session.dragListing)
        }
        root.clearTarget()
        return accepted
    }

    // In the view's own coordinates, so the band reads the listing, not the row.
    function hoverAt(at) {
        if (root.dropScope !== null || !at)
            return
        var viewer = root.session.pane
        var list = viewer ? viewer.listArea : null
        if (!list || !viewer || root.targetDir !== Search.baseOf(viewer))
            return
        var pt = root.mapToItem(list, at.x, at.y)
        if (root.lit())
            root.session.hoverBegan(root.listingIndex, root.targetPane.join(root.targetDir, root.row.n), pt.y, list.height)
        else
            root.session.hoverMoved(pt.y, list.height)
    }
}
