.import "../../ui/js/Drag.js" as Drag
.import "dragfixture.js" as Fixture
.import "collidefixture.js" as CollideFixture
.import "sourcefixture.js" as Source
.import "../../ui/js/Tabs.js" as Tabs

// #259: the drop follows the keys held at the drop, not the lift, run against the shipped key record in ui/js/DragOut.js.
function run(check) {
    var rows = [{ n: "omarchy", d: true }, { n: "flea", d: true }, { n: "a.txt", d: false }, { n: "b.txt", d: false }]

    var plainDropMarker = Drag.markerPayload([0], false, "/d", 56)
    var copyDropMarker = Drag.markerPayload([0], true, "/d", 56)
    check("a drop holding ctrl copies a plain lift", Drag.dropVerb(plainDropMarker, Qt.MoveAction, 56, 1, -1), "copy")
    check("a drop holding shift moves a ctrl lift", Drag.dropVerb(copyDropMarker, Qt.CopyAction, 56, 0, 1), "move")
    check("a drop holding ctrl with shift links a plain lift", Drag.dropVerb(plainDropMarker, Qt.MoveAction, 56, 1, 1), "link")
    check("a drop that released ctrl moves a ctrl lift", Drag.dropVerb(copyDropMarker, Qt.CopyAction, 56, 0, -1), "move")
    check("a drop with no keys seen keeps the lift verb", Drag.dropVerb(plainDropMarker, Qt.MoveAction, 56, -1, -1), "move")
    check("and an absent seen keeps it too", Drag.dropVerb(plainDropMarker, Qt.MoveAction, 56), "move")
    check("dropHeld keeps the lift bit on -1", Drag.dropHeld(false, -1), false)
    check("dropHeld keeps an absent seen too", Drag.dropHeld(true), true)
    check("dropHeld takes a held key over the lift", Drag.dropHeld(false, 1), true)
    check("dropHeld takes a released key over the lift", Drag.dropHeld(true, 0), false)
    var shiftDrop = []
    Drag.dropInto(Fixture.pane(shiftDrop, [], rows), copyDropMarker, ["file:///d/a.txt"], "/d/omarchy", 56, "", "", Qt.CopyAction, 0, 1)
    check("a drop released ctrl and holding shift moves",
        shiftDrop.length === 1 ? shiftDrop[0].op : "nothing sent", "move")

    var store = CollideFixture.realDropKeys()
    check("a fresh store holds no marker", store.marker, "")
    store.track({ key: Qt.Key_Control }, true)
    check("stray taps outside any drag never arm it", store.ctrl, -1)
    var first = store.stamped({ "text/plain": "a" })
    var second = store.stamped({ "text/plain": "a" })
    check("each lift keeps its payload and gets its own number",
        [first["text/plain"], first[store.liftMime], second[store.liftMime]].join("|"), "a|1|2")
    store.enter("m", "1")
    store.track({ key: Qt.Key_Control }, true)
    store.track({ key: Qt.Key_Shift }, true)
    check("a ctrl press is held", store.ctrl, 1)
    check("and a shift press beside it", store.shift, 1)
    store.track({ key: Qt.Key_Control }, false)
    check("a ctrl release clears it", store.ctrl, 0)
    store.track({ key: Qt.Key_Control }, true)
    // settle() stands in for the turn's end, where a leave's queued settle runs.
    store.leave()
    store.settle()
    store.enter("m", "1")
    check("the same drag at the next target keeps every key seen, the gap between included", store.ctrl + " " + store.shift, "1 1")
    store.enter("m", "2")
    check("a second lift of the same rows starts unseen", store.ctrl + " " + store.shift, "-1 -1")
    store.track({ key: Qt.Key_Control }, true)
    store.enter("n", "2")
    check("a new drag resets ctrl", store.ctrl, -1)
    check("and shift too", store.shift, -1)
    store.enter("f", "")
    store.track({ key: Qt.Key_Control }, true)
    store.leave()
    store.settle()
    check("a drag with no lift ends at a leave no entrance follows", store.marker + " " + store.ctrl, " -1")
    store.enter("f", "")
    store.track({ key: Qt.Key_Control }, true)
    store.leave()
    store.enter("f", "")
    store.settle()
    check("and keeps its keys when it moves on to the next target", store.ctrl, 1)
    store.clear()
    check("a drop consumes the drag", store.marker, "")
    check("and clears what was seen", store.ctrl, -1)

    rowWiring(check)
    leaveWiring(check)

    var paneSource = Source.source("ui/Pane.qml")
    check("the pane funnels presses into the drop keys",
        paneSource.indexOf("DragOut.keys.track(event, true)") >= 0, true)
    check("and releases too",
        paneSource.indexOf("DragOut.keys.track(event, false)") >= 0, true)
    check("the key record lives in a library a launch already compiles, never a singleton of its own",
        Source.source("ui/qmldir").indexOf("DropKeys") < 0, true)

    hostWiring(check)
}

