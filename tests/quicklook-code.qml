//@ pragma ShellId flea-quicklook-code-test

import QtQuick
import Quickshell
import Quickshell.Io
import "flea" as Flea
import "langmark-count.js" as LangCost
import "flea/js/Icons.js" as Icons

// The full backend/bat sequence starts schema-seeded; quicklook-code-defaults.qml separately tests empty and explicit-OFF states with wrap absent.
ShellRoot {
    id: root

    readonly property bool again: Quickshell.env("QLCODE_RUN") === "again"
    readonly property int settleMs: 250
    readonly property int giveUpMs: 12000
    readonly property int fixtureRows: 10
    // The fixture's lines: the 132-line file, and the long file's 60 lines with the 6,000-character one at 40.
    readonly property int iconLines: 132
    readonly property int longAt: 40
    readonly property int longChars: 6000
    // 03-remote.txt: a markup line and an ampersand line, read on the remote route.
    readonly property var remoteLines: ["first line", "<img src=\"http://127.0.0.1:9/x\">", "a & b"]
    property int checks: 0
    property int failures: 0
    property int at: 0
    property var awaiting: null
    property var keys: null
    property double stamp: Date.now()
    property double calmFrom: 0
    property bool ticking: false
    property bool finished: false
    // Every reply the Quick Look slot received: its first and last line.
    property var replies: []
    // Live frames judged while a move runs: the lines drawn in them are coloured.
    property bool sampling: false
    property int liveFrames: 0
    property int midBase: 0
    property var bad: []
    // The backend the remote leg wraps to record what Quick Look asks of it.
    property var spy: null
    property int topBefore: 0
    property int lastTop: 0

    readonly property var freshOps: [{ boot: true }, { open: "00-notes.md" }, { markdownW: true },
        { move: "01-icons.rs", kind: "styled" }, { icons: true }, { scrollEnd: true }, { tab: true },
        { move: "02-more.rs", kind: "styled", walk: true }, { move: "03-plain.txt", kind: "text" },
        { remoteOn: true }, { move: "03-remote.txt", kind: "remote" }, { move: "04-nul.txt", kind: "binary" }, { move: "05-over.log", kind: "large" },
        { move: "06-long.rs", kind: "plain" }, { wrap: true }, { reopen: true }, { tabReturn: true },
        { csv: "07-table.csv" }, { csv: "08-table.tsv" }, { done: true }]
    readonly property var againOps: [{ boot: true }, { open: "01-icons.rs", remembered: true }, { unwrap: true }, { done: true }]
    readonly property var ops: root.again ? root.againOps : root.freshOps

    function log(line) { console.log("QLCODE " + line) }
    function check(label, actual, expected) {
        root.checks += 1
        var ok = JSON.stringify(actual) === JSON.stringify(expected)
        if (!ok) root.failures += 1
        root.log((ok ? "PASS " : "FAIL ") + label + " got=" + JSON.stringify(actual) + " expected=" + JSON.stringify(expected))
    }
    function finish() {
        if (root.finished) return
        root.finished = true
        root.log("DONE " + root.checks + " checks, " + root.failures + " failed")
        quitter.start()
    }
    function pane() { return body.item ? body.item.currentPane : null }
    function pv() { return root.pane() ? root.pane().preview : null }
    function descendants(item) {
        var out = [item]
        for (var i = 0; i < out.length; i++) {
            var kids = out[i].children || []
            for (var j = 0; j < kids.length; j++) out.push(kids[j])
        }
        return out
    }
    function within(item, test) { return item ? root.descendants(item).filter(test) : [] }
    function textPane() {
        var p = root.pv()
        var found = root.within(p ? p.panesItem : null, function (n) { return typeof n.keepTop === "function" })
        return found.length > 0 ? found[0] : null
    }
    function code() { var t = root.textPane(); return t ? t.bodyItem : null }
    function checkTextState(label, wrapped, total) {
        var state = JSON.parse(previewReader.previewTextState(false))
        root.check(label, [state.path, state.visible, state.ready, state.wrap, state.total],
            [root.textPane().path, true, true, wrapped, total])
    }
    function bar() {
        var found = root.within(root.textPane(), function (n) { return typeof n.geometry === "function" && typeof n.closeState === "function" })
        return found.length > 0 ? found[0] : null
    }
    // The StyledText bodies the line view has built and shows, top to bottom.
    function bodies() {
        var c = root.code()
        return root.within(c, function (n) { return n.visible && n.textFormat === Text.StyledText })
            .sort(function (a, b) { return a.mapToItem(c, 0, 0).y - b.mapToItem(c, 0, 0).y })
    }
    // The line numbers drawn: the PlainText Texts that read as a bare number.
    function gutters() {
        return root.within(root.code(), function (n) { return n.visible && n.textFormat === Text.PlainText && /^[0-9]+$/.test(n.text) })
    }
    function frameText() {
        var found = root.within(root.textPane(), function (n) { return n.visible && n.textFormat === Text.PlainText && (n.text === "binary file" || n.text === "too large to preview") })
        return found.length > 0 ? found[0].text : ""
    }
    function nameOf() { var t = root.textPane(); return t && t.path ? t.path.split("/").pop() : "" }
    function topLine() { var l = root.textPane().list; return Math.max(0, l.indexAt(0, l.contentY + 1)) + 1 }
    function key(text) { root.keys.keyClickChar(text, Qt.NoModifier, -1) }
    function press(code) { root.keys.keyClick(code, Qt.NoModifier, -1) }
    function calm(ok) {
        if (!ok) { root.calmFrom = 0; return false }
        if (root.calmFrom === 0) root.calmFrom = Date.now()
        return Date.now() - root.calmFrom >= root.settleMs
    }
    function indexOf(name) {
        for (var i = 0; i < root.pane().total; i++) {
            var row = root.pane().rowFor(i)
            if (row && row.n === name) return i
        }
        return -1
    }
    // ui.json as the backend wrote it, "" until a write has landed.
    function savedWrap() {
        uiFile.reload()
        var m = /"wrap":\s*(true|false)/.exec(uiFile.text())
        return m ? m[1] : ""
    }
    // The file's own state once drawn: the answer is in, the lines in view are held, and the swap has let go of the picture before it.
    function drawn(name, kind) {
        var t = root.textPane(), c = root.code()
        if (t === null || c === null || !root.pv().active || root.nameOf() !== name) return false
        if (kind === "large") return t.tooLarge && root.pv().lookReady
        if (!c.active) return false
        if (kind === "binary") return c.answer === "binary" && root.pv().lookReady
        if (kind === "text" || kind === "remote") return c.settled && c.firstScreen && root.pv().lookReady
        return c.answer === kind && c.firstScreen && root.pv().lookReady && root.pv().swapState().holding === false
    }
    function begin() {
        root.replies = []
        root.bad = []
        root.liveFrames = 0
        if (root.spy) root.spy.asks = []
        root.midBase = root.pv() ? root.pv().swapState().midFrames : 0
    }
    // Every frame drawn while a move runs: whatever lines are on screen are coloured.
    function sample() {
        if (!root.sampling || !root.pv() || !root.pv().active) return
        var texts = root.bodies().filter(function (t) { return t.text.length > 0 })
        if (texts.length === 0) return
        root.liveFrames += 1
        var plain = texts.filter(function (t) { return t.text.indexOf("<font") < 0 })
        if (plain.length > 0 && root.bad.length < 5) root.bad.push("an uncoloured line at " + root.nameOf())
    }

    // What a stalled op saw, for the log.
    function stalled() {
        var p = root.pv(), t = root.textPane(), c = root.code()
        return "preview=" + (p ? p.active + "/" + p.kind + "/" + p.status + "/" + p.lookReady : "none") + " pane=" + (t ? t.path.split("/").pop() + "/" + t.status : "none")
            + " code=" + (c ? c.answer + "/" + c.total + "/" + c.firstScreen : "none") + " cursor=" + (root.pane() ? root.pane().cursorIndex : -1)
            + (t ? " top=" + root.topLine() + " longest=" + root.bodies().reduce(function (m, b) { return Math.max(m, b.text.length) }, 0) + " wrap=" + t.wrap + "/" + Flea.ViewState.previewWrap : "")
    }

    function run(op) {
        root.awaiting = null
        if (op.boot) {
            root.awaiting = function () {
                var p = root.pane()
                if (!p || p.listInFlight || p.listingState !== "ready" || p.total < root.fixtureRows || !p.storageKnown) return false
                root.keys = Qt.createQmlObject("import QtTest; TestEvent {}", p.listArea)
                p.listArea.forceActiveFocus()
                if (root.again) {
                    root.check("a ui.json that holds wrap on starts wrapped", Flea.ViewState.previewWrap, true)
                } else {
                    root.check("a schema-seeded ui.json starts unwrapped", [Flea.ViewState.previewWrap, root.savedWrap()], [false, "false"])
                    root.check("no Quick Look is built before the first Space", root.pv(), null)
                }
                return true
            }
        } else if (op.open !== undefined) {
            root.begin()
            root.pane().cursorIndex = root.indexOf(op.open)
            root.press(Qt.Key_Space)
            root.awaiting = function () {
                var p = root.pv()
                if (!p || !p.active) return false
                if (op.open.slice(-3) === ".md") return root.calm(p.isMarkdown && p.markdownShown !== null && p.markdownShown.contentReady)
                if (!root.calm(root.drawn(op.open, "styled"))) return false
                if (op.remembered) {
                    root.check("a Quick Look opened under a remembered wrap draws wrapped", [root.textPane().wrap, root.code().wrap], [true, true])
                    root.checkTextState("Quick Look IPC reports remembered wrap and ready code", true, root.iconLines)
                }
                return true
            }
        } else if (op.markdownW) {
            root.key("w")
            root.awaiting = function () {
                if (!root.calm(true)) return false
                root.check("w on a Markdown Quick Look flips nothing", [Flea.ViewState.previewWrap, root.pv().isCodeText, root.savedWrap() !== "true"], [false, false, true])
                root.check("and the Markdown bar has no view control", !root.pv().markdownShown.barGeometry().segment, true)
                return true
            }
        } else if (op.move !== undefined) {
            root.begin()
            root.sampling = !!op.walk
            root.key("j")
            root.awaiting = function () {
                if (!root.calm(root.drawn(op.move, op.kind))) return false
                root.sampling = false
                root.judgeMove(op)
                return true
            }
        } else if (op.remoteOn) {
            root.remoteRoute()
        } else if (op.icons) {
            root.judgeIcons()
        } else if (op.scrollEnd) {
            var list = root.textPane().list, cl = root.code()
            root.replies = []
            list.contentY = list.contentHeight - list.height
            root.awaiting = function () {
                if (!root.calm(cl.covered(root.iconLines - 3, root.iconLines))) return false
                var want = cl.needed()
                root.check("scrolling to the end asks for the lines in view and one screen above, and ends at the file's last line",
                    [root.replies.length > 0, root.replies.every(function (r) { return r.first >= want.from && r.last <= want.to }), want.to],
                    [true, true, root.iconLines])
                root.check("and the last line is drawn", root.bodies().some(function (b) { return b.text.replace(/<[^>]*>/g, "").indexOf("fn f" + root.iconLines + "(") === 0 }), true)
                return true
            }
        } else if (op.tab) {
            root.press(Qt.Key_Tab)
            root.awaiting = function () {
                if (!root.calm(true)) return false
                root.check("Tab puts the keyboard on the close mark", [root.pv().markdownCloseFocused, root.bar().closeState().focused], [true, true])
                root.press(Qt.Key_Tab)
                return true
            }
        } else if (op.wrap) {
            root.wrapSequence()
        } else if (op.reopen) {
            root.press(Qt.Key_Space)
            root.awaiting = function () {
                if (root.pv().active) return false
                root.press(Qt.Key_Space)
                root.awaiting = function () {
                    if (!root.calm(root.drawn("06-long.rs", "plain"))) return false
                    root.check("closing and reopening Quick Look keeps the wrap", [root.textPane().wrap, root.longBody().lineCount > 3], [true, true])
                    return true
                }
                return false
            }
        } else if (op.tabReturn) {
            root.press(Qt.Key_Tab)
            root.awaiting = function () {
                if (!root.calm(root.pv().markdownCloseFocused)) return false
                root.press(Qt.Key_Return)
                root.awaiting = function () {
                    if (root.pv().active) return false
                    root.check("Return on the focused close mark closes Quick Look", root.pv().active, false)
                    return true
                }
                return false
            }
        } else if (op.unwrap) {
            root.key("w")
            root.awaiting = function () {
                if (!root.calm(Flea.ViewState.previewWrap === false && root.savedWrap() === "false")) return false
                root.check("w unwraps and the unwrapped choice is written", [root.textPane().wrap, root.savedWrap()], [false, "false"])
                root.checkTextState("Quick Look IPC reports w unwrapped and ready code", false, root.iconLines)
                return true
            }
        } else if (op.csv) {
            if (root.pv().active) root.key("j")
            else {
                root.pane().setCursor(root.indexOf(op.csv))
                root.press(Qt.Key_Space)
            }
            root.awaiting = function () {
                if (!root.calm(root.nameOf() === op.csv && root.code() && root.code().firstScreen && root.pv().lookReady)) return false
                var state = JSON.parse(previewReader.previewTextState(false))
                root.check("Quick Look IPC reports ready " + op.csv,
                    [state.path, state.ready, state.wrap, state.total, state.height > 0],
                    [root.textPane().path, true, null, 3, true])
                return true
            }
        } else if (op.done) {
            root.finish()
        }
    }

    // The 6,000-character line's body text.
    function longBody() {
        var found = root.bodies().filter(function (b) { return b.text.length > root.longChars - 100 })
        return found.length > 0 ? found[0] : null
    }
    // The pane as Preview.qml sets it on network or phone storage (truncate), its backend wrapped to record each ask.
    function remoteRoute() {
        var t = root.textPane(), real = t.backend
        root.spy = Qt.createQmlObject("import QtQuick; QtObject { property var real: null; property var asks: []; signal codeResult(var message)\n"
            + "function askCode(slot, source, first, count) { asks.push(source); return real.askCode(slot, source, first, count) } }", root)
        root.spy.real = real
        real.codeResult.connect(root.spy.codeResult)
        t.backend = root.spy
        t.truncate = true
        root.awaiting = function () { return root.calm(root.drawn("03-plain.txt", "remote")) }
    }
    function judgeIcons() {
        var t = root.textPane(), c = root.code(), g = root.bar().geometry(), row = root.pane().rowFor(root.pane().cursorIndex)
        root.checkTextState("Quick Look IPC reports non-empty ready code before w", false, root.iconLines)
        root.check("the bar draws the row's mark, the name and the count, a close mark and no segment",
            [g.markName, g.name.text, g.lines.text, g.countShown, g.segment !== null, g.close !== null],
            [Icons.glyphForRow(row.i, row.p), "01-icons.rs", "132 lines", true, false, true])
        var captured = LangCost.codeState(root.pane(), false, Text.StyledText)
        root.check("the native capture reader sees real coloured code and its Rust bar",
            [captured.path, captured.answer, captured.firstScreen, captured.colors.length > 0, captured.language.slug,
                captured.colors.every(function(color) { return captured.inks.indexOf(color) >= 0 }),
                captured.colors.some(function(color) { return color !== captured.inks[0] })],
            [c.path, "styled", true, true, "rust", true, true])
        root.check("the code bar draws its Rust mark in the existing foreground slot",
            [g.language !== null ? g.language.slug : "", g.mark.visible, g.language !== null ? String(g.language.color) : "",
                g.language !== null ? g.language.markSize : 0],
            ["rust", false, String(root.bar().langLoader.glyph.color), g.mark.markSize])
        root.check("the bar reads mark, name, count, close from left to right", [g.mark.x < g.name.x, g.name.x < g.lines.x, g.lines.x < g.close.x], [true, true, true])
        var texts = root.bodies()
        root.check("the first line is line 1, coloured, with the gutter", [c.lines[0].indexOf("fn f1(") === 0, texts[0].text.indexOf("<font") >= 0, t.numbered, root.gutters()[0].text],
            [true, true, true, "1"])
        root.check("the gutter sits left of the text", root.gutters()[0].mapToItem(c, 0, 0).x < texts[0].mapToItem(c, 0, 0).x, true)
        root.check("the first screen asked for one range, not the file", [root.replies.length, root.replies[0].first, root.replies[0].last < root.iconLines], [1, 1, true])
        root.awaiting = null
    }

    function judgeMove(op) {
        var t = root.textPane(), c = root.code(), g = root.bar().geometry()
        root.check(op.move + ": the bar names the file", g.name.text, op.move)
        if (op.walk) {
            root.check("j between two code files drew live frames", root.liveFrames > 0, true)
            root.check("every live frame's lines are coloured", root.bad, [])
            root.check("the swap drew no half-built frame", root.pv().swapState().midFrames - root.midBase, 0)
            root.check("the move asked at most once", root.replies.length <= 1, true)
        } else if (op.kind === "text") {
            root.check(op.move + ": plain text draws no gutter", [t.numbered, root.gutters().length], [false, 0])
            root.check(op.move + ": the bar counts its lines", [g.lines.text, g.countShown], ["8 lines", true])
        } else if (op.kind === "remote") {
            var shown = root.bodies().map(function (b) { return b.text })
            root.check(op.move + ": the remote route draws the file's own lines in order, plain, no gutter", [c.lines, t.fromFile, t.numbered, root.gutters().length], [root.remoteLines, true, false, 0])
            root.check(op.move + ": the markup and ampersand lines are escaped text, never a tag", [shown[1].indexOf("&lt;img") === 0, shown[2], shown.some(function (b) { return b.indexOf("<img") >= 0 })], [true, "a &amp; b", false])
            root.check(op.move + ": the backend is never given the path", root.spy.asks.filter(function (a) { return a.path !== undefined }).length, 0)
            t.truncate = false
            t.backend = root.spy.real
        } else if (op.kind === "binary") {
            root.check(op.move + ": a binary file draws the frame under the bar", [root.frameText(), c.visible, g.countShown, t.status], ["binary file", false, false, "ready"])
        } else if (op.kind === "large") {
            root.check(op.move + ": a file past 1 MiB draws the too-large frame and asks nothing", [root.frameText(), c.visible, root.replies.length], ["too large to preview", false, 0])
            root.check(op.move + ": the status keeps its sentence", t.status, "This file is too large to preview.")
        } else if (op.kind === "plain") {
            root.check(op.move + ": a line over 5,000 bytes shows the file as plain text, with the gutter", [c.answer, t.numbered], ["plain", true])
        }
    }

    function wrapSequence() {
        var t = root.textPane(), list = t.list
        // The view starts a little above the long line; ListView places an unbuilt row by estimate, so the first visible line is read, not assumed.
        list.positionViewAtIndex(root.longAt - 11, ListView.Beginning)
        var steps = [
            { state: "off", test: function () { var top = root.topLine(), still = top === root.lastTop; root.lastTop = top; return still && top > 10 && top < root.longAt && root.longBody() !== null },
              act: function () {
                  var lb = root.longBody()
                  root.topBefore = root.topLine()
                  root.check("before w the long line is one row ending in an ellipsis", [lb.lineCount, lb.truncated, Flea.ViewState.previewWrap], [1, true, false])
                  root.checkTextState("Quick Look IPC reports unwrapped long code before w", false, 60)
                  root.key("w") } },
            { state: "on", test: function () { return Flea.ViewState.previewWrap && t.wrap && root.longBody() !== null && root.longBody().lineCount > 3 && root.savedWrap() === "true" },
              act: function () {
                  var lb = root.longBody(), number = root.gutters().filter(function (g) { return g.text === String(root.longAt) })
                  root.check("w wraps the long line into several rows under its own gutter number", [lb.lineCount > 3, number.length], [true, 1])
                  root.check("the first visible line is the one it was", root.topLine(), root.topBefore)
                  root.check("the choice is written to ui.json", root.savedWrap(), "true")
                  root.checkTextState("Quick Look IPC reports w wrapped and ready code", true, 60)
                  root.key("w") } },
            { state: "off again", test: function () { return !Flea.ViewState.previewWrap && !t.wrap && root.longBody() !== null && root.longBody().lineCount === 1 && root.savedWrap() === "false" },
              act: function () {
                  root.check("w again unwraps: one row, the first visible line kept, the choice written", [root.longBody().lineCount, root.topLine(), root.savedWrap()], [1, root.topBefore, "false"])
                  root.checkTextState("Quick Look IPC reports second w unwrapped and ready code", false, 60)
                  root.key("w") } },
            { state: "on last", test: function () { return Flea.ViewState.previewWrap && root.longBody() !== null && root.longBody().lineCount > 3 && root.savedWrap() === "true" },
              act: function () { root.check("a third w wraps again", root.topLine(), root.topBefore) } }
        ]
        var n = 0
        root.awaiting = function () {
            if (!root.calm(steps[n].test())) return false
            steps[n].act()
            n += 1
            root.calmFrom = 0
            return n >= steps.length
        }
    }

    Flea.IpcPreviewState { id: previewReader; pane: root.pane() }

    FloatingWindow {
        id: window
        implicitWidth: 1200
        implicitHeight: 760
        Loader {
            id: body
            anchors.fill: parent
            source: "file://" + Quickshell.env("QLCODE_UI") + "/WindowBody.qml"
            onLoaded: item.host = window
            onStatusChanged: if (status === Loader.Error) { root.log("FAIL WindowBody failed to load"); root.failures += 1; root.finish() }
        }
    }
    Connections {
        target: window.contentItem.Window.window
        function onFrameSwapped() { root.sample() }
    }
    Connections {
        target: root.pane() ? root.pane().backend : null
        function onCodeResult(message) {
            if (message.slot !== "look") return
            root.replies = root.replies.concat([{ first: message.first, last: message.first + (message.lines ? message.lines.length : 0) - 1 }])
        }
    }
    FileView {
        id: uiFile
        path: Quickshell.env("QLCODE_STATE") + "/flea/ui.json"
        printErrors: false
        blockLoading: true
    }
    Timer { id: quitter; interval: 100; onTriggered: Qt.exit(root.failures > 0 ? 1 : 0) }

    Timer {
        interval: 20
        running: true
        repeat: true
        onTriggered: {
            if (root.ticking || root.finished) return
            root.ticking = true
            try { root.tick() } finally { root.ticking = false }
        }
    }
    function tick() {
        if (Date.now() - root.stamp > root.giveUpMs) {
            root.check("op " + root.at + " completes (" + root.stalled() + ")", "timeout", "done")
            root.awaiting = null
            root.at += 1
            root.stamp = Date.now()
            if (root.at >= root.ops.length) root.finish()
            return
        }
        if (root.awaiting === null) {
            if (root.at >= root.ops.length) { root.finish(); return }
            root.run(root.ops[root.at])
            if (root.awaiting === null) { root.at += 1; root.stamp = Date.now() }
            return
        }
        if (root.awaiting()) {
            root.awaiting = null
            root.at += 1
            root.stamp = Date.now()
            root.calmFrom = 0
        }
    }
}
