import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Markdown.js" as Markdown

// QuickLookPrepare builds its unseen warm table once, on the first rested document that holds a table, and never under a held key.
ShellRoot {
    id: root
    readonly property string dir: Quickshell.env("FLEA_TABLEWARM_DIR")
    // Polls of the probe timer an event may take before it fails by name; counted, never timed.
    readonly property int landPollLimit: 300
    readonly property int tickMs: 20
    // The held key's moves, each one tick apart, well inside the sweep's rest.
    readonly property int sweepMoves: 15
    readonly property int sweepRestMs: 300
    property int failures: 0
    property int checks: 0
    property int step: 0
    property int waited: 0
    property int moves: 0
    // The list fixture's text, which the shell script writes to list.md byte for byte.
    readonly property string listTable: "- item\n\n  | a | b |\n  | - | - |\n  | 1 | 2 |\n"

    function check(label, actual, expected) {
        checks++
        var ok = JSON.stringify(actual) === JSON.stringify(expected)
        if (!ok) failures++
        console.log("TABLEWARM " + (ok ? "PASS " : "FAIL ") + label + " got=" + JSON.stringify(actual) + " expected=" + JSON.stringify(expected))
    }
    function finish() {
        console.log("TABLEWARM DONE " + checks + " checks, " + failures + " failed")
        Qt.exit(failures ? 1 : 0)
    }
    function landedWithin(name, ready) {
        if (ready) {
            root.waited = 0
            return true
        }
        if (++root.waited > root.landPollLimit) {
            root.check(name + " lands within " + root.landPollLimit + " polls", "gave up", "landed")
            root.finish()
        }
        return false
    }
    // A prepare has settled on a path once it shows it and holds no request, the warm table's included.
    function settled(prep, path) { return prep.preparedPath === path && prep.asked === null }
    function counts(prep) { return { warms: prep.tableWarms, warmed: prep.tableWarmed, reads: prep.reads, answers: prep.workerAnswers } }

    // A pane the prepare reads: one name per cursor index, every row a small regular file.
    component StubPane: QtObject {
        property var names: []
        property int cursorIndex: 0
        property var rows: []
        property bool listInFlight: false
        property bool storageKnown: true
        property string storageClass: ""
        property string path: root.dir
        function rowFor(i) { return { n: names[i], d: false, s: 900, p: 33188, k: 0 } }
        function join(a, b) { return a + "/" + b }
    }

    StubPane { id: firstPane; names: ["note.md", "t1.md", "t2.md"] }
    StubPane { id: heldPane; names: ["note.md", "t1.md", "t2.md"] }
    StubPane { id: takenPane; names: ["t2.md"] }
    StubPane { id: nestedPane; names: ["note.md", "quote.md"] }
    Flea.QuickLookPrepare { id: first; pane: firstPane; restMs: 1 }
    Flea.QuickLookPrepare { id: held; pane: heldPane; restMs: root.sweepRestMs }
    Flea.QuickLookPrepare { id: taken; pane: takenPane; restMs: 1 }
    Flea.QuickLookPrepare { id: nested; pane: nestedPane; restMs: 1 }
    StubPane { id: listPane; names: ["list.md"] }
    Flea.QuickLookPrepare { id: listed; pane: listPane; restMs: 1 }
    // The opened prepare records any warm request as it goes out, since the worker can answer one inside a probe tick.
    property bool openedWarmAsked: false
    StubPane { id: openPane; names: ["t1.md"] }
    // Quick Look opens while the parse is out: the request goes to the worker at rest, and the answer lands after Space.
    Flea.QuickLookPrepare {
        id: opened
        pane: openPane
        restMs: 1
        onAskedChanged: {
            if (opened.asked !== null) opened.resting = false
            if (opened.asked !== null && opened.asked.warm === true) root.openedWarmAsked = true
        }
    }
    StubPane { id: spacedPane; names: ["t1.md"] }
    // Quick Look opens while the warm table's parse is out: its answer lands after Space and builds nothing.
    Flea.QuickLookPrepare { id: spaced; pane: spacedPane; restMs: 1; onAskedChanged: if (spaced.asked !== null && spaced.asked.warm === true) spaced.resting = false }
    // The cursor overtakes the first warm on the turn after it goes out, so its answer is dropped and the next rested table asks again.
    property int overtakenWarms: 0
    StubPane { id: overPane; names: ["t2.md", "quote.md"] }
    Flea.QuickLookPrepare {
        id: overtaken
        pane: overPane
        restMs: 1
        onAskedChanged: {
            if (overtaken.asked === null || overtaken.asked.warm !== true || ++root.overtakenWarms > 1)
                return
            Qt.callLater(function () { overPane.cursorIndex = 1 })
        }
    }

    Timer {
        interval: root.tickMs
        running: true
        repeat: true
        onTriggered: {
            if (root.step === 0) {
                // The warm's own Markdown parses to one table with a bold cell, a code span and a link, so the faces it warms are real.
                var warm = Markdown.blocks(String(first.tableWarmText), root.dir, "#000000", "#ffffff")
                var cells = warm.length > 0 && warm[0].rows ? warm[0].rows[0].join(" ") : ""
                root.check("the warm Markdown is one three column table", [warm.length, warm[0].type, warm[0].cols], [1, "table", 3])
                root.check("the warm row holds bold, code and a link", [/<strong>x|<b>x/.test(cells), cells.indexOf("<code") >= 0, cells.indexOf("<a href=") >= 0], [true, true, true])
                var quote = Markdown.blocks("> | a | b |\n> | - | - |\n> | 1 | 2 |\n", root.dir, "#000000", "#ffffff")
                root.check("the nested fixture's table sits in a quote's parts", [quote[0].type, quote[0].parts ? quote[0].parts[0].type : "none"], ["quote", "table"])
                var list = Markdown.blocks(root.listTable, root.dir, "#000000", "#ffffff")
                var item = list[0].parts ? list[0].parts[0] : []
                root.check("the list fixture's table sits in an item's parts", [list[0].type, Array.isArray(item), item.some(function (b) { return b.type === "table" })], ["list", true, true])
                first.moved()
                root.step = 1
            } else if (root.step === 1) {
                if (!root.landedWithin("the note", root.settled(first, root.dir + "/note.md"))) return
                root.check("a rested document with no table never warms", root.counts(first), { warms: 0, warmed: false, reads: 1, answers: 1 })
                firstPane.cursorIndex = 1
                root.step = 2
            } else if (root.step === 2) {
                if (!root.landedWithin("the first table", root.settled(first, root.dir + "/t1.md"))) return
                root.check("the first rested table warms once", root.counts(first), { warms: 1, warmed: true, reads: 2, answers: 2 })
                firstPane.cursorIndex = 2
                root.step = 3
            } else if (root.step === 3) {
                if (!root.landedWithin("the second table", root.settled(first, root.dir + "/t2.md"))) return
                root.check("a second rested table does not warm again", root.counts(first), { warms: 1, warmed: true, reads: 3, answers: 3 })
                firstPane.cursorIndex = 0
                root.step = 4
            } else if (root.step === 4) {
                if (!root.landedWithin("the note again", root.settled(first, root.dir + "/note.md"))) return
                root.check("a later note leaves the warm as it was", root.counts(first), { warms: 1, warmed: true, reads: 4, answers: 4 })
                root.step = 5
            } else if (root.step === 5) {
                // A held key repeats across event-loop turns between two tables: nothing is read and nothing warms until it rests.
                heldPane.cursorIndex = heldPane.cursorIndex === 1 ? 2 : 1
                if (++root.moves < root.sweepMoves) return
                root.check("a held key over tables reads and warms nothing", root.counts(held), { warms: 0, warmed: false, reads: 0, answers: 0 })
                root.step = 6
            } else if (root.step === 6) {
                if (!root.landedWithin("the held key's rest", root.settled(held, root.dir + "/" + heldPane.names[heldPane.cursorIndex]))) return
                // The entry the first prepare stored last is the note, so the table it rests on goes to the worker.
                root.check("the rest after a held key warms once", root.counts(held), { warms: 1, warmed: true, reads: 1, answers: 1 })
                heldPane.cursorIndex = 0
                root.step = 7
            } else if (root.step === 7) {
                if (!root.landedWithin("the held prepare's note", root.settled(held, root.dir + "/note.md"))) return
                heldPane.cursorIndex = 2
                root.step = 8
            } else if (root.step === 8) {
                if (!root.landedWithin("the held prepare's second table", root.settled(held, root.dir + "/t2.md"))) return
                root.check("a held prepare's later table does not warm again", root.counts(held), { warms: 1, warmed: true, reads: 3, answers: 3 })
                // The entry stored last is t2.md's, so a fresh prepare resting on it takes it without a parse.
                taken.moved()
                root.step = 9
            } else if (root.step === 9) {
                if (!root.landedWithin("the taken table", root.settled(taken, root.dir + "/t2.md"))) return
                root.check("a rested table taken without a parse warms once", root.counts(taken), { warms: 1, warmed: true, reads: 1, answers: 0 })
                nested.moved()
                root.step = 10
            } else if (root.step === 10) {
                if (!root.landedWithin("the nested note", root.settled(nested, root.dir + "/note.md"))) return
                root.check("the nested prepare's note never warms", root.counts(nested), { warms: 0, warmed: false, reads: 1, answers: 1 })
                nestedPane.cursorIndex = 1
                root.step = 11
            } else if (root.step === 11) {
                if (!root.landedWithin("the quoted table", root.settled(nested, root.dir + "/quote.md"))) return
                root.check("a table inside a quote warms once", root.counts(nested), { warms: 1, warmed: true, reads: 2, answers: 2 })
                listed.moved()
                root.step = 12
            } else if (root.step === 12) {
                if (!root.landedWithin("the listed table", root.settled(listed, root.dir + "/list.md"))) return
                root.check("a table inside a list item warms once", root.counts(listed), { warms: 1, warmed: true, reads: 1, answers: 1 })
                opened.moved()
                root.step = 13
            } else if (root.step === 13) {
                if (!root.landedWithin("the table answered after Space", opened.preparedPath === root.dir + "/t1.md")) return
                root.check("a table answered after Space never warms or asks for one", [root.counts(opened), opened.resting, root.openedWarmAsked], [{ warms: 0, warmed: false, reads: 1, answers: 1 }, false, false])
                spaced.moved()
                root.step = 14
            } else if (root.step === 14) {
                if (!root.landedWithin("the warm answered after Space", root.settled(spaced, root.dir + "/t1.md"))) return
                // The entry the opened prepare stored is t1.md's, so this one takes it and only the warm goes to the worker.
                root.check("a warm table answered after Space builds nothing", [root.counts(spaced), spaced.resting], [{ warms: 0, warmed: false, reads: 1, answers: 0 }, false])
                overtaken.moved()
                root.step = 15
            } else if (root.step === 15) {
                if (!root.landedWithin("the table after an overtaken warm", root.settled(overtaken, root.dir + "/quote.md"))) return
                root.check("a warm the cursor overtakes leaves the next rested table to warm", [root.counts(overtaken), root.overtakenWarms], [{ warms: 1, warmed: true, reads: 2, answers: 2 }, 2])
                root.finish()
            }
        }
    }
}
