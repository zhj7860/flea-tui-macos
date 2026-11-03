//@ pragma ShellId flea-markdown-code-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/CodeRuns.js" as CodeRuns

// tests/markdown-code.sh's harness: Markdown Source and fenced blocks over the real backend and bat, in Quick Look and in the column.
ShellRoot {
    id: shell

    readonly property string dir: Quickshell.env("MDCODE_DIR")
    // Keeps the unknown-language fence waiting long enough to expose a check before its own reply.
    readonly property int unknownReplyDelayMs: 1200
    property int checks: 0
    property int failures: 0
    property bool done: false
    property int phase: 0
    property int ticks: 0
    // The file and view each pane shows; a phase changes them, and the pane answers by drawing them.
    property string quickFile: "notes.md"
    property string quickView: "source"
    property string columnFile: "notes.md"
    // Frames sampled while the column's fences scroll, and how many showed a fence in view still owed its colours.
    property bool sampling: false
    property int sweepSteps: 0
    property int sampledFrames: 0
    property int plainFrames: 0
    property int fencesSeen: 0
    property var visitedFences: ({})
    property var missedColours: ({})
    property bool framePulse: false
    property bool wheelReported: false
    property bool flinging: false
    property int flingFrames: 0
    property var awaitingFlingFences: ({})
    property int waitingFrames: 0
    property int earlyScreens: 0
    property var fenceHeights: ({})
    property int wrapTop: 0
    // The inks the engine's roles take, as the panes compute them: role 3 is yellow.
    readonly property var inks: CodeRuns.inks(Flea.Theme.palette, Flea.Theme.fallbackColor, String(Flea.Theme.color.foreground))

    function log(line) { console.log("MARKDOWN_CODE " + line) }
    function check(ok, label) {
        shell.checks += 1
        if (!ok) shell.failures += 1
        shell.log((ok ? "PASS " : "FAIL ") + label)
    }
    function finish() {
        if (shell.done) return
        shell.done = true
        shell.log("DONE " + shell.checks + " checks, " + shell.failures + " failed")
        quitter.start()
    }
    function next(name) {
        shell.phase += 1
        shell.ticks = 0
        shell.log("phase " + shell.phase + " " + name)
    }
    // Sample input: '<font color="#ffffff">a &amp; b</font><br>&lt;img&gt;' reads as 'a & b\n<img>'.
    function readBack(markup) {
        return String(markup).replace(/<br>/g, "\n").replace(/<[^>]*>/g, "").replace(/&nbsp;/g, " ").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&amp;/g, "&")
    }
    function inkTag(role, text) { return "<font color=\"" + shell.inks[role] + "\">" + text }

    function descendants(item) {
        var out = [item]
        for (var i = 0; i < out.length; i++) {
            var kids = out[i].children || []
            for (var j = 0; j < kids.length; j++) out.push(kids[j])
        }
        return out
    }
    function within(item, test) { return item ? shell.descendants(item).filter(test) : [] }
    // The PreviewMarkdown inside a host: only it has sourceChars.
    function docOf(host) {
        var found = shell.within(host, function (n) { return typeof n.sourceChars === "number" })
        return found.length > 0 ? found[0] : null
    }
    // A fence's box and its text, the Text being the box's only child.
    function fencesOf(host) { return shell.within(host, function (n) { return n.objectName === "fenceBox" }) }
    function fenceWith(host, info) {
        var found = shell.fencesOf(host).filter(function (f) { return f.info === info })
        return found.length > 0 ? found[0] : null
    }
    function settled(fence) { return fence.token === 0 && fence.next > fence.fenceLines.length }
    function enginePaint(fence) {
        var reply = columnAsks.replies[fence.slot]
        if (!(columnAsks.asks[fence.slot] > 0) || !reply || reply.state !== "styled" || !shell.settled(fence)) return false
        var colours = reply.lines.some(function (row) { return row.some(function (run, at) { return at % 2 === 0 && run > 0 }) })
        var expected = reply.lines.map(function (row) { return CodeRuns.styled(row, shell.inks) }).join("<br>")
        return colours && fence.children[0].textFormat === Text.StyledText && fence.children[0].text === expected
    }
    // The gutter's number Texts in a host's Source; each sits beside its row's body.
    function gutters(host) {
        return shell.within(host, function (n) { return n.visible && n.textFormat === Text.PlainText && /^[0-9]+$/.test(n.text) })
    }
    function bodyOfLine(host, number) {
        var found = shell.gutters(host).filter(function (n) { return n.text === String(number) })
        return found.length > 0 ? found[0].parent.children[1] : null
    }
    function refusal(doc, state, text, status) {
        var code = doc.sourceItem.parent
        var messages = shell.within(quick, function (n) { return n.visible && n.text === text })
        var message = messages.length === 1 ? messages[0] : null
        var at = message ? message.mapToItem(quick, 0, 0) : null
        shell.check(code.answer === state && message !== null && message.width > 0 && message.height > 0
            && at.x >= 0 && at.y >= 0 && at.x + message.width <= quick.width && at.y + message.height <= quick.height,
            state + " Source shows the code preview's refusal text")
        shell.check(code.total === 0 && code.shown === 0 && doc.sourceItem.count === 0 && shell.gutters(quick).length === 0,
            state + " Source has no CodeLines rows")
        shell.check(doc.firstScreen && code.parent.parent.parent.firstScreen && !doc.loading && quick.status === status,
            state + " Source reports ready without waiting forever")
    }

    // A fence laid out in the foreground: the layout a fence starts from, at the fence's own width.
    Text {
        id: probe
        visible: false
        textFormat: Text.StyledText
        wrapMode: Text.Wrap
        font.family: Flea.Theme.font.family
        font.pixelSize: Flea.Theme.font.body
    }

    Flea.Backend { id: realBackend }

    // The backend a pane asks through: the real one, with the colour asks for fences counted by their slot.
    component CountingBackend: Item {
        required property var inner
        property int fenceAsks: 0
        // The lines the pane asks for, fences included, so a long file's asks can be counted against its length.
        property int linesAsked: 0
        property var languages: ({})
        property var slots: ({})
        property var asks: ({})
        property var replies: ({})
        property var pending: []
        signal codeResult(var message)
        function askCode(slot, source, first, count) {
            if (String(slot).indexOf(":fence:") >= 0)
                fenceAsks += 1
            linesAsked += count
            var token = inner.askCode(slot, source, first, count)
            languages[token] = source.lang || ""
            slots[token] = slot
            asks[slot] = (asks[slot] || 0) + 1
            return token
        }
        function deliver(message) {
            if (slots[message.token]) replies[slots[message.token]] = message
            codeResult(message)
        }
        Connections {
            target: inner
            function onCodeResult(message) {
                if (languages[message.token] === "toml") {
                    pending = pending.concat([{ message: message, after: Date.now() + 250 }])
                    shell.log("toml reply " + JSON.stringify(message))
                } else if (languages[message.token] === "flea-unknown-language") {
                    pending = pending.concat([{ message: message, after: Date.now() + shell.unknownReplyDelayMs }])
                    shell.log("unknown reply delayed token=" + message.token)
                } else deliver(message)
            }
        }
        Timer {
            interval: 16
            repeat: true
            running: pending.length > 0
            onTriggered: {
                var now = Date.now()
                var ready = pending.filter(function (p) { return p.after <= now })
                pending = pending.filter(function (p) { return p.after > now })
                for (var i = 0; i < ready.length; i++) deliver(ready[i].message)
            }
        }
    }
    CountingBackend { id: quickAsks; inner: realBackend }
    CountingBackend { id: columnAsks; inner: realBackend }

    FloatingWindow {
        id: window
        implicitWidth: 1000
        implicitHeight: 760
        color: "#101315"

        Flea.MarkdownPane {
            id: quick
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: 560
            active: true
            view: shell.quickView
            path: shell.dir + "/" + shell.quickFile
            size: 1
            backend: quickAsks
        }

        Flea.PreviewMarkdown {
            id: column
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: 400
            active: true
            compact: true
            slot: "column"
            backend: columnAsks
            path: shell.dir + "/" + shell.columnFile
            size: 1
        }

        Rectangle {
            width: 1
            height: 1
            color: shell.framePulse ? "#101315" : "#111416"
        }
    }

    // Each phase waits for what it draws, then checks it; a phase that never draws fails the run.
    Timer {
        interval: 100
        repeat: true
        running: !shell.done
        onTriggered: {
            shell.ticks += 1
            if (shell.ticks > 600) {
                shell.check(false, "phase " + shell.phase + " never drew what it waits for")
                shell.finish()
                return
            }
            shell.step()
        }
    }

    function step() {
        var qdoc = shell.docOf(quick)
        var cdoc = shell.docOf(column)
        if (shell.phase === 0) {
            if (!qdoc || !quick.contentReady || !qdoc.firstScreen || qdoc.shownView !== "source") return
            var first = shell.bodyOfLine(quick, 1)
            var sourceCode = qdoc.sourceItem.parent
            shell.check(first !== null, "Source draws a gutter from 1")
            shell.check(first !== null && first.text.indexOf("Field notes") >= 0 && first.text.indexOf("<font color=") >= 0
                && first.text === CodeRuns.styled(sourceCode.rowAt(1), shell.inks),
                "the heading line is drawn in the ink the engine gives it")
            shell.check(quick.lineLabel === "48 lines", "the bar counts 48 lines [" + quick.lineLabel + "]")
            shell.next("big source")
            shell.quickFile = "big.md"
            quickAsks.linesAsked = 0
            return
        }
        if (shell.phase === 1) {
            if (!qdoc || !quick.contentReady || !qdoc.firstScreen || qdoc.rawText.length === 0) return
            shell.check(quickAsks.linesAsked > 0 && quickAsks.linesAsked < qdoc.rawText.split("\n").length / 4,
                "a 3,000-line Source asks only for the lines in view [" + quickAsks.linesAsked + " of " + qdoc.rawText.split("\n").length + "]")
            shell.waitingFrames = 0
            shell.earlyScreens = 0
            shell.next("quick look rendered")
            shell.quickView = "rendered"
            shell.quickFile = "notes.md"
            return
        }
        if (shell.phase === 2) {
            if (!qdoc || !qdoc.firstScreen || qdoc.shownView !== "rendered" || qdoc.rawText.indexOf("## What shipped") < 0) return
            var toml = shell.fenceWith(quick, "toml")
            if (!toml || !shell.settled(toml)) return
            var figures = shell.within(quick, function (n) { return n.objectName === "figureItem" })
            if (figures.length > 0 && figures[0].failed) {
                shell.check(false, "the mermaid figure failed: " + figures[0].error)
                shell.finish()
                return
            }
            if (figures.length > 0 && !figures[0].ready) return
            var text = toml.children[0].text
            shell.check(text.indexOf(shell.inkTag(3, "preview")) >= 0, "the toml header is drawn in the yellow ink, Quick Look")
            shell.check(new RegExp(shell.inkTag(3, "240")).test(text), "the toml 240 is drawn in the yellow ink, Quick Look")
            shell.check(shell.waitingFrames > 0 && shell.earlyScreens === 0,
                "the first screen waits for its fence colours [" + shell.waitingFrames + " waiting frames, " + shell.earlyScreens + " early screens]")
            var infoFences = shell.fencesOf(quick).filter(function (f) { return f.info !== "" }).length
            shell.check(quickAsks.fenceAsks === infoFences && infoFences === 1,
                "one colour ask per fence with an info string, none for the plain fence [" + quickAsks.fenceAsks + " asks, " + infoFences + " fences]")
            probe.width = toml.children[0].width
            probe.text = toml.fenceLines.map(function (line) { return CodeRuns.styled([0, line], shell.inks) }).join("<br>")
            shell.check(shell.fenceHeights[toml.slot] === toml.height && toml.children[0].implicitHeight === probe.implicitHeight,
                "the toml fence keeps its plain height once coloured [" + toml.children[0].implicitHeight + " " + probe.implicitHeight + "]")
            shell.check(figures.length > 0 && figures[0].ready
                && shell.fencesOf(quick).every(function (f) { return f.info !== "mermaid" }),
                "a mermaid fence still draws its figure and asks for no colour")
            var plain = shell.fencesOf(quick).filter(function (f) { return f.info === "" })
            shell.check(plain.length > 0 && plain.every(function (f) { return !f.coloured && f.token === 0 && f.children[0].textFormat === Text.PlainText }),
                "a fence with no info string asks nothing and draws plain")
            shell.next("column")
            return
        }
        if (shell.phase === 3) {
            if (!cdoc || !cdoc.firstScreen || cdoc.shownView !== "rendered") return
            var ctoml = shell.fenceWith(column, "toml")
            if (!ctoml || !shell.settled(ctoml)) return
            var ctext = ctoml.children[0].text
            shell.check(ctext.indexOf(shell.inkTag(3, "preview")) >= 0 && new RegExp(shell.inkTag(3, "240")).test(ctext),
                "the toml fence is drawn in the yellow ink in the column")
            var columnInfo = shell.fencesOf(column).filter(function (f) { return f.info !== "" }).length
            shell.check(columnAsks.fenceAsks === columnInfo && columnInfo === 1,
                "the column asks once per fence with an info string [" + columnAsks.fenceAsks + " asks, " + columnInfo + " fences]")
            shell.next("column fences scroll")
            shell.columnFile = "fences.md"
            return
        }
        if (shell.phase === 4) {
            if (!cdoc || !cdoc.firstScreen || cdoc.rawText.indexOf("fn f40") < 0) return
            shell.sweepSteps = 0
            shell.sampledFrames = 0
            shell.plainFrames = 0
            shell.fencesSeen = 0
            shell.visitedFences = ({})
            shell.missedColours = ({})
            shell.sampling = true
            shell.next("sweep")
            return
        }
        if (shell.phase === 5) {
            if (shell.sampling || shell.flinging) return
            if (!shell.wheelReported) {
                shell.check(Object.keys(shell.visitedFences).length === 40 && Object.keys(shell.visitedFences).every(function (slot) { return columnAsks.asks[slot] > 0 }),
                    "all 40 named-language fences in the wheel scroll ask the engine")
                shell.check(Object.keys(shell.missedColours).length === 0 && shell.plainFrames === 0 && shell.sampledFrames > 0,
                    "every presented wheel frame draws engine colours [" + shell.plainFrames + " of "
                    + shell.sampledFrames + " frames, " + Object.keys(shell.visitedFences).length + " distinct fences]")
                shell.wheelReported = true
                shell.flinging = true
                shell.docOf(column).bodyItem.contentY = 0
                return
            }
            shell.check(shell.flingFrames === 60, "the fling was sampled for 60 frames")
            shell.log("FLING " + Object.keys(shell.awaitingFlingFences).length + " distinct fences seen before their reply")
            shell.next("markup source")
            shell.quickFile = "markup.md"
            shell.quickView = "source"
            shell.columnFile = "markup.md"
            return
        }
        if (shell.phase === 6) {
            if (!qdoc || !quick.contentReady || !qdoc.firstScreen || qdoc.shownView !== "source") return
            if (qdoc.rawText.indexOf("<b>x</b> <img src=x> &amp;") < 0) return
            var literal = shell.bodyOfLine(quick, 2)
            if (!literal || literal.text === "") return
            shell.check(literal.textFormat === Text.StyledText && shell.readBack(literal.text) === "<b>x</b> <img src=x> &amp;",
                "Source draws <b>, <img> and &amp; as literal text")
            shell.next("markup fence")
            return
        }
        if (shell.phase === 7) {
            if (!cdoc || !cdoc.firstScreen || cdoc.rawText.indexOf("<img") < 0) return
            var html = shell.fenceWith(column, "html")
            if (!html || !shell.settled(html)) return
            var unknown = shell.fenceWith(column, "flea-unknown-language")
            if (!unknown || (!shell.settled(unknown) && !unknown.refused)) return
            var htext = html.children[0].text
            shell.check(shell.readBack(htext) === html.fenceLines.join("\n"), "a fence holding an img tag draws literally")
            shell.check(unknown.refused || (shell.settled(unknown) && unknown.fenceLines.every(function (_, i) {
                return unknown.held[i + 1].every(function (value, at) { return at % 2 !== 0 || value === 0 })
            })), "an unknown fence language falls back to foreground text after its own reply")
            shell.next("long source")
            shell.quickFile = "long.md"
            return
        }
        if (shell.phase === 8) {
            if (!qdoc || !qdoc.firstScreen || qdoc.rawText.indexOf("line 100 ") < 0) return
            qdoc.sourceItem.positionViewAtIndex(30, ListView.Beginning)
            shell.next("source wrap off")
            return
        }
        if (shell.phase === 9) {
            if (!qdoc.firstScreen) return
            shell.wrapTop = qdoc.sourceItem.indexAt(0, qdoc.sourceItem.contentY + 1)
            var unwrapped = shell.bodyOfLine(quick, shell.wrapTop + 1)
            if (!unwrapped) return
            shell.check(unwrapped.wrapMode === Text.NoWrap && unwrapped.elide === Text.ElideRight && unwrapped.truncated,
                "Source defaults to an ellipsis on a long line")
            quick.wrap = true
            shell.next("source wrap on")
            return
        }
        if (shell.phase === 10) {
            if (!qdoc.firstScreen) return
            var wrapped = shell.bodyOfLine(quick, shell.wrapTop + 1)
            if (!wrapped) return
            shell.check(wrapped.wrapMode === Text.WrapAtWordBoundaryOrAnywhere && wrapped.elide === Text.ElideNone
                && !wrapped.truncated && qdoc.sourceItem.indexAt(0, qdoc.sourceItem.contentY + 1) === shell.wrapTop,
                "Source wraps the long line and keeps the same top line")
            shell.next("large source refusal")
            shell.quickFile = "over.md"
            return
        }
        if (shell.phase === 11) {
            if (!qdoc || !qdoc.sourceItem || qdoc.sourceItem.parent.answer !== "large") return
            shell.refusal(qdoc, "large", "too large to preview", "This file is too large to preview.")
            shell.next("failed source refusal")
            shell.quickFile = "unreadable.md"
            return
        }
        if (shell.phase === 12) {
            if (!qdoc || !qdoc.sourceItem || qdoc.sourceItem.parent.answer !== "failed") return
            shell.refusal(qdoc, "failed", "This file could not be read.", "This file could not be read.")
            shell.next("binary source refusal")
            shell.quickFile = "binary.md"
            return
        }
        if (shell.phase === 13) {
            if (!qdoc || !qdoc.sourceItem || qdoc.sourceItem.parent.answer !== "binary") return
            shell.refusal(qdoc, "binary", "binary file", "ready")
            shell.finish()
        }
    }

    // frameSwapped samples the just-presented state before scheduling the next scroll.
    function presentedFrame() {
        var quickDoc = shell.docOf(quick)
        if (quickDoc && shell.phase === 2) {
            var waiting = shell.fencesOf(quick).filter(function (f) { return f.awaiting })
            if (waiting.length > 0) {
                shell.waitingFrames += 1
                if (quickDoc.firstScreen || !quickDoc.loading || quickDoc.status !== "loading") shell.earlyScreens += 1
                for (var w = 0; w < waiting.length; w++) shell.fenceHeights[waiting[w].slot] = waiting[w].height
            }
        }
        if (!shell.sampling && !shell.flinging) return
        var body = shell.docOf(column).bodyItem
        var inView = shell.fencesOf(column).filter(function (f) {
            var top = f.mapToItem(body, 0, 0).y
            return top + f.height > 0 && top < body.height
        })
        if (shell.flinging) {
            for (var f = 0; f < inView.length; f++)
                if (inView[f].awaiting) shell.awaitingFlingFences[inView[f].slot] = true
            shell.flingFrames += 1
            if (shell.flingFrames % 3 === 0)
                Qt.callLater(shell.scrollColumn, 2)
            if (shell.flingFrames === 60) shell.flinging = false
            return
        }
        shell.sampledFrames += 1
        shell.fencesSeen = Math.max(shell.fencesSeen, inView.length)
        for (var f = 0; f < inView.length; f++) shell.visitedFences[inView[f].slot] = true
        var plain = false
        for (var k = 0; k < inView.length; k++) {
            if (inView[k].info !== "" && !shell.enginePaint(inView[k])) {
                shell.missedColours[inView[k].slot] = true
                plain = true
            }
        }
        if (plain) shell.plainFrames += 1
        if (shell.sweepSteps % 12 === 11) Qt.callLater(shell.scrollColumn, 1)
        shell.sweepSteps += 1
        if (shell.sweepSteps >= 720) shell.sampling = false
    }
    function scrollColumn(pages) {
        var body = shell.docOf(column).bodyItem
        body.contentY = Math.min(body.contentY + pages * body.height, body.contentHeight - body.height)
    }
    Connections {
        target: column.Window.window
        function onFrameSwapped() { shell.presentedFrame() }
    }
    // A changing test pixel keeps frames presenting even when the scroller rests; this timer never samples them.
    Timer {
        interval: 16
        repeat: true
        running: !shell.done
        onTriggered: shell.framePulse = !shell.framePulse
    }

    Timer {
        id: quitter
        interval: 300
        onTriggered: Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
