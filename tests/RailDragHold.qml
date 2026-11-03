import QtQuick
import "flea" as Flea
import "flea/js/Drag.js" as DragOps

// A real internal row drag reaches child DropAreas without pointer hover, then leaves the overlay rail.
Item {
    id: root
    required property var pane
    required property var host
    required property var report
    property var sidebar: null
    property var catcher: null
    property var target: null
    property var row: null
    property double enteredAt: 0
    readonly property var cases: ["trash", "home", "favourite", "tag"]

    Component {
        id: childTarget
        DropArea {
            anchors.fill: parent
            keys: [DragOps.ROWS_MIME]
        }
    }
    Item {
        id: source
        width: 2
        height: 2
        Drag.dragType: Drag.Internal
        Drag.keys: [DragOps.ROWS_MIME]
        Drag.supportedActions: Qt.CopyAction
        Drag.proposedAction: Qt.CopyAction
    }

    function findRow(kind) {
        for (var i = 0; i < root.sidebar.entries.length; i++) {
            var entry = root.sidebar.entries[i]
            if (entry.kind === kind) return root.sidebar.railItemFor(i)
        }
        return null
    }
    function moveTo(item, x, y) {
        var point = item.mapToItem(root, x, y)
        source.x = point.x
        source.y = point.y
    }
    function dropArea(item) {
        if (item.containsDrag !== undefined) return item
        for (var i = 0; i < item.children.length; i++) {
            var found = root.dropArea(item.children[i])
            if (found) return found
        }
        return null
    }
    function acceptInternal(drag) { drag.accepted = true }
    function steps() {
        var out = [function () {
            root.sidebar = root.host.children.filter(function (item) { return String(item).indexOf("QQuickLoader") === 0 && item.item })[0].item
            root.catcher = root.host.children.filter(function (item) { return item.objectName === "dragReveal" })[0] || null
            root.report("the rail catcher is found by name", root.catcher !== null, true)
            // An unrelated area before the catcher makes a depth-first first-area lookup read the wrong receiver.
            var decoy = childTarget.createObject(root.host.children[0], { keys: ["application/x-flea-priority-decoy"] })
            root.report("an unrelated area precedes the named catcher", root.dropArea(root.host) === decoy, true)
            Flea.ViewState.changeLeaf("places", { showTags: true, favourites: [{ label: "Drag hold", path: root.pane.path + "/Documents" }] })
            root.pane.tags().take([{ n: "note.txt", tg: ["Red"] }], true)
            return true
        }]
        root.cases.forEach(function (kind) {
            out.push(function () {
                root.row = root.findRow(kind)
                if (!root.row) return false
                // These rows gain their transfer DropAreas in look235; reproduce that child ownership on the real rail here.
                root.target = kind === "trash" ? root.dropArea(root.row) : childTarget.createObject(root.row, { keys: kind === "tag" ? [] : [DragOps.ROWS_MIME] })
                source.Drag.mimeData = DragOps.mimeFor(root.pane, [root.pane.total + 1], false)
                if (kind === "trash") {
                    root.report("the real Trash bridge accepts rows from the lifting backend", root.row.dropDecisions().accepts(source.Drag.mimeData[DragOps.ROWS_MIME], [], root.pane.path), true)
                    // Qt's internal drag carries no MIME data, so bridge decisions are checked separately from receiver priority.
                    root.target.entered.connect(root.acceptInternal)
                }
                root.moveTo(root.host, 1, root.host.height / 2)
                source.Drag.active = true
                return true
            })
            out.push(function () {
                if (!root.host.revealed || root.host.railX !== 0) return false
                root.moveTo(root.row, root.row.width / 2, root.row.height / 2)
                root.enteredAt = Date.now()
                return true
            })
            out.push(function () {
                if (Date.now() - root.enteredAt < root.host.settleMs + 300) return false
                root.report(kind + " row drag has no pointer or focus hold", [root.host.over, root.host.edgeShown, root.host.focusWanted], [false, false, false])
                root.report(kind + " child DropArea holds the row drag", root.target.containsDrag, true)
                root.report(kind + " row answers before the rail catcher", root.catcher ? root.catcher.containsDrag : "missing", false)
                root.report(kind + " row drag keeps the overlay rail revealed", root.host.revealed, true)
                root.report(kind + " row drag keeps the rail at x 0", root.host.railX, 0)
                root.moveTo(root.pane, root.pane.width * 0.6, root.pane.height / 2)
                source.Drag.active = false
                return true
            })
            out.push(function () {
                if (root.host.revealed || root.sidebar.parent.visible) return false
                root.report(kind + " row drag leaving lets the rail withdraw", root.host.railX, -root.sidebar.parent.width)
                if (kind === "trash") root.target.entered.disconnect(root.acceptInternal)
                else root.target.destroy()
                root.target = null
                return true
            })
        })
        return out
    }
}
