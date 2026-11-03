import QtQuick
import "js/Filter.js" as Filter
import "js/Menu.js" as Menu
import "js/Ops.js" as Ops
import "js/Search.js" as Search
import "js/Tags.js" as Tags

// One pane's file tags, built only when a listing first carries one or a tag key or menu first asks.
Item {
    id: root
    required property var pane
    // The 88 px slot stands on every row of a folder once a tagged row has been seen in it.
    property bool latched: false
    // Every tag this session has seen set, which is what the rail's TAGS section lists.
    property var inUse: ({})
    // The changes sent and not yet answered, oldest first; each settagged answer or settags refusal takes the oldest.
    property var pending: []
    // The backend's read of a selection reaching past the held window, and the one still out.
    property var asked: null
    property var asking: null
    property int askId: 0

    // A rows reply is the whole held window; a fresh listing starts the latch over.
    function take(items, fresh) {
        var seen = Tags.stamp(items, root.latched, root.inUse, fresh)
        root.latched = seen.latched
        if (seen.grew) root.inUse = Object.assign({}, root.inUse)
    }

    // Each target's tags while every target is in the held window; null once one is outside it, where only the backend knows.
    function filesFor(indices) {
        var files = []
        for (var i = 0; i < indices.length; i++) {
            var row = root.pane.rowFor(indices[i])
            if (!row) return null
            files.push(row.tg || [])
        }
        return files
    }

    // Names the selection a backend read answers for: the numbering, the selection's version and, with no selection, the cursor.
    function selectionKey() {
        var pane = root.pane
        return pane.backend.heldListing + ":" + pane.selectionVersion + ":" + (pane.selectionCount() > 0 ? "" : pane.cursorIndex)
    }

    // The flyout's rows for the selection: seven tags with digit hints, then Remove all tags; absent until a backend read lands.
    function flyout() {
        var files = root.filesFor(Ops.targetIndices(root.pane))
        if (files !== null) return Tags.tagEntries(Tags.statesFor(files), Theme.tag.fallback)
        var asked = root.asked !== null && root.asked.key === root.selectionKey() ? root.asked : null
        return Tags.tagEntries(asked ? Tags.statesFrom(asked.applied, asked.mixed) : {}, Theme.tag.fallback)
    }

    // A selection past the held window asks what its rows carry (again: re-ask after a write); the answer redraws the flyout.
    function ask(again) {
        var rows = Ops.targetIndices(root.pane)
        if (rows.length === 0 || root.filesFor(rows) !== null) return
        var key = root.selectionKey()
        if (again !== true && ((root.asked !== null && root.asked.key === key) || (root.asking !== null && root.asking.key === key))) return
        root.askId += 1
        root.asking = { id: root.askId, key: key, listing: root.pane.backend.heldListing }
        root.pane.backend.send({ c: "tagstates", rows: rows, id: root.askId })
    }

    // A flyout choice toggles that tag over the selection, or clears every tag off it; the backend decides add or remove for all.
    function choose(name) {
        var rows = Ops.targetIndices(root.pane)
        if (rows.length === 0) return
        var clear = name === Tags.CLEAR_ID
        root.pending = root.pending.concat([{ tag: clear ? "" : name }])
        root.pane.backend.send({ c: "settags", rows: rows, op: clear ? "clear" : "toggle", tag: clear ? "" : name })
    }

    // T opens the Tags flyout straight from the listing, the same list the menu's Tags row opens.
    function openMenu() {
        var pane = root.pane
        if (pane.lockedTarget.length > 0) return
        if (!pane.canTag) {
            pane.message("This filesystem does not support file tags.", true)
            return
        }
        var menu = pane.contextMenu()
        if (!Menu.openAtCursor(pane, menu, Theme.spacing.rowPaddingX)) return
        for (var i = 0; i < menu.entries.length; i++) {
            if (menu.entries[i].action === "tags") {
                menu.openSubmenu(i)
                return
            }
        }
    }

    // A tag walks Home for that tag, an explicit walk like any search; esc returns to the listing.
    function openTag(name) {
        if (!name || !Search.takesQuery(root.pane)) return
        Filter.close(root.pane)
        Search.openQuery(root.pane, "tag:" + name)
    }

    // A tagstates answer for the read still out lands only in the numbering it was asked in.
    function statesDone(message) {
        var asking = root.asking
        if (asking === null || message.id !== asking.id) return
        root.asking = null
        if (message.listing !== asking.listing) return
        root.asked = { key: asking.key, applied: message.applied || [], mixed: message.mixed || [] }
        root.pane.contextMenu().refreshProviderRows()
    }

    // A settagged answer lands the oldest pending change: forget every read made before it, ask the visible window again, and say it when a file changed or a row was skipped.
    function setTaggedDone(message) {
        var change = root.pending.length > 0 ? root.pending[0] : null
        root.pending = root.pending.slice(1)
        var flyoutUp = root.pane.menuVisible === true
        // An open flyout keeps drawing its last read until the fresh one lands, so no box blanks between the two.
        if (!flyoutUp) root.asked = null
        root.asking = null
        if (!change) return
        root.pane.backend.window(root.pane.held, root.pane.windowSize)
        if (flyoutUp) root.ask(true)
        // The backend sends data and the UI words it: the changed sentence, the skipped one, or both.
        var line = Tags.doneLine(message.op, message.ok || 0, change.tag, message.skipped)
        if (line !== "") root.pane.message(line, false)
    }

    // A held window that lands while a flyout is up carries the tags just written; the menu's rows source follows it a turn later, so the redraw waits for that turn.
    Connections {
        target: root.pane
        function onRowsChanged() {
            var menu = root.pane.contextMenu()
            if (menu.submenuOpen === true) Qt.callLater(function() { menu.refreshProviderRows() })
        }
    }

    Connections {
        target: root.pane.backend
        function onTagStatesResult(message) { root.statesDone(message) }
        function onSettagged(message) { root.setTaggedDone(message) }
        // A refused settags answers its own pending change; a backend that stopped answers none of them.
        function onFailed(where, input) {
            if (where === "backend" || where === "read") {
                root.pending = []
                root.asked = null
                root.asking = null
            } else if (where === "settags" || (where === "stale" && input === "settags")) {
                root.pending = root.pending.slice(1)
            }
        }
    }
}
