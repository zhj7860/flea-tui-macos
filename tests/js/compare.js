.import "../../ui/js/Compare.js" as Compare
.import "../../ui/js/Menu.js" as Menu
.import "../../ui/js/Ops.js" as Ops
.import "../../ui/js/Keymap.js" as Keymap
.import "../../ui/js/PreviewKeys.js" as PreviewKeys
.import "../../ui/js/Focus.js" as Focus
.import "sourcefixture.js" as Source

var REG = 0o100644
var DIR = 0o040755
var LINK = 0o120777

// The board's patch: context from line 9, six lines go and six come in at 12 to 17, context to line 20.
var PATCH = "--- /w/notes-a.md\n+++ /w/notes-b.md\n@@ -9,12 +9,12 @@\n ## Previews\n \n Each kind asks for what it shows.\n" +
    "-Thumbnails never load on phones.\n-The map holds every row.\n-A taller preview costs nothing.\n-Ports keep their slots.\n-Marks ship one size.\n-Facts fold into two lines.\n" +
    "+Thumbnails stay cache-only on phones.\n+The map holds the visible rows.\n+A taller preview costs what a shorter one did.\n+Ports keep their slots while scrolling.\n+Marks share one optical size.\n+Facts fold into one line.\n" +
    " Only the visible lines are asked for.\n A newer request cancels an older one.\n The frame runs to the column bottom.\n"

function menuState(kinds) {
    return { hasRow: true, selectionCount: kinds ? kinds.length : 1, rowMode: REG, clipboardAvailable: false,
        rowIsSymlink: false, hiddenActions: [], compareKinds: kinds }
}
function actions(kinds) { return Menu.listingEntries(menuState(kinds)).map(function (r) { return r.action || "|" }) }

