//@ pragma ShellId flea-search-sizes-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Search.js" as Search
import "flea/js/DirSizes.js" as DirSizes

// A folder row a live answer lists draws its size in the first frame it appears, once this search has seen that folder.
ShellRoot {
    id: root

    readonly property string fixture: Quickshell.env("SIZES_DIR")
    readonly property int tickMs: 20
    readonly property int giveUpMs: 10000
    // Past the list's settle timer and one dirsize round trip, so a size that would fill late has filled.
    readonly property int quietMs: 500
    // "s" lists every folder, "sc" drops the sand folders, one backspace lists them again, the next the folder's own rows; the grid draws no Size cell.
    readonly property var ops: [
        { open: true }, { start: true }, { strike: "s", label: "first key" }, { strike: "c", label: "narrowed" },
        { back: true, label: "widened again" }, { back: true, label: "cleared" }, { view: "grid" },
        { strike: "s", label: "grid view", bare: true }, { view: "list" }, { strike: "c", label: "list again", carries: true },
        { settle: 300 }
    ]
    property int at: 0
    property var awaiting: null
    property double stamp: Date.now()
    property int checks: 0
    property int failures: 0
    property var pane: null
    property var keys: null
    property int gen: 0
    property bool ticking: false
    // Every folder this search has drawn a complete size for, by full path, with its bytes.
    property var seen: ({})
    // The answer being watched: frames are sampled only while it is set.
    property var answer: null

    function check(label, actual, expected) {
        root.checks += 1
        var ok = JSON.stringify(actual) === JSON.stringify(expected)
        if (!ok) root.failures += 1
        console.log("SEARCHSIZES " + (ok ? "PASS " : "FAIL ") + label + " got=" + JSON.stringify(actual) + " expected=" + JSON.stringify(expected))
    }
    function finish() {
        console.log("SEARCHSIZES DONE checks=" + root.checks + " failed=" + root.failures)
        Qt.exit(root.failures > 0 ? 1 : 0)
    }
    // Each drawn folder row of the window: its full path, the Size cell text, the size state behind it and the size its line carried.
    function folders() {
        var out = []
        for (var i = 0; i < root.pane.visibleRows; i++) {
            var item = root.pane.visibleItemFor(i)
            if (!item || !item.visible || !item.row || !item.row.d) continue
            var size = item.dirSize
            out.push({ key: root.pane.join(Search.baseOf(root.pane), item.row.n), text: item.sizeText(),
                bytes: size && !size.partial ? size.bytes : null, carried: item.row.z === undefined ? null : item.row.z })
        }
        return out
    }
    function answered() { return root.pane.searchGen === root.gen && !root.pane.searchRunning && root.pane.searchSettledAt >= root.pane.searchKeyAt }
    function landed() { return !root.pane.listInFlight && root.pane.searchMode.length === 0 && root.pane.total > 0 }
    function quiet(since) { return Date.now() - since >= root.quietMs && !DirSizes.hasPending(root.pane.dirSizeState) }

    FloatingWindow {
        id: win
        implicitWidth: 1400
        implicitHeight: 1000
        color: Flea.Theme.color.background
    }
    Flea.Backend { id: realBackend }
    Component {
        id: paneComponent
        Flea.Pane {
            width: 1400
            height: 1000
            backend: realBackend
        }
    }

    // Each rows landing marks the next frame as the one the answer's rows first appear in.
    Connections {
        target: root.pane
        enabled: root.answer !== null
        function onRowsChanged() {
            root.answer.lands += 1
            root.answer.landAt = Date.now()
            for (var i = 0; i < root.pane.rows.length; i++)
                if (root.pane.rows[i].z !== undefined) root.answer.inlined.push(root.pane.held + i)
        }
        function onDirSizeStateChanged() { root.answer.writes += 1 }
    }
    // Every row the list asks a dirsize for while the answer is watched.
    Connections {
        target: root.pane ? root.pane.listArea : null
        enabled: root.answer !== null
        function onDirSizesApplied(ask) { root.answer.asked = root.answer.asked.concat(ask) }
    }
    // What each frame draws, read after polish and before the scene is synced, so it is the frame on screen.
    Connections {
        target: win.contentItem.Window.window
        function onAfterAnimating() {
            if (root.answer !== null && root.answer.lands > 0 && !root.answer.bare) root.sample(root.answer)
        }
    }

    // A folder seen before must draw its size the first frame it appears; any folder's Size cell, once drawn, never changes in this answer.
    function sample(a) {
        a.frames += 1
        var rows = root.folders()
        for (var i = 0; i < rows.length; i++) {
            var row = rows[i]
            var first = a.first[row.key]
            if (first === undefined) {
                a.first[row.key] = { text: row.text, sized: row.bytes !== null }
                if (row.carried !== null && row.bytes !== row.carried) a.inlineLate.push(row.key + " " + row.text)
                if (row.bytes === null) {
                    a.unsized += 1
                    if (root.seen[row.key] !== undefined) a.unsizedSeen.push(row.key)
                } else if (root.seen[row.key] !== undefined && root.seen[row.key] !== row.bytes) {
                    a.wrong.push(row.key + " " + row.bytes + " not " + root.seen[row.key])
                }
            } else if (first.text !== row.text) {
                // A placeholder that fills is what a listing draws for a folder it has not sized; a drawn size that changes is not.
                if (first.sized) a.changed.push(row.key + " " + first.text + " to " + row.text)
                else a.filled += 1
                a.first[row.key] = { text: row.text, sized: row.bytes !== null }
            }
        }
    }

    Timer {
        interval: root.tickMs
        running: true
        repeat: true
        onTriggered: {
            if (root.ticking) return
            root.ticking = true
            try { root.tick() } finally { root.ticking = false }
        }
    }

    function tick() {
        if (Date.now() - root.stamp > root.giveUpMs) {
            root.check("probe completes", "timeout at op " + root.at + " " + JSON.stringify(root.ops[root.at - 1]), "complete")
            root.finish()
            return
        }
        if (root.awaiting !== null && !root.awaiting()) return
        root.awaiting = null
        if (root.at >= root.ops.length) {
            root.finish()
            return
        }
        root.stamp = Date.now()
        root.run(root.ops[root.at])
        root.at += 1
    }

    // One key, then every frame until the answer and its sizes are quiet; the counts are per answer.
    function strike(character, label, bare, carries) {
        root.gen += 1
        var a = { label: label, bare: bare === true, carries: carries === true, lands: 0, landAt: 0, frames: 0, writes: 0, unsized: 0, filled: 0, first: ({}),
            unsizedSeen: [], wrong: [], changed: [], inlineLate: [], inlined: [], asked: [], asks: realBackend.dirSizeRequests }
        root.answer = a
        if (character === "BS") Search.shrink(root.pane)
        else Search.extend(root.pane, character)
        root.awaiting = function () {
            if (!root.answered() || a.lands === 0 || !root.quiet(a.landAt)) return false
            root.answer = null
            root.verdict(a)
            return true
        }
    }

    function verdict(a) {
        var asks = realBackend.dirSizeRequests - a.asks
        if (a.bare) {
            console.log("SEARCHSIZES COUNTS " + a.label + " lands=" + a.lands + " inlined=" + a.inlined.length + " dirsizeAsks=" + asks)
            root.check(a.label + ": the answer landed", a.lands > 0, true)
            root.check(a.label + ": an answer to a view with no Size cell carries no folder size", a.inlined, [])
            return
        }
        var rows = root.folders()
        console.log("SEARCHSIZES COUNTS " + a.label + " folders=" + rows.length + " lands=" + a.lands + " frames=" + a.frames
            + " unsizedAtFirstFrame=" + a.unsized + " filledLater=" + a.filled + " inlined=" + a.inlined.length
            + " dirsizeAsks=" + asks + " askedRows=" + a.asked.length + " sizeStateWrites=" + a.writes)
        root.check(a.label + ": a frame drew the answer", a.frames > 0, true)
        if (a.carries) root.check(a.label + ": the session still carries the sizes it knows once a view draws them", a.inlined.length > 0, true)
        root.check(a.label + ": a size its line carried draws in the frame its row first appears", a.inlineLate, [])
        root.check(a.label + ": a row whose line carried its size is never asked for it",
            a.asked.filter(function (row) { return a.inlined.indexOf(row) >= 0 }), [])
        root.check(a.label + ": every folder this search sized before draws its size in the frame it appears", a.unsizedSeen, [])
        root.check(a.label + ": a size drawn in the first frame is the folder's size", a.wrong, [])
        root.check(a.label + ": no drawn size changes later in the answer", a.changed, [])
        var known = rows.every(function (row) { return root.seen[row.key] !== undefined })
        // An answer that lists only folders this search sized before asks the backend for no size at all.
        if (known) root.check(a.label + ": an answer of sized folders asks for no dirsize", asks, 0)
        // After the answer is quiet every folder row holds its whole size, which the next answer is held to.
        root.check(a.label + ": every folder row is sized once the answer is quiet", rows.filter(function (row) { return row.bytes === null }).length, 0)
        for (var i = 0; i < rows.length; i++)
            if (rows[i].bytes !== null) root.seen[rows[i].key] = rows[i].bytes
    }

    function run(op) {
        if (op.open) {
            Flea.ViewState.changeKey("view", "list")
            root.pane = paneComponent.createObject(win.contentItem)
            root.keys = Qt.createQmlObject("import QtTest; TestEvent {}", root.pane.listArea)
            root.pane.open(root.fixture)
            var since = Date.now()
            // The folder's own listing sizes its folders first, which proves the Size column is on for this storage.
            root.awaiting = function () {
                if (!root.landed() || !root.quiet(since)) return false
                var rows = root.folders()
                return rows.length > 0 && rows.every(function (row) { return row.bytes !== null })
            }
        } else if (op.start) {
            root.pane.listArea.forceActiveFocus()
            root.keys.keyClickChar("f", Qt.NoModifier, -1)
            root.awaiting = function () { return root.pane.searchMode === "typing" }
        } else if (op.view !== undefined) {
            root.pane.chooseView(op.view)
            root.awaiting = function () { return root.pane.viewMode === op.view }
        } else if (op.strike !== undefined) {
            root.strike(op.strike, op.label, op.bare, op.carries)
        } else if (op.back) {
            root.strike("BS", op.label)
        } else if (op.settle !== undefined) {
            // Rows still building at exit warn as items in creation at engine destruction.
            var until = Date.now() + op.settle
            root.awaiting = function () { return Date.now() >= until }
        }
    }
}
