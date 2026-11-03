.import "../../ui/js/Tabs.js" as Tabs
.import "tabsfixture.js" as Fixture
.import "../../ui/js/Swap.js" as Swap

// What a tab switch restores and what it must re-list: issues 91 and 93, nixfred. The stub pane
// is tests/js/tabsfixture.js, shared with tests/js/tabs.js.

function run(check) {
    // Issue 93, nixfred: a search begun in home walks home, so its scope is where the user already
    // was. Dropping it leaves the pane's rows on the walk's results, and a destination equal to that
    // scope used to look like the one switch that re-lists nothing: the new tab showed search rows.
    var scoped = Fixture.pane("/home/gm")
    scoped.searchMode = "results"
    scoped.searchQuery = "gm"
    scoped.searchFrom = "/home/gm"
    Tabs.openNew(scoped)
    check("a tab opened onto the scope its search walked lists it again",
          scoped.listed.join(","), "/home/gm")

    var switching = Fixture.pane("/home/gm")
    Tabs.openNew(switching)
    switching.listed = []
    switching.searchMode = "results"
    switching.searchQuery = "gm"
    switching.searchFrom = "/home/gm"
    Tabs.selectAt(switching, 0)
    check("switching to a tab standing on that scope lists it again",
          switching.listed.join(","), "/home/gm")

    var closing = Fixture.pane("/home/gm")
    Tabs.openNew(closing)
    closing.listed = []
    closing.searchMode = "results"
    closing.searchQuery = "gm"
    closing.searchFrom = "/home/gm"
    Tabs.closeAt(closing, 1)
    check("closing a searching tab onto one on that scope lists it again",
          closing.listed.join(","), "/home/gm")

    // Issue 94, nixfred: a selection is row indices, and the one switch that re-lists nothing was
    // restoring it verbatim. Two things renumber the rows under a hidden tab and neither was checked.
    var same = Fixture.pane("/home/gm/Work")
    same.selection.toggle(3)
    same.selection.toggle(4)
    var unchanged = Tabs.snapshot(same)
    same.clearSelection()
    Tabs.apply(same, unchanged)
    check("an unchanged directory restores the selection it recorded",
          same.selectedIndices().join(","), "3,4")

    var reread = Fixture.pane("/home/gm/Work")
    reread.selection.toggle(3)
    reread.selection.toggle(4)
    var stale = Tabs.snapshot(reread)
    reread.backend.listRequests += 1
    Tabs.apply(reread, stale)
    check("a listing re-read while the tab was hidden carries none of it back",
          reread.selectedIndices().join(","), "")

    var reordered = Fixture.pane("/home/gm/Work")
    reordered.selection.toggle(3)
    reordered.thumbState = "stale"
    reordered.dirSizeState = "stale"
    reordered.tabs = { items: [], index: 0, pendingCursor: -1, pendingSortBy: "", pendingSortDesc: false }
    var otherOrder = Tabs.snapshot(reordered)
    otherOrder.sortBy = "size"
    otherOrder.sortDesc = true
    Tabs.apply(reordered, otherOrder)
    check("a different order in the other tab drops the selection and both row-indexed caches",
          reordered.selectedIndices().length + "|" + (reordered.thumbState === "stale") + "|" + (reordered.dirSizeState === "stale"),
          "0|false|false")
    check("and the order that tab recorded is the one asked for, with its first window",
          reordered.sorted.join(",") + "|" + reordered.backend.sortBy + ":" + reordered.backend.sortDesc
          + "|" + reordered.windows.join(","), "size:true|size:true|0:40")

    // A half-typed search or a filter leaves the pane's own rows in place, so only "results" re-lists:
    // widening that test would re-read the directory and drop the selection on a switch with one open.
    var typing = Fixture.pane("/home/gm")
    typing.selection.toggle(2)
    Tabs.openNew(typing)
    typing.listed = []
    typing.searchMode = "typing"
    Tabs.selectAt(typing, 0)
    check("switching with the search field open but no results re-lists nothing",
          typing.listed.join(","), "")
    check("and the tab's own selection comes back rather than being dropped",
          typing.selectedIndices().join(","), "2")

    // The dotfile answer is the tab's own. One tab turns dotfiles on, which writes the standing
    // preference too; switching back to the tab that had them off used to list them anyway, because
    // ui/Pane.qml re-read that preference on the way into every listing.
    var dots = Fixture.pane("/home/gm")
    Tabs.openNew(dots)
    dots.showHidden = true
    dots.preferenceHidden = true
    dots.path = "/home/gm/Work"
    dots.listed = []
    Tabs.selectAt(dots, 0)
    check("a tab that had dotfiles off keeps them off when the other tab turned them on",
          dots.showHidden, false)
    check("and the switch is a re-listing, because the rows it wants are not the ones on screen",
          dots.listed.join(","), "/home/gm")
    // The listing swap keeps rows on screen only in the view they were listed in, see ui/js/Swap.js.
    check("and in the same view it lets the swap hold the rows on screen until it lands",
          dots.clearedAtOnce, false)
    var viewed = Fixture.pane("/home/gm")
    Tabs.openNew(viewed)
    viewed.viewMode = "grid"
    viewed.path = "/home/gm/Work"
    viewed.listed = []
    Tabs.selectAt(viewed, 0)
    check("a switch to a tab in another view clears at once rather than drawing these rows in that view",
          viewed.listed.join(",") + "|" + viewed.viewMode + "|" + viewed.clearedAtOnce, "/home/gm|list|true")

    // Issue 91, nixfred: an order the fresh listing already has is spent on that same reply, cursor
    // and all. Left pending it revived on the reply answering the user's next sort and reverted it.
    var already = Fixture.pane("/home/gm/a")
    already.tabs = { items: [], index: 0, pendingCursor: 9, pendingSelected: null,
                     pendingSortBy: "name", pendingSortDesc: false }
    Tabs.applyPending(already)
    check("an order the listing already has asks for no sort", already.sorted.length, 0)
    check("and the cursor is restored on that same reply", already.cursorIndex, 9)
    check("and the pending order is spent", already.tabs.pendingSortBy, "")
    already.backend.sort("size", true)
    already.sorted = []
    already.tabs.pendingCursor = -1
    Tabs.applyPending(already)
    check("so a later user sort survives the reply that answers it",
          already.sorted.length + "|" + already.backend.sortBy + ":" + already.backend.sortDesc, "0|size:true")

    // A listing past its deadline is let go by the tab operation that lists and left standing by one that lists nothing.
    function waitingTabs() {
        var w = Fixture.pane("/home/gm")
        Tabs.openNew(w)
        w.path = "/home/gm/Work"
        w.listed = []
        w.listInFlight = true
        w.listingState = "waiting"
        w.stateMessage = "That folder is not responding."
        return w
    }
    function wait(w) { return w.listInFlight + "|" + w.listingState + "|" + w.said.length }
    var picked = waitingTabs()
    Tabs.selectAt(picked, 0)
    check("switching tabs past the wait lists the tab's folder", picked.listed.join(",") + "|" + wait(picked), "/home/gm|false|loading|0")
    var current = waitingTabs()
    Tabs.selectAt(current, 1)
    check("selecting the current tab lists nothing and keeps the wait", current.listed.length + "|" + wait(current), "0|true|waiting|0")
    var alike = waitingTabs()
    alike.tabs.items[0].path = "/home/gm/Work"
    Tabs.selectAt(alike, 0)
    check("a tab on the folder being shown still lists, the held listing is not its answer", alike.listed.join(",") + "|" + wait(alike), "/home/gm/Work|false|loading|0")
    var opened = waitingTabs()
    Tabs.openNew(opened)
    check("a new tab past the wait lists its folder", opened.listed.join(",") + "|" + Tabs.count(opened) + "|" + wait(opened), "/home/gm/Work|3|false|loading|0")
    var dropped = waitingTabs()
    Tabs.closeAt(dropped, 0)
    check("closing a hidden tab lists nothing and keeps the wait", dropped.listed.length + "|" + Tabs.count(dropped) + "|" + wait(dropped), "0|1|true|waiting|0")
    var closed = waitingTabs()
    Tabs.closeAt(closed, 1)
    check("closing the current tab lists the one it lands on", closed.listed.join(",") + "|" + wait(closed), "/home/gm|false|loading|0")
    var moved = waitingTabs()
    Tabs.move(moved, 0, 1)
    check("reordering lists nothing and keeps the wait",
          moved.tabs.items.map(function (tab) { return tab.path }).join(",") + "|" + moved.listed.length + "|" + wait(moved), "/home/gm/Work,/home/gm|0|true|waiting|0")
    var received = waitingTabs()
    check("a waiting pane takes a dropped tab", Tabs.canReceive(received), true)
    check("and lists its folder", Tabs.receiveTab(received, JSON.stringify(["222", "tok", "/tmp/r", "list", ""]), 1) + "|" + received.listed.join(",") + "|" + wait(received), "true|/tmp/r|false|loading|0")
    var sent = waitingTabs()
    check("a tab moved out of a waiting pane closes", Tabs.closeTabAfterMove(sent, 0) + "|" + Tabs.count(sent) + "|" + wait(sent), "closed|1|true|waiting|0")
    var direct = Fixture.pane("/tmp/one")
    Tabs.openNew(direct)
    direct.listingPath = direct.path = "/tmp/two"
    direct.listInFlight = true
    direct.superseded = false
    Tabs.closeAt(direct, 1)
    check("a direct close while loading closes the tab, refusing nothing", Tabs.count(direct) + "|" + direct.said.join(""), "1|")
    check("and the surviving tab is current, listed over the one out", Tabs.currentIndex(direct) + "|" + direct.path + "|" + direct.superseded, "0|/tmp/one|true")
    // The path the fixture's openWithoutHistory received from Tabs.closeAt, not the listingPath the stub wrote.
    var asked = direct.listed[direct.listed.length - 1]
    check("and the closed tab's late listed line is dropped, the surviving tab's is not", asked + "|" + Swap.onListed({}, true, "/tmp/two", asked, false) + "|" + (Swap.onListed({}, true, "/tmp/one", asked, false) !== Swap.DROP), "/tmp/one|" + Swap.DROP + "|true")
}
