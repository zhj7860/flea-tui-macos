.import "../../ui/js/Collide.js" as Collide
.import "../../ui/js/Drag.js" as Drag
.import "../../ui/js/DropDev.js" as DropDev
.import "../../ui/js/Messages.js" as Messages
.import "collidefixture.js" as Fixture
.import "sourcefixture.js" as Source

// The FAT card in the collision flow and the hover seams on the drag session, over the real CollideHost and FileDrag; the cards need the shell, so a stub and source scans stand in.

var BACKEND = "import QtQuick\nimport \"../../ui/js/Swap.js\" as Swap\nQtObject {\n"
    + "    signal collisions(int id, int total, var names, bool mergeable)\n    signal mergeCollisions(int id, int total, var names)\n"
    + "    signal fatnames(int id, var renames, string fstype, string volume)\n"
    + "    signal failed(string where, string input, string message, int mode)\n"
    + "    property real heldListing: 0\n    property var sent: []\n"
    + "    function send(object) { sent.push(Swap.named(object, heldListing)) }\n}\n"
var CARD = "import QtQuick\nQtObject {\n    signal chosen(string choice)\n    property bool opened: false\n    property var shown: []\n"
    + "    function open(title, list, note) { shown.push([title, list.length, note]); opened = true }\n}\n"
var RENAMES = [{ old: "clip: a.mp4", new: "clip_ a.mp4", d: false, i: "video-x-generic" },
               { old: "notes?.md", new: "notes_.md", d: false, i: "text-x-generic" }]
var PATHS = ["/s/clip: a.mp4", "/s/notes?.md"]

function scene() {
    var parent = Qt.createComponent("QtQuick", "Item").createObject(null)
    var backend = Qt.createQmlObject(BACKEND, parent, Qt.resolvedUrl("backend.qml"))
    backend.heldListing = 7
    var out = { parent: parent, backend: backend, focused: 0, said: [] }
    out.pane = { path: "/run/media/gm/USB", backend: backend, clipboard: { paths: PATHS, moving: false },
                 listArea: { forceActiveFocus: function () { out.focused += 1 } },
                 message: function (text) { out.said.push(text) } }
    out.host = Fixture.built("CollideHost.qml", parent, { pane: out.pane })
    out.card = Qt.createQmlObject(CARD, parent, Qt.resolvedUrl("card.qml"))
    out.host.fatCard = out.card
    out.card.chosen.connect(out.host.decideFat)
    out.fresh = function () { return { c: "transfer", op: "copy", paths: PATHS, dest: "/run/media/gm/USB" } }
    return out
}

function flow(check) {
    var at = scene()
    var backend = at.backend, host = at.host, card = at.card
    host.ask(at.fresh(), null, false)
    check("a paste asks the collisions question first, with no FAT answer on it", JSON.stringify(backend.sent),
          JSON.stringify([{ c: "collisions", id: 1, dest: "/run/media/gm/USB", paths: PATHS }]))
    backend.fatnames(1, RENAMES, "exfat", "128GB")
    check("a FAT answer opens the card on the machine's own fields", JSON.stringify(card.shown),
          JSON.stringify([["2 names cannot exist on 128GB (exFAT)", 2, "exFAT refuses : ? * \" < > | and trailing dots or spaces."]]))
    check("the transfer is still waiting behind it", host.pending !== null && backend.sent.length, 1)
    backend.fatnames(9, RENAMES, "exfat", "128GB")
    check("an answer to another question opens nothing", card.shown.length, 1)
    card.chosen("rename")
    check("Rename and copy asks the same question again with the answer on it", JSON.stringify(backend.sent[1]),
          JSON.stringify({ c: "collisions", id: 1, dest: "/run/media/gm/USB", fat: "rename", paths: PATHS }))
    check("and gives the focus back to the listing", at.focused, 1)
    backend.collisions(1, 0, [], false)
    check("no collision sends the transfer with the answer on it", JSON.stringify(backend.sent[2]),
          JSON.stringify({ c: "transfer", op: "copy", paths: PATHS, dest: "/run/media/gm/USB", fat: "rename", collide: Collide.NONE, collideId: 1 }))
    check("and lets go of the wait", host.pending, null)

    host.ask(at.fresh(), null, false)
    backend.fatnames(2, RENAMES, "exfat", "128GB")
    card.chosen("skip")
    check("Skip them rides the question the same way", backend.sent[4].fat + "|" + backend.sent[4].id, "skip|2")
    backend.collisions(2, 0, [], false)
    check("and the transfer", backend.sent[5].fat + "|" + backend.sent[5].collide, "skip|" + Collide.NONE)

    var before = backend.sent.length
    host.ask(at.fresh(), null, false)
    backend.fatnames(3, RENAMES, "exfat", "128GB")
    card.chosen("cancel")
    check("Cancel sends nothing past its question and lets go", (backend.sent.length - before) + "|" + (host.pending === null), "1|true")
    check("so the next paste may ask", host.ask(at.fresh(), null, false), true)
    backend.failed("stale", "collisions", "the listing changed", 0)
    check("a refused question closes the card and ends the wait", card.opened + "|" + (host.pending === null), "false|true")
    at.parent.destroy()
}

