//@ pragma ShellId flea-pv-compare-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Ops.js" as Ops
import "flea/js/Focus.js" as Focus
import "flea/js/Icons.js" as Icons
import "flea/js/Menu.js" as Menu
import "flea/js/PreviewKeys.js" as PreviewKeys

// tests/pv-compare.sh's harness: the real Quick Look overlay hosts the Compare kind. Stub answers draw the board's hunk and each refusal at the recipe's geometry; the live backend then answers a real pair in its jail.
ShellRoot {
    id: root

    readonly property string fixture: Quickshell.env("PVCMP_DIR")
    readonly property int tickMs: 20
    readonly property int giveUpMs: 20000
    // diff -u of the fixture pair: three lines of context, six removed, six added, three more of context.
    readonly property string hunk: " ## Previews\n \n Each kind asks for what it shows.\n"
        + "-Thumbnails never load on phones.\n-The map holds every row.\n-A taller preview costs nothing.\n-Ports keep their slots.\n-Marks ship one size.\n-Facts fold into two lines.\n"
        + "+Thumbnails stay cache-only on phones.\n+The map holds the visible rows.\n+A taller preview costs what a shorter one did.\n+Ports keep their slots while scrolling.\n+Marks share one optical size.\n+Facts fold into one line.\n"
        + " Only the visible lines are asked for.\n A newer request cancels an older one.\n The frame runs to the column bottom.\n"
    readonly property string stubA: "/w/notes-a.md"
    readonly property string stubB: "/w/notes-b.md"
    readonly property string stubPatch: "--- " + root.stubA + "\n+++ " + root.stubB + "\n@@ -9,12 +9,12 @@\n" + root.hunk
    readonly property string livePatch: "--- " + root.fixture + "/notes-a.md\n+++ " + root.fixture + "/notes-b.md\n@@ -9,12 +9,12 @@\n" + root.hunk
    property int checks: 0
    property int failures: 0
    property int at: 0
    property var awaiting: null
    property double stamp: Date.now()
    property bool ticking: false
    property bool finished: false
    property var clicker: null
    property var liveReply: null
    property int liveToken: 0

    function log(line) { console.log("PVCMP " + line) }
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
    function descendants(item) {
        var out = [item]
        for (var i = 0; i < out.length; i++) {
            var kids = out[i].children || []
            for (var j = 0; j < kids.length; j++) out.push(kids[j])
        }
        return out
    }
    function item() { return look.surfaceItem() }
    // The built delegates, top to bottom; a delegate is the one item holding a modelData.
    function rowItems() {
        var view = root.item() ? root.item().children.filter(function (n) { return n.contentItem !== undefined })[0] : null
        if (!view) return []
        return root.descendants(view.contentItem).filter(function (n) { return n.modelData !== undefined }).sort(function (a, b) { return a.y - b.y })
    }
    function textsOf(row) { return row.children.filter(function (n) { return n.text !== undefined }) }
    function same(a, b) { return Qt.colorEqual(a, b) }
    // A part of the shared button, found by the objectName ui/DialogButton.qml gives it.
    function named(scope, name) { return root.descendants(scope).filter(function (n) { return n.objectName === name })[0] }
    function sentenceShown() {
        var shown = root.descendants(root.item()).filter(function (n) { return n.text !== undefined && n.visible && n.horizontalAlignment === Text.AlignHCenter })
        return shown.length === 1 ? shown[0].text : "(" + shown.length + " sentences)"
    }
    function landedWhole() { return look.active && look.landed && look.fade >= 1 && root.item() !== null && root.item().status === "compare" }
    function closed() { return !look.active && look.surfaceItem() === null }
    function click(target) {
        var centre = target.mapToItem(null, target.width / 2, target.height / 2)
        root.clicker.mouseClick(look, centre.x, centre.y, Qt.LeftButton, Qt.NoModifier, 0)
    }
    function previewKey(key, text, modifiers) {
        return Focus.handleKey({ key: key, text: text, modifiers: modifiers }, {
            preview: look, renameEditor: function() { return null }, searchMode: "", recentMode: "",
            focusView: "list", viewMode: "list", path: root.stubA, cursorIndex: 0, selectionVersion: 0
        }, null)
    }
    function answer(index, state, patch) {
        stub.compareResult({ token: stub.asked[index].token, state: state, patch: patch })
    }

    // Opens a pair and waits for its one ask; each step's checks run once its closure answers true.
    function openPair(a, b, icon) {
        look.openCompare(a, b, icon || "text-markdown")
        return function () { return stub.asked.length === root.expectedAsks }
    }
    property int expectedAsks: 0

    // icon and mark are given where the bar's mark is the point: a .log row's icon must draw the mark its row draws.
    function refusal(name, a, b, state, sentence, title, icon, mark) {
        return [
            function () { root.expectedAsks += 1; return root.openPair(a, b, icon) },
            function () {
                root.check(name + " asks once for its open", [stub.asked.length, stub.asked[stub.asked.length - 1].a, stub.asked[stub.asked.length - 1].b], [root.expectedAsks, a, b])
                root.check(name + " holds the card back until the answer", [look.revealed, look.lookEmptyFrames], [false, 0])
                root.answer(root.expectedAsks - 1, state, "")
                return root.landedWhole
            },
            function () {
                root.check(name + " says its sentence in the body", root.sentenceShown(), sentence)
                root.check(name + " title names the two files and no count", root.item().barGeometry().title.text, title)
                var g = root.item().barGeometry()
                if (icon) root.check(name + " bar mark is the mark its row draws", [g.markName, Icons.glyphForRow(icon, 0o100644)], [mark, mark])
                root.check(name + " has no Copy patch button and no rows", [g.copy.visible, root.rowItems().length], [false, 0])
                var before = opener.copies.length
                PreviewKeys.act("copyPatch", { preview: look })
                root.check(name + " y copies nothing", opener.copies.length, before)
                root.previewKey(Qt.Key_Tab, "\t", Qt.NoModifier)
                root.check(name + " Tab skips absent Copy and focuses Close", [g.copy.activeFocus, g.close.activeFocus, g.close.ringItem.visible], [false, true, true])
                root.clicker.keyClick(Qt.Key_Backtab, Qt.ShiftModifier, -1)
                root.check(name + " Shift+Tab stays on the only visible control", g.close.activeFocus, true)
                root.check(name + " the overlay never showed an empty card", look.lookEmptyFrames, 0)
                PreviewKeys.act("escape", { preview: look })
                return root.closed
            }
        ]
    }

    readonly property var steps: [].concat([
        function () {
            // Compare.html resolves its pixels at body 14 and caption 12, so the run is pinned there and every number below is the board's own.
            Flea.ViewState.state = { display: { textSize: { mode: 14 } } }
            root.check("the suite runs at the board's text size", [Flea.Theme.font.body, Flea.Theme.font.caption], [14, 12])
            root.check("nothing is built or asked before a compare is opened", [stub.asked.length, look.surfaceItem(), look.active], [0, null, false])
            root.clicker = Qt.createQmlObject("import QtTest; TestEvent {}", look)
            root.expectedAsks = 1
            return root.openPair(root.stubA, root.stubB)
        },
        function () {
            root.check("one ask for the open, naming the two paths", [stub.asked.length, stub.asked[0].a, stub.asked[0].b], [1, root.stubA, root.stubB])
            root.check("the card is held back while the diff is asked", [look.revealed, look.status, look.lookEmptyFrames], [false, "loading", 0])
            // A reply for another token is dropped, and the real one lands.
            stub.compareResult({ token: stub.asked[0].token + 50, state: "identical", patch: "" })
            root.check("a reply for another token is dropped", root.item().answer, "")
            root.answer(0, "diff", root.stubPatch)
            return root.landedWhole
        },
        function () {
            var g = root.item().barGeometry(), rows = root.rowItems()
            root.check("the overlay opened whole, with no empty frame", look.lookEmptyFrames, 0)
            root.check("the bar is the board's 27", g.bar.height, 27)
            root.check("the bar's mark is the markdown mark, 14 in", [g.markName, g.mark.x], ["markdown", 14])
            root.check("the title follows the mark by 9", g.title.x, g.mark.x + g.mark.width + 9)
            root.check("the title reads the board's count", g.title.text, "notes-a.md and notes-b.md · 12 lines differ")
            root.check("the title is the foreground", root.same(g.title.color, Flea.Theme.color.foreground), true)
            // The shared button: its frame is the board's 20 high, and its caption the board's 12, with the 1 px frame inside 8 either side.
            var frame = root.named(g.copy, "buttonFrame"), caption = root.named(g.copy, "buttonLabel")
            root.check("Copy patch is the shared strip button, a 20 high frame", frame.height, 20)
            root.check("Copy patch keeps 8 either side of its caption and rounds its 1 px muted frame", [g.copy.width - caption.implicitWidth, frame.width, frame.border.width, root.same(frame.border.color, Flea.Theme.color.muted)], [2 * 8 + 2, Math.round(caption.implicitWidth + 2 * 8 + 2), 1, true])
            root.check("Copy patch has a foreground caption at the board's 12", [caption.text, root.same(caption.color, Flea.Theme.color.foreground), caption.font.pixelSize], ["Copy patch", true, Flea.Theme.font.caption])
            root.check("the close sits in its 24 slot, 9 after Copy patch, 14 from the edge", [g.close.width, g.close.x - (g.copy.x + g.copy.width), g.bar.width - (g.close.x + g.close.width)], [24, 9, 14])
            root.check("the body holds the hunk header and eighteen lines", rows.length, 19)
            var pitch = root.item().rowHeight
            root.check("rows sit at the line height plus 1 px either side", [rows[1].y - rows[0].y, pitch], [22, 22])
            var head = root.textsOf(rows[0]), context = root.textsOf(rows[1]), removed = root.textsOf(rows[4]), added = root.textsOf(rows[10])
            var inks = root.item().inks
            root.check("the hunk header starts at the text column, 107 in, in the cyan ink", [head[3].text, head[3].x, root.same(head[3].color, inks[6])], ["@@ -9,12 +9,12 @@", 107, true])
            root.check("a context row has both numbers in the muted ink", [context[0].text, context[1].text, context[0].visible, context[1].visible, root.same(context[0].color, Flea.Theme.color.muted)], ["9", "9", true, true, true])
            root.check("a context row has no sign and the foreground text", [context[2].text, context[3].text, root.same(context[3].color, Flea.Theme.color.foreground)], ["", "## Previews", true])
            root.check("the gutter is 34 wide twice, 10 apart, then a 9 sign column", [context[0].x + context[0].width, context[1].x, context[1].x + context[1].width, context[2].x, context[2].width], [34, 34 + 10, 2 * 34 + 10, 2 * (34 + 10), 9])
            root.check("a removed row shows only its old number, in red", [removed[0].text, removed[0].visible, removed[1].visible, removed[2].text, root.same(removed[2].color, inks[1]), root.same(removed[3].color, inks[1])], ["12", true, false, "-", true, true])
            root.check("an added row shows only its new number, in green", [added[1].text, added[0].visible, added[1].visible, added[2].text, root.same(added[2].color, inks[2]), root.same(added[3].color, inks[2])], ["12", false, true, "+", true, true])
            root.check("the inks are the code renderer's red, green and cyan", [root.same(inks[1], Flea.Theme.color.foreground), root.same(inks[2], Flea.Theme.color.foreground), root.same(inks[6], Flea.Theme.color.foreground)], [false, false, false])
            root.check("a row is text alone, with no fill", rows.every(function (r) { return r.children.every(function (n) { return String(n).indexOf("Rectangle") < 0 }) }), true)
            root.check("the text is plain, whitespace kept", [removed[3].textFormat, added[3].text], [Text.PlainText, "Thumbnails stay cache-only on phones."])
            // j and k, Down and Up, neither move the listing cursor nor swap either of the overlay's two files.
            var keyRoot = { preview: look, cursorIndex: 0 }
            PreviewKeys.act("cursorDown", keyRoot)
            PreviewKeys.act("cursorUp", keyRoot)
            root.check("j and k leave the cursor and both files alone", [keyRoot.cursorIndex, look.path, look.comparePath], [0, root.stubA, root.stubB])
            // The diff scrolls by the text preview's own wheel handler: one FastScrollHandler parented to the list, not the bars' own.
            var list = root.item().children.filter(function (n) { return n.contentItem !== undefined })[0]
            root.check("the diff's wheel is the text preview's FastScrollHandler", root.descendants(root.item()).filter(function (n) { return n.objectName === "fleaScroll" && n.parent === list }).length, 1)
            root.previewKey(Qt.Key_Backtab, "", Qt.ShiftModifier)
            root.check("initial Shift+Tab enters Close with its own focus ring", [g.close.activeFocus, g.close.ringItem.visible], [true, true])
            root.clicker.keyClick(Qt.Key_Tab, Qt.NoModifier, -1)
            root.check("Tab wraps Close to Copy with its real focus frame", [g.copy.activeFocus, g.copy.focusShown], [true, true])
            root.clicker.keyClick(Qt.Key_Tab, Qt.NoModifier, -1)
            root.check("Tab advances Copy to Close", [g.copy.activeFocus, g.close.activeFocus], [false, true])
            root.clicker.keyClick(Qt.Key_Backtab, Qt.ShiftModifier, -1)
            root.check("Shift+Tab returns Close to Copy", g.copy.activeFocus, true)
            root.clicker.keyClick(Qt.Key_Return, Qt.NoModifier, -1)
            root.check("Return activates focused Copy once and keeps Compare open", [opener.copies.length, opener.copies[0], look.active], [1, root.stubPatch, true])
            opener.copies = []
            // y and the button each copy the whole patch once, headers included.
            PreviewKeys.act("copyPatch", { preview: look })
            root.check("y copies the whole patch once", [opener.copies.length, opener.copies[0]], [1, root.stubPatch])
            root.click(g.copy)
            return function () { return opener.copies.length === 2 }
        },
        function () {
            root.check("the button copies the same patch once more", [opener.copies.length, opener.copies[1]], [2, root.stubPatch])
            root.click(root.item().barGeometry().close)
            return root.closed
        },
        function () {
            root.check("a click on close closed the overlay", [look.active, look.surfaceItem()], [false, null])
            root.expectedAsks = 1
            return function () { return true }
        }
    ], root.refusal("identical", "/w/notes-a.md", "/w/notes-b.md", "identical", "The two files are identical.", "notes-a.md and notes-b.md"),
       root.refusal("binary", "/w/shot-a.png", "/w/shot-b.png", "binary", "These files are binary, so there is nothing to compare.", "shot-a.png and shot-b.png"),
       root.refusal("over", "/w/dump-a.log", "/w/dump-b.log", "over", "These files are over 1 MiB, too large to compare.", "dump-a.log and dump-b.log", "text-x-generic", "file-text"),
       [
        function () {
            root.check("each open made exactly one ask", stub.asked.length, 4)
            // The live backend: the same four answers and a missing file, from real files in the jail.
            root.liveAsk(root.fixture + "/notes-a.md", root.fixture + "/notes-b.md")
            return function () { return root.liveReply !== null }
        },
        function () {
            root.check("live: the pair differs and the patch is what diff -u prints, labelled with the real paths", [root.liveReply.state, root.liveReply.patch], ["diff", root.livePatch])
            root.liveAsk(root.fixture + "/same-a.md", root.fixture + "/same-b.md")
            return function () { return root.liveReply !== null }
        },
        function () {
            root.check("live: equal files are identical", [root.liveReply.state, root.liveReply.patch], ["identical", ""])
            root.liveAsk(root.fixture + "/shot-a.png", root.fixture + "/shot-b.png")
            return function () { return root.liveReply !== null }
        },
        function () {
            root.check("live: a NUL in the first 8 KiB is binary", root.liveReply.state, "binary")
            root.liveAsk(root.fixture + "/dump-a.log", root.fixture + "/dump-b.log")
            return function () { return root.liveReply !== null }
        },
        function () {
            root.check("live: past 1 MiB is over", root.liveReply.state, "over")
            root.liveAsk(root.fixture + "/notes-a.md", root.fixture + "/none.md")
            return function () { return root.liveReply !== null }
        },
        function () {
            root.check("live: a missing file fails", root.liveReply.state, "failed")
            root.liveAsk(root.fixture + "/notes-a.md", root.fixture)
            return function () { return root.liveReply !== null }
        },
        function () {
            root.check("live: a folder fails", root.liveReply.state, "failed")
            root.liveAsk(root.fixture + "/latin1.md", root.fixture + "/notes-b.md")
            return function () { return root.liveReply !== null }
        },
        function () {
            root.check("live: invalid UTF-8 refuses a lossy clipboard patch", [root.liveReply.state, root.liveReply.patch], ["failed", ""])
            root.liveAsk(root.fixture + "/dump-a.log", root.fixture + "/none.md")
            return function () { return root.liveReply !== null }
        },
        function () {
            root.check("live: opening both regular files precedes the size check", root.liveReply.state, "failed")
            return null
        }
    ], root.wiring())

    // The menu's Compare choice, from the rows the pane reads to the open overlay, through the same Menu and Focus code the pane runs.
    function menuChoice(selected) {
        menuPane.selected = selected
        var picked = Ops.markedRows(menuPane)
        var entries = Menu.listingEntries({ hasRow: true, selectionCount: selected.length, rowMode: 0o100644, hiddenActions: [], compareKinds: Ops.kinds(picked) })
        return entries.filter(function (e) { return e.action === "compare" })[0] || null
    }
    function wiring() {
        return [
            function () {
                root.asksBefore = stub.asked.length
                var row = root.menuChoice([3, 1])
                root.check("two marked files show the Compare row", row !== null && row.label, "Compare")
                root.check("the menu builds no ask of its own", stub.asked.length, root.asksBefore)
                Focus.act(row.action, menuPane, 0, null)
                return function () { return stub.asked.length === root.asksBefore + 1 }
            },
            function () {
                var ask = stub.asked[root.asksBefore]
                root.check("the choice asks for the first and second marked path, in listing order", [ask.a, ask.b], ["/w/notes-a.md", "/w/notes-b.md"])
                root.check("the overlay is held back until the answer", [look.active, look.revealed], [true, false])
                root.answer(root.asksBefore, "diff", root.stubPatch)
                return root.landedWhole
            },
            function () {
                root.check("the overlay opened with the first file's mark and the board's title", [look.iconName, root.item().barGeometry().title.text], ["text-markdown", "notes-a.md and notes-b.md · 12 lines differ"])
                PreviewKeys.act("escape", { preview: look })
                return root.closed
            },
            function () {
                root.check("a folder among the two hides the row", root.menuChoice([1, 2]), null)
                root.check("three marked files hide the row", root.menuChoice([0, 1, 3]), null)
                root.check("one marked file hides the row", root.menuChoice([1]), null)
                Focus.act("compare", menuPane, 0, null)
                root.check("a Compare choice over three files opens nothing", [stub.asked.length, look.active], [root.asksBefore + 1, false])
                return null
            }
        ]
    }
    property int asksBefore: 0

    function liveAsk(a, b) {
        root.liveReply = null
        root.liveToken = realBackend.askCompare(a, b)
    }

    QtObject {
        id: stub
        property var asked: []
        property int compareToken: 0
        signal compareResult(var message)
        signal meta(int row, int w, int h, int orient, real durationMs, int sampleRate, int entries, real unpacked, bool archiveFailed, var names, real lines, bool partial, bool linesFailed, string target, bool targetDir, string owner)
        signal metaResult(var message)
        function askCompare(a, b) {
            stub.compareToken += 1
            stub.asked.push({ token: stub.compareToken, a: a, b: b })
            return stub.compareToken
        }
    }
    QtObject {
        id: menuPane
        property var selected: []
        property string path: "/w"
        property string searchBase: ""
        property var rows: [{ n: "other.txt", p: 0o100644, i: "text-x-generic" }, { n: "notes-a.md", p: 0o100644, i: "text-markdown" },
                            { n: "folder", p: 0o040755, i: "folder", d: true }, { n: "notes-b.md", p: 0o100644, i: "text-markdown" }]
        function selectedIndices() { return menuPane.selected }
        function rowFor(index) { return menuPane.rows[index] || null }
        function join(base, name) { return base + "/" + name }
        function quickLook() { return look }
    }
    QtObject {
        id: opener
        property var copies: []
        function copyText(text) { opener.copies.push(text) }
    }
    QtObject {
        id: stubPane
        property var backend: stub
        property var opener: opener
        property int cursorIndex: 0
        property string storageClass: "local"
        property bool listInFlight: false
        property var thumbState: ({})
        signal rowsChanged()
        property var listArea: QtObject { function forceActiveFocus() {} }
    }

    Flea.Backend { id: realBackend }
    Connections {
        target: realBackend
        function onCompareResult(message) {
            if (message.token === root.liveToken) root.liveReply = message
        }
    }

    FloatingWindow {
        id: win
        implicitWidth: 1200
        implicitHeight: 800
        color: Flea.Theme.color.background
        Item {
            anchors.fill: parent
            Flea.Preview {
                id: look
                pane: stubPane
            }
        }
    }
    Timer { id: quitter; interval: 100; onTriggered: Qt.exit(root.failures > 0 ? 1 : 0) }

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
            root.check("step " + root.at + " completes", "timeout", "done")
            root.finish()
            return
        }
        if (root.awaiting !== null) {
            if (!root.awaiting()) return
            root.awaiting = null
            root.at += 1
            root.stamp = Date.now()
            return
        }
        if (root.at >= root.steps.length) { root.finish(); return }
        var next = root.steps[root.at]()
        if (next === null || next === undefined) { root.at += 1; root.stamp = Date.now() }
        else root.awaiting = next
    }
}
