//@ pragma ShellId flea-raildrop-test
import QtQuick
import Quickshell
import Quickshell.Io
import "flea" as Flea
import "flea/js/Drag.js" as Drag
import "flea/js/DragOut.js" as DragOut

// The real receiver, cue, collision host and backend run against marked fixture folders.
ShellRoot {
    id: root
    readonly property string fixture: Quickshell.env("RAILDROP_FIXTURE")
    property int checks: 0
    property int failed: 0
    property int stage: 0
    property int leg: 0
    property var event: null
    property string landedName: ""
    property bool done: false

    function check(label, actual, expected) {
        root.checks += 1
        if (JSON.stringify(actual) !== JSON.stringify(expected)) root.failed += 1
        console.log("RAILDROP " + (JSON.stringify(actual) === JSON.stringify(expected) ? "ok " : "FAIL ")
            + label + " got=" + JSON.stringify(actual) + " expected=" + JSON.stringify(expected))
    }
    function finish() {
        if (root.done) return
        root.done = true
        receiver.leave()
        console.log("RAILDROP DONE checks=" + root.checks + " failed=" + root.failed)
        backend.quit()
    }
    function name() { return ["a.txt", "b.txt", "c.txt"][root.leg] }
    function destination() { return root.fixture + (root.leg === 1 ? "/usb" : "/favorite") }
    function list(path) { backend.send({ c: "list", path: path, first: 64 }) }
    function offered(index) {
        var row = rows.itemAt(index)
        var point = row.mapToItem(rail, row.width / 2, row.height / 2)
        var marker = Drag.markerPayload([root.leg], false, paneStub.path, backend.dirDev, true, false, backend.heldListing)
        return { x: point.x, y: point.y,
            urls: [Drag.uriFor(paneStub.path + "/" + root.name())], proposedAction: Qt.CopyAction, accepted: true,
            getDataAsString: function (type) { return type === Drag.ROWS_MIME ? marker : type === DragOut.keys.liftMime ? "probe" + root.leg : "" },
            accept: function (action) { root.check("receiver acknowledges CopyAction after its own transfer", action, Qt.CopyAction) } }
    }
    function begin() {
        root.event = root.offered(root.leg === 1 ? 1 : 0)
        receiver.enterAt(root.event)
        root.check("hover starts with unknown device", receiver.held.dev, 0)
        root.stage = 2
    }
    function rowsLanded(items) {
        var names = items.map(function (row) { return row.n })
        if (root.stage === 0) { root.stage = 1; return }
        if (root.stage === 5) {
            root.landedName = names.find(function (n) { return root.leg === 2 ? n !== "c.txt" : n === root.name() }) || ""
            root.check("the destination holds the incoming file", root.landedName.length > 0, true)
            if (root.leg === 2) root.check("Keep both kept the occupied name", names.indexOf("c.txt") >= 0, true)
            root.stage = 6
            root.list(paneStub.path)
        } else if (root.stage === 6) {
            root.check("source presence follows the chosen verb", names.indexOf(root.name()) >= 0, root.leg === 1)
            root.stage = 7
            backend.send({ c: "undo" })
        } else if (root.stage === 8) {
            root.check("undo restores or keeps the source", names.indexOf(root.name()) >= 0, true)
            root.stage = 9
            root.list(root.destination())
        } else if (root.stage === 9) {
            root.check("undo removes the incoming destination", names.indexOf(root.landedName) >= 0, false)
            if (root.leg === 2) { root.finish(); return }
            root.leg += 1
            root.stage = 1
        }
    }

    Flea.Backend {
        id: backend
        onRows: function (start, items) { root.rowsLanded(items) }
        onTransferDone: function (id, ok, failed) {
            root.check("transfer completed one file", ok + "|" + failed, "1|0")
            root.check("transfer uses the folder verb", proxy.lastVerb, root.leg === 1 ? "copy" : "move")
            root.stage = 5
            root.list(root.destination())
        }
        onUndone: function (op, ok) {
            root.check("the existing undo journal reverses the drop", op + "|" + ok, (root.leg === 1 ? "copy" : "move") + "|true")
            root.stage = 8
            root.list(paneStub.path)
        }
        onQuitReady: Quickshell.execDetached(["kill", String(Quickshell.processId)])
        onFailed: function (where, path, reason) { root.check("backend " + where + ": " + reason, false, true); root.finish() }
        Component.onCompleted: root.list(root.fixture + "/source")
    }
    // Only the USB device number is a stand-in; the stat request and all file operations are real.
    QtObject {
        id: proxy
        readonly property var dirDev: backend.dirDev
        readonly property real heldListing: backend.heldListing
        property string lastVerb: ""
        signal metaResult(var message)
        signal collisions(int id, int total, var names, bool mergeable)
        signal mergeCollisions(int id, int total, var names)
        signal fatnames(int id, var renames, string fstype, string volume)
        signal failed(string where, string input, string message, int mode)
        function send(message) {
            if (message.c === "transfer") proxy.lastVerb = message.op
            backend.send(message)
        }
    }
    Connections {
        target: backend
        function onMetaResult(message) {
            if (message.t !== "devs") return
            var map = {}
            for (var path in message.devs) map[path] = message.devs[path] + (path === root.fixture + "/usb" ? 1 : 0)
            proxy.metaResult({ t: "devs", id: message.id, devs: map })
        }
        function onCollisions(id, total, names, mergeable) { proxy.collisions(id, total, names, mergeable) }
        function onMergeCollisions(id, total, names) { proxy.mergeCollisions(id, total, names) }
        function onFatnames(id, renames, fstype, volume) { proxy.fatnames(id, renames, fstype, volume) }
    }
    QtObject {
        id: paneStub
        readonly property string path: root.fixture + "/source"
        readonly property var backend: proxy
        readonly property bool listInFlight: false
        readonly property var statusBar: bar
        readonly property var listArea: focusItem
        readonly property var clipboard: ({ paths: [], moving: false })
        property string focusView: "list"
        function focusRequested() {}
        function asks() { return collide }
        function message(text, error) { root.check("pane message " + text, error === true, false) }
    }
    QtObject {
        id: bar
        property var dragFeedbackOwner: null
        property var activities: []
        property string line: ""
        function setActivity(owner, text, transfer) {
            bar.line = text
            bar.activities = text ? [{ text: text, transfer: transfer }] : []
        }
    }

    FloatingWindow {
        implicitWidth: 700
        implicitHeight: 400
        Item { id: focusItem; focus: true }
        Item {
            id: rail
            width: 230
            height: parent.height
            readonly property var navigationPane: paneStub
            readonly property var entries: [
                { label: "Favorite", group: "favourite", kind: "favourite", path: root.fixture + "/favorite", glyph: "folder" },
                { label: "USB", group: "device", kind: "volume", path: root.fixture + "/usb", mounted: true, size: 128000000000, glyph: "usb" },
                { label: "Pixel", group: "device", kind: "phone", path: "", mounted: true, size: null, glyph: "smartphone" },
                { label: "Recent", group: "recent", kind: "recent", path: "flea:recent", glyph: "history" }
            ]
            function railItemFor(index) { return rows.itemAt(index) }
            Flea.RailDrop { id: receiver; sidebar: rail; viewport: scroller }
            Flickable {
                id: scroller
                anchors.fill: parent
                clip: true
                contentWidth: width
                contentHeight: height + rows.count * Flea.Theme.railRowHeight
                onContentYChanged: receiver.reaim()
                Repeater {
                    id: rows
                    model: rail.entries
                    delegate: Flea.SidebarRow { y: index * height }
                }
            }
        }
        Flea.CollideHost { id: collide; pane: paneStub; source: Qt.resolvedUrl("flea/CollideConfirm.qml") }
    }
    Timer {
        interval: 30
        running: !root.done
        repeat: true
        onTriggered: {
            if (root.stage === 1) root.begin()
            else if (root.stage === 2 && receiver.held && receiver.held.dev > 0) {
                var row = rows.itemAt(root.leg === 1 ? 1 : 0)
                var expected = root.leg === 1 ? "Copy 1 item to USB" : "Move 1 item to Favorite · Ctrl copies, Shift moves"
                root.check("the hovered rail row names the folder verb", bar.line, expected)
                root.check("the row shows the existing drop cue", row.trailingLabel ? row.trailingLabel.text : "", root.leg === 1 ? "copy here" : "move here")
                root.check("the cue hides the row's ordinary indicator", row.indicatorSlot.visible, false)
                root.check("the cue reserves room beside the label", row.trailingLabel && row.labelItem.width + row.labelItem.x < row.trailingLabel.x, true)
                root.check("the cue stays inside the clipped rail viewport", row.trailingLabel.parent.parent.parent === scroller && scroller.clip, true)
                var held = receiver.held
                scroller.contentY = row.height
                root.check("a row scrolled away from the pointer loses its cue", row.trailingLabel, null)
                scroller.contentY = 0
                root.check("a row returned by scrolling asks its device again", receiver.held.dev, 0)
                receiver.aim(root.event.x, rows.itemAt(2).y + 5)
                root.check("phone root never lights", receiver.held, null)
                root.check("leaving restores the ordinary indicator", row.indicatorSlot.visible, true)
                root.check("phone root names no folder", bar.line.indexOf("to a folder") >= 0, true)
                proxy.metaResult({ t: "devs", id: held.id, devs: held.path === "" ? {} : { [held.path]: held.dev } })
                root.check("a reply after leaving cannot light a row", receiver.held, null)
                receiver.aim(root.event.x, root.event.y)
                root.check("returning to a row starts unknown again", receiver.held.dev, 0)
                proxy.metaResult({ t: "devs", id: held.id, devs: { [held.path]: held.dev } })
                root.check("the previous visit cannot answer the new hover", receiver.held.dev, 0)
                root.stage = 3
            } else if (root.stage === 3 && receiver.held && receiver.held.dev > 0) {
                root.stage = 4
                receiver.dropAt(root.event)
            } else if (root.stage === 4 && collide.opened) {
                root.check("an occupied name opens the collision card", root.leg, 2)
                root.check("the transfer still waits on the card", proxy.lastVerb, "copy")
                collide.item.chosen("keep")
                collide.item.opened = false
            }
        }
    }
}
