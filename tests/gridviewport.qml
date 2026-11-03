//@ pragma ShellId flea-gridviewport-test
import QtQuick
import QtTest
import Quickshell
import "flea" as Flea

// A switch to Grid builds only the viewport's tiles before its first frame, the cache rows after it, and draws no half-built frame: a real pane, counted, never timed.
// Sample output: "GRIDVIEWPORT SWITCH first to=grid frames=2 partial=0 held=0 built=66 firstFrame=52 reused=0 cols=7 vrows=7 plan=66 live=66".
ShellRoot {
    id: root
    readonly property string fixture: Quickshell.env("FLEA_GV_DIR") || ""
    readonly property int entries: Number(Quickshell.env("FLEA_GV_ENTRIES") || "0")
    property int checks: 0
    property int failures: 0
    property int frames: 0
    property var pane: null
    property var steps: []
    property var waitFor: null
    property double waitUntil: 0
    property double deadline: 0
    property bool quietNeeded: false
    property int quietMark: -1
    property double quietSince: 0
    property double railBy: 0
    // Frames since the key, and how many of them drew a Grid with tiles that were not whole.
    property int keyFrames: 0
    property int partialFrames: 0
    property int builtAtKey: 0
    property int heldAtKey: -1
    property double keyAt: 0
    property double keyDoneAt: 0
    // Tiles the Grid held, and how many of them this switch built, on the first frame that draws the Grid; -1 until one does.
    property int firstFrameTiles: -1
    property int firstFrameBuilt: -1

    function fail(text) {
        failures += 1
        console.log("GRIDVIEWPORT FAIL " + text)
    }
    function check(name, ok, detail) {
        checks += 1
        if (!ok) fail(name + " " + detail)
        else console.log("GRIDVIEWPORT ok " + name)
    }
    function finish() {
        ticker.stop()
        console.log("GRIDVIEWPORT DONE " + checks + " checks, " + failures + " failed")
        Qt.quit()
    }
    function isGrid(area) { return area !== null && area.columns !== undefined }
    // The Grid is whole when it is up, visible, past its hold and drew its first tile.
    function whole() {
        if (!pane) return false
        var area = pane.listArea
        return pane.viewMode === "grid" && isGrid(area) && area.visible && !area.hiddenHeld && area.count > 0 && area.itemAtIndex(0) !== null
    }
    // The Grid wherever it sits, hidden or not; the pane exposes it only while it is the view in use.
    function findGrid(item) {
        if (!item) return null
        if (item.cellHeightPx !== undefined && item.prebuild !== undefined) return item
        var kids = item.children || []
        for (var i = 0; i < kids.length; i++) {
            var hit = findGrid(kids[i])
            if (hit) return hit
        }
        return null
    }
    // Tiles the Grid lays out now: parked and pooled ones are not in its content.
    function laidOut(grid) {
        var n = 0, kids = grid.contentItem.children
        for (var i = 0; i < kids.length; i++)
            if (kids[i].index !== undefined && kids[i].prebuilt !== true && kids[i].pooled !== true && kids[i].parent === grid.contentItem) n++
        return n
    }
    function built() { var grid = findGrid(pane); return grid ? grid.prebuild.createdCount : 0 }
    // Every delegate the Grid holds, parked and pooled ones too; a hidden Grid holds none.
    function held() { var grid = findGrid(pane); return grid ? grid.prebuild.createdCount - grid.prebuild.destroyedCount : 0 }
    function landed() {
        return !pane.listInFlight && !pane.swap.holding && pane.total === entries
    }
    function quiet() { root.quietNeeded = true; root.quietMark = -1; root.railBy = Date.now() + 4000 }
    function railSettled() { return pane !== null && pane.sidebar !== null && pane.sidebar.railDeadlineElapsed }
    // A frame draws the Grid when the pane is on it, it is visible and it holds a tile.
    function drawsGrid() {
        var grid = findGrid(pane)
        return pane !== null && pane.viewMode === "grid" && grid !== null && grid.visible && laidOut(grid) > 0
    }
    // One switch: the chord, then frames counted until the Grid is whole and the hold has ended.
    function switchTo(name, key) {
        return [
            quiet,
            function () {
                root.keyFrames = root.frames
                root.partialFrames = 0
                root.builtAtKey = root.built()
                root.heldAtKey = root.held()
                pane.listArea.forceActiveFocus()
                root.firstFrameTiles = -1
                root.firstFrameBuilt = -1
                root.keyAt = Date.now()
                root.keyDoneAt = 0
                // keyClick spins the event loop, so the wait is armed first and holds the report until the click has returned.
                root.waitUntil = Date.now() + 3000
                root.waitFor = function () { return root.keyDoneAt > 0 && root.whole() }
                keys.keyClick(key, Qt.ControlModifier, -1)
                root.keyDoneAt = Date.now()
            },
            function () {
                var area = pane.listArea
                var viewport = area.columns * area.visibleTileRows
                console.log("GRIDVIEWPORT SWITCH " + name + " to=grid frames=" + (root.frames - root.keyFrames) + " partial=" + root.partialFrames + " held=" + root.heldAtKey
                    + " built=" + (root.built() - root.builtAtKey) + " firstFrame=" + root.firstFrameTiles + " reused=" + (root.firstFrameTiles - root.firstFrameBuilt)
                    + " cols=" + area.columns + " vrows=" + area.visibleTileRows + " plan=" + area.landingTiles + " live=" + root.laidOut(area))
                check(name + ": the Grid is whole after the key", root.whole(), "viewMode=" + pane.viewMode)
                check(name + ": no frame drew a half-built Grid", root.partialFrames === 0, "partial=" + root.partialFrames)
                // The hidden Grid's model drains on hide (StableModel.drainHidden), so every switch builds its tiles and takes none from a pool.
                check(name + ": the hidden Grid held no delegate at the key", root.heldAtKey === 0, "held=" + root.heldAtKey)
                // The first frame that draws the Grid holds the viewport's tiles and one spare row at most; the cache rows come after it.
                check(name + ": the first Grid frame holds the viewport's tiles and no cache row", root.firstFrameTiles >= viewport && root.firstFrameTiles <= area.columns * (area.visibleTileRows + 1), "first=" + root.firstFrameTiles + " viewport=" + viewport)
                check(name + ": the first Grid frame reused no tile", root.firstFrameTiles >= 0 && root.firstFrameTiles === root.firstFrameBuilt, "first=" + root.firstFrameTiles + " built=" + root.firstFrameBuilt)
            },
            function () { root.waitUntil = Date.now() + 3000; root.waitFor = function () { var g = root.findGrid(pane); return root.laidOut(g) >= g.landingTiles } },
            function () {
                var g = root.findGrid(pane)
                check(name + ": the cache rows are laid out after the frame, none missing", root.laidOut(g) >= g.landingTiles, "laidOut=" + root.laidOut(g) + " plan=" + g.landingTiles)
            }
        ]
    }
    // A chord back to another view, and the pane really on it with the Grid hidden.
    function back(name, key, mode) {
        return [
            quiet,
            function () {
                pane.listArea.forceActiveFocus()
                keys.keyClick(key, Qt.ControlModifier, -1)
                root.waitUntil = Date.now() + 3000
                root.waitFor = function () { var g = root.findGrid(pane); return pane.viewMode === mode && g !== null && !g.visible }
            },
            function () { check(name + ": the " + mode + " view is up and the Grid hidden", pane.viewMode === mode && !root.findGrid(pane).visible, "viewMode=" + pane.viewMode) }
        ]
    }

    FloatingWindow {
        id: win
        implicitWidth: 1200
        implicitHeight: 800
        Flea.Backend { id: probeBackend }
        Component {
            id: paneComponent
            Flea.Pane {
                width: 1200
                height: 800
                backend: probeBackend
            }
        }
        TestEvent { id: keys }
        Item {
            id: frameProbe
            Connections {
                target: frameProbe.Window.window
                function onFrameSwapped() {
                    root.frames += 1
                    if (root.keyAt <= 0 || root.frames <= root.keyFrames || !root.pane || root.pane.viewMode !== "grid") return
                    if (root.drawsGrid() && root.firstFrameTiles < 0) {
                        root.firstFrameTiles = root.laidOut(root.findGrid(root.pane))
                        root.firstFrameBuilt = root.built() - root.builtAtKey
                    }
                    if (!root.whole()) root.partialFrames += 1
                }
            }
        }
    }

    Component.onCompleted: {
        steps = [
            function () { pane = paneComponent.createObject(win.contentItem); pane.open(fixture); root.waitFor = landed },
            function () {
                check("the fixture is listed whole", pane.total === entries, "total=" + pane.total)
                check("the view is list", pane.viewMode === "list", "viewMode=" + pane.viewMode)
            }
        ].concat(switchTo("first", Qt.Key_3), back("grid to list", Qt.Key_1, "list"), switchTo("second", Qt.Key_3), back("grid to columns", Qt.Key_2, "columns"), switchTo("third", Qt.Key_3), [finish])
        deadline = Date.now() + 40000
    }

    Timer {
        id: ticker
        interval: 10
        running: true
        repeat: true
        onTriggered: {
            if (Date.now() > root.deadline) {
                root.fail("stalled with " + root.steps.length + " steps left")
                root.finish()
                return
            }
            if (root.quietNeeded) {
                if (!root.railSettled()) {
                    root.quietMark = -1
                    if (Date.now() > root.railBy) { root.fail("the rail never settled"); root.finish() }
                    return
                }
                if (root.quietMark !== root.frames) { root.quietMark = root.frames; root.quietSince = Date.now(); return }
                if (Date.now() - root.quietSince < 300) return
                root.quietNeeded = false
            }
            if (root.waitFor ? !root.waitFor() && (root.waitUntil === 0 || Date.now() < root.waitUntil)
                             : Date.now() < root.waitUntil) return
            root.waitFor = null
            root.waitUntil = 0
            if (root.steps.length === 0) return
            var step = root.steps[0]
            root.steps = root.steps.slice(1)
            try {
                step()
            } catch (error) {
                root.fail("a step threw: " + error)
                root.finish()
            }
        }
    }
}
