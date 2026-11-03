.pragma library

.import "Anchor.js" as Anchor
.import "Format.js" as Format
.import "Nav.js" as Nav
.import "Swap.js" as Swap

// The status line a reload answers with, one whole sentence per count, each filled by Format.fill.
var WORDS = {
    one: "Reloaded · 1 row changed",
    many: "Reloaded · %1 rows changed"
}

// Sample input: 2 is "Reloaded · 2 rows changed", 1 is "Reloaded · 1 row changed".
function line(changed) {
    return changed === 1 ? WORDS.one : Format.fill(WORDS.many, Format.count(changed))
}

// A listing out refuses itself and a search owns its header, so both go quiet.
function begin(pane, wire) {
    if (Nav.loading(pane)) {
        pane.message(Swap.LOADING, false)
        return false
    }
    if (pane.searchMode.length > 0)
        return false
    // A reload past the wait retries the folder waited on, which a first listing has not yet made the pane's path.
    var waitedOn = pane.listingState === "waiting" ? Nav.trimSlash(pane.listingPath || "") : ""
    // A reload that lists lets a waiting listing go first, the way ui/Pane.qml openWithoutHistory does.
    Anchor.clearWaiting(pane)
    // Recent re-reads its history rather than re-listing its base, which is the root.
    if (pane.recentMode.length > 0) {
        pane.refresh("")
    } else {
        if (waitedOn.length > 0 && waitedOn !== pane.path) {
            pane.openWithoutHistory(waitedOn)
            return true
        }
        wire.anchor = Anchor.watched(pane, true, pane.anchorRowHeight)
    }
    // Set after the anchored re-read above, because opening the listing clears it first.
    pane.reloadFrom = pane.total
    pane.reloadChanged = -1
    return true
}

// Runs on every rows reply; only a manual reload owes a notice, said whenever rows changed.
function landed(pane) {
    if (pane.reloadFrom < 0)
        return ""
    // The backend counts added plus removed on a same-path re-list; a missing one falls back to net delta.
    var changed = pane.reloadChanged >= 0 ? pane.reloadChanged : Math.abs(pane.total - pane.reloadFrom)
    pane.reloadFrom = -1
    pane.reloadChanged = -1
    if (changed === 0)
        return ""
    var text = line(changed)
    pane.message(text, false)
    return text
}
