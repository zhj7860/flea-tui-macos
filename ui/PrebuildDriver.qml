import QtQuick
import QtQml.Models

// One driver for List, Grid and Columns: quiet turns park the next landing's delegates, adopted with 0 built.
QtObject {
    id: root

    required property Item view
    required property var model
    property var pane: null
    // The delegates a full landing from the top lays out; every delegate the view holds counts against it, pooled ones too.
    property int limit: 0
    // The view's own hold, such as the cursor restore after a show; a start while it stands waits for it to clear.
    property bool held: false
    // What the view does to a delegate it parks past its count, and to one a landing takes back.
    property var park: function (cell) {}
    property var adopt: function (cell) {}
    // False parks the driver and drops the parked delegates; a non-negative cap bounds it for measurement.
    property bool enabled: true
    property int max: -1
    property int rowsPerTick: 3
    // One frame at 60 Hz: the quiet-turn cadence, the key hold and every restart.
    readonly property int frameMs: 16
    // Kept wake times, so the suites read the last tick's age; older ones drop.
    readonly property int keepTicks: 400

    property int parkedCount: 0
    // Delegates created and destroyed, parked and pooled ones included; the difference is every delegate the view holds.
    property int createdCount: 0
    property int destroyedCount: 0
    readonly property int want: Math.max(0, (root.max < 0 ? root.limit : Math.min(root.limit, root.max)) - (root.createdCount - root.destroyedCount))
    // Work ticks oldest first, and every wake with the last one's time: a driver that stops shows both still.
    property var tickAt: []
    property int wakes: 0
    property double wakeAt: -1
    // The first window settles before quiet turns build: the first landing holds the driver, so startup builds no parked rows.
    property double countAt: -1
    readonly property int holdMs: 1000

    // Read as bindings, since not every pane declares a listing flight or an input time.
    readonly property bool paneHeld: !!root.pane && (root.pane.listInFlight === true || root.pane.renamingIndex >= 0)
    readonly property real keyAt: root.pane && root.pane.inputAt ? root.pane.inputAt : 0
    readonly property bool quiet: !root.view.moving && !root.model.warm
    onPaneHeldChanged: if (!root.paneHeld) root.start()
    onQuietChanged: if (root.quiet) root.start()
    onHeldChanged: if (!root.held) root.start()
    onLimitChanged: root.start()
    onEnabledChanged: if (root.enabled) root.start(); else root.drop()
    // A hidden view holds no delegates, so the hide drops the parked ones and the show refills them.
    readonly property bool shown: root.view.visible
    onShownChanged: if (root.shown) root.start(); else root.drop()

    // One shot per wake: a timed hold waits once for its end, any other hold stops until its own change starts the driver.
    readonly property Timer timer: Timer { interval: root.frameMs; onTriggered: root.tick() }

    // Ms until a tick may build: 0 now, what is left of the first landing's hold or a key's frame, or -1 while held until a start.
    function wait() {
        if (!root.enabled || !root.view.visible || root.held || !root.pane || root.paneHeld) return -1
        if (!root.quiet || root.countAt < 0) return -1
        var now = Date.now()
        return Math.max(0, root.countAt + root.holdMs - now, root.keyAt + root.frameMs - now)
    }
    function start() {
        if (root.enabled && root.pane && root.view.visible && !root.held && !root.timer.running) {
            root.timer.interval = root.frameMs
            root.timer.start()
        }
    }
    // A key or a cursor move pushes the next tick a frame out.
    function kick() {
        if (root.timer.running) {
            root.timer.interval = root.frameMs
            root.timer.restart()
        }
    }
    // A landing takes parked delegates into its count with no reuse signal, so each count change adopts them.
    function landed() {
        var kids = root.view.contentItem.children
        for (var i = 0; i < kids.length; i++)
            if (kids[i].prebuilt === true && kids[i].index < root.view.count) root.adoptCell(kids[i])
        if (root.countAt < 0 && root.view.count > 0 && root.pane) root.countAt = Date.now()
        root.start()
    }
    // A built delegate past the count parks, unless a warm fill laid it out for the pool; true when it parked.
    function built(cell) {
        root.createdCount += 1
        if (root.model.warm || cell.DelegateModel.inPersistedItems !== true && cell.index >= 0 && cell.index < root.view.count) return false
        root.parkCell(cell)
        return true
    }
    function gone(cell) {
        root.destroyedCount += 1
        if (cell.prebuilt === true) root.parkedCount -= 1
    }
    function parkCell(cell) {
        if (cell.prebuilt === true) return
        cell.prebuilt = true
        root.parkedCount += 1
        root.park(cell)
    }
    function adoptCell(cell) {
        if (cell.prebuilt !== true) return
        cell.prebuilt = false
        root.parkedCount -= 1
        cell.DelegateModel.inPersistedItems = false
        root.adopt(cell)
    }
    // The lowest index past the count with no delegate, so the parked rows are the ones the next landing draws first.
    function hole() {
        var kept = root.model.persistedItems, at = root.view.count
        for (var k = 0; k < kept.count; k++) {
            var i = kept.get(k).itemsIndex
            if (i > at) break
            if (i === at) at += 1
        }
        return at
    }
    function tick() {
        root.wakes += 1
        root.wakeAt = Date.now()
        var wait = root.wait()
        if (wait !== 0) {
            if (wait > 0) { root.timer.interval = wait; root.timer.start() }
            return
        }
        var parked = root.parkedCount
        for (var n = root.rowsPerTick; n > 0 && root.want > 0; n--) {
            var cell = root.model.items.create(root.hole())
            if (!cell) break
            // A create takes a pooled delegate before it builds one, and that one parks as a built one does.
            root.parkCell(cell)
        }
        // A tick that parked nothing found no work left, so the driver stops until the next start.
        if (root.parkedCount === parked) return
        root.tickAt.push(root.wakeAt)
        if (root.tickAt.length > root.keepTicks) root.tickAt = root.tickAt.slice(-root.keepTicks)
        root.timer.interval = root.frameMs
        root.timer.start()
    }
    function drop() {
        root.timer.stop()
        // removeGroups only warns on a bad index or count, and both come from the group itself.
        var kept = root.model.persistedItems
        if (kept.count > 0) kept.removeGroups(0, kept.count, "persistedItems")
    }
}
