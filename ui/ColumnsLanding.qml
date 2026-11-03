import QtQuick
import "js/Columns.js" as Columns
import "js/Swap.js" as Swap

// A changing ancestor keeps its own slot's last rows until the replacement or the listing swap's cap.
Item {
    id: root
    property var area: null
    property string target: ""
    property var held: ({})
    property var previous: null
    property int version: 0
    property bool expired: false
    property bool minimum: false
    property double startedAt: 0
    property double markSince: 0

    function begin(carry, asks) {
        var now = Date.now()
        var next = {}, inheritedSince = 0, old = Columns.neighbourAsks(root.area.pane.path, root.area.width, root.area.columnsLimit)
        if (carry) {
            for (var i = 1; i <= asks.length; i++) {
                var path = asks[asks.length - i], from = old[old.length - i]
                var key = root.area.peekKey(path)
                var ready = root.area.peeked[key] !== undefined && root.area.peekOrders[key] === root.area.orderOf(path)
                if (ready || path === carry.seed && carry.rows !== null || !from) continue
                var source = root.stateFor(from), reading = source !== null && root.isLoading(source, from)
                var since = reading ? source.held[from].shownAt : undefined
                next[path] = { rows: root.area.rowsFor(from), mode: root.area.deniedMode(from), ready: false,
                               loading: reading, shownAt: since }
                if (since !== undefined) inheritedSince = Math.max(inheritedSince, since)
            }
        }
        // Only a carried superseding request keeps the previous landing's cap and shown minimum.
        if (!carry) root.previous = null
        else if (root.target === root.area.pane.path) {
            root.previous = Object.keys(root.held).length ? {
                target: root.target, held: root.held, expired: root.expired, minimum: root.minimum,
                startedAt: root.startedAt, markSince: root.markSince
            } : null
        }
        root.target = carry ? carry.target : ""
        root.held = next
        root.expired = false
        root.minimum = inheritedSince > 0 && inheritedSince + Swap.MIN_SHOW_MS > now
        root.startedAt = now
        root.markSince = inheritedSince
        root.version++
        root.armCap(); root.armMinimum()
    }
    function stateFor(path) {
        if (root.version < 0) return null
        var state = root.area.pane.path === root.target ? root : root.previous
        return state && state.target === root.area.pane.path && state.held[path] !== undefined ? state : null
    }
    function waiting(path) { return root.stateFor(path) !== null }
    function isLoading(state, path) { return state.expired || state.held[path].loading === true }
    function loading(path) { var state = root.stateFor(path); return state !== null && root.isLoading(state, path) }
    function rows(path, ordinary) {
        var state = root.stateFor(path)
        return state === null ? ordinary : root.isLoading(state, path) ? [] : state.held[path].rows
    }
    function mode(path, ordinary) {
        var state = root.stateFor(path)
        return state === null ? ordinary : root.isLoading(state, path) ? -1 : state.held[path].mode
    }

    function remove(path, state) {
        var next = Object.assign({}, state.held)
        delete next[path]
        state.held = next
        if (!Object.keys(next).length) {
            state.minimum = false
            if (state !== root) root.previous = null
        }
        root.version++
        root.armCap(); root.armMinimum()
    }
    function answered(path) {
        for (var state of [root, root.previous]) {
            if (!state || state.held[path] === undefined) continue
            if (root.isLoading(state, path) && state.minimum) {
                var next = Object.assign({}, state.held)
                next[path] = Object.assign({}, next[path], { ready: true })
                state.held = next
                root.version++
            } else root.remove(path, state)
        }
    }
    function landed() {
        if (root.area.pane.path !== root.target) return
        root.previous = null
        root.version++
        root.armCap(); root.armMinimum()
    }
    // Only the LoadingState's shown signal starts the minimum, including a mark built while its column is hidden.
    function markShown(path, shown) {
        var state = root.stateFor(path)
        if (!shown || !state || !root.isLoading(state, path)) return
        // Bookkeeping must not invalidate loadingRows while its Loader reports shown.
        var now = Date.now()
        state.held[path].shownAt = now
        state.markSince = now
        state.minimum = true
        root.armMinimum()
    }
    // The same two timers serve both landings without restarting either deadline.
    function armCap() {
        cap.stop()
        var left = -1, now = Date.now()
        for (var state of [root, root.previous]) {
            if (!state || state.expired || !Object.keys(state.held).length) continue
            var owed = Math.max(0, state.startedAt + Swap.CAP_MS - now)
            left = left < 0 ? owed : Math.min(left, owed)
        }
        if (left >= 0) { cap.interval = left; cap.start() }
    }
    function armMinimum() {
        minShow.stop()
        var left = -1, now = Date.now()
        for (var state of [root, root.previous]) {
            if (!state || !state.minimum) continue
            var owed = Math.max(0, state.markSince + Swap.MIN_SHOW_MS - now)
            left = left < 0 ? owed : Math.min(left, owed)
        }
        if (left >= 0) { minShow.interval = left; minShow.start() }
    }
    function expire() {
        var now = Date.now()
        for (var state of [root, root.previous])
            if (state && !state.expired && state.startedAt + Swap.CAP_MS <= now) state.expired = true
        root.version++
        root.armCap()
    }
    function releaseMinimum() {
        var now = Date.now()
        for (var state of [root, root.previous]) {
            if (!state || !state.minimum || state.markSince + Swap.MIN_SHOW_MS > now) continue
            state.minimum = false
            var paths = Object.keys(state.held)
            for (var path of paths) if (state.held[path].ready) root.remove(path, state)
        }
        root.armMinimum()
    }
    Timer { id: cap; onTriggered: root.expire() }
    Timer { id: minShow; onTriggered: root.releaseMinimum() }
}
