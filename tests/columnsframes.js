.pragma library

// Actual live rows in each shown column, read at the window's afterAnimating signal.
function census(area) {
    var found = [], stack = [area]
    while (stack.length) {
        var o = stack.pop()
        if (!o) continue
        if (o.viewport !== undefined && o.drawsEmpty !== undefined && o.visible && o.width > 0) {
            var count = 0, firstName = "", firstY = Infinity, kids = o.viewport.contentItem.children
            for (var it of kids)
                if (it.live && it.visible && it.row && it.y + it.height > o.viewport.contentY && it.y < o.viewport.contentY + o.viewport.height) {
                    count++
                    if (it.y < firstY) { firstY = it.y; firstName = it.row.n }
                }
            found.push({ x: Math.round(o.mapToItem(area, 0, 0).x), rows: count, total: o.rowTotal, firstName: firstName })
        }
        if (o.children !== undefined) for (var child of o.children) stack.push(child)
    }
    found.sort(function (a, b) { return a.x - b.x })
    return { columns: found, third: area.shownIsDir ? "folder" : area.previewStateName(), hasThird: area.thirdShown,
             preview: { row: area.previewColumn.row !== null, ready: area.previewColumn.ready, state: area.previewColumn.previewState },
             capturing: area.swapState().capturing, holding: area.swapState().holding, loading: area.pane.swap.markSince > 0,
             listing: area.pane.swap.describe(), path: area.pane.path }
}
