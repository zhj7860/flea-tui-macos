.pragma library

// The readers tests/button-members.qml holds the controls to A's numbers with: pure, over the items themselves.

// Sample input: the colors.toml body Theme.applyColors reads, as stock tokyo-night sets its accent, muted, background and foreground; the sandbox has no theme and its own accent is grey, so a harness pins this one.
var COLOURED_THEME = 'accent = "#7aa2f7"\nmuted = "#414868"\nbackground = "#1a1b26"\nforeground = "#a9b1d6"\n'
// Sample input: the same four roles of stock kanagawa (accent equal to foreground) and stock white (a grey accent), the themes whose accent carries no colour.
var KANAGAWA_THEME = 'accent = "#dcd7ba"\nmuted = "#54546D"\nbackground = "#1f1f28"\nforeground = "#dcd7ba"\n'
var WHITE_THEME = 'accent = "#6e6e6e"\nmuted = "#808080"\nbackground = "#ffffff"\nforeground = "#000000"\n'

// Sample input: rgba(Qt.rgba(1, 0.5, 0, 0.14)) answers "1,0.5,0,0.14".
function rgba(c) { return [c.r, c.g, c.b, c.a].map(function (v) { return Math.round(v * 1000) / 1000 }).join(",") }
function alphaOf(c) { return Math.round(c.a * 1000) / 1000 }
// A pressed control is scaled, so a position read through it carries float noise.
function thousandth(v) { return Math.round(v * 1000) / 1000 }

function find(item, name) {
    var stack = [item]
    while (stack.length > 0) {
        var o = stack.pop()
        if (o.objectName === name) return o
        var kids = o.children !== undefined ? o.children : []
        for (var i = 0; i < kids.length; i++) stack.push(kids[i])
    }
    return null
}

// The bordered items a viewer can see now: a frame that is not showing does not count.
function shownBordered(item) {
    var stack = [item]
    var out = 0
    while (stack.length > 0) {
        var o = stack.pop()
        if (o.border !== undefined && o.border.width > 0 && o.visible) out++
        var kids = o.children !== undefined ? o.children : []
        for (var i = 0; i < kids.length; i++) stack.push(kids[i])
    }
    return out
}

// How many items under one draw a border, so a frameless mark is proved by finding none.
function bordered(item) {
    var stack = [item]
    var out = 0
    while (stack.length > 0) {
        var o = stack.pop()
        if (o.border !== undefined && o.border.width > 0) out++
        var kids = o.children !== undefined ? o.children : []
        for (var i = 0; i < kids.length; i++) stack.push(kids[i])
    }
    return out
}

// What a DialogButton draws, read off its own items (ringItem must find no buttonRing; geometry holds focus to rest); any other build fails by name.
function read(button) {
    var frame = find(button, "buttonFrame")
    var wash = find(button, "buttonWash")
    var label = find(button, "buttonLabel")
    if (!frame || !wash || !label) return { missing: button.toString(), outerHeight: button.height }
    var inner = wash.mapToItem(frame, 0, 0)
    var at = frame.mapToItem(button, 0, 0)
    var ink = label.mapToItem(button, 0, 0)
    return {
        outerHeight: button.height, frameColor: rgba(frame.border.color), frameWidth: frame.border.width, frameHeight: frame.height, frameFill: alphaOf(frame.color),
        ink: rgba(label.color), labelSize: label.font.pixelSize, washAlpha: alphaOf(wash.color),
        washInsetX: thousandth(inner.x), washInsetY: thousandth(inner.y), washShrink: thousandth(frame.width - wash.width),
        ringItem: find(button, "buttonRing") !== null, scale: button.scale, opacity: button.opacity,
        box: [button.x, button.y, button.width, button.height].map(thousandth).join(","),
        frameBox: [at.x, at.y, frame.width, frame.height].map(thousandth).join(","),
        labelBox: [ink.x, ink.y, label.width, label.height].map(thousandth).join(",")
    }
}

// Keyboard focus on the item, then what it draws and how many borders show; read() with the focus given first.
function focusRead(item) {
    item.forceActiveFocus()
    var out = read(item)
    out.borders = shownBordered(item)
    return out
}
