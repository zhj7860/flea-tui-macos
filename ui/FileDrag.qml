import QtQuick
import "js/Drag.js" as DragOps
import "js/DragOut.js" as DragOut
import "js/Ops.js" as Ops
import "js/Search.js" as Search

// The platform drag belongs to the view: a tab switch may destroy the pressed delegate inside QDrag.exec().
Item {
    id: root

    required property var pane
    // A peek column's {pane, dir, v, w}: its rows are in no listing, so a lift carries the row's own path instead.
    property var peekSource: null
    // The window the gesture speaks in: the listing's pane, or the pane a peek column belongs to.
    readonly property var host: root.pane || (root.peekSource ? root.peekSource.pane : null)
    property var dragRows: []
    // The numbering dragRows were read in, fixed at the lift so a drop after a re-list is refused rather than resolved anew.
    property real dragListing: 0
    property int dropIndex: -1
    // The hovered folder a drop lands in after it opens: a swap may rebuild the lit delegate on another row.
    property string dropDest: ""
    property int dropDestDev: 0
    property bool dragCopy: false
    property bool dragShift: false
    property bool dragLink: false
    property bool awaitingPaths: false
    property bool buttonUp: false
    property var dragMime: ({})
    property var feedback: null
    // Drops callout 2: the folder the pointer rests on and the autoscroll band it rests in; the timers are built on first use.
    property int hoverIndex: -1
    property string hoverPath: ""
    property int scrollDir: 0
    property var hoverTimers: null

    Drag.dragType: Drag.Automatic
    // Plain lift offers copy alone, narrowed by modifiers (a browser uploader refuses move); Ctrl copy, Shift move, both link, so any receiver takes the lift's verb.
    Drag.supportedActions: root.dragLink ? Qt.LinkAction : root.dragCopy ? Qt.CopyAction : root.dragShift ? Qt.MoveAction : Qt.CopyAction
    Drag.proposedAction: root.dragLink ? Qt.LinkAction : root.dragCopy ? Qt.CopyAction : root.dragShift ? Qt.MoveAction : Qt.CopyAction
    Drag.mimeData: root.dragMime
    // The receiver moves or copies itself: deleting on its acceptance would trash files before Files reads them.
    Drag.onDragFinished: function () { root.liftEnded() }

    function liftBegan(index, centroid) {
        if (!root.pane || root.pane.listInFlight || index < 0 || !root.pane.rowFor(index)) return
        if (root.pane.cancelSlowClick) root.pane.cancelSlowClick()
        root.buttonUp = false
        root.awaitingPaths = false
        if (root.pane) root.pane.awaitingPaths = false
        root.dragRows = DragOps.carried(root.pane, index)
        root.dragListing = root.pane.backend ? root.pane.backend.heldListing : 0
        root.dropIndex = -1
        root.dropDest = ""
        root.dropDestDev = 0
        // Ctrl is the threshold's, and a paths reply must not sample it again.
        root.dragCopy = DragOps.copying(centroid.modifiers)
        root.dragShift = DragOps.shifting(centroid.modifiers)
        root.dragLink = DragOps.linking(centroid.modifiers)
        root.dragMime = DragOps.mimeFor(root.pane, root.dragRows, root.dragCopy, root.dragShift)
        if (root.dragMime["text/uri-list"]) {
            root.startOffer()
            return
        }
        if (!root.pane.backend || !DragOut.askAllowed(root.pane.pathsPending, root.pane.clipPending)) {
            root.cannotLeave()
            return
        }
        root.awaitingPaths = true
        if (root.pane) root.pane.awaitingPaths = true
        var dev = root.pane.backend.dirDev || 0
        root.feedback = { own: true, copy: root.dragCopy, shift: root.dragShift, dev: dev,
                          deletable: DragOps.listingDeletable(root.pane), count: root.dragRows.length, canLeave: true }
        root.say(DragOps.feedbackLine(root.feedback, "", dev))
        var rows = root.dragRows.slice()
        var listing = root.dragListing
        var copy = root.dragCopy
        var shift = root.dragShift
        var link = root.dragLink
        root.pane.pathsPending = {
            kind: "drag", rows: rows, listing: listing, copy: copy, shift: shift, link: link,
            deliver: function (list, pending) { root.deliverPaths(list, pending) }
        }
        root.pane.backend.send({ c: "paths", rows: rows, listing: listing })
    }

    function liftPeek(row, centroid) {
        if (!root.peekSource || !row) return
        root.buttonUp = false
        root.dragRows = []
        root.dragListing = 0
        root.dropIndex = -1
        root.dropDest = ""
        root.dropDestDev = 0
        root.dragCopy = DragOps.copying(centroid.modifiers)
        root.dragShift = DragOps.shifting(centroid.modifiers)
        root.dragLink = DragOps.linking(centroid.modifiers)
        root.dragMime = root.peekMime(row, root.dragCopy, root.dragShift)
        root.startOffer()
    }

    // No rows in the marker, so no receiver resolves it by index (DragOps.canDropByIndex needs rows); the uri is the column's directory plus the name.
    function peekMime(row, copy, shift) {
        var src = root.peekSource
        var path = src.pane.join(src.dir, row.n)
        var mime = {}
        mime[DragOps.ROWS_MIME] = DragOps.markerPayload([], copy, src.dir, src.v, src.w, shift === true)
        mime["text/uri-list"] = DragOps.uriFor(path) + "\r\n"
        mime["text/plain"] = path
        return mime
    }

    function liftReleased() {
        root.buttonUp = true
    }

    function liftMoved(centroid) {
        if (root.awaitingPaths || root.Drag.active) return
        root.dragCopy = DragOps.copying(centroid.modifiers)
        root.dragShift = DragOps.shifting(centroid.modifiers)
        root.dragLink = DragOps.linking(centroid.modifiers)
    }

    function startOffer() {
        root.dragMime = DragOut.keys.stamped(root.dragMime)
        root.feedback = DragOps.feedbackFor(root.dragMime[DragOps.ROWS_MIME],
            (root.dragMime["text/uri-list"] || "").split("\r\n"))
        root.showTarget("", root.feedback.dev)
        // Drag.Automatic runs QDrag::exec synchronously, so a finish inside it must not overwrite the hold: arm the watch first.
        if (root.host) root.host.dragHolding = true
        root.Drag.active = true
    }

    function deliverPaths(list, pending) {
        root.awaitingPaths = false
        if (root.pane) root.pane.awaitingPaths = false
        var held = root.pane && root.pane.backend ? root.pane.backend.heldListing : 0
        if (root.buttonUp || held !== pending.listing || !list || list.length !== pending.rows.length) {
            root.cannotLeave()
            return
        }
        root.dragCopy = pending.copy
        root.dragShift = pending.shift === true
        root.dragLink = pending.link === true || (pending.copy === true && pending.shift === true)
        root.dragMime = root.mimeForPaths(pending.rows, list, pending.copy, root.dragShift)
        root.startOffer()
    }

    function mimeForPaths(rows, paths, copy, shift) {
        var mime = {}
        var dev = root.pane.backend ? root.pane.backend.dirDev : 0
        mime[DragOps.ROWS_MIME] = DragOps.markerPayload(rows, copy, Search.baseOf(root.pane), dev, DragOps.listingDeletable(root.pane), shift === true)
        var uris = []
        for (var i = 0; i < paths.length; i++) uris.push(DragOps.uriFor(paths[i]))
        mime["text/uri-list"] = uris.join("\r\n") + "\r\n"
        mime["text/plain"] = paths.join("\n")
        return mime
    }

    // Too wide carries no uri-list, so the gesture ends here and the refusal reads as a pane message.
    function cannotLeave() {
        var line = DragOps.line(root.dragRows.length, "", root.dragCopy, root.dragLink) + DragOps.reachNote(false)
        root.awaitingPaths = false
        root.liftEnded()
        if (root.host) root.host.message(line, false)
    }

    function verbAt(marker, row, seenCopy, seenShift) {
        return DragOps.verbFor(DragOps.isOwnDrag(marker), DragOps.dropHeld(DragOps.markerCopying(marker), seenCopy),
                               DragOps.dropHeld(DragOps.markerShift(marker), seenShift), DragOps.markerDev(marker),
                               row ? row.v : 0, DragOps.markerDeletable(marker))
    }

    function liftEnded() {
        root.Drag.active = false
        if (root.host) { root.host.dragHolding = false; root.host.awaitingPaths = false; root.host.pointerHeld = false }
        root.dragRows = []
        root.dragListing = 0
        root.dragMime = ({})
        root.dropIndex = -1
        root.dropDest = ""
        root.dropDestDev = 0
        root.dragCopy = false
        root.dragShift = false
        root.dragLink = false
        root.feedback = null
        root.hoverIndex = -1
        root.hoverPath = ""
        root.scrollDir = 0
        if (root.hoverTimers) root.hoverTimers.stopRest()
        // A different view may now speak for this gesture; its activity is separate from every transfer.
        var bar = root.host ? root.host.statusBar : null
        if (bar && bar.dragFeedbackOwner) bar.dragFeedbackOwner.say("")
    }

    // A folder row under the pointer starts the rest that opens it and the band that scrolls; a move restarts both.
    function hoverBegan(index, path, y, height) {
        root.hoverIndex = index
        root.hoverPath = path
        root.scrollDir = DragOut.band(y, height)
        root.ensureHoverTimers()
        root.hoverTimers.rest()
    }

    function hoverMoved(y, height) {
        root.scrollDir = DragOut.band(y, height)
        if (root.scrollDir !== 0) root.ensureHoverTimers()
        if (root.hoverTimers) root.hoverTimers.rest()
    }

    function hoverEnded() {
        root.hoverIndex = -1
        root.hoverPath = ""
        root.scrollDir = 0
        if (root.hoverTimers) root.hoverTimers.stopRest()
    }

    function ensureHoverTimers() {
        if (root.hoverTimers !== null)
            return
        root.hoverTimers = Qt.createComponent("HoverTimers.qml").createObject(root, { session: root })
    }

    function say(text) {
        var bar = root.host ? root.host.statusBar : null
        if (!bar) return
        if (!text) {
            if (bar.dragFeedbackOwner === root) {
                bar.dragFeedbackOwner = null
                bar.setActivity(root, "", Ops.emptyTransfer())
            }
            return
        }
        if (bar.activities.some(function (entry) { return entry.transfer.running })) return
        if (bar.dragFeedbackOwner && bar.dragFeedbackOwner !== root)
            bar.setActivity(bar.dragFeedbackOwner, "", Ops.emptyTransfer())
        bar.dragFeedbackOwner = root
        bar.setActivity(root, text, Ops.emptyTransfer())
    }

    function enterTarget(marker, urls, name, destDev, shelf, proposed) {
        root.feedback = DragOps.feedbackFor(marker, urls, shelf, proposed)
        root.showTarget(name, destDev)
    }

    function showTarget(name, destDev) {
        if (!root.feedback) return
        root.dragCopy = DragOps.copyingFor(root.feedback, destDev)
        root.dragLink = DragOps.linkingFor(root.feedback, destDev)
        root.say(DragOps.feedbackLine(root.feedback, name, destDev))
    }

    function leaveTarget() {
        var bar = root.host ? root.host.statusBar : null
        if (!bar || bar.dragFeedbackOwner !== root) return
        root.say(root.feedback && root.feedback.own
            ? DragOps.feedbackLine(root.feedback, "", root.feedback.dev) : "")
    }

    Connections {
        target: root.host ? root.host.statusBar : null
        function onActivitiesChanged() {
            var bar = root.host.statusBar
            if (bar.dragFeedbackOwner === root
                    && bar.activities.some(function (entry) { return entry.transfer.running })) root.say("")
        }
    }
}