function hover(check) {
    var at = Fixture.scene(7)
    var session = at.session
    var rested = [], stopped = []
    session.hoverTimers = { rest: function () { rested.push(1) }, stopRest: function () { stopped.push(1) } }
    session.hoverBegan(2, "/d/omarchy", 10, 400)
    check("resting on a folder row names it and its band", session.hoverIndex + "|" + session.hoverPath + "|" + session.scrollDir,
          "2|/d/omarchy|-1")
    check("and starts the rest", rested.length, 1)
    session.hoverMoved(200, 400)
    check("a move out of the band stops the scroll", session.scrollDir, 0)
    check("and restarts the rest rather than spending it", rested.length, 2)
    session.hoverMoved(395, 400)
    check("the bottom band scrolls down", session.scrollDir, 1)
    session.hoverEnded()
    check("leaving clears the row, the band and the rest", session.hoverIndex + "|" + session.hoverPath + "|" + session.scrollDir + "|" + stopped.length,
          "-1||0|1")
    session.hoverBegan(2, "/d/omarchy", 395, 400)
    session.liftEnded()
    check("the end of the drag clears them too", session.hoverPath + "|" + session.scrollDir + "|" + stopped.length, "|0|2")
    at.parent.destroy()
}

function built(check) {
    var timers = Source.source("ui/HoverTimers.qml")
    check("the rest reads the live setting", timers.indexOf("ViewState.openFoldersWhileDragging") >= 0, true)
    check("the rest is the module's 0.7 s", timers.indexOf("interval: DragOut.OPEN_MS") >= 0, true)
    check("the scroll runs only while a band is held", timers.indexOf("running: root.session.scrollDir !== 0") >= 0, true)
    check("a view without a scroll position is left alone", timers.indexOf("view.contentY === undefined") >= 0, true)
    var drag = Source.source("ui/FileDrag.qml")
    check("the timers are built on first use, with no placeholder", drag.indexOf('Qt.createComponent("HoverTimers.qml").createObject(root') >= 0
          && drag.indexOf("Loader") < 0, true)
    var crumb = Source.source("ui/Crumb.qml")
    check("a crumb builds its drop target when a drag lifts or it is first hovered",
          crumb.indexOf("onDragLiveChanged: if (crumb.dragLive) crumb.armDrop()") >= 0
          && crumb.indexOf("onHoveredChanged: if (hovered) crumb.armDrop()") >= 0, true)
    check("and hands it the crumb the frame belongs to", crumb.indexOf("{ crumb: crumb, pane: crumb.dropPane") >= 0, true)
    var area = Source.source("ui/CrumbDrop.qml")
    check("the crumb's drop is the floor's own receiver, so it decides the verb and sends the one transfer the floor does",
          area.indexOf("Flea.DropInto {") >= 0 && area.indexOf("text/uri-list") < 0 && area.indexOf("verbFor") < 0, true)
    check("and is named by the crumb's text", Source.source("ui/DropInto.qml").indexOf("root.label || root.dest") >= 0
          && crumb.indexOf("label: String(crumb.modelData.text") >= 0, true)
    var row = Source.source("ui/RowDrag.qml")
    check("a peek row drops through the pane that shows it", row.indexOf("root.dropScope.pane") >= 0 && row.indexOf("root.dropScope.dir") >= 0, true)
    var card = Source.source("ui/FatNamesConfirm.qml")
    check("the card is placed and sized by the shared card rules", card.indexOf("Theme.cardOrigin(root.width, width)") >= 0
          && card.indexOf("Theme.cardSpan(root.contentWidth") >= 0, true)
    check("its buttons are the shared one, in the board's order", card.indexOf("Collide.FAT_BUTTONS.cancel") < card.indexOf("Collide.FAT_BUTTONS.skip")
          && card.indexOf("Collide.FAT_BUTTONS.skip") < card.indexOf("Collide.FAT_BUTTONS.rename"), true)
    check("Rename and copy is the primary and carries the ring as the card opens", card.indexOf("primary: true") >= 0
          && card.indexOf("property string focusName: Collide.FAT_DEFAULT") >= 0, true)
    check("a first-frame file never imports the card", ["ui/Pane.qml", "ui/PaneWire.qml", "ui/WindowBody.qml", "ui/Row.qml"].every(function (file) {
        return Source.source(file).indexOf("FatNamesConfirm") < 0 }), true)
}