// The pane's asks(), run from its own source: the first ask builds the host once, owned by the pane, and a broken host is refused by name.
function hostWiring(check) {
    var asks = new Function("root", "Qt", "Component", Source.block(Source.source("ui/Pane.qml"), "function asks()", "ui/Pane.qml"))
    var made = []
    var ready = { status: 1, createObject: function (parent, props) { made.push({ parent: parent, props: props }); return { host: made.length } } }
    var builder = { asked: [], createComponent: function (file) { this.asked.push(file); return ready } }
    var pane = { collide: null, overlayParent: { overlay: true } }
    var first = asks(pane, builder, { Ready: 1 })
    var again = asks(pane, builder, { Ready: 1 })
    check("the first ask builds the collision host once, owned by the pane and drawn on the overlay",
        builder.asked.join(",") + "|" + made.length + "|" + (made[0].parent === pane) + "|" + (made[0].props.pane === pane)
            + "|" + (made[0].props.parent === pane.overlayParent) + "|" + (first === again), "CollideHost.qml|1|true|true|true|true")
    var broken = { status: 3, errorString: function () { return "Type CollideCard unavailable" } }
    var thrown = ""
    try {
        asks({ collide: null, overlayParent: null }, { createComponent: function () { return broken } }, { Ready: 1 })
    } catch (e) {
        thrown = e.message
    }
    check("a host that cannot load is refused by name with its load error", thrown, "CollideHost.qml did not load: Type CollideCard unavailable")
}

// The real ui/RowDrag.qml and ui/FileDrag.qml over one store: a shift held over the folder row moves a lift that would copy.
function rowWiring(check) {
    var at = CollideFixture.scene(7)
    var marker = Drag.markerPayload([0], false, "/s", 56)
    check("a folder row takes a path drag", at.target.enter(marker, ["file:///s/a.txt"], "", "", Qt.MoveAction), true)
    at.keys.track({ key: Qt.Key_Shift }, true)
    at.target.dropped(marker, ["file:///s/a.txt"], "", "", Qt.MoveAction)
    check("a path drop onto the row follows the shift held there", at.pane.collide.pending ? at.pane.collide.pending.op : "nothing", "move")
    check("and the drop clears the store", at.keys.marker + " " + at.keys.shift, " -1")
    at.keys.enter("m")
    at.keys.track({ key: Qt.Key_Control }, true)
    check("a refused drop onto the row says why", at.target.refuseDrop(marker, ["file:///d/omarchy"], "", "") !== "", true)
    check("and clears the store too", at.keys.marker + " " + at.keys.ctrl, " -1")
    at.target.enter(marker, ["file:///s/a.txt"], "", "", Qt.MoveAction, "4")
    dropArea(at.target).exited()
    at.keys.settle()
    at.keys.track({ key: Qt.Key_Shift }, true)
    at.target.enter(marker, ["file:///s/a.txt"], "", "", Qt.MoveAction, "4")
    check("a shift pressed after leaving the row counts when the same drag comes back", at.keys.shift, 1)
    at.target.enter(marker, ["file:///s/a.txt"], "", "", Qt.MoveAction, "5")
    check("and a new lift over the row starts unseen", at.keys.shift, -1)
    at.target.enter(marker, ["file:///s/a.txt"], "", "", Qt.MoveAction, "")
    at.keys.track({ key: Qt.Key_Shift }, true)
    dropArea(at.target).exited()
    at.keys.settle()
    check("a drag with no lift that leaves the row ends there", at.keys.marker + " " + at.keys.shift, " -1")
    // The row's shipped entrance, run as written, hands the drag's own lift number to the entrance.
    var entered = Source.block(Source.source("ui/RowDrag.qml"), "function enterAt(drag, at)", "ui/RowDrag.qml")
    var onEntered = eval("(function (root, Tabs, DragOps, DragOut) { return function (drag) {" + entered + "} })")(
        { enter: function () { return at.target.enter.apply(at.target, arguments) }, hoverAt: function () {} },
        Tabs, Drag, { keys: at.keys })
    var offered = {}
    offered[Drag.ROWS_MIME] = marker
    offered[at.keys.liftMime] = "6"
    onEntered({ urls: ["file:///s/a.txt"], proposedAction: Qt.MoveAction, getDataAsString: function (type) { return offered[type] || "" } })
    check("the row's entered handler names the drag by its lift", at.keys.lift, "6")
    at.parent.destroy()

    var own = CollideFixture.scene(7)
    var liftNumber = "", handled = false
    // Offscreen's platform drag returns at once, so the drop lands inside the lift; once only, as the row's entrance rewrites the feedback.
    own.session.feedbackChanged.connect(function () {
        if (own.session.feedback === null || handled) return
        handled = true
        var lifted = own.session.dragMime[Drag.ROWS_MIME]
        liftNumber = own.session.dragMime[own.keys.liftMime]
        own.target.enter(lifted, [], "", "", Qt.MoveAction, liftNumber)
        own.keys.track({ key: Qt.Key_Shift }, true)
        own.target.dropped(lifted, [], "")
    })
    own.session.liftBegan(0, { modifiers: Qt.NoModifier })
    var sent = own.pane.collide.pending
    check("a by-index drop onto the row follows the shift held there", sent ? sent.c + " " + sent.op : "nothing", "transfer move")
    check("and the drag it started carried the lift's number", liftNumber, "1")
    own.parent.destroy()
}

