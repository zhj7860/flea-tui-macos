//@ pragma ShellId flea-rename-list-bottom-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Filter.js" as Filter

// The real ui/List.qml renames the last row of a long listing; its grown error editor must stay inside the viewport.
ShellRoot {
    id: root

    readonly property int totalRows: 1202
    readonly property int lastRow: totalRows - 1
    readonly property int stepTicks: 100
    readonly property int settleTicks: 6
    property int checks: 0
    property int failures: 0
    property var request: ({ source: "/fixture/f1199.txt", destination: "/fixture/pending.md" })
    property Item view: null
    property real parkedY: -1

    function check(ok, label) {
        root.checks += 1
        if (!ok) {
            root.failures += 1
            console.log("RENAMELISTBOTTOM FAIL " + label)
        }
    }

    function finish(note) {
        flowTimer.stop()
        if (note.length > 0) {
            root.failures += 1
            console.log("RENAMELISTBOTTOM FAIL " + note)
        }
        console.log("RENAMELISTBOTTOM DONE checks=" + root.checks + " failed=" + root.failures)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    Component { id: paneStub; RenamePaneStub {} }
    property var stubPane: paneStub.createObject(root, { mode: "list", totalRows: root.totalRows })

    Window {
        id: win
        width: 1000
        height: 700
        visible: true
        Component.onCompleted: {
            root.view = listComponent.createObject(win.contentItem, { pane: root.stubPane, menu: root.stubPane.menu, width: 1000, height: 619 })
            root.stubPane.listArea = root.view
            flowTimer.start()
        }
    }

    // Pane.qml wires the list's cursorClamped to Filter.clampCursor the same way.
    Connections {
        target: root.view
        function onCursorClamped(first, last) { Filter.clampCursor(root.stubPane, first, last) }
    }

    Component { id: listComponent; Flea.List {} }
    // A Grid or Columns editor showing an error line, which the hidden List must not read.
    QtObject {
        id: otherEditor
        property QtObject editorField: QtObject { property real errorHeight: 22 }
    }

    function cellNow() { return root.view ? root.view.itemAtIndex(root.lastView()) : null }
    function lastView() { return Filter.viewOf(root.stubPane.shown, root.lastRow) }
    function editorOf(cell) { return cell ? cell.editorField : null }
    function editorBegun() { var e = root.editorOf(root.cellNow()); return e !== null && e.begun }
    // The editor's own box in the viewport, the same terms ui/Ipc.qml's renameState reports.
    function editorBox() {
        var e = root.editorOf(root.cellNow())
        if (!e) return null
        var p = e.mapToItem(root.view, 0, 0)
        return { top: p.y, bottom: p.y + e.height, height: e.height }
    }

    property int step: 0
    property int waited: 0
    function settled() { return root.waited >= root.settleTicks }

    // Each entry is [ready, run]: run fires once ready answers true, and a step that never gets ready fails by name.
    readonly property var flow: [
        [function () { return root.view && root.view.count > 0 }, function () {
            root.view.forceActiveFocus()
            root.stubPane.setCursor(root.lastRow, 0)
        }],
        [function () { return root.settled() }, function () {
            root.stubPane.renamingIndex = root.lastRow
        }],
        [function () { return root.editorBegun() }, function () {
            var box = root.editorBox()
            root.check(box !== null && box.top >= 0 && box.bottom <= root.view.height,
                "open parks the last editor whole: top=" + (box ? box.top : -1) + " bottom=" + (box ? box.bottom : -1) + " height=" + root.view.height)
            root.parkedY = root.view.contentY
            root.stubPane.renameError = "b-existing1200.md already exists. Choose another name to preserve both files."
        }],
        [function () { var e = root.editorOf(root.cellNow()); return e !== null && e.errorHeight > 0 }, function () {
        }],
        [function () { return root.settled() }, function () {
            var box = root.editorBox()
            var e = root.editorOf(root.cellNow())
            console.log("RENAMELISTBOTTOM grown top=" + (box ? box.top : -1) + " bottom=" + (box ? box.bottom : -1)
                + " height=" + root.view.height + " contentY=" + root.view.contentY + " parkedY=" + root.parkedY
                + " errH=" + (e ? e.errorHeight : -1) + " rowHeight=" + (root.cellNow() ? root.cellNow().height : -1))
            root.check(e !== null && e.errorHeight > 0, "the refusal still expands the last row")
            root.check(box !== null && box.top >= 0 && box.bottom <= root.view.height,
                "grown last editor remains entirely within its viewport")
            root.check(root.view.containRenameError !== true, "the contain flag is spent once the growth lands")
            // Pane.qml keeps the List built, hidden, behind Grid and Columns.
            root.view.visible = false
            root.stubPane.renameError = ""
        }],
        [function () { return root.settled() }, function () {
            // Hiding took the List editor's focus and closed it; the rename reopens in the other view.
            root.stubPane.editorOverride = otherEditor
            root.stubPane.renamingIndex = root.lastRow
        }],
        [function () { return root.settled() }, function () {
            root.stubPane.renameError = "c-existing1201.md already exists. Choose another name to preserve both files."
        }],
        [function () { return root.settled() }, function () {
            root.check(root.stubPane.renamingIndex === root.lastRow, "the rename stays open behind the hidden List")
            root.check(root.view.renameErrorHeight === 0, "a hidden List reads no rename error height: " + root.view.renameErrorHeight)
            root.check(root.view.containRenameError !== true, "a hidden List arms no contain")
            root.check(root.view.count === 0, "a rename in another view builds no hidden List rows: " + root.view.count)
            root.finish("")
        }]
    ]

    Timer {
        id: flowTimer
        interval: 20
        repeat: true
        onTriggered: {
            var entry = root.flow[root.step]
            if (!entry[0]()) {
                root.waited += 1
                if (root.waited > root.stepTicks) { flowTimer.stop(); root.finish("step " + root.step + " never became ready") }
                return
            }
            root.waited = 0
            entry[1]()
            root.step += 1
        }
    }
}