// The backend's answers for the crumbs of /home/u/usb/sub, where usb is a symlink onto a stick (device 42) and the rest sits on device 7.
var ANSWERS = { "/": 7, "/home": 7, "/home/u": 7, "/home/u/usb": 42 }

function verb(target, listing, srcDev, known) {
    var dev = DropDev.devFor(known, target)
    return dev + "|" + Drag.dropVerb(Drag.markerPayload([0], false, listing, srcDev), 0, dev)
}

// The shipped bindings, run on a stand-in root, so a renamed property or a rewired source fails here.
function shipped(file, marker, root) {
    var line = Source.slice(Source.source(file), marker, "\n")
    return new Function("root", "DropDev", "return (" + line.substring(marker.length) + ")")(root, DropDev)
}

function crumbdev(check) {
    var area = Source.source("ui/CrumbDrop.qml")
    check("the crumb takes its device from the backend's answer for its own path, never a static guess or the listing's",
          area.indexOf("DropDev.devFor") >= 0 && area.indexOf("pathDevs") >= 0 && area.indexOf("destDev: 0") < 0 && area.indexOf("dirDev") < 0, true)
    check("and no mount table decides it, the rail's or the network service's",
          area.indexOf("mountPoints") < 0 && area.indexOf("networkService") < 0 && area.indexOf("sidebar") < 0
          && Source.source("ui/NetworkMounts.qml").indexOf("DropDev") < 0 && Source.source("ui/Sidebar.qml").indexOf("mountsAnswered") < 0, true)
    var pane = { backend: { pathDevs: ANSWERS } }
    check("the shipped binding reads the answer for the crumb's own path",
          shipped("ui/CrumbDrop.qml", "destDev:", { pane: pane, dest: "/home/u" }) + "|"
          + shipped("ui/CrumbDrop.qml", "destDev:", { pane: pane, dest: "/home/u/usb" }), "7|42")
    check("and is unknown without a pane, a backend or an answer",
          shipped("ui/CrumbDrop.qml", "destDev:", { pane: null, dest: "/home/u" }) + "|"
          + shipped("ui/CrumbDrop.qml", "destDev:", { pane: { backend: null }, dest: "/home/u" }) + "|"
          + shipped("ui/CrumbDrop.qml", "destDev:", { pane: pane, dest: "/etc" }), "0|0|0")
}

function crumbflow(check) {
    var through = "/home/u/usb/sub"
    check("a crumb above a symlink onto another volume copies: its own answer differs from the source's",
          verb("/home/u", through, 42, ANSWERS), "7|copy")
    check("the symlink's own crumb answers the stick's device, so it moves",
          verb("/home/u/usb", through, 42, ANSWERS), "42|move")
    check("a crumb on the source's own device moves",
          verb("/home/u", "/home/u/docs", 7, ANSWERS), "7|move")
    check("an unanswered crumb copies, whether the answers are missing, empty, null or lack the path",
          verb("/home/u", through, 42, undefined) + "|" + verb("/home/u", through, 42, null) + "|"
          + verb("/home/u", through, 42, {}) + "|" + verb("/etc", through, 42, ANSWERS), "0|copy|0|copy|0|copy|0|copy")
    check("an unanswered crumb copies even when an answered ancestor sits on the source's own device",
          verb("/home/u", "/home/u/docs", 7, { "/": 7, "/home": 7 }), "0|copy")
    check("an answer of 0, a stat that failed, copies",
          verb("/home/u", "/home/u/docs", 7, { "/home/u": 0 }), "0|copy")
    check("an unknown source device copies whatever the crumb answers",
          verb("/home/u", "/home/u/docs", 0, ANSWERS), "7|copy")
    check("a volume mounted after anything was read still copies, because no table is read: only the crumb's own answer decides",
          verb("/run/media/gm", "/run/media/gm/USB/x", 42, { "/": 7, "/run": 7, "/run/media": 7, "/run/media/gm": 7, "/run/media/gm/USB": 42 }) + "|"
          + verb("/run/media/gm/USB", "/run/media/gm/USB/x", 42, { "/run/media/gm/USB": 42 }), "7|copy|42|move")
    check("a trailing slash names the same crumb",
          DropDev.devFor(ANSWERS, "/home/u/") + "|" + DropDev.devFor(ANSWERS, "/"), "7|7")
    check("held keys keep their meaning over the answered device",
          Drag.dropVerb(Drag.markerPayload([0], false, "/home/u/docs", 7), 0, 7, 1, undefined)
          + "|" + Drag.dropVerb(Drag.markerPayload([0], false, "/home/u/docs", 7), 0, 0, undefined, 1), "copy|move")
}

