.import "../../ui/js/Swap.js" as Swap
.import "../../ui/js/PreviewSwap.js" as PreviewSwap
.import "sourcefixture.js" as Source

// A slow source on a fake clock: the screen changes inside 100 ms of the key, to the whole state or the loading state, and
// a drawn loading state stands Swap.MIN_SHOW_MS. Every time and state below comes from ui/js/Swap.js and PreviewSwap.js.

// A folder through ui/PaneSwap.qml's decisions, 1 ms a step from the key at 0, its listed and rows lines arriving at landsAt.
function slowListing(landsAt, held) {
    var state = Swap.begin(Swap.idle(), held ? "ready" : "loading", "", {}, 0)
    // Past a fallback Nav.forget leaves the pane loading; ui/LoadingState.qml shows at once through heldOff, else after its hold-off.
    var loadingAt = held ? -1 : 0
    var mark = 0
    var rowsAt = -1
    var whole = -1
    var action = ""
    var drawn = function () { return whole >= 0 ? action : state.holding ? "held" : mark > 0 ? "loading" : "blank" }
    var first = drawn()
    var changed = -1
    var to = ""
    for (var t = 1; t <= 1000 && whole < 0; t++) {
        // ui/PaneSwap.qml hold() runs its cap timer Swap.capLeft from the key.
        if (state.holding && Swap.capLeft(state, t) === 0) {
            state = Swap.expired(state)
            loadingAt = t
        }
        if (mark === 0 && loadingAt >= 0 && (state.fellBack || t - loadingAt >= Swap.markHoldOff("")))
            mark = t
        if (t === landsAt) {
            if (Swap.onListed(state, true, "/n", "/n", Swap.marked(mark, true, "", state.walk)) === Swap.KEEP)
                state = Swap.kept(state, { total: 3, path: "/n" })
            rowsAt = t
        }
        // A waiting rows line is taken again when the minShow timer runs out.
        if (rowsAt >= 0 && t >= rowsAt) {
            var left = Swap.marked(mark, true, "", state.walk) ? Swap.showLeft(mark, t) : 0
            action = Swap.onRows(state, true, true, left)
            if (action === Swap.WAIT)
                rowsAt = t + left
            else
                whole = t
        }
        if (changed < 0 && drawn() !== first) {
            changed = t
            to = drawn()
        }
    }
    return { changed: changed, to: to, action: action, whole: whole, stood: mark > 0 && whole >= 0 ? whole - mark : 0 }
}

// A held preview through ui/PreviewSwap.qml's decisions, its own work starting at 0 and whole at landsAt.
function slowPreview(landsAt, isPdf) {
    var s = { holding: true, ready: false, fellBack: false, shownAt: 0 }
    var minShowAt = -1
    var whole = -1
    var drawn = function () { return PreviewSwap.frameKind(s.holding, s.ready, s.fellBack, s.holding && s.shownAt > 0) || "landed" }
    // land(): a whole preview goes now, or when the minShow timer runs out.
    var land = function (t) {
        var wait = PreviewSwap.releaseIn(s.ready, true, s.shownAt, t)
        if (wait > 0) {
            minShowAt = t + wait
        } else if (wait === 0) {
            s.holding = false
            whole = t
        }
    }
    var first = drawn()
    var changed = -1
    var to = ""
    for (var t = 1; t <= 1000 && whole < 0; t++) {
        // start() runs the cap timer PreviewSwap.capMs from the preview's own work.
        if (s.holding && t === PreviewSwap.capMs(isPdf)) {
            var next = PreviewSwap.fallBack(true, s.shownAt, t)
            s.shownAt = next.shownAt
            s.fellBack = true
            if (next.keeps)
                minShowAt = t + next.left
            else
                s.holding = false
        }
        if (t === landsAt) {
            s.ready = true
            s.fellBack = false
            if (s.holding)
                land(t)
            else
                whole = t
        }
        if (s.holding && t === minShowAt) {
            if (PreviewSwap.releaseIn(s.ready, true, s.shownAt, t) < 0) {
                s.holding = false
                s.fellBack = true
            } else {
                land(t)
            }
        }
        if (changed < 0 && drawn() !== first) {
            changed = t
            to = drawn()
        }
    }
    return { changed: changed, to: to, whole: whole, stood: s.shownAt > 0 && whole >= 0 ? whole - s.shownAt : 0 }
}

function squashed(s) {
    return String(s).replace(/\s+/g, " ")
}

