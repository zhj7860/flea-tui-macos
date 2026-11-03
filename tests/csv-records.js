.import QtQuick 2.15 as Quick

// Multiline CSV and TSV records keep one delegate, ordinal and count on every reader path.
function rowsInView(root, table) {
    return root.descendants(table.list).filter(function (row) {
        if (row.rec === undefined || row.index === undefined) return false
        var point = row.mapToItem(table.list, 0, 0)
        return point.y >= 0 && point.y < table.list.height
    }).sort(function (a, b) { return a.index - b.index })
}

function numberOf(row) {
    var text = row.children.filter(function (child) {
        return child.visible && child.x === 0 && typeof child.text === "string"
    })[0]
    return text ? Number(text.text) : null
}

function screen(root, table, label, numbered) {
    var rows = rowsInView(root, table)
    root.check(label + ": every drawn delegate has a record", rows.length > 0 && rows.every(function (row) {
        return row.rec !== null
    }), true)
    root.check(label + ": drawn records are contiguous", rows.length > 0 && rows.every(function (row) {
        return row.rec !== null && Number(row.rec.cells[0]) === row.index + 1
    }), true)
    if (numbered) root.check(label + ": drawn numbers count records", rows.map(numberOf), rows.map(function (row) {
        return row.index + 1
    }))
}

function steps(root, column, quick, backend) {
    var out = []
    function scenario(extension, ending, mode) {
        var label = "records " + extension + " " + ending + " " + mode
        out.push(function () {
            column.active = false
            quick.active = false
            column.backend = mode === "plain-file" ? null : backend
            quick.backend = mode === "plain-file" ? null : backend
            column.truncate = mode === "engine-text"
            quick.truncate = mode === "engine-text"
            column.path = root.fixture + "/records-" + ending + "." + extension
            quick.path = column.path
            column.active = true
            quick.active = true
            root.wait(label + ": first screens", function () {
                return root.firstScreenOf(root.colTable()) && root.firstScreenOf(root.qlTable())
                    && root.inView(root.colTable(), "first second") && root.inView(root.qlTable(), "first second")
            })
        })
        out.push(function () {
            var col = root.colTable()
            var ql = root.qlTable()
            root.check(label + ": exact count text", quick.countText(), "801 rows")
            root.check(label + ": one model row per record", ql.bodyRows, 801)
            root.check(label + ": column keeps one row per record for paging", [col.limit, col.bodyRows], [0, 801])
            screen(root, col, label + " column top", false)
            screen(root, ql, label + " quicklook top", true)
            ql.list.positionViewAtIndex(449, Quick.ListView.Beginning)
            root.wait(label + ": middle record draws", function () {
                return root.inView(ql, "middle second third")
            })
        })
        out.push(function () {
            var ql = root.qlTable()
            var row = ql.list.itemAtIndex(449)
            root.check(label + ": far jump lands on record 450", row && row.rec ? row.rec.cells[0] : null, "450")
            screen(root, ql, label + " quicklook middle", true)
            root.check(label + ": count after far jump", quick.countText(), "801 rows")
            ql.list.positionViewAtIndex(ql.bodyRows - 1, Quick.ListView.End)
            root.wait(label + ": last record draws", function () { return root.inView(ql, "last end") })
        })
        out.push(function () {
            var ql = root.qlTable()
            var row = ql.list.itemAtIndex(800)
            root.check(label + ": EOF is record 801", row && row.rec ? row.rec.cells[0] : null, "801")
            root.check(label + ": EOF number is 801", row ? numberOf(row) : null, 801)
            screen(root, ql, label + " quicklook EOF", true)
            root.check(label + ": count at EOF", quick.countText(), "801 rows")
        })
    }
    for (var e = 0; e < 2; e++)
        for (var f = 0; f < 2; f++)
            for (var m = 0; m < 3; m++)
                scenario(["csv", "tsv"][e], ["closed", "open"][f], ["engine-file", "engine-text", "plain-file"][m])
    out.push(function () {
        root.check("record readers: no partial first screen was drawn", root.partialFrames, 0)
    })
    return out
}