function dropdev(check) {
    check("a listing asks for each ancestor and never itself, the root first",
          JSON.stringify(DropDev.askPaths("/home/u/usb/sub")) + JSON.stringify(DropDev.askPaths("/home/u/usb/sub/")),
          JSON.stringify(["/", "/home", "/home/u", "/home/u/usb"]) + JSON.stringify(["/", "/home", "/home/u", "/home/u/usb"]))
    check("the root, a relative path and a gvfs listing ask nothing, so their crumbs copy",
          JSON.stringify([DropDev.askPaths("/"), DropDev.askPaths("docs/x"), DropDev.askPaths(""),
                          DropDev.askPaths("/run/user/1000/gvfs/smb-share:server=s,share=d/x")]), "[[],[],[],[]]")
    check("answers join the ones kept and a newer answer replaces an older one, a failed one included",
          JSON.stringify(DropDev.merged({ "/": 7, "/home": 7 }, { "/home": 0, "/mnt": 9 })), JSON.stringify({ "/": 7, "/home": 0, "/mnt": 9 }))
    check("forgetting drops only the asked paths and leaves the kept object alone",
          JSON.stringify(DropDev.without({ "/": 7, "/home": 7, "/mnt": 9 }, ["/home/", "/gone"])) + "|"
          + JSON.stringify(DropDev.without(null, ["/"])), JSON.stringify({ "/": 7, "/mnt": 9 }) + "|{}")
    var big = {}
    for (var i = 0; i < 300; i++) big["/p" + i] = 7
    check("past 256 kept paths the older answers go whole and the newest stay",
          JSON.stringify(DropDev.merged(big, { "/new": 5 })), JSON.stringify({ "/new": 5 }))
}

function wire(check) {
    var root = { pathDevs: {} }
    Messages.route(root, JSON.parse('{"t":"devs","devs":{"/":7,"/home/u/usb":42}}'))
    Messages.route(root, JSON.parse('{"t":"devs","devs":{"/home/u":0}}'))
    check("the backend's devs lines accumulate in the backend object's answers",
          JSON.stringify(root.pathDevs), JSON.stringify({ "/": 7, "/home/u/usb": 42, "/home/u": 0 }))
    var sent = []
    var back = { dirDev: 0, pickerOnly: false, _devsFor: "", send: function (message) { sent.push(JSON.stringify(message)) } }
    back.listed = new Function("root", "DropDev", "return function (total, readMs, sortMs, path, changed, gen) {"
        + Source.block(Source.source("ui/Backend.qml"), "onListed:", "ui/Backend.qml") + "}")(back, DropDev)
    // Every landing goes through the real route, which sets the listing's device before it emits listed.
    function land(path, dev) { Messages.route(back, { t: "listed", n: 3, read: 1, sort: 1, path: path, changed: 0, gen: 0, v: dev }) }
    land("/home/u/usb/sub", 42)
    land("/home/u/usb/sub", 42)
    check("each landing asks the ancestors once, and a re-read of the same folder asks nothing more",
          sent.join(""), '{"c":"devs","paths":["/","/home","/home/u","/home/u/usb"]}')
    land("/home/u/usb/sub", 7)
    land("/", 7)
    land("/run/user/1000/gvfs/smb-share:server=s,share=d", 7)
    check("the same path on another device asks again, and the root or a gvfs listing asks nothing",
          sent.length + "|" + back.dirDev, "2|7")
    back.pickerOnly = true
    back._devsFor = ""
    land("/home/u/docs", 7)
    check("the chooser's backend refuses every command but its own, so it asks nothing", sent.length, 2)
    // A kept answer can outlive a mount: a listing under the stick forgets the stale answer, so a drop copies until the new one lands.
    var usb = "/run/media/gm/USB"
    back.pickerOnly = false
    back._devsFor = ""
    back.pathDevs = { "/run/media/gm/USB": 7 }
    land(usb + "/sub", 9)
    var before = verb(usb, "/home/u/docs", 7, back.pathDevs)
    Messages.route(back, { t: "devs", devs: { "/run/media/gm/USB": 9 } })
    check("a crumb asked again reads unknown and copies until the new answer lands, then reads the stick's device",
          before + "|" + verb(usb, "/home/u/docs", 7, back.pathDevs), "0|copy|9|copy")
}

