.pragma library

.import "Drag.js" as Drag
.import "DragOut.js" as DragOut
.import "DropDev.js" as DropDev

var sequence = 0

// Sample input: a mounted volume at "/run/media/u/USB/" names "/run/media/u/USB"; a phone root names nothing.
function destination(entry, marker, urls, shelf, plain) {
    if (!entry || entry.kind === "recent" || entry.kind === "trash" || entry.kind === "tag"
            || entry.kind === "phone" || entry.mounted === false) return ""
    var path = DropDev.normalize(entry.path)
    if (path.charAt(0) !== "/" || /^\/run\/user\/[0-9]+\/gvfs\/(mtp|gphoto2|afc):[^/]+$/i.test(path)) return ""
    if (marker && !Drag.markerFields(marker)) return ""
    var paths = DragOut.sources(urls, plain, marker, shelf)
    if (paths.length === 0 || DragOut.refusal(paths, path, marker, shelf) !== "") return ""
    return path
}

// The rail's existing rows supply geometry, including the scroller's offset; headings name no row.
function rowAt(sidebar, x, y) {
    for (var i = 0; i < sidebar.entries.length; i++) {
        var row = sidebar.railItemFor(i)
        if (!row || !row.visible) continue
        var at = row.mapFromItem(sidebar, x, y)
        if (at.x >= 0 && at.y >= 0 && at.x < row.width && at.y < row.height) return i
    }
    return -1
}

// A new hover never borrows cached device facts from an earlier mount or gesture.
function pending(path) {
    sequence += 1
    return { path: path, id: sequence, dev: 0 }
}

// Sample input: answer({path:"/usb",id:7,dev:0}, 7, {"/usb":42}) names device 42; a superseded id leaves it unknown.
function answer(held, id, devs) {
    if (!held || held.id !== id || !Object.prototype.hasOwnProperty.call(devs || {}, held.path)) return held
    return { path: held.path, id: held.id, dev: DropDev.devFor(devs, held.path) }
}

// The ordinary folder transfer asks the collision host first, which owns the card and the undo path.
function drop(pane, entry, held, marker, urls, shelf, plain, proposed, ctrl, shift) {
    if (!pane || !pane.backend || pane.listInFlight) return false
    var path = destination(entry, marker, urls, shelf, plain)
    if (!path) return false
    return Drag.dropInto(pane, marker, urls, path, held && held.path === path ? held.dev : 0,
                         shelf, plain, proposed, ctrl, shift)
}
