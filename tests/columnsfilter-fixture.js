.pragma library
.import "flea/js/Contrast.js" as Contrast

// Matches interleave with non-matches in name order, so a step from a kept row skips a hidden row: "ap" keeps rows 0, 2, 4, 6, 8 and 10, 6 of the 12 below.
function buildRows() {
    return [
        { n: "Apps", d: true, i: "folder", p: 493, s: 0, m: 1, t: false, k: 0 },
        { n: "Clips", d: true, i: "folder", p: 493, s: 0, m: 2, t: false, k: 0 },
        { n: "Maps", d: true, i: "folder", p: 493, s: 0, m: 2, t: false, k: 0 },
        { n: "balsam.txt", d: false, i: "text-x-generic", p: 420, s: 3, m: 3, t: false, k: 0 },
        { n: "caption.png", d: false, i: "text-x-generic", p: 420, s: 4, m: 4, t: false, k: 0 },
        { n: "drift.txt", d: false, i: "text-x-generic", p: 420, s: 5, m: 5, t: false, k: 0 },
        { n: "gap.md", d: false, i: "text-x-generic", p: 420, s: 6, m: 6, t: false, k: 0 },
        { n: "hold.txt", d: false, i: "text-x-generic", p: 420, s: 7, m: 7, t: false, k: 0 },
        { n: "napkin.txt", d: false, i: "text-x-generic", p: 420, s: 8, m: 8, t: false, k: 0 },
        { n: "orbit.md", d: false, i: "text-x-generic", p: 420, s: 9, m: 9, t: false, k: 0 },
        { n: "paper.pdf", d: false, i: "text-x-generic", p: 420, s: 10, m: 10, t: false, k: 0 },
        { n: "quince.txt", d: false, i: "text-x-generic", p: 420, s: 11, m: 11, t: false, k: 0 }
    ]
}

function buildParentRows() {
    return [
        { n: "studio", d: true, i: "folder", p: 493, s: 0, m: 1, t: false, k: 0 },
        { n: "field", d: true, i: "folder", p: 493, s: 0, m: 2, t: false, k: 0 },
        { n: "notes.txt", d: false, i: "text-x-generic", p: 420, s: 1, m: 3, t: false, k: 0 }
    ]
}

// A search result is a path: base name "report-final.md", folder "docs".
function searchRow() { return { n: "docs/report-final.md", d: false, i: "text-x-generic", p: 420, s: 1, m: 1, t: false, k: 0 } }

// Columns rows take List's match mark: a "/" row marks its plain name and a search row also splits name and folder, read by item and model value and never by shown text; the pane flips to a search for one turn and back.
function searchPane(query) { return { searchMode: "files", filterQuery: "", swap: { answeredQuery: query } } }

// The name label takes the row's own ink while a query marks it: accent on the cursor row, the rest ink elsewhere.
function nameInkFailures(cursorRow, restRow, theme) {
    var out = []
    cursorRow.cursor = true
    if (!Qt.colorEqual(cursorRow.ink, theme.color.accent)) out.push("cursor row ink " + cursorRow.ink + ", want accent")
    if (!Qt.colorEqual(cursorRow.nameItem().color, cursorRow.ink)) out.push("cursor name ink " + cursorRow.nameItem().color + ", want its ink " + cursorRow.ink)
    cursorRow.cursor = false
    if (!Qt.colorEqual(restRow.nameItem().color, restRow.ink)) out.push("rest name ink " + restRow.nameItem().color + ", want its ink " + restRow.ink)
    return out
}

// The folder takes List's cellInk (ui/Row.qml) and the clip mark follows the drawn label, on a marking search row.
function inkFailures(probe, theme) {
    var out = []
    var fg = theme.color.foreground
    var folder = probe.folderItem()
    probe.hovered = false
    var restRatio = Contrast.ratio(String(folder.color), String(theme.color.background))
    // muted and metadata derive from one colour, so the role is told apart by moving muted away while the ink is read.
    var kept = theme.color.muted
    theme.color.muted = "#ff00ff"
    if (!Qt.colorEqual(folder.color, theme.color.metadata)) out.push("rest folder ink " + folder.color + ", want List's rest ink " + theme.color.metadata)
    theme.color.muted = kept
    if (restRatio < 4.5) out.push("rest folder ink " + folder.color + " is " + restRatio.toFixed(2) + ":1 on the background, want at least 4.5:1")
    probe.cursor = true
    if (!Qt.colorEqual(folder.color, fg)) out.push("cursor folder ink " + folder.color + ", want foreground")
    probe.cursor = false
    probe.clipMark = "scissors"
    var label = probe.nameItem()
    var end = label.mapToItem(probe, 0, 0).x + Math.min(label.implicitWidth, label.width) + theme.spacing.gap
    if (Math.abs(probe.clipX() - end) > 0.01) out.push("marking row clip mark at " + probe.clipX() + ", want " + end + " after the visible label")
    probe.clipMark = ""
    return out
}

// Whether a row's mark content draws the search split; a row that marks nothing has none.
function locating(row) { var p = row.markPart(); return p !== null && p.locating }

// Items a row has built, Loader items included, for the report's counted line.
function built(item) {
    var n = 1
    for (var i = 0; i < item.children.length; i++) n += built(item.children[i])
    return n
}

// Measured ceilings: a marked row builds its mark content and nothing a drop or a clip would (31 and 29 before).
var SLASH_ITEMS = 29
var SEARCH_ITEMS = 28

