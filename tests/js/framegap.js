.import "../framegap.js" as Gap

// Hand-built stand-ins for the QML items Gap.rows reads, so the pure reader is proved both ways without a window.
var INSET = 3

function hostBox(width, height) {
    return { children: [], width: width, height: height, visible: true, opacity: 1, clip: false, parent: null }
}

function itemBox(host, x, y, width, height, border, fill) {
    var o = { children: [], parent: host, width: width, height: height, visible: true, opacity: 1, clip: false,
              border: border, radius: 0, color: fill, x0: x, y0: y }
    o.mapToItem = function (target, x, y, w, h) { return { x: o.x0 + x, y: o.y0 + y, width: w, height: h } }
    host.children.push(o)
    return o
}

// Sample input: frameBox(50, 50, 100, 30) reads back box "50,50,100,30".
function frameBox(host, x, y, width, height) {
    return itemBox(host, x, y, width, height,
                   { width: 2, color: { a: 1, r: 1, g: 1, b: 1 } }, { a: 0, r: 0, g: 0, b: 0 })
}

function ruleBox(host, x, y, width, height) {
    return itemBox(host, x, y, width, height,
                   { width: 0, color: { a: 0, r: 0, g: 0, b: 0 } }, { a: 1, r: 1, g: 1, b: 1 })
}

function sideOf(rows, side) {
    for (var i = 0; i < rows.length; i++) if (rows[i].side === side) return rows[i]
    return null
}

function run(check) {
    // A frame 1 px above a rule: only its bottom side is under.
    var near = hostBox(400, 300)
    frameBox(near, 50, 50, 100, 30)
    ruleBox(near, 50, 81, 100, 1)
    var nearRows = Gap.rows("near", near, 1, INSET, "rest", 14)
    check("a frame a hairline from a rule has four sides", nearRows.length, 4)
    check("its bottom gap is the 1 px to the rule", sideOf(nearRows, "bottom").rule, 1)
    check("its bottom side is under the inset", sideOf(nearRows, "bottom").under, true)
    check("its top side is clear of the inset", sideOf(nearRows, "top").under, false)
    check("its left side is clear of the inset", sideOf(nearRows, "left").under, false)
    check("its right side is clear of the inset", sideOf(nearRows, "right").under, false)

    // A frame far from every rule and edge: no side is under.
    var far = hostBox(400, 300)
    frameBox(far, 50, 50, 100, 30)
    var farRows = Gap.rows("far", far, 1, INSET, "rest", 14)
    var farUnder = farRows.some(function (r) { return r.under })
    check("a clear frame still has four sides", farRows.length, 4)
    check("no side of a clear frame is under the inset", farUnder, false)

    // A frame touching its host's top edge: only its top side is under.
    var edged = hostBox(400, 300)
    frameBox(edged, 50, 0, 100, 30)
    var edgedRows = Gap.rows("edged", edged, 1, INSET, "rest", 14)
    check("its top edge gap is 0", sideOf(edgedRows, "top").edge, 0)
    check("its top side is under the inset", sideOf(edgedRows, "top").under, true)
    check("its bottom side stays clear", sideOf(edgedRows, "bottom").under, false)

    // A rule touching the frame: the touched side reports gap 0 and is under.
    var touched = hostBox(400, 300)
    frameBox(touched, 50, 50, 100, 30)
    ruleBox(touched, 50, 80, 100, 1)
    var touchedRows = Gap.rows("touched", touched, 1, INSET, "rest", 14)
    check("a touched side reports gap 0", sideOf(touchedRows, "bottom").rule, 0)
    check("a touched side is under the inset", sideOf(touchedRows, "bottom").under, true)
}
