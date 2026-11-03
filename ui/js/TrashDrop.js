.pragma library

.import "Drag.js" as Drag
.import "DragOut.js" as DragOut
.import "Ops.js" as Ops
.import "Swap.js" as Swap
.import "Mounts.js" as Mounts

// Only rows lifted in this window may trash through ui/RailTrashRow.qml, with dd's request and z's undo.
// Sample marker: "<instance>\n1,3\nmove\n%2Fd\n42\n1\n0\n7".
function markerRows(marker) {
    var field = String(marker).split("\n")[1] || ""
    if (field.length === 0) return []
    var rows = []
    var parts = field.split(",")
    for (var i = 0; i < parts.length; i++) {
        if (!/^[0-9]+$/.test(parts[i])) return []
        var n = Number(parts[i])
        if (!Number.isInteger(n) || n < 0) return []
        rows.push(n)
    }
    return rows
}

// The request or null: carried paths survive listing changes; rows are only for a selection too wide to carry paths, on its source listing in lift-time numbering, so src/backend/rowguard.rs refuses stale indices.
function request(marker, urls, path, backend) {
    if (!Drag.isOwnDrag(marker)) return null
    // Issue 133: a GVFS mount has no trash, so the drop is refused up front as d and the menu are.
    if (!Mounts.trashable(Drag.markerSource(marker) || path)) return null
    var paths = DragOut.filePaths(urls)
    if (paths.length > 0) return { c: "trash", paths: paths }
    var rows = markerRows(marker)
    var listing = Drag.markerListing(marker)
    if (rows.length === 0 || listing <= 0 || !Drag.sameListing(marker, path) || !Drag.liftedBy(marker, backend)) return null
    return Swap.named({ c: "trash", rows: rows }, listing)
}

// Whether the drag can trash its carried files here, used by the hover check and status line.
function accepts(marker, urls, path, backend) {
    return request(marker, urls, path, backend) !== null
}

// Sends trash through the pane's backend and answers whether it sent; the trashed reply clears the selection and re-reads the listing.
function drop(pane, marker, urls) {
    if (!pane || !pane.backend) return false
    var sent = request(marker, urls, pane.path, pane.backend)
    if (!sent) return false
    // Where the cursor lands once the rows are gone, as dd sets it; only a drag from this listing has one.
    var rows = Drag.sameListing(marker, pane.path) && Drag.liftedBy(marker, pane.backend) ? markerRows(marker) : []
    var first = rows.length > 0 ? rows[0] : -1
    for (var i = 1; i < rows.length; i++)
        if (rows[i] < first) first = rows[i]
    pane.trashedFirst = first
    pane.backend.send(sent)
    return true
}

// The status bar while the drag rests on the Trash row. Sample: "Move 2 items to Trash".
function line(marker, urls, path, backend) {
    if (!accepts(marker, urls, path, backend)) return ""
    var rows = markerRows(marker)
    var n = rows.length > 0 ? rows.length : DragOut.filePaths(urls).length
    return "Move " + Ops.items(n) + " to Trash"
}