// A peek or carried column row names no device, so a drag entering the pane asks the backend for the visible folder rows' paths once.
function columnasks(check) {
    var pane = { join: function (base, name) { return base === "/" ? "/" + name : base + "/" + name } }
    var rows = [{ n: "deep", d: true, i: "folder" }, { n: "a.txt", d: false, i: "text-x-generic" }, { n: "big", d: true, v: 5 }, { n: "late", d: true }]
    check("only the visible folder rows with no device of their own are asked, by full path",
          JSON.stringify(DropDev.folderAsks(rows, "/home/u", 0, 2, pane)) + JSON.stringify(DropDev.folderAsks(rows, "/", 2, 9, pane))
          + JSON.stringify(DropDev.folderAsks(null, "/", 0, 3, pane)), '["/home/u/deep"]["/late"][]')
    var sent = []
    var back = { pickerOnly: false, _dropAsked: "", pathDevs: { "/a/deep": 7, "/keep": 9 }, send: function (message) { sent.push(JSON.stringify(message)) } }
    back.askDropDevs = new Function("root", "DropDev", "return function (token, paths) {"
        + Source.block(Source.source("ui/Backend.qml"), "function askDropDevs(", "ui/Backend.qml") + "}")(back, DropDev)
    back.askDropDevs("3", ["/a/deep", "/a/more"])
    back.askDropDevs("3", ["/a/deep", "/a/more"])
    check("one drag asks a set once, and a known answer stands until its new one lands",
          sent.join("") + JSON.stringify(back.pathDevs), '{"c":"devs","paths":["/a/deep","/a/more"]}{"/a/deep":7,"/keep":9}')
    back.askDropDevs("4", ["/a/deep", "/a/more"])
    back.askDropDevs("4", [])
    check("another drag asks again, and an empty set asks nothing", sent.length, 2)
    back.pickerOnly = true
    back.askDropDevs("5", ["/x"])
    check("the chooser's backend asks nothing", sent.length, 2)
    // The columns area's real ask: the drawn neighbour columns' answers in one request, nothing when the area is hidden, nothing for a column that is not drawn.
    var asked = []
    var drawn = function (name, paths) { return name ? { dropAsks: function () { return paths } } : null }
    var area = { visible: true, pane: { backend: { askDropDevs: function (token, paths) { asked.push(token + ":" + paths.join(",")) } } } }
    var ask = function (grandparent, parent, child) {
        return new Function("root", "greatGrandparentLoader", "grandparentLoader", "parentColumn", "childColumn",
            "return function (token) {" + Source.block(Source.source("ui/ColumnsArea.qml"), "function askDropDevs(", "ui/ColumnsArea.qml") + "}")(
            area, { item: null }, { item: grandparent }, parent, child)
    }
    ask(drawn("g", ["/g/a"]), drawn("p", ["/p/b", "/p/c"]), drawn("c", ["/c/d"]))("7")
    area.visible = false
    ask(drawn("g", ["/g/a"]), drawn("p", ["/p/b"]), drawn("c", ["/c/d"]))("8")
    area.visible = true
    ask(null, drawn("p", []), drawn("c", ["/c/d"]))("9")
    check("the columns area asks every drawn neighbour column's rows in one request, and nothing while hidden",
          asked.join("|"), "7:/g/a,/p/b,/p/c,/c/d|9:/c/d")
    // The reply lands through the real handler, as a merge, so the listing's ancestor answers and the drag's folder answers live in one map.
    var landed = { pathDevs: { "/home": 6 } }
    Messages.route(landed, { t: "devs", devs: { "/home/u/deep": 7 } })
    var first = landed.pathDevs
    Messages.route(landed, { t: "devs", devs: { "/home/u/more": 8 } })
    check("a devs reply merges into the map as a new object, and the earlier answers stand",
          JSON.stringify(landed.pathDevs) + (first !== landed.pathDevs) + JSON.stringify(first),
          '{"/home":6,"/home/u/deep":7,"/home/u/more":8}true{"/home":6,"/home/u/deep":7}')
}

function run(check) {
    flow(check)
    hover(check)
    built(check)
    crumbdev(check)
    crumbflow(check)
    dropdev(check)
    wire(check)
    columnasks(check)
}