function run(check) {
    check("a fallback's first frame lands inside 100 ms of the key: the cap, then a frame each for input and its own draw and two for the Timer's 16 ms resolution, at 120 Hz",
          Swap.CAP_MS + 4 * 1000 / 120 <= 100, true)
    check("a loading state stands at least 100 ms, under which a change still reads as instant", Swap.MIN_SHOW_MS >= 100, true)
    check("no mark drawn owes nothing", Swap.showLeft(0, 5000), 0)
    check("a mark drawn 40 ms ago owes the rest of its minimum", Swap.showLeft(1000, 1040), Swap.MIN_SHOW_MS - 40)
    check("and one past its minimum owes nothing", Swap.showLeft(1000, 1000 + Swap.MIN_SHOW_MS + 1), 0)

    // The listing swap: rows held from a settled folder, and rows into a pane that had none to hold.
    var settled = Swap.begin(Swap.idle(), "ready", "", {}, 1000)
    check("rows landing while a loading state owes time wait for it",
          Swap.onRows(Swap.kept(Swap.expired(settled), { total: 3 }), true, true, 20), Swap.WAIT)
    check("and land once it owes none", Swap.onRows(Swap.kept(Swap.expired(settled), { total: 3 }), true, true, 0), Swap.LAND)
    check("a mark already drawn keeps an unheld listing's listed line for its rows",
          Swap.onListed(Swap.idle(), true, "/n", "/n", true), Swap.KEEP)
    var loads = [40, 90, 110, 140, 400]
    var held = loads.map(function (ms) { return slowListing(ms, true) })
    var unheld = loads.map(function (ms) { return slowListing(ms, false) })
    check("held rows landing at 40, 90, 110, 140 and 400 ms change the screen at",
          held.map(function (r) { return r.changed + " " + r.to }).join(", "), "40 land, 66 loading, 66 loading, 66 loading, 66 loading")
    check("and draw the whole folder at", held.map(function (r) { return r.whole }).join(","), "40,166,166,166,400")
    check("an unheld listing's rows draw the whole folder at the same times",
          unheld.map(function (r) { return r.whole + " " + r.action }).join(", "), "40 apply, 166 land, 166 land, 166 land, 400 land")
    check("an unheld listing changes the screen at",
          unheld.map(function (r) { return r.changed + " " + r.to }).join(", "), "40 apply, 66 loading, 66 loading, 66 loading, 66 loading")
    check("no listing changes the screen later than the cap",
          held.concat(unheld).every(function (r) { return r.changed > 0 && r.changed <= Swap.CAP_MS }), true)
    check("and no loading state drawn is replaced before its minimum",
          held.concat(unheld).every(function (r) { return r.stood === 0 || r.stood >= Swap.MIN_SHOW_MS }), true)
    check("a walk's mark keeps the longer hold-off", Swap.markHoldOff("results"), Swap.HOLD_MS)
    check("and a walk's or a search's lines never wait on a drawn mark, a directory listing's do",
          [Swap.marked(1000, true, "results", true), Swap.marked(1000, true, "typing", false), Swap.marked(1000, true, "", true),
           Swap.marked(1000, false, "", false), Swap.marked(0, true, "", false), Swap.marked(1000, true, "", false)].join(","),
          "false,false,false,false,false,true")
    var paneStates = Source.source("ui/PaneStates.qml")
    check("the pane's loading mark takes its hold-off from the swap",
          paneStates.indexOf("holdOffMs: Swap.markHoldOff(root.pane.searchMode)") >= 0, true)
    check("and tells its swap when it is drawn", paneStates.indexOf("onShownChanged: root.pane.swap.markShown(shown)") >= 0, true)
    var loading = squashed(Source.source("ui/LoadingState.qml"))
    check("the mark draws at once on a fallback and otherwise when its hold-off timer runs out, the two terms slowListing models",
          paneStates.indexOf("heldOff: root.pane.swap.fellBack") >= 0 && loading.indexOf("readonly property bool shown: root.visible && (root.armed || root.heldOff)") >= 0
          && loading.indexOf("interval: root.holdOffMs running: root.visible onTriggered: root.armed = true") >= 0 && loading.indexOf("visible: root.armed || root.heldOff") >= 0, true)
    var paneSwap = Source.source("ui/PaneSwap.qml")
    check("the swap's cap timer runs what Swap.capLeft answers",
          squashed(Source.block(paneSwap, "function hold(", "ui/PaneSwap.qml")).indexOf("cap.interval = Swap.capLeft(root.phase, now) cap.restart()") >= 0
          && squashed(paneSwap).indexOf("Timer { id: cap repeat: false onTriggered: {") >= 0, true)
    check("the swap keeps a listed line while the mark is drawn",
          squashed(Source.block(paneSwap, "function takeListed(", "ui/PaneSwap.qml")).indexOf("var marked = Swap.marked(root.markSince, root.pane.listInFlight, root.pane.searchMode, root.phase.walk) var action = Swap.onListed(root.phase, root.pane.listInFlight, path, root.pane.listingPath, marked)") >= 0, true)
    var take = squashed(Source.block(paneSwap, "function takeRows(", "ui/PaneSwap.qml"))
    check("and holds rows back for the rest of the mark's minimum",
          take.indexOf("var marked = Swap.marked(root.markSince, root.pane.listInFlight, root.pane.searchMode, root.phase.walk) var left = marked ? Swap.showLeft(root.markSince, Date.now()) : 0 var action = Swap.onRows(root.phase, root.pane.listInFlight, root.pane.listedSeen, left)") >= 0
          && take.indexOf("minShow.interval = left minShow.restart()") >= 0, true)
    // Two rows lines can arrive inside the minimum: an anchor window follows the list's own window while the listing is out.
    var flat = squashed(paneSwap)
    var stop = squashed(Source.block(paneSwap, "function stopWaiting(", "ui/PaneSwap.qml"))
    var ended = squashed(Source.block(paneSwap, "function onListInFlightChanged(", "ui/PaneSwap.qml"))
    check("a second rows line inside the minimum is kept behind the first, not written over it",
          paneSwap.indexOf("property var waiting: []") >= 0
          && take.indexOf("root.waiting.push({ start: start, items: items, kinds: kinds, listing: listing, gen: gen })") >= 0, true)
    check("and every kept line lands with its own gen in arrival order when the minimum ends, the queue cleared on every stop",
          flat.indexOf("for (var i = 0; i < rows.length; i++) root.takeRows(rows[i].start, rows[i].items, rows[i].kinds, rows[i].listing, rows[i].gen)") >= 0
          && stop.indexOf("root.waiting = []") >= 0 && ended.indexOf("if (root.pane.listInFlight) return") >= 0
          && ended.indexOf("root.stopWaiting()") > ended.indexOf("if (root.pane.listInFlight) return"), true)

    // The preview swap: an image and a PDF whole at the same times, under a picture that takes the loading state.
    check("a preview not yet whole is not let go", PreviewSwap.releaseIn(false, true, 0, 5000), -1)
    check("nor one whose own work has not started", PreviewSwap.releaseIn(true, false, 0, 5000), -1)
    check("a whole preview with no loading state on screen goes at once", PreviewSwap.releaseIn(true, true, 0, 5000), 0)
    check("a picture of the loading state counts as the loading state", PreviewSwap.frameKind(true, false, true, true), "loading")
    var images = loads.map(function (ms) { return slowPreview(ms, false) })
    var pdfs = loads.map(function (ms) { return slowPreview(ms, true) })
    check("previews whole at 40, 90, 110, 140 and 400 ms change the screen at",
          images.map(function (r) { return r.changed + " " + r.to }).join(", "), "40 landed, 66 loading, 66 loading, 66 loading, 66 loading")
    check("and draw the whole preview at", images.map(function (r) { return r.whole }).join(","), "40,166,166,166,400")
    check("a PDF draws its page at the same times", pdfs.map(function (r) { return r.whole }).join(","), "40,166,166,166,400")
    check("no preview changes the screen later than the cap",
          images.concat(pdfs).every(function (r) { return r.changed > 0 && r.changed <= Swap.CAP_MS }), true)
    check("and no loading state drawn is replaced before its minimum",
          images.concat(pdfs).every(function (r) { return r.stood === 0 || r.stood >= Swap.MIN_SHOW_MS }), true)
    var previewSwap = Source.source("ui/PreviewSwap.qml")
    var fall = squashed(Source.block(previewSwap, "function fallBack(", "ui/PreviewSwap.qml"))
    check("the cap gives the held picture the loading state the content now draws, as PreviewSwap.fallBack answers",
          fall.indexOf("var next = PreviewSwap.fallBack(held, root.shownAt, Date.now()) root.shownAt = next.shownAt if (!next.keeps)") >= 0
          && fall.indexOf("root.fellBack = true layer.item.scheduleUpdate() minShow.interval = next.left") >= 0, true)
    check("and the cap timer runs PreviewSwap.capMs from the preview's own start",
          squashed(Source.block(previewSwap, "function start(", "ui/PreviewSwap.qml")).indexOf("cap.interval = PreviewSwap.capMs(isPdf) cap.restart()") >= 0, true)
    check("and a whole preview waits out what the loading state is owed",
          squashed(Source.block(previewSwap, "function check(", "ui/PreviewSwap.qml")).indexOf("PreviewSwap.releaseIn(root.ready, root.started, root.shownAt, Date.now())") >= 0, true)
    var above = previewSwap.split("    Connections {\n        target: root.syncArmed")[0].replace(/\s+$/, "").split("\n").slice(-2)
    check("one comment line above the sync Connections names the basic loop's scheduledUpdateCompleted wait",
        above[0].trim().indexOf("//") !== 0 && above[1].trim().indexOf("//") === 0 && above[1].indexOf("scheduledUpdateCompleted") >= 0, true)
}
