import QtQuick
import "js/PreviewSwap.js" as PreviewSwap

// A preview's last picture held on screen while the next preview builds under it, and let go in the frame
// the new one is whole; see AGENTS.md "The preview swap". The layer exists only while a hold does, so a
// settled preview is drawn directly and costs no texture.
Item {
    id: root

    // What the surface draws: the host's children land in here.
    default property alias content: content.data
    // Quick Look keeps its panes eager outside this wrapper and builds only it on first open, so
    // the picture captures that outer container rather than children of its own. Null draws as before.
    property Item captureSource: null
    // The host's answer: what is under the picture is the whole preview it was asked for.
    property bool ready: true
    // True for the column, where a move during a hold means held j, and the stale picture gives way to loading.
    property bool burstEnds: false
    // What the host paints behind the panes, laid under them inside the picture only: text drawn into a clear
    // layer blends its edges against nothing and comes out heavier than the same text drawn on its real ground.
    property color ground: "transparent"
    property real groundInset: 0
    property real groundRadius: 0

    property bool capturing: false
    property bool holding: false
    property bool started: false
    property bool fellBack: false
    // Set just before the frame that first syncs the layer; the picture is taken in that frame's render.
    property bool syncArmed: false
    // The event loop ran after the arming frame's afterAnimating, so its afterSynchronizing came queued (threaded loop).
    property bool syncQueued: false
    property var key: undefined
    property var queued: []

    // What ui/Ipc.qml previewSwapState reads: how each hold ended and every frame drawn half-built.
    property int holds: 0
    property int fallbacks: 0
    property int bursts: 0
    property int heldFrames: 0
    property int midFrames: 0
    property int loadingFrames: 0
    property var last: ({ ms: 0, end: "" })
    property double since: 0

    // A move: the change runs once a picture of the preview as it stands is frozen, or at once when nothing needs one.
    // After a burst the loading state stays live under held j; atWork is the new preview's own start, which is held again.
    function hold(apply, key, atWork) {
        if (atWork !== true && root.fellBack && root.burstEnds && !root.capturing && !root.holding) {
            root.run([apply])
            return
        }
        var action = PreviewSwap.onMove({ capturing: root.capturing, holding: root.holding, key: root.key },
                                        key, root.burstEnds)
        if (action === PreviewSwap.BURST) {
            root.bursts += 1
            root.release("burst", true)
            root.run([apply])
            return
        }
        if (action === PreviewSwap.JOIN) {
            // A newer target means the work already started was for a row the cursor has left.
            if (root.key !== key) {
                root.key = key
                root.started = false
                cap.stop()
            }
            if (root.holding)
                root.run([apply])
            else if (apply)
                root.queued.push(apply)
            return
        }
        if (!root.visible || root.width <= 0 || root.height <= 0) {
            root.run([apply])
            return
        }
        root.key = key
        root.started = false
        root.fellBack = root.fellBack && root.shownAt > 0
        root.since = Date.now()
        root.holds += 1
        root.queued = apply ? [apply] : []
        root.syncArmed = false
        root.capturing = true
        captureGuard.restart()
    }

    // The host: the new preview's own work has begun, so the cap counts from here.
    function start(isPdf) {
        if (!root.holding && !root.capturing)
            return
        root.started = true
        cap.interval = PreviewSwap.capMs(isPdf)
        cap.restart()
        Qt.callLater(root.check)
    }

    // A folder wait keeps the live picture under its own fallback, so the old work's cap stops here.
    function stopCap() { cap.stop() }

    function captured() {
        if (!root.capturing)
            return
        captureGuard.stop()
        root.syncArmed = false
        // holding first: with capturing cleared first the Loader would drop the frozen layer for one binding pass.
        root.holding = true
        root.capturing = false
        var pending = root.queued
        root.queued = []
        root.run(pending)
        root.check()
    }

    // True while an unanswered folder waits under the live picture: its own fallback bounds the wait.
    property bool folderHold: false

    function check() {
        if (root.folderHold)
            return
        if (root.holding && PreviewSwap.releaseIn(root.ready, root.started, root.shownAt, Date.now()) >= 0)
            root.land()
    }

    function release(end, fell) {
        root.endTimers(fell)
        captureGuard.stop()
        if (root.capturing || root.holding) {
            root.last = { ms: Date.now() - root.since, end: end }
            // The layer goes in this frame, but it lets go of its source only when its deferred delete runs: a hidden
            // source would leave this frame with neither drawn, and the late unref would ask for one frame more.
            if (layer.item)
                layer.item.sourceItem = null
        }
        root.syncArmed = false
        root.capturing = false
        root.holding = false
        root.started = false
        root.fellBack = fell === true
        var pending = root.queued
        root.queued = []
        root.run(pending)
    }

    // Quick Look closing: nothing queued may run after it, and the picture goes with it.
    function cancel() {
        root.queued = []
        root.release("cancelled", false)
    }

    function run(changes) {
        for (var i = 0; i < changes.length; i++) {
            if (changes[i])
                changes[i]()
        }
    }

    // tests/preview-swap.qml reparents its body under the picture; the default alias
    // covers declarative children and this covers the one runtime move.
    function contentItem() { return content }

    function describe() {
        return { holding: root.holding, capturing: root.capturing, fellBack: root.fellBack, holds: root.holds,
                 fallbacks: root.fallbacks, bursts: root.bursts, heldFrames: root.heldFrames,
                 midFrames: root.midFrames, loadingFrames: root.loadingFrames, last: root.last, shownMs: root.shownMs }
    }

    onReadyChanged: {
        if (root.ready)
            root.fellBack = false
        root.readyNow()
    }
    onVisibleChanged: if (!root.visible) root.release("hidden", false)

    // When this swap put the loading state on screen, 0 while none stands, and how long the last one stood.
    // Timing: it stands Swap.MIN_SHOW_MS from then, across a burst and a new hold, until a whole preview lands.
    property double shownAt: 0
    property int shownMs: 0

    // A whole preview lets go now, or once the loading state on screen has stood its minimum.
    function land() {
        var wait = PreviewSwap.releaseIn(root.ready, root.started, root.shownAt, Date.now())
        if (wait > 0) {
            minShow.interval = wait
            minShow.restart()
        } else {
            root.release("landed", false)
        }
    }

    // Past the cap the content draws the loading state, and the held picture is taken again from it.
    // Order: the picture retakes in the next frame, and the new preview lands under it once the minimum is spent.
    function fallBack() {
        var held = root.holding && layer.item !== null
        var next = PreviewSwap.fallBack(held, root.shownAt, Date.now())
        root.shownAt = next.shownAt
        if (!next.keeps) {
            root.release("expired", true)
            return
        }
        root.fellBack = true
        layer.item.scheduleUpdate()
        minShow.interval = next.left
        minShow.restart()
    }

    // A fallback or a burst starts a loading state; anything else ends it, and a whole preview says how long it stood.
    function shown(fell) {
        if (fell === true) {
            if (root.shownAt === 0)
                root.shownAt = Date.now()
            return
        }
        if (root.shownAt > 0 && root.ready)
            root.shownMs = Date.now() - root.shownAt
        root.shownAt = 0
    }

    function endTimers(fell) {
        cap.stop()
        minShow.stop()
        root.shown(fell)
    }

    // A preview turning whole while nothing is held is drawn live, which ends the loading state it replaced.
    function readyNow() {
        if (root.ready && !root.holding && !root.capturing)
            root.shown(false)
        root.check()
    }

    // The loading state has stood its minimum: a whole preview lands, and one still building goes live so the mark can crawl.
    Timer {
        id: minShow
        repeat: false
        onTriggered: {
            if (!root.holding || root.folderHold)
                return
            if (PreviewSwap.releaseIn(root.ready, root.started, root.shownAt, Date.now()) < 0)
                root.release("expired", true)
            else
                root.land()
        }
    }

    Item {
        id: content
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            anchors.margins: root.groundInset
            radius: root.groundRadius
            color: root.ground
            visible: root.capturing || root.holding
        }
    }

    // The picture: the content drawn once into a texture that then stops updating, shown in its place.
    Loader {
        id: layer
        anchors.fill: parent
        active: root.capturing || root.holding
        sourceComponent: ShaderEffectSource {
            sourceItem: root.captureSource !== null ? root.captureSource : content
            hideSource: root.capturing || root.holding
            visible: root.capturing || root.holding
            live: false
            onScheduledUpdateCompleted: root.captured()
        }
    }

    // While a picture stands for the preview, the pointer reaches nothing under it: no hover, wheel or press.
    MouseArea {
        anchors.fill: parent
        enabled: root.capturing || root.holding
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onWheel: function (wheel) { wheel.accepted = true }
    }

    Timer {
        id: cap
        repeat: false
        onTriggered: {
            if (root.folderHold)
                return
            if (!root.holding && !root.capturing)
                return
            root.fallbacks += 1
            root.fallBack()
        }
    }

    // The first sync queues a repaint, so the change runs after it; the basic loop emits inside the frame, so it waits for scheduledUpdateCompleted.
    Connections {
        target: root.syncArmed ? root.Window.window : null
        function onAfterSynchronizing() { if (root.syncQueued) root.captured() }
    }
    function markSyncQueued() { root.syncQueued = root.syncArmed }

    // A window that is not drawing never completes a capture, so the change goes ahead unheld.
    Timer {
        id: captureGuard
        interval: PreviewSwap.CAPTURE_MS
        repeat: false
        onTriggered: if (root.capturing) root.release("uncaptured", false)
    }

    // afterAnimating runs on this thread just before each frame is synchronised, so it sees what that frame draws.
    // Live from the first hold until ready lands after the release, so a half-built frame is never drawn uncounted; an idle window still pays nothing.
    Connections {
        target: (root.capturing || root.holding || !root.ready) ? root.Window.window : null
        function onAfterAnimating() {
            var source = root.captureSource !== null ? root.captureSource : content
            if (!root.syncArmed && root.capturing && root.visible && layer.item !== null && source.width > 0
                    && source.height > 0) {
                root.syncArmed = true
                root.syncQueued = false
                Qt.callLater(root.markSyncQueued)
            }
            if (!root.visible)
                return
            var kind = PreviewSwap.frameKind(root.capturing || root.holding, root.ready, root.fellBack,
                                             root.holding && root.shownAt > 0)
            if (kind === "held")
                root.heldFrames += 1
            else if (kind === "mid")
                root.midFrames += 1
            else if (kind === "loading")
                root.loadingFrames += 1
        }
    }
}
