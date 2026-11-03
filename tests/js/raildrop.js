.import "../../ui/js/Drag.js" as Drag
.import "../../ui/js/RailDrop.js" as RailDrop
.import "../../ui/js/Messages.js" as Messages
.import "../../ui/js/Devices.js" as Devices
.import "collidefixture.js" as Fixture
.import "sourcefixture.js" as Source

// Read the native fixture's mktemp path and simple jq object so the parser sees its actual mountpoint.
function nativeFixture(check) {
    var script = Source.source("tests/drag.sh")
    // Sample input: XDEV=$(mktemp -d "$XDG_RUNTIME_DIR/flea-drag-xdev-XXXXXXXX") || exit 1
    var creates = script.match(/XDEV=\$\(mktemp -d [^\n]+/g) || []
    check("all and R7 share one tmpfs fixture creation", creates.length, 1)
    // Sample input: XDEV=$(mktemp -d "$XDG_RUNTIME_DIR/flea-drag-xdev-XXXXXXXX") captures $XDG_RUNTIME_DIR/flea-drag-xdev-XXXXXXXX.
    var template = creates.length === 1 ? creates[0].match(/mktemp -d "?([^" )]+)/) : null
    // Sample input: jq -nc --arg path "$XDEV/big" '{blockdevices:[{mountpoints:[$path]}]}' > "$SB/lsblk.json"
    var object = script.match(/jq -nc --arg path "\$XDEV\/big" '([^'\n]+)' > "\$SB\/lsblk.json"/)
    if (!template || !object) throw new Error("native drag lsblk fixture seam moved")
    var runtime = "/run/user/1000"
    // Sample input: $XDG_RUNTIME_DIR/flea-drag-xdev-XXXXXXXX becomes /run/user/1000/flea-drag-xdev-Fixture1/big.
    var path = template[1].replace(/\$XDG_RUNTIME_DIR/g, runtime).replace(/X+$/, "Fixture1") + "/big"
    // Sample input: {mountpoints:[$path]} becomes {"mountpoints":["/run/user/1000/flea-drag-xdev-Fixture1/big"]}.
    var body = object[1].replace(/\$path/g, JSON.stringify(path)).replace(/([{,])([A-Za-z][A-Za-z0-9_]*):/g, '$1"$2":')
    var rows = Devices.parseDevices(body)
    check("native fixture mounts become exactly one USB row", rows.length, 1)
    check("native USB row preserves its runtime path and capacity", rows.map(function (row) {
        return [row.label, row.kind, row.path, row.mounted, row.size].join("|")
    }).join(","), "USB|volume|" + runtime + "/flea-drag-xdev-Fixture1/big|true|128000000000")
    var old = JSON.parse(body)
    old.blockdevices[0].mountpoints = ["/dev/shm/flea-drag-xdev-Fixture1/big"]
    check("the former dev-shm fixture is correctly hidden", Devices.parseDevices(JSON.stringify(old)).length, 0)
}