function run(plain) {
    // check compares with ===, so lists and numbers go through JSON to compare by value.
    function check(label, got, want) { plain(label, JSON.stringify(got), JSON.stringify(want)) }
    check("two regular files offer Compare", Menu.canCompare([REG, REG]), true)
    check("regular files qualify regardless of permission bits", Menu.canCompare([0o100000, 0o100755]), true)
    check("one marked file does not", Menu.canCompare([REG]), false)
    check("three marked files do not", Menu.canCompare([REG, REG, REG]), false)
    check("a folder among them does not", Menu.canCompare([REG, DIR]), false)
    check("a second directory mode does not", Menu.canCompare([REG, 0o040000]), false)
    check("a link stays a link and does not qualify", Menu.canCompare([REG, LINK]), false)
    check("no kinds, or kinds that are not a list, do not", [Menu.canCompare(undefined), Menu.canCompare(null), Menu.canCompare("")], [false, false, false])

    check("a symlink pair hides Compare", actions([LINK, LINK]).indexOf("compare"), -1)
    var opened = [], selection = [4800, 3]
    var wide = { cursorIndex: 4800, selectedIndices: function () { return selection },
        rowFor: function (index) { return index === 4800 ? { n: "b.txt", p: REG, i: "text-x-generic" } : null },
        menuSelectionIdentity: function () { return "wide" },
        menuActions: { ready: true, identity: "wide", selectedKinds: [REG, REG] },
        quickLook: function () { return { openCompare: function (a, b, icon) { opened.push([a, b, icon]) } } } }
    check("marks more than one held window apart still show Compare", Menu.canCompare(Ops.menuKinds(wide)), true)
    Ops.open(wide, ["/wide/b.txt", "/wide/a.txt"])
    check("validated paths outside the window open in listing order", opened.map(function (pair) { return pair.slice(0, 2) }), [["/wide/a.txt", "/wide/b.txt"]])
    wide.menuActions.identity = "retired"
    check("an old snapshot cannot supply an unheld kind", Menu.canCompare(Ops.menuKinds(wide)), false)
    Ops.open(wide, ["/wide/b.txt", "/wide/a.txt"])
    check("an old snapshot cannot open Compare", opened.length, 1)
    wide.menuActions.identity = "wide"
    wide.menuActions.ready = false
    check("an unready snapshot cannot supply an unheld kind", Menu.canCompare(Ops.menuKinds(wide)), false)
    wide.menuActions.ready = true
    wide.menuActions.selectedKinds = [REG]
    check("a matching snapshot with the wrong count cannot supply an unheld kind", Menu.canCompare(Ops.menuKinds(wide)), false)

    var shown = actions([REG, REG])
    check("the row is present for two files", shown.indexOf("compare") >= 0, true)
    check("the row sits before Add to Favorites", shown.indexOf("compare") + 1 === shown.indexOf("addFavourite"), true)
    check("the row is absent for three files", actions([REG, REG, REG]).indexOf("compare"), -1)
    check("the row is absent for one file", actions([REG]).indexOf("compare"), -1)
    check("the row is absent with no kinds read", actions(undefined).indexOf("compare"), -1)
    var hidden = menuState([REG, REG])
    hidden.hiddenActions = ["compare"]
    check("Settings can hide Compare over two regular files", Menu.listingEntries(hidden).some(function (entry) { return entry.action === "compare" }), false)
    var background = menuState([REG, REG])
    background.hasRow = false
    check("a background menu omits Compare despite two regular marks", Menu.listingEntries(background).some(function (entry) { return entry.action === "compare" }), false)
    check("header, rail, Places and Trash inventories omit Compare",
        [Menu.headerEntries([], false), Menu.railEntries({kind: "favourite"}), Menu.placeEntries(menuState([REG, REG])), Menu.trashEntries(2, false)]
            .map(function (entries) { return entries.some(function (entry) { return entry.action === "compare" }) }),
        [false, false, false, false])
    var row = Menu.listingEntries(menuState([REG, REG])).filter(function (r) { return r.action === "compare" })[0]
    check("the row is Compare with the columns glyph and no submenu", [row.label, row.glyph, row.submenu === undefined], ["Compare", "columns", true])
    check("no key opens it", Keymap.PRESET_KEYS.concat(Keymap.SHARED_KEYS).filter(function (r) { return r.action === "compare" }).length, 0)

    check("one differing line", Compare.title("a.md", "b.md", 1), "a.md and b.md · 1 line differs")
    check("twelve differing lines", Compare.title("notes-a.md", "notes-b.md", 12), "notes-a.md and notes-b.md · 12 lines differ")
    check("a pair with no patch names the files alone", Compare.title("notes-a.md", "notes-b.md", null), "notes-a.md and notes-b.md")
    check("a file named like a placeholder is not read as one", Compare.title("%2", "b", 1), "%2 and b · 1 line differs")
    check("the board's sentences, one whole string each", [Compare.sentence("identical"), Compare.sentence("binary"), Compare.sentence("over")],
        ["The two files are identical.", "These files are binary, so there is nothing to compare.", "These files are over 1 MiB, too large to compare."])

    var rows = Compare.rows(PATCH)
    check("the board's hunk is a header and eighteen lines", [rows.length, rows[0].kind, rows[0].text], [19, "hunk", "@@ -9,12 +9,12 @@"])
    check("twelve lines differ", Compare.changed(rows), 12)
    check("the first context line is 9 and 9", [rows[1].kind, rows[1].oldNo, rows[1].newNo, rows[1].text], ["context", 9, 9, "## Previews"])
    check("a removed line carries only its old number", [rows[4].kind, rows[4].oldNo, rows[4].newNo], ["removed", 12, 0])
    check("an added line carries only its new number", [rows[10].kind, rows[10].oldNo, rows[10].newNo, rows[10].text], ["added", 0, 12, "Thumbnails stay cache-only on phones."])
    check("the last context line is 20 and 20", [rows[18].oldNo, rows[18].newNo], [20, 20])
    check("the blank context line keeps its place", [rows[2].text, rows[2].oldNo], ["", 10])
    check("a second hunk restarts the numbers", Compare.rows("--- a\n+++ b\n@@ -1 +1 @@\n-x\n+y\n@@ -40,2 +40,2 @@\n z\n-q\n+r\n").map(function (r) { return r.oldNo + "/" + r.newNo }).join(" "), "0/0 1/0 0/1 0/0 40/40 41/0 0/41")
    check("a line holding --- inside a hunk is a removed line", Compare.rows("--- a\n+++ b\n@@ -1 +1 @@\n---x\n+y\n")[1].text, "--x")
    check("a missing final newline is a note with no number", Compare.rows("--- a\n+++ b\n@@ -1 +1 @@\n-x\n\\ No newline at end of file\n+y\n")[2].kind, "note")

    // y: the preview context's own row, and the listing's y stays copy.
    var presets = ["default", "vim", "mac", "windows"]
    check("y copies the patch in the preview context of every preset", presets.map(function (p) { return Keymap.lookupFor(p, 0, "y", Qt.NoModifier, "preview", "gui") }),
        ["copyPatch", "copyPatch", "copyPatch", "copyPatch"])
    check("y means nothing in a PDF or media preview", [Keymap.lookupFor("default", 0, "y", Qt.NoModifier, "pdf", "gui"), Keymap.lookupFor("default", 0, "y", Qt.NoModifier, "media", "gui")], ["", ""])
    check("the listing keeps y as copy", Keymap.lookupFor("default", 0, "y", Qt.NoModifier, "listing", "gui"), "copy")
    var copied = 0
    var pane = { preview: { isCompare: true, revealStrip: function () {}, copyPatch: function () { copied += 1 } } }
    PreviewKeys.act("copyPatch", pane)
    check("the action reaches the overlay once", copied, 1)
    var event = { key: 0, text: "y", modifiers: Qt.NoModifier }
    var regularPreview = { preview: { active: true, isPdf: false, isMedia: false, isCompare: false } }
    var binding = Keymap.PRESET_KEYS.filter(function (row) { return row.action === "copyPatch" && row.context === "preview" })[0]
    var slot = Keymap.PRESET_KEYS.indexOf(binding)
    Keymap.PRESET_KEYS.splice(slot, 1)
    check("before Compare's binding a regular preview had no y action", Focus.lookup(event, regularPreview), "")
    Keymap.PRESET_KEYS.splice(slot, 0, binding)
    check("after Compare's binding y cannot copy a non-Compare file", Focus.lookup(event, regularPreview), "copyPatch")
    var ignored = 0, nonCompare = { isCompare: false }
    var compareLoader = { item: { copyPatch: function () { ignored += 1 } } }
    var guardedCopy = new Function("root", "compareLoader", Source.block(Source.source("ui/Preview.qml"), "function copyPatch()", "ui/Preview.qml"))
    PreviewKeys.act("copyPatch", { preview: { revealStrip: function () {}, copyPatch: function () { guardedCopy(nonCompare, compareLoader) } } })
    check("the production preview guard copies nothing outside Compare", ignored, 0)
    var other = { cursorIndex: 0, preview: { isCompare: true, revealStrip: function () {}, close: function () {} } }
    PreviewKeys.act("cursorDown", other)
    check("the cursor keys leave a Compare overlay as it is", other.cursorIndex, 0)

    var view = Source.source("ui/CompareView.qml")
    check("the copy route is the opener's text copy and nothing else", (view.match(/copyText\(/g) || []).length, 1)
    check("a diff row is text alone, with no fill under it", Source.slice(view, "delegate: Item", "Flea.ViewportScrollBars").indexOf("Rectangle"), -1)
}
