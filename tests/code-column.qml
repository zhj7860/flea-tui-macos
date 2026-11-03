//@ pragma ShellId flea-code-column-test

import QtQuick
import Quickshell
import Quickshell.Io
import "flea" as Flea

// tests/code-column.sh's harness: the Columns preview over the real backend draws code in the theme's inks, never plain first.
ShellRoot {
    id: root

    readonly property string fixture: Quickshell.env("CODECOL_DIR")
    // The second run: the backend cannot find bat, so the same file is drawn plain.
    readonly property bool noBat: Quickshell.env("CODECOL_NOBAT") === "1"
    readonly property int tickMs: 20
    readonly property int settleMs: 250
    readonly property int giveUpMs: 20000
    // The markup file's one line, naming the suite's listener.
    readonly property string imgLine: Quickshell.env("CODECOL_IMG")
    property int checks: 0
    property int failures: 0
    property var pane: null
    property var keys: null
    property int at: 0
    property var awaiting: null
    property double stamp: Date.now()
    property double calmFrom: 0
    property bool ticking: false
    property bool finished: false
    // Asks counted at each move's start, the largest line any reply reached, and the listings seen while a reload runs, and the asks and queued loads made then.
    property int askBase: 0
    property int farthest: 0
    property bool watchLoad: false
    property int loadsSeen: 0
    property int askedLoading: 0
    // The lines the shown file grows by in the reload, and the ask token before it.
    readonly property int grownLines: 5
    property int reloadBase: 0
    property int wideReplies: 0
    // The frames sampled while a walk runs: drawn live (not under the swap's picture) and what was wrong with them.
    property bool sampling: false
    property int liveFrames: 0
    property int midBase: 0
    property var bad: []
    // Frames the swap counts as half-built, and those of them that drew a line of code.
    property int midFrames: 0
    property int midDrawn: 0

    readonly property var ops: root.noBat
        ? [{ open: true }, { view: true }, { text: "00-notes.md" }, { move: "j", show: "01-icons.rs", plain: true }, { done: true }]
        : [{ open: true }, { view: true }, { text: "00-notes.md" },
           { move: "j", show: "01-icons.rs", coloured: true }, { stale: true },
           { walk: ["j", "k", "j", "k", "j", "k"], files: ["02-more.rs", "01-icons.rs", "02-more.rs", "01-icons.rs", "02-more.rs", "01-icons.rs"] },
           { burst: ["j", "k", "j", "k", "j", "k"], file: "01-icons.rs" },
           { move: "j", show: "02-more.rs", coloured: true }, { move: "j", show: "03-nul.txt", binary: true },
           { move: "j", show: "04-over.log", large: true }, { move: "j", show: "05-long.rs", long: true },
           { move: "j", show: "06-img.xml", literal: true }, { reload: true }, { wide: true }, { done: true }]

    function log(line) { console.log("CODECOL " + line) }
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
        if (root.pane) root.pane.destroy()
        quitter.start()
    }
    function descendants(item) {
        var out = [item]
        for (var i = 0; i < out.length; i++) {
            var kids = out[i].children || []
            for (var j = 0; j < kids.length; j++) out.push(kids[j])
        }
        return out
    }
    // The CodeLines the pane holds, built or not: one item that can start a view of a file.
    function codeCount() {
        if (!root.pane) return -1
        return root.descendants(root.pane).filter(function (n) { return typeof n.rowAt === "function" && typeof n.fresh === "function" }).length
    }
    function column() { return root.pane ? root.pane.previewColumnItem : null }
    function drawnLines(code) {
        var row = code ? code.viewport.itemAtIndex(0) : null
        return row ? Math.min(code.shown, Math.ceil(code.viewport.height / row.height)) : -1 // An unbuilt first row must fail the drawn-line checks.
    }
    // The CodeLines under the column's lines: the one item that can say which line it holds.
    function codeOf(col) {
        if (!col) return null
        var all = root.descendants(col.linesItem)
        for (var i = 0; i < all.length; i++)
            if (typeof all[i].rowAt === "function") return all[i]
        return null
    }
    // The drawn line texts, top to bottom: the StyledText bodies the view has built.
    function bodies(code) {
        return root.descendants(code).filter(function (n) {
            if (!n.visible || n.textFormat !== Text.StyledText) return false
            var y = n.mapToItem(code.viewport, 0, 0).y
            return y >= 0 && y < code.viewport.height
        }).sort(function (a, b) { return a.mapToItem(code, 0, 0).y - b.mapToItem(code, 0, 0).y })
    }
    // What a StyledText string reads as once drawn.
    function plainOf(styled) {
        return styled.replace(/<[^>]*>/g, "").replace(/&nbsp;/g, " ").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
            .replace(/&quot;/g, "\"").replace(/&amp;/g, "&")
    }
    function ink(role) { return root.codeOf(root.column()).inks[role] }
    function key(text) { root.keys.keyClickChar(text, Qt.NoModifier, -1) }
    function nameShown(col) { return col && col.path ? col.path.split("/").pop() : "" }
    function calm(ok) {
        if (!ok) { root.calmFrom = 0; return false }
        if (root.calmFrom === 0) root.calmFrom = Date.now()
        return Date.now() - root.calmFrom >= root.settleMs
    }
    // The column's file is drawn whole: its lines answered and as many built as the frame shows.
    function drawn(name, answer) {
        var col = root.column(), code = root.codeOf(col)
        return col !== null && code !== null && root.nameShown(col) === name && code.active && code.answer === answer
            && (answer === "binary" || root.bodies(code).length === root.drawnLines(code))
    }
    function backend() { return root.pane.backend }

    // Every frame the walk draws live is judged: the lines are coloured, whole and one file's.
    function sample() {
        var col = root.column()
        if (root.sampling && col !== null && col.swap !== null && !col.swap.capturing && !col.swap.holding && !col.swap.ready && !col.swap.fellBack) {
            var cd = root.codeOf(col)
            root.midFrames += 1
            if (cd !== null && cd.lines.some(function (l) { return l.length > 0 }))
                root.midDrawn += 1
        }
        if (!root.sampling || col === null || col.swap === null || col.swap.holding || col.swap.capturing || !col.swap.ready) return
        var code = root.codeOf(col)
        if (code === null) return
        root.liveFrames += 1
        var texts = root.bodies(code)
        var why = ""
        // 01-icons.rs holds fn f1, f2 ..., 02-more.rs holds fn g1, g2 ...
        var letter = root.nameShown(col).indexOf("01-") === 0 ? "f" : "g"
        if (texts.length !== root.drawnLines(code)) why = "draws " + texts.length + " lines"
        for (var i = 0; why === "" && i < texts.length; i++) {
            if (texts[i].text.indexOf("<font") < 0) why = "line " + (i + 1) + " is uncoloured"
            else if (root.plainOf(texts[i].text).indexOf("fn " + letter + (i + 1) + "(") !== 0) why = "line " + (i + 1) + " is not the file's own"
        }
        if (why === "") return
        if (root.bad.length < 5) root.bad.push(why + " at " + root.nameShown(col))
    }
    function walkVerdict(label, moves) {
        root.check(label + " live frames sampled", root.liveFrames > 0, true)
        root.check(label + " live frames are coloured, whole and one file's", root.bad, [])
        root.check(label + " the swap drew no mid frame", root.column().swap.midFrames - root.midBase, 0)
        root.check(label + " one ask per move", root.backend().codeToken - root.askBase, moves)
        root.sampling = false
    }

    function run(op) {
        root.awaiting = null
        if (op.open) {
            Flea.ViewState.changeKey("view", "list")
            root.pane = paneComponent.createObject(win.contentItem)
            root.keys = Qt.createQmlObject("import QtTest; TestEvent {}", root.pane.listArea)
            root.pane.open(root.fixture)
            root.awaiting = function () { return !root.pane.listInFlight && root.pane.path === root.fixture && root.pane.total === 7 }
        } else if (op.view) {
            root.keys.keyClick(Qt.Key_2, Qt.ControlModifier, -1)
            root.awaiting = function () { return root.calm(root.pane.viewMode === "columns" && root.column() !== null && root.pane.cursorIndex === 0) }
        } else if (op.show !== undefined && op.move === undefined) {
            root.check("the cursor starts on the first file", root.pane.rowFor(root.pane.cursorIndex).n, op.show)
            root.awaiting = function () { return root.calm(root.drawn(op.show, op.plain ? "plain" : "styled")) && root.verdict(op) }
        } else if (op.text !== undefined) {
            root.check("the cursor starts on the first file", root.pane.rowFor(root.pane.cursorIndex).n, op.text)
            root.awaiting = function () {
                if (!root.calm(root.nameShown(root.column()) === op.text)) return false
                root.check(op.text + " is text that is not code and builds no CodeLines", [root.codeCount(), root.column().linesItem.active, root.backend().codeToken], [0, false, 0])
                return true
            }
        } else if (op.move !== undefined) {
            root.askBase = root.backend().codeToken
            root.key(op.move)
            root.awaiting = function () {
                var answer = op.binary ? "binary" : op.large ? "large" : (op.long || op.plain) ? "plain" : "styled"
                if (op.large) return root.calm(root.nameShown(root.column()) === op.show && root.column().linesItem.tooLarge) && root.verdict(op)
                return root.calm(root.drawn(op.show, answer)) && root.verdict(op)
            }
        } else if (op.stale) {
            var code = root.codeOf(root.column()), before = code.lines.join("|")
            code.answered({ token: 0, state: "plain", total: 1, first: 1, lines: [[0, "STALE"]] })
            root.check("a reply with no ask in flight is dropped", [code.answer, code.lines.join("|")], ["styled", before])
            // An ask in flight holds a token: a reply naming another is dropped and the answer to the real ask still lands.
            var staleName = root.nameShown(root.column())
            code.reset()
            code.ask()
            var pending = code.token
            code.answered({ token: pending + 99, state: "plain", total: 1, first: 1, lines: [[0, "STALE"]] })
            root.check("a reply for a token that is not the one in flight is dropped", [pending > 0, code.token === pending, code.answer, code.total], [true, true, "", 0])
            root.awaiting = function () {
                if (!root.calm(root.drawn(staleName, "styled"))) return false
                root.check("the real reply lands after the stale one", [code.answer, code.lines.join("|") === before], ["styled", true])
                return true
            }
        } else if (op.reload) {
            var shownCode = root.codeOf(root.column())
            root.check("a CodeLines is live and active for the reload", [root.codeCount(), shownCode.active], [1, true])
            root.check("the reload starts from the shown file's one line", shownCode.lines.length, 1)
            root.loadsSeen = 0
            root.askedLoading = 0
            root.reloadBase = root.backend().codeToken
            // The shown file grows on disk (size and mtime move), so the landing must ask for the new lines.
            var grown = [root.imgLine]
            for (var g = 1; g <= root.grownLines; g++) grown.push("extra line " + g)
            grownFile.setText(grown.join("\n") + "\n")
            root.watchLoad = true
            root.pane.refresh(root.fixture + "/06-img.xml", false)
            root.awaiting = function () {
                var grownCode = root.codeOf(root.column())
                if (!root.calm(!root.pane.listInFlight && root.loadsSeen > 0 && grownCode !== null && grownCode.lines.length === 1 + root.grownLines && root.drawn("06-img.xml", "styled"))) return false
                root.watchLoad = false
                root.check("the listing loaded under a live CodeLines", root.loadsSeen > 0, true)
                root.check("no code ask or queued load while the listing loads", root.askedLoading, 0)
                root.check("the reload asks the grown file again", root.backend().codeToken > root.reloadBase, true)
                root.check("the grown file's reply replaces the shown lines", grownCode.lines, grown)
                grownFile.setText(root.imgLine + "\n") // both runs share the fixture
                return true
            }
        } else if (op.wide !== undefined) {
            // A window over the line cap: asked in cap-sized parts, so it settles.
            var wide = wideComponent.createObject(win.contentItem, { backend: realBackend, slot: "wide", fromText: true, path: "wide.rs" })
            var wideLines = []
            for (var n = 1; n <= 1500; n++) wideLines.push("fn w" + n + "() {}")
            wide.text = wideLines.join("\n")
            wide.height = (wide.lineCap + 100) * wide.rowHeight
            // The slot's own replies are counted: the listing the reload's write set off may re-list again under the column, which asks on its own slot.
            root.wideReplies = 0
            wide.active = true
            root.awaiting = function () {
                if (!root.calm(wide.settled && wide.covered(1, wide.needed().to))) return false
                var reach = wide.needed().to
                root.check("a window over the cap is wider than the cap", reach > wide.lineCap, true)
                root.check("a window over the cap is asked in cap-sized parts", root.wideReplies, Math.ceil(reach / wide.lineCap))
                wide.destroy()
                return true
            }
        } else if (op.walk !== undefined) {
            root.beginWalk()
            var step = 0, waiting = false
            root.awaiting = function () {
                if (!waiting) {
                    root.key(op.walk[step])
                    waiting = true
                    root.calmFrom = 0
                    return false
                }
                if (!root.calm(root.drawn(op.files[step], "styled"))) return false
                waiting = false
                step += 1
                if (step < op.walk.length) return false
                root.walkVerdict("j and k between two code files", op.walk.length)
                return true
            }
        } else if (op.burst !== undefined) {
            root.beginWalk()
            var sent = 0
            root.awaiting = function () {
                if (sent < op.burst.length) { root.key(op.burst[sent]); sent += 1; return false }
                if (!root.calm(root.drawn(op.file, "styled"))) return false
                root.check("a burst of keys ends on the last file", root.nameShown(root.column()), op.file)
                root.check("burst live frames are coloured, whole and one file's", root.bad, [])
                root.check("burst never drew a line of code in a half-built frame", root.midDrawn, 0)
                root.check("a burst asks at most once per key", root.backend().codeToken - root.askBase <= op.burst.length, true)
                root.sampling = false
                return true
            }
        } else if (op.done) {
            root.finish()
        }
    }
    // Ctrl+Space, the settle's own route, tried while the listing is out (after the flip, when the preview's gate has seen it): it must queue nothing.
    function tryLoad() {
        if (!root.pane.listInFlight) return
        var chosen = root.descendants(root.pane).filter(function (n) { return typeof n.followSelection === "function" })[0]
        chosen.loadQueuedKey = ""
        root.pane.loadSelectionPreview()
        root.askedLoading += chosen.loadQueuedKey === "" ? 0 : 1
    }
    function beginWalk() {
        root.askBase = root.backend().codeToken
        root.midBase = root.column().swap.midFrames
        root.liveFrames = 0
        root.midFrames = 0
        root.midDrawn = 0
        root.bad = []
        root.sampling = true
    }

    // The checks of one file once it is drawn.
    function verdict(op) {
        var col = root.column(), code = root.codeOf(col), texts = root.bodies(code), name = op.show
        if (op.coloured || op.plain) {
            var first = texts[0].text
            root.check(name + " draws its lines", [texts.length, root.plainOf(first).indexOf("fn ") === 0], [root.drawnLines(code), true])
            root.check(name + " asks the backend once per move", root.backend().codeToken - root.askBase <= 1, true)
            root.check(name + " asks for no more than the frame's lines", root.farthest <= Math.ceil(code.viewport.height / code.rowHeight), true)
            root.check(name + " has a muted number gutter", col.linesItem.numbered, true)
            if (op.coloured) {
                root.check(name + " the fn keyword draws in the magenta ink", first.indexOf("<font color=\"" + root.ink(5) + "\">fn</font>") >= 0, true)
                root.check(name + " a string draws in the green ink", first.indexOf("<font color=\"" + root.ink(2) + "\">&quot;") >= 0, true)
                root.check(name + " the inks are not the foreground", [root.ink(5) !== root.ink(0), root.ink(2) !== root.ink(0), root.ink(4) !== root.ink(0)], [true, true, true])
            } else {
                root.check(name + " is drawn plain with no bat", texts.filter(function (t) { return t.text.indexOf("<font") >= 0 }).length, 0)
                root.check(name + " the backend answered plain", code.answer, "plain")
            }
        } else if (op.binary) {
            root.check(name + " says binary file under the row's mark", [col.frameNote(), col.glyphState(), col.linesItem.blank], ["binary file", true, true])
            root.check(name + " draws no line", texts.length, 0)
        } else if (op.large) {
            root.check(name + " says too large to preview and asks nothing", [col.frameNote(), root.backend().codeToken - root.askBase], ["too large to preview", 0])
        } else if (op.long) {
            root.check(name + " is plain", code.answer, "plain")
            root.check(name + " draws four lines", texts.length, 4)
            root.check(name + " no line is coloured", texts.filter(function (t) { return t.text.indexOf("<font") >= 0 }).length, 0)
            root.check(name + " every line ends in an ellipsis", texts.filter(function (t) { return t.truncated && t.contentWidth <= t.width }).length, 4)
        } else if (op.literal) {
            root.check(name + " draws the markup as text", root.plainOf(texts[0].text), root.imgLine)
            root.check(name + " writes no tag from the file", texts.filter(function (t) { return t.text.indexOf("<img") >= 0 }).length, 0)
        }
        return true
    }

    FloatingWindow {
        id: win
        implicitWidth: 1400
        implicitHeight: 800
        color: Flea.Theme.color.background
        Item { id: frameProbe }
    }
    Connections {
        target: frameProbe.Window.window
        function onAfterAnimating() { root.sample() }
    }
    Flea.Backend { id: realBackend }
    FileView {
        id: grownFile
        path: root.fixture + "/06-img.xml"
        printErrors: false
        blockWrites: true
    }
    Connections {
        target: realBackend
        function onCodeResult(message) {
            if (message.slot === "wide") root.wideReplies += 1
            var reach = message.first + (message.lines ? message.lines.length : 0) - 1
            if (reach > root.farthest) root.farthest = reach
        }
    }
    Connections {
        target: root.pane
        function onListInFlightChanged() {
            if (!root.watchLoad) return
            // The asks between the flip in and the flip out.
            root.askedLoading += (root.pane.listInFlight ? -1 : 1) * realBackend.codeToken
            root.loadsSeen += root.pane.listInFlight ? 1 : 0
            if (root.pane.listInFlight) Qt.callLater(root.tryLoad)
        }
    }
    Component {
        id: wideComponent
        Flea.CodeLines { width: 600 }
    }
    Timer { id: quitter; interval: 100; onTriggered: Qt.exit(root.failures > 0 ? 1 : 0) }

    Component {
        id: paneComponent
        Flea.Pane {
            width: 1400
            height: 800
            backend: realBackend
        }
    }

    Timer {
        interval: root.tickMs
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
            var tc = root.column(), tk = root.codeOf(tc)
            root.log("timeout at " + root.nameShown(tc) + " answer=" + (tk ? tk.answer : "?") + " rowState=" + (tc ? tc.rowState : "?") + " ready=" + (tc ? tc.swap.ready : "?"))
            root.check("op " + root.at + " completes", "timeout", "done")
            root.finish()
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
