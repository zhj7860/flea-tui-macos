//@ pragma ShellId flea-langmarks-count-test
import QtQuick
import Quickshell
import "flea" as Flea
import "langmark-count.js" as LangCost
import "flea/js/LangMarkPaths.js" as LangMarkPaths

// Real delegates prove demand construction, ink, geometry and teardown across reuse.
ShellRoot {
    id: root
    property var failures: []
    property int phase: 0
    property var idle: []
    property var fullIdle: []
    property var labelXs: []
    property int barIdle: 0
    property int barFullIdle: 0
    property var codeCounts: []
    property var fullCodeCounts: []
    property var marks: []
    property var delegates: [listRow, tile, column]
    property var labels: ["Row", "GridTile", "ColumnRow"]
    property var ceilings: [17, 13, 15]
    property var born: [bornRow, bornTile, bornColumn]
    property var plainRow: ({n: "notes.ini", d: false, i: "text-x-generic", p: 420, s: 13, m: 1758835200})
    property var codeRow: ({n: "main.rs", d: false, i: "text-x-generic", p: 420, s: 13, m: 1758835200})

    Flea.Row { id: listRow; width: 800; row: root.plainRow; kindNames: []; hiddenCols: [] }
    Flea.GridTile { id: tile; width: 160; height: 160; row: root.plainRow }
    Flea.ColumnRow { id: column; width: 300; row: root.plainRow }

    Flea.Row { id: bornRow; width: 800; row: root.codeRow; kindNames: []; hiddenCols: [] }
    Flea.GridTile { id: bornTile; width: 160; height: 160; row: root.codeRow }
    Flea.ColumnRow { id: bornColumn; width: 300; row: root.codeRow }

    Flea.QuickLookBar { id: codeBar; width: 600; name: "notes.ini" }

    function check(ok, reason) { if (!ok) root.failures.push(reason) }

    function each(action) {
        for (var i = 0; i < root.delegates.length; i++) action(root.delegates[i], i)
    }

    function checkMarkGeometry() {
        root.each(function(row, i) {
            var loader = row.langLoader, mark = loader ? loader.item : null
            root.check(loader !== null && loader.active && mark !== null, root.labels[i] + " builds no live language mark")
            if (!mark) return
            root.check(LangCost.census(row, true).types.LangMark === 1, root.labels[i] + " builds more than one language mark")
            root.check(mark.slug === row.langSlug && LangMarkPaths.pathFor(mark.slug).length > 0, "Rust geometry is missing")
            root.check(mark.page === "M4 7V2h10l6 6v14H17 M14 2v6h6" && mark.strokeWidth === 2, "the file page or its stroke changed")
            root.check(loader.glyph.visible === false, root.labels[i] + " still draws the kind glyph beside the language mark")
            root.check(loader.x === loader.glyph.x && loader.y === loader.glyph.y
                && loader.width === loader.glyph.width && loader.height === loader.glyph.height, root.labels[i] + " leaves its glyph slot")
            var origin = mark.mapToItem(loader.glyph.parent, 0, 0)
            var centre = mark.mapToItem(loader.glyph.parent, mark.width / 2, mark.height / 2)
            root.check(mark.x === 0 && mark.y === 0 && mark.width === loader.glyph.width && mark.height === loader.glyph.height
                && Math.abs(origin.x - loader.glyph.x) < 0.01 && Math.abs(origin.y - loader.glyph.y) < 0.01
                && Math.abs(centre.x - loader.glyph.x - loader.glyph.width / 2) < 0.01
                && Math.abs(centre.y - loader.glyph.y - loader.glyph.height / 2) < 0.01, root.labels[i] + " loaded mark leaves its glyph slot")
            root.check(String(mark.color) === String(loader.glyph.color), root.labels[i] + " changes the glyph ink")
            root.check(mark.markSize === loader.glyph.markSize, root.labels[i] + " changes the glyph size")
            var shape = mark.children[0]
            root.check(shape && Math.abs(shape.x - (mark.width - mark.markSize) / 2) < 0.01
                && Math.abs(shape.y - (mark.height - mark.markSize) / 2) < 0.01, root.labels[i] + " does not centre its page")
            var svg = LangCost.census(mark, true).objects.filter(function(object) { return /^QQuickPathSvg/.test(String(object)) })
            root.check(svg.length === 2 && svg[0].path === mark.page && svg[1].path === LangMarkPaths.pathFor(mark.slug),
                root.labels[i] + " does not draw the approved page and filled logo")
            if (root.marks[i]) root.check(root.marks[i] === mark, root.labels[i] + " rebuilds its mark for a state change")
            root.marks[i] = mark
        })
    }

    function checkMarks() {
        root.checkMarkGeometry()
        root.each(function(row, i) {
            var visible = LangCost.state(row).markVisible
            root.check(visible === true, root.labels[i] + " language mark is invisible")
            if (visible !== true) console.log("LANGCOST INVISIBLE phase=" + root.phase + " surface=" + root.labels[i] + " slug=" + row.langSlug)
        })
    }

    // Mutate each real mark, leaving its generic glyph hidden, then use the same reader and assertions.
    function visibilityControls() {
        root.each(function(row, i) {
            var mark = row.langLoader.item, held = root.failures
            mark.visible = false
            root.failures = []
            root.checkMarkGeometry()
            var before = root.failures.slice()
            root.failures = []
            root.checkMarks()
            var after = root.failures.slice()
            mark.visible = true
            root.failures = held
            root.check(before.length === 0, root.labels[i] + " invisible control changes the original geometry assertions")
            root.check(after.length === 1 && after[0] === root.labels[i] + " language mark is invisible",
                root.labels[i] + " accepts an invisible mark with a hidden fallback glyph")
            console.log("LANGCOST CONTROL " + root.labels[i] + " blank-slot originalErrors=" + before.length
                + " correctedErrors=" + after.length + " restored=" + LangCost.state(row).markVisible)
        })
    }

    Timer {
        interval: 400
        repeat: true
        running: true
        onTriggered: root.advance()
    }

    function advance() {
        if (root.phase === 0) {
            root.barIdle = LangCost.census(codeBar, false).total
            root.barFullIdle = LangCost.census(codeBar, true).total
            root.check(codeBar.langLoader === null, "an unmapped code bar builds a language mark")
            codeBar.name = "main.rs"
            for (var b = 0; b < root.born.length; b++) {
                var initial = root.born[b]
                root.check(initial.langLoader !== null && initial.langLoader.item !== null,
                    root.labels[b] + " born on a code file builds no language mark")
            }
            root.each(function(row, i) {
                root.idle[i] = LangCost.plain(root.failures, row, root.labels[i], root.ceilings[i])
                root.fullIdle[i] = LangCost.census(row, true).total
                root.labelXs[i] = LangCost.state(row).labelX
                row.row = root.codeRow
            })
        } else if (root.phase === 1) {
            var geometry = codeBar.geometry()
            root.check(geometry.language && geometry.language.slug === "rust" && geometry.language.visible === true && geometry.mark.visible === false,
                "the Quick Look bar draws no Rust language mark")
            root.check(LangCost.census(codeBar, false).total - root.barIdle === 5
                && LangCost.census(codeBar, true).total - root.barFullIdle === 8, "the code bar does not add five delegate/eight full objects")
            codeBar.name = "notes.ini"
            root.checkMarks()
            root.each(function(row, i) {
                root.codeCounts[i] = LangCost.census(row, false).total
                root.fullCodeCounts[i] = LangCost.census(row, true).total
                root.check(root.codeCounts[i] - root.idle[i] === 5, root.labels[i] + " does not add exactly five delegate objects")
                root.check(root.fullCodeCounts[i] - root.fullIdle[i] === 8, root.labels[i] + " does not add exactly eight objects including paths and transforms")
                root.check(LangCost.state(row).labelX === root.labelXs[i], root.labels[i] + " moves its filename column")
                console.log("LANGCOST " + root.labels[i] + " code=" + root.codeCounts[i] + " added="
                    + (root.codeCounts[i] - root.idle[i]) + " fullAdded=" + (root.fullCodeCounts[i] - root.fullIdle[i]))
                row.cursor = true
            })
        } else if (root.phase === 2) {
            root.check(codeBar.langLoader === null && LangCost.census(codeBar, false).total === root.barIdle
                && LangCost.census(codeBar, true).total === root.barFullIdle, "the code bar retains language objects after reuse")
            console.log("LANGCOST QuickLookBar noncode-added=0 code-added=5 fullAdded=8 reuse=0")
            root.checkMarks()
            root.check(String(listRow.langLoader.item.color) === String(Flea.Theme.color.foreground), "list cursor does not lift the mark")
            root.each(function(row) {
                row.clipMark = "scissors"
                row.row = {n: "app.py", d: false, i: "text-x-generic", p: 420, s: 13}
            })
        } else if (root.phase === 3) {
            root.checkMarks()
            root.each(function(row, i) {
                root.check(row.langLoader.item.slug === "python", root.labels[i] + " does not update a reused code mark")
                root.check(Math.abs(LangCost.effectiveAlpha(row.langLoader.item) - 0.55) < 0.01, root.labels[i] + " does not dim its mark to 0.55")
                row.clipMark = ""
                row.cursor = false
                row.row = root.plainRow
            })
            root.marks = []
        } else if (root.phase === 4) {
            root.each(function(row, i) {
                LangCost.plain(root.failures, row, root.labels[i] + " reused", root.idle[i])
                root.check(LangCost.census(row, true).total === root.fullIdle[i], root.labels[i] + " retains objects after reuse")
                row.row = root.codeRow
                row.thumb = Quickshell.env("LANGMARK_THUMB")
            })
        } else if (root.phase === 5) {
            root.each(function(row, i) {
                root.check(row.thumbDrawn && row.iconStatus === Image.Ready, root.labels[i] + " thumbnail control failed to decode")
                root.check(row.langLoader === null && LangCost.languageObjects(LangCost.census(row, true)) === 0,
                    root.labels[i] + " builds a language mark behind its thumbnail")
                row.thumb = Quickshell.env("LANGMARK_THUMB") + ".missing"
            })
        } else if (root.phase === 6) {
            root.checkMarks()
            root.each(function(row, i) {
                root.check(!row.thumbDrawn && row.iconStatus === Image.Error, root.labels[i] + " missing thumbnail control did not fail")
                row.thumb = ""
                row.row = {n: "main.rs", d: true, i: "folder", p: 493, s: 13}
            })
            root.marks = []
        } else if (root.phase === 7) {
            root.each(function(row, i) {
                LangCost.plain(root.failures, row, root.labels[i] + " directory", root.idle[i])
                row.row = {n: "main.rs", d: false, i: "text-x-generic", p: 0o120777, s: 13}
            })
        } else {
            root.each(function(row, i) {
                LangCost.plain(root.failures, row, root.labels[i] + " symlink", root.idle[i])
            })
            // Destructive controls use the born fixtures only after every live reuse assertion.
            root.delegates = root.born
            root.checkMarks()
            root.visibilityControls()
            for (var f = 0; f < root.failures.length; f++) console.log("LANGCOST FAIL " + root.failures[f])
            if (root.failures.length === 0) console.log("LANGCOST PASS noncode-added=0 code-added="
                + (root.codeCounts[0] - root.idle[0]) + "," + (root.codeCounts[1] - root.idle[1]) + ","
                + (root.codeCounts[2] - root.idle[2]) + " reuse=0 thumbnail=0 fallback=1 inks=ok cut=0.55")
            Quickshell.execDetached(["kill", String(Quickshell.processId)])
        }
        root.phase += 1
    }
}