// A hover-open swaps the lit delegate onto another row: leaving clears the folder it recorded, and never a folder another row recorded since.
function leaveWiring(check) {
    var gone = CollideFixture.scene(7)
    gone.target.row = { n: "Photos", d: true }
    gone.target.enter("", ["file:///x/a.txt"], "", "", Qt.CopyAction)
    gone.pane.path = "/d/Photos"
    gone.target.row = { n: "p2.txt", d: false }
    dropArea(gone.target).exited()
    check("leaving the reused row clears the recorded folder", gone.session.dropDest + "|" + gone.session.dropIndex, "|-1")
    var sentBefore = gone.backend.sent.length
    check("a later drop on that reused file row takes nothing", gone.target.dropped("", ["file:///x/a.txt"], "", "", Qt.CopyAction), false)
    check("and sends nothing, leaving that drop to the floor", gone.backend.sent.length, sentBefore)
    var other = CollideFixture.built("RowDrag.qml", gone.parent, { session: gone.session, listingIndex: 3, row: { n: "Docs", d: true } })
    check("another folder row takes the next drag", other.enter("", ["file:///x/a.txt"], "", "", Qt.CopyAction), true)
    check("a drop on it lands in that row", other.dropped("", ["file:///x/a.txt"], "", "", Qt.CopyAction), true)
    check("and in no earlier folder", gone.backend.sent.length > sentBefore ? gone.backend.sent[sentBefore].dest : "", "/d/Docs")
    gone.parent.destroy()
    var late = CollideFixture.scene(7)
    late.target.row = { n: "Photos", d: true }
    late.target.enter("", ["file:///x/a.txt"], "", "", Qt.CopyAction)
    var next = CollideFixture.built("RowDrag.qml", late.parent, { session: late.session, listingIndex: 3, row: { n: "Docs", d: true } })
    next.enter("", ["file:///x/a.txt"], "", "", Qt.CopyAction)
    dropArea(late.target).exited()
    check("an exit arriving after another row took the hover keeps that row's folder", late.session.dropDest + "|" + late.session.dropIndex, "/d/Docs|3")
    late.parent.destroy()
}

// The row's own DropArea, whose exited handler is the shipped leave path.
function dropArea(row) {
    for (var i = 0; i < row.children.length; i++) {
        var kid = row.children[i]
        if (kid.containsDrag !== undefined) return kid
        if (kid.item && kid.item.containsDrag !== undefined) return kid.item
    }
    throw new Error("RowDrag has no DropArea")
}