// Match labels a row draws: an armed row builds its mark under the bare strip and draws none until a query marks.
function drawnMatches(item) {
    if (!item.visible) return 0
    var n = item.matchStart !== undefined && item.armed !== undefined ? 1 : 0
    for (var i = 0; i < item.children.length; i++) n += drawnMatches(item.children[i])
    return n
}

// Match labels a row has built, drawn or not: a hidden column builds none.
function builtMatches(item) {
    var n = item.matchStart !== undefined && item.armed !== undefined ? 1 : 0
    for (var i = 0; i < item.children.length; i++) n += builtMatches(item.children[i])
    return n
}
function columnMatches(area) {
    var n = 0
    for (var i = 0; i < activeCount(area); i++) { var row = area.itemAtIndex(i); if (row !== null) n += builtMatches(row) }
    return n
}
// Esc clears the standing query, then "/" opens over the hidden column, then the column shows again under the strip.
function hiddenFailures(area, pane, press) {
    var out = []
    press(Qt.Key_Escape, "")
    area.visible = false
    pane.filterTyping = true
    if (activeCount(area) !== 12 || columnMatches(area) !== 0)
        out.push("hidden columns keep " + activeCount(area) + " rows with " + columnMatches(area) + " marks built, want 12 with 0")
    area.visible = true
    if (columnMatches(area) !== 12) out.push("columns shown under the strip build " + columnMatches(area) + " marks, want 12")
    pane.filterTyping = false
    return out
}

// Measured ceiling: the bare strip arms a row so the first character only fills the mark it built.
var ARMED_ITEMS = 29

function armFailures(row, restItems) {
    var armedItems = built(row)
    console.log("COLUMNSFILTER armed rest=" + restItems + " armed=" + armedItems)
    var out = []
    if (!row.markArmed || row.marking) out.push("a row under the bare strip arms " + row.markArmed + " and marks " + row.marking + ", want true and false")
    if (armedItems > ARMED_ITEMS) out.push("an armed row builds " + armedItems + " items, want at most " + ARMED_ITEMS)
    if (row.dropClipBuilt()) out.push("an armed row builds the drop label and clip mark, want none")
    if (drawnMatches(row) !== 0) out.push("an armed row draws " + drawnMatches(row) + " match labels before a query marks, want 0")
    if (!row.nameItem().visible) out.push("an armed row hides its plain name")
    return out
}

function markFailures(slashRow, searchRowItem, pane, theme) {
    var slashItems = built(slashRow)
    var searchItems = built(searchRowItem)
    var languageItems = searchRowItem.langLoader ? built(searchRowItem.langLoader) : 0
    console.log("COLUMNSFILTER rowitems slash=" + slashItems + " search=" + searchItems + " language=" + languageItems + " search-core=" + (searchItems - languageItems))
    var out = inkFailures(searchRowItem, theme)
    if (searchRowItem.langSlug !== "markdown" || !searchRowItem.langLoader || !searchRowItem.langLoader.item || languageItems !== 3)
        out.push("the Markdown search row builds " + languageItems + " language items, want its Loader, mark and Shape")
    if (slashItems > SLASH_ITEMS || searchItems - languageItems > SEARCH_ITEMS)
        out.push("marked row cores build " + slashItems + " and " + (searchItems - languageItems) + " items, want at most " + SLASH_ITEMS + " and " + SEARCH_ITEMS)
    var mark = slashRow.nameItem()
    if (!slashRow.marking || locating(slashRow)) out.push("slash row marking " + slashRow.marking + " locating " + locating(slashRow) + ", want true false")
    if (mark.matchStart !== 0 || mark.matchLength !== 2) out.push("slash run " + mark.matchStart + "," + mark.matchLength + ", want 0,2")
    if (slashRow.folderItem() !== null) out.push("slash row builds a folder text, want none")
    if (drawnMatches(slashRow) !== 1) out.push("slash row draws " + drawnMatches(slashRow) + " match labels, want 1")
    if (slashRow.dropClipBuilt() || searchRowItem.dropClipBuilt()) out.push("a marked row that is no drop target and holds no clip mark builds the drop label and clip mark, want none")
    var hit = searchRowItem.nameItem()
    if (!locating(searchRowItem)) out.push("search row locating false, want true")
    if (hit.matchStart !== 7 || hit.matchLength !== 5) out.push("search run " + hit.matchStart + "," + hit.matchLength + ", want 7,5 on the base name")
    if (searchRowItem.folderItem().text !== "docs") out.push("search folder " + searchRowItem.folderItem().text + ", want docs")
    pane.searchMode = "files"
    pane.swap.answeredQuery = "ap"
    if (!locating(slashRow) || slashRow.markQuery !== "ap") out.push("pane search gives locating " + locating(slashRow) + " query " + slashRow.markQuery + ", want true ap from the answered query")
    pane.searchMode = ""
    pane.swap.answeredQuery = ""
    if (locating(slashRow)) out.push("leaving the search leaves locating on")
    return out
}

// QML helpers live here to hold tests/columnsfilter.qml under its 400 cap.
function activeCount(area) { return area.activeColumn().viewport.count }
function parentNames(area) { return area.peekNames("/probe") }
function preview(area) { return area.previewColumn }
function stamps(ipc) { return JSON.parse(ipc.seam.filterStamps()) }
function shownHas(pane, row) { return pane.shown !== null && pane.shown.indexOf(row) >= 0 }
function answerParentPeek(backend, windowSize) {
    var rows = buildParentRows()
    backend.peeked("/probe", false, rows.length, rows, false, 0, false, windowSize)
}
