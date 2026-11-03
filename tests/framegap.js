.pragma library

// The frame-to-line reader tests/framegap.qml holds every framed control to: pure, over the items themselves.

// A line is at most this many hairlines thick and at least this many pixels long; anything shorter is a mark, not a rule.
var LINE_THICK = 2
var LINE_LONG = 16

// Sample input: typeOf(MenuRow_QMLTYPE_98_QML_107(0x55)) answers "MenuRow"; typeOf(QQuickRectangle(0x55)) answers "Rectangle".
function typeOf(o) {
    var s = String(o)
    var m = s.match(/^(?:QQuick)?([A-Za-z0-9]+?)(?:_QMLTYPE_[0-9]+)?(?:_QML_[0-9]+)?\(/)
    return m ? m[1] : s
}

function isQmlType(o) { return /_QML(TYPE)?_[0-9]+\(/.test(String(o)) }
// Qt Quick's own types: an inline delegate of one of these is named by the component that holds it.
var BASE_TYPES = ["Item", "Rectangle", "Row", "Column", "Grid", "Flickable", "ListView", "Repeater", "Loader", "Text"]

// Shown means visible, not faded out, and not scrolled past an ancestor's clip.
function shown(o, host) {
    var fade = 1
    for (var p = o; p; p = p.parent) {
        if (!p.visible) return false
        fade *= p.opacity
        if (p !== o && p.clip) {
            var r = o.mapToItem(p, 0, 0, o.width, o.height)
            if (r.x >= p.width || r.y >= p.height || r.x + r.width <= 0 || r.y + r.height <= 0) return false
        }
        if (p === host) break
    }
    return fade > 0
}

// The component a frame belongs to and the words that name it, for the audit row.
function owner(o, host) {
    for (var p = o; p && p !== host; p = p.parent)
        if (isQmlType(p) && BASE_TYPES.indexOf(typeOf(p)) < 0) return p
    return host
}
function nameOf(item) {
    var words = item.label || item.text || item.glyph || item.name || item.objectName || ""
    return String(words).replace(/[\t\n]/g, " ")
}

// Qt reports a border nobody set as one black pixel, and the harness pins a theme with no black role, so that pair is no frame.
function framed(o) {
    var c = o.border.color
    return o.border.width > 0 && c.a > 0 && !(o.border.width === 1 && c.r === 0 && c.g === 0 && c.b === 0 && c.a === 1)
}

// Every shown bordered rectangle and every shown thin filled one under the host, in the host's coordinates.
function collect(host, hairline) {
    var frames = []
    var lines = []
    var stack = [host]
    while (stack.length > 0) {
        var o = stack.pop()
        var kids = o.children !== undefined ? o.children : []
        for (var i = 0; i < kids.length; i++) stack.push(kids[i])
        if (o.border === undefined || o.radius === undefined || !(o.width > 0 && o.height > 0) || !shown(o, host)) continue
        var box = o.mapToItem(host, 0, 0, o.width, o.height)
        if (framed(o)) {
            frames.push({ item: o, box: box, weight: o.border.width })
            continue
        }
        var thin = Math.min(box.width, box.height)
        if (o.color.a > 0 && thin <= LINE_THICK * hairline && Math.max(box.width, box.height) >= LINE_LONG)
            lines.push({ item: o, box: box })
    }
    return { frames: frames, lines: lines }
}

function inside(a, b) {
    return a.x >= b.x && a.y >= b.y && a.x + a.width <= b.x + b.width && a.y + a.height <= b.y + b.height
}

// A frame holding a line or another component's frame is a card or a strip: its four sides are lines for the controls inside it.
function split(found, host) {
    var controls = []
    var lines = []
    var all = found.frames.concat(found.lines)
    all.forEach(function (g) { g.owner = owner(g.item, host) })
    for (var i = 0; i < found.frames.length; i++) {
        var f = found.frames[i]
        var holds = all.some(function (g) { return g.item !== f.item && (g.owner !== f.owner || f.owner === host) && inside(g.box, f.box) })
        if (!holds) { controls.push(f); continue }
        var b = f.box
        var w = f.weight
        lines.push({ item: f.item, owner: f.owner, box: { x: b.x, y: b.y, width: b.width, height: w } })
        lines.push({ item: f.item, owner: f.owner, box: { x: b.x, y: b.y + b.height - w, width: b.width, height: w } })
        lines.push({ item: f.item, owner: f.owner, box: { x: b.x, y: b.y, width: w, height: b.height } })
        lines.push({ item: f.item, owner: f.owner, box: { x: b.x + b.width - w, y: b.y, width: w, height: b.height } })
    }
    for (var j = 0; j < found.lines.length; j++) {
        var l = found.lines[j]
        // A line inside a control frame is part of that control (a check box's bar), not a rule beside it.
        if (!controls.some(function (c) { return inside(l.box, c.box) })) lines.push(l)
    }
    return { controls: controls, lines: lines }
}

// Sample input: a frame at y 10 to 40 over a rule at y 42 answers bottom 2. A line crossing the frame answers a negative distance.
function gaps(f, lines, host) {
    var b = f.box
    var out = { top: { rule: Infinity, edge: b.y }, bottom: { rule: Infinity, edge: host.height - b.y - b.height },
                left: { rule: Infinity, edge: b.x }, right: { rule: Infinity, edge: host.width - b.x - b.width } }
    for (var i = 0; i < lines.length; i++) {
        var l = lines[i].box
        if (lines[i].item === f.item || lines[i].owner === f.owner && f.owner !== host) continue
        var across = l.width >= l.height
        if (across && l.x < b.x + b.width && l.x + l.width > b.x) {
            if (l.y + l.height / 2 <= b.y + b.height / 2) out.top.rule = Math.min(out.top.rule, b.y - l.y - l.height)
            else out.bottom.rule = Math.min(out.bottom.rule, l.y - b.y - b.height)
        } else if (!across && l.y < b.y + b.height && l.y + l.height > b.y) {
            if (l.x + l.width / 2 <= b.x + b.width / 2) out.left.rule = Math.min(out.left.rule, b.x - l.x - l.width)
            else out.right.rule = Math.min(out.right.rule, l.x - b.x - b.width)
        }
    }
    return out
}

function round(v) { return Math.round(v * 100) / 100 }

// A frame inside a Flickable whose content outruns its viewport, below the host: the fold may cut it by design.
function scrolls(item, host) {
    for (var p = item.parent; p && p !== host; p = p.parent)
        if (p.contentY !== undefined && p.contentHeight > p.height) return true
    return false
}

// The bordered frame and the caption under a picker chip, whatever box the frame draws in.
function chipFind(chip, key) {
    var stack = [chip]
    while (stack.length > 0) {
        var o = stack.pop()
        if (key === "frame" && o.border !== undefined && o.border.width > 0) return o
        if (key === "caption" && o.text !== undefined && o.font !== undefined) return o
        var kids = o.children !== undefined ? o.children : []
        for (var i = 0; i < kids.length; i++) stack.push(kids[i])
    }
    return null
}

// One row per side for a picker chip frame against its strip top and rule, same judgement as rows().
function chipRows(host, name, box, stripTop, ruleTop, hairline, inset, state, stop, focused) {
    var top = round(box.y - stripTop)
    var bottom = round(ruleTop - box.y - box.height)
    var bottomEdge = round(bottom + hairline)
    return [{ host: host, name: name, state: state, stop: stop, side: "top", rule: top, edge: top, inset: inset, under: top < inset, focused: focused },
            { host: host, name: name, state: state, stop: stop, side: "bottom", rule: bottom, edge: bottomEdge, inset: inset, under: bottom < inset || bottomEdge < inset, focused: focused }]
}

// One row per frame and side: the nearest line and the host's edge, each against the inset.
function rows(hostName, host, hairline, inset, state, stop) {
    var parts = split(collect(host, hairline), host)
    var out = []
    for (var i = 0; i < parts.controls.length; i++) {
        var f = parts.controls[i]
        var who = f.owner
        var g = gaps(f, parts.lines, host)
        // Scrolled content cut by the host's top or bottom edge is judged by what the fold shows: one CLIPPED row, no side checks.
        if ((g.top.edge < 0 || g.bottom.edge < 0) && scrolls(f.item, host)) {
            out.push({ host: hostName, owner: typeOf(who), name: nameOf(who), frame: typeOf(f.item) + ":" + nameOf(f.item), box: [f.box.x, f.box.y, f.box.width, f.box.height].map(round).join(","),
                       state: state, stop: stop, side: "fold", rule: "none", edge: round(Math.min(g.top.edge, g.bottom.edge)), inset: inset, under: false, clipped: true })
            continue
        }
        for (var side in g) {
            var rule = g[side].rule
            var edge = g[side].edge
            out.push({ host: hostName, owner: typeOf(who), name: nameOf(who), frame: typeOf(f.item) + ":" + nameOf(f.item), box: [f.box.x, f.box.y, f.box.width, f.box.height].map(round).join(","),
                       state: state, stop: stop, side: side, rule: rule === Infinity ? "none" : round(rule), edge: round(edge),
                       inset: inset, under: rule < inset || edge < inset })
        }
    }
    return out
}
