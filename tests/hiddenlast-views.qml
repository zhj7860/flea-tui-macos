//@ pragma ShellId flea-hiddenlast-views-test

import QtQuick
import Quickshell
import "flea" as Flea

// "Hidden files last" orders one folder the same way through every request a view sends, on the real backend: a pane's list and sort, a column's peek, then the chooser's list and its header sort, with the setting on and then off in one run.
ShellRoot {
    id: root

    readonly property string fixture: Quickshell.env("HLV_DIR")
    readonly property int tickMs: 20
    readonly property int giveUpMs: 20000
    readonly property int windowRows: 50
    // The fixture is .config (dir), Alpha (dir), .hidden, .zeta, beta, gamma; folders first holds inside each part and names order by name_order (src/backend/sort.rs), so a dot sorts before a letter, and a reversed sort reverses the visible files and the hidden files alike (.hidden .zeta becomes .zeta .hidden) while the hidden part still follows every visible entry.
    readonly property var plainAsc: [".config", "Alpha", ".hidden", ".zeta", "beta", "gamma"]
    readonly property var plainDesc: ["Alpha", ".config", "gamma", "beta", ".zeta", ".hidden"]
    readonly property var lastAsc: ["Alpha", "beta", "gamma", ".config", ".hidden", ".zeta"]
    readonly property var lastDesc: ["Alpha", "gamma", "beta", ".config", ".zeta", ".hidden"]
    property var steps: []
    property int at: 0
    property bool armed: false
    property double armedAt: 0
    property var landed: null
    property bool peekEcho: false
    property var win: null
    property int checks: 0
    property int failures: 0
    property bool finished: false

    function names(items) { return items.map(function (row) { return row.n }) }
    function check(label, got, want) {
        root.checks += 1
        var ok = JSON.stringify(got) === JSON.stringify(want)
        if (!ok) root.failures += 1
        console.log("HLV " + (ok ? "PASS " : "FAIL ") + label + " got=" + JSON.stringify(got) + " expected=" + JSON.stringify(want))
    }
    function finish() {
        if (root.finished) return
        root.finished = true
        console.log("HLV DONE " + root.checks + " checks, " + root.failures + " failed")
        Qt.exit(root.failures > 0 ? 1 : 0)
    }
    function pickerRows() {
        return root.win && root.win.listingState === "ready" && root.win.rows.length === root.plainAsc.length ? root.names(root.win.rows) : null
    }

    // One setting, five requests: the order each must answer is the setting's, never a path's.
    function setting(on) {
        var tag = on ? "on " : "off "
        var asc = on ? root.lastAsc : root.plainAsc
        var desc = on ? root.lastDesc : root.plainDesc
        return [
            { label: tag + "pane list", start: function () { be.list(root.fixture, root.windowRows, true, false) }, read: function () { return root.landed }, want: asc },
            { label: tag + "pane sort", start: function () { be.sort("name", true); be.window(0, root.windowRows) }, read: function () { return root.landed }, want: desc },
            { label: tag + "column peek", start: function () { be.peek(root.fixture, root.windowRows, true) }, read: function () { return root.landed }, want: asc },
            { label: tag + "column peek echoes the setting", start: function () { be.peek(root.fixture, root.windowRows, true) }, read: function () { return root.landed === null ? null : root.peekEcho }, want: on },
            { label: tag + "chooser list", start: function () { root.win.showHidden = true; root.win.openWithoutHistory(root.fixture) }, read: root.pickerRows, want: asc },
            { label: tag + "chooser header sort", start: function () { root.win.requestSort({ key: "name", desc: true }) }, read: function () { return root.win.sortDesc ? root.pickerRows() : null }, want: desc }
        ]
    }

    Flea.Backend { id: be }

    Connections {
        target: be
        function onRows(start, items) { if (start === 0 && root.armed) root.landed = root.names(items) }
        function onPeeked(path, hidden, total, rows, readFailed, mode, hiddenLast) {
            if (!root.armed || path !== root.fixture) return
            root.peekEcho = hiddenLast
            root.landed = root.names(rows)
        }
    }

    Component.onCompleted: {
        var comp = Qt.createComponent("flea/PickerWindow.qml")
        if (comp.status !== Component.Ready) {
            console.log("HLV FAIL compile " + comp.errorString())
            Qt.exit(1)
            return
        }
        root.win = comp.createObject(root).pickerWin
        // The chooser's header sort writes the default sort and keeps its own until the window closes, so the second pass puts both back before it lists.
        root.steps = root.setting(true).concat([{ label: "setting off and the default sort back", start: function () { Flea.ViewState.changeKey("hiddenLast", false); Flea.ViewState.changeLeaf("sort", { key: "name", reverse: false }); root.win.requestSort({ key: "name", desc: false }) }, read: function () { return root.win.sortDesc ? null : root.pickerRows() } }], root.setting(false))
        root.armedAt = Date.now()
    }

    Timer {
        interval: root.tickMs
        running: true
        repeat: true
        onTriggered: {
            if (root.finished) return
            if (Date.now() - root.armedAt > root.giveUpMs) {
                root.check("step " + (root.at < root.steps.length ? root.steps[root.at].label : "?") + " answers", "timeout", "answer")
                root.finish()
                return
            }
            if (root.at >= root.steps.length) { root.finish(); return }
            // The chooser answers its own first listing before any step asks it for another.
            if (root.at === 0 && !(root.win && root.win.listingState === "ready")) return
            var step = root.steps[root.at]
            if (!root.armed) {
                root.landed = null
                root.peekEcho = false
                root.armed = true
                root.armedAt = Date.now()
                step.start()
                return
            }
            var got = step.read()
            if (got === null || got === undefined) return
            if (step.want !== undefined) root.check(step.label, got, step.want)
            root.armed = false
            root.at += 1
            root.armedAt = Date.now()
        }
    }
}
