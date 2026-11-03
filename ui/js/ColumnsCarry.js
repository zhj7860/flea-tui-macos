.pragma library
.import "Columns.js" as Columns
.import "FolderSorts.js" as FolderSorts
.import "Format.js" as Format

// Navigations carry answered peeks across a listing and refresh them without clearing drawn rows.

// A peek answers at most this many rows, src/backend/peek.rs PEEK_CAP.
var PEEK_CAP = 512

// The folder order a column asks under, as the tag its peek key and reply carry.
// Sample input: orderOf({ folderSorts: {}, rememberSort: true }, "/a", []) is "" for a folder with no order of its own.
function orderOf(state, path, drawn, newest) {
    var order = FolderSorts.peekOrder(state.folderSorts, path, state.rememberSort, drawn, newest, state.sort)
    return Columns.orderTag(order.by, order.desc)
}

// A read of the peeked rows that a binding re-evaluates when a peek lands; version is the trigger.
function rowsFor(peeked, key, path, version) {
    return version >= 0 && path.length > 0 && peeked[key] ? peeked[key] : []
}

// -1 for a path that was not denied, so mode 0, the denial whose stat failed too, stays its own answer.
function deniedMode(denials, key, version) {
    return version >= 0 && denials[key] !== undefined ? denials[key] : -1
}

// What a drag from a peek column's row needs. Sample input: peekSource(pane, "/a", { "/a": { v: 7, w: false } }, 0).
function peekSource(pane, path, facts, version) {
    var held = version >= 0 ? facts[path] : undefined
    return path.length > 0 ? { pane: pane, dir: path, v: held ? held.v : 0, w: held ? held.w : true } : null
}

// True when the target is the parent of the shown path: the one hop whose child is the folder left.
// Sample input: isBack("/a/b/c", "/a/b") is true, isBack("/a/b", "/a/b/c") and isBack("/", "/") are false.
function isBack(here, target) {
    return String(target) !== String(here) && String(target) === Columns.ancestorParent(here)
}

// A peek sorts name-first with folders first, so the listing must match that order exactly.
// Sample input: sameOrder({ by: "name", desc: false, foldersFirst: true, groupByKind: false }, "") is true.
function sameOrder(list, tag) {
    return list.by === "name" && list.desc !== true && list.foldersFirst !== false && list.groupByKind !== true
        && (tag === "" || tag === "name0")
}

// The held window as peek rows; a link or an executable seeds nothing, shaped differently in a peek.
// Sample input: peekRows([{ n: "a", d: false, i: "text-x-generic", s: 1 }], 1).
function peekRows(rows, count) {
    var out = []
    for (var i = 0; i < count; i++) {
        var row = rows[i]
        if (!row || row.l !== undefined || (Number(row.p) & Format.S_IFMT) === Format.S_IFLNK || (row.d !== true && row.i === "application-x-executable"))
            return null
        out.push({ n: row.n, d: row.d === true, i: row.i })
    }
    return out
}

// A navigation plan, or null before the first listing has anything to carry.
// Sample input: plan(area at "/a/b/c" listing "/a/b", ["/a"], { foldersFirst: true, groupByKind: false }).pre is ["/a"].
function plan(area, asks, state) {
    var p = area.pane, here = p.path, target = p.listingPath
    if (!here || !target)
        return null
    var tag = area.orderOf(here), count = Math.min(p.windowSize, PEEK_CAP, p.total)
    var list = { by: p.backend.sortBy, desc: p.backend.sortDesc, foldersFirst: state.foldersFirst, groupByKind: state.groupByKind }
    var clean = p.held === 0 && p.filterQuery === "" && p.searchMode === "" && p.rows.length >= count && sameOrder(list, tag)
    return { target: target, seed: here, tag: tag, pre: asks.filter(function (path) { return path !== target && path !== here }),
             rows: clean ? peekRows(p.rows, count) : null, facts: { v: p.backend.dirDev || 0, w: p.backend.dirWritable !== false } }
}

// A landing keeps answered drawn folders under the same key and order, plus the old third while its replacement waits.
function landing(carry, area, asks) {
    var next = { peeked: {}, denials: {}, orders: {}, facts: {}, pending: {} }
    if (!carry || carry.target !== area.pane.path)
        return next
    var paths = asks.slice()
    if (area.shownChildPath && paths.indexOf(area.shownChildPath) < 0) paths.push(area.shownChildPath)
    for (var i = 0; i < paths.length; i++) {
        var path = paths[i], key = area.peekKey(path)
        if (area.peeked[key] === undefined || area.peekOrders[key] !== area.orderOf(path))
            continue
        next.peeked[key] = area.peeked[key]
        next.orders[key] = area.peekOrders[key]
        if (area.denials[key] !== undefined) next.denials[key] = area.denials[key]
        if (area.peekFacts[path] !== undefined) next.facts[path] = area.peekFacts[path]
    }
    var seedKey = area.peekKey(carry.seed), seedTag = area.orderOf(carry.seed)
    if ((asks.indexOf(carry.seed) >= 0 || isBack(carry.seed, carry.target))
            && carry.rows !== null && carry.tag === seedTag && next.peeked[seedKey] === undefined) {
        next.peeked[seedKey] = carry.rows
        next.orders[seedKey] = seedTag
        next.facts[carry.seed] = carry.facts
    }
    if (asks.indexOf(carry.seed) >= 0 || isBack(carry.seed, carry.target)) paths.push(carry.seed)
    // A watched refresh already out must still land after navigation, even when its folder's settled rows are kept.
    for (var path of paths) {
        var sent = Columns.sentKey(area.peekKey(path), area.pane.windowSize, area.orderOf(path))
        if (Columns.hasAsk(area.pending, sent)) next.pending[sent] = area.pending[sent]
    }
    return next
}