function run(check) {
    nativeFixture(check)
    var sidebar = Source.source("ui/Sidebar.qml")
    check("the rail owns one shared receiver", (sidebar.match(/RailDrop \{/g) || []).length, 1)
    check("the real rail's scroller updates the hovered target", Source.block(sidebar, "onContentYChanged:", "ui/Sidebar.qml").indexOf("fileDrop.reaim()") >= 0, true)
    var source = "/source", urls = ["file:///source/a.txt"]
    var kinds = [
        { label: "Home", group: "home", kind: "home", path: "/home/u" },
        { label: "Favorite", group: "favourite", kind: "favourite", path: "/favorite" },
        { label: "USB", group: "device", kind: "volume", path: "/usb", mounted: true },
        { label: "Disk", group: "device", kind: "disk", path: "/", mounted: true },
        { label: "Share", group: "network", kind: "share", path: "/share", mounted: true },
        { label: "Phone storage", group: "favourite", kind: "favourite", path: "/run/user/1000/gvfs/mtp:host=Pixel/Internal storage" }
    ]
    var marker = Drag.markerPayload([0], false, source, 42, true, false, 7)
    var asked = [], pane = { backend: {}, listInFlight: false,
        asks: function () { return { ask: function (request) { asked.push(request); return true } } } }
    for (var i = 0; i < kinds.length; i++) {
        var entry = kinds[i]
        var path = RailDrop.destination(entry, marker, urls, "", "")
        check(entry.label + " is a folder target", path, entry.path)
        var first = RailDrop.pending(path), devs = {}
        devs[path] = 42
        var same = RailDrop.answer(first, first.id, devs)
        devs[path] = 43
        var other = RailDrop.answer(first, first.id, devs)
        var late = RailDrop.answer(first, first.id - 1, devs)
        var cases = [
            ["same", same, marker, -1, -1, "move"], ["other", other, marker, -1, -1, "copy"],
            ["unknown", first, marker, -1, -1, "copy"], ["late", late, marker, -1, -1, "copy"],
            ["Ctrl at lift", same, Drag.markerPayload([0], true, source, 42), -1, -1, "copy"],
            ["Shift at lift", first, Drag.markerPayload([0], false, source, 42, true, true), -1, -1, "move"],
            ["Ctrl at drop", same, marker, 1, 0, "copy"], ["Shift at drop", other, marker, 0, 1, "move"],
            ["released Ctrl", same, Drag.markerPayload([0], true, source, 42), 0, 0, "move"],
            ["link at drop", first, marker, 1, 1, "relative"]
        ]
        for (var j = 0; j < cases.length; j++) {
            var c = cases[j]
            asked = []
            check(entry.label + " takes " + c[0], RailDrop.drop(pane, entry, c[1], c[2], urls, "", "", Qt.CopyAction, c[3], c[4]), true)
            check(entry.label + " verb for " + c[0], asked.length === 1 ? asked[0].op : "nothing", c[5])
            check(entry.label + " keeps path identity for " + c[0], asked.length === 1 ? asked[0].paths.join("|") + ":" + asked[0].dest : "nothing", "/source/a.txt:" + path)
        }
    }
    var refusals = [
        { kind: "phone", path: "/phone", mounted: true }, { kind: "volume", path: "/usb", mounted: false },
        { kind: "recent", path: "/recent" }, { kind: "favorite", path: "" },
        { kind: "favorite", path: "relative" }, { kind: "favorite", path: "/source/" },
        { kind: "favorite", path: "/source/a.txt/child" },
        { kind: "favorite", path: "/run/user/1000/gvfs/mtp:host=Pixel/" }
    ]
    asked = []
    for (var r = 0; r < refusals.length; r++) {
        check("refusal " + r + " names no folder", RailDrop.destination(refusals[r], marker, urls, "", ""), "")
        check("refusal " + r + " writes nothing", RailDrop.drop(pane, refusals[r], null, marker, urls, "", "", 0, -1, -1), false)
    }
    check("no refused transfer asks a collision question", asked.length, 0)
    check("a pathless own drag cannot borrow listing rows", RailDrop.destination(kinds[1], marker, [], "", "/source/a.txt"), "")
    check("malformed marker refuses even with paths", RailDrop.destination(kinds[1], "bad", urls, "", ""), "")
    check("foreign plain text carries its local path", RailDrop.destination(kinds[1], "", [], "", "/source/a.txt"), "/favorite")
    var hover = RailDrop.pending("/favorite"), answered = { "/favorite": 42 }
    check("a left row drops its answer", RailDrop.answer(null, hover.id, answered), null)
    var again = RailDrop.pending("/favorite")
    check("returning to the same row still drops the earlier hover's answer", RailDrop.answer(again, hover.id, answered).dev, 0)
    check("another path cannot answer this hover", RailDrop.answer(again, again.id, { "/usb": 42 }).dev, 0)
    check("a matching reply updates device without mutating the pending snapshot", RailDrop.answer(again, again.id, answered).dev + "|" + again.dev, "42|0")
    var messages = [], backend = { pathDevs: { "/favorite": 9 }, metaResult: function (line) { messages.push(line) } }
    Messages.route(backend, { t: "devs", id: hover.id, devs: answered })
    check("a tagged answer goes to the hover and never fills the shared cache", messages.length + "|" + backend.pathDevs["/favorite"], "1|9")
    Messages.route(backend, { t: "devs", devs: answered })
    check("untagged breadcrumb answers still fill the shared map", backend.pathDevs["/favorite"], 42)

    // Drive the real collision host: the rail sends no write until the existing question is answered.
    var scene = Fixture.scene(7)
    check("the rail enters the real collision flow", RailDrop.drop(scene.pane, kinds[1], RailDrop.answer(hover, hover.id, answered), marker, urls, "", "", 0, -1, -1), true)
    check("a rail drop first asks collisions, not transfer", Fixture.verbs(scene.backend), "collisions")
    var question = scene.backend.sent[0]
    scene.backend.collisions(question.id, 0, [], false)
    check("the existing host releases the move", Fixture.verbs(scene.backend) + "|" + scene.backend.sent[1].op, "collisions,transfer|move")
    pane.listInFlight = true
    check("a loading pane refuses", RailDrop.drop(pane, kinds[1], hover, marker, urls, "", "", 0, -1, -1), false)
    scene.parent.destroy()
}
