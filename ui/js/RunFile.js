.pragma library

.import "Format.js" as Format
.import "Anchor.js" as Anchor
.import "Icons.js" as Icons

// The run card's own decisions, the way ui/js/Collide.js holds its card's: which buttons a kind draws, where the ring opens, and how the keys walk them.

var LABELS = { cancel: "Cancel", text: "Open as text", run: "Run", terminal: "Run in terminal" }
// Run in terminal is the default because it shows the output; a desktop handler, where one is named, is offered first and takes it instead.
var START = "terminal"
var KINDS = ["script", "elf", "appimage"]
var KIND_LABELS = { script: "Shell script", elf: "Program", appimage: "AppImage application bundle" }

// The board's own default: the handler where the desktop names one for an AppImage, Run in terminal everywhere else, and the primary frame sits there.
function defaultButton(kind, hasHandler) {
    if (kind === "appimage" && hasHandler === true)
        return "handler"
    return START
}

// Left to right, the board's own order, text a script's alone since a binary is not text; the board's tweak focus = terminal | run | text | cancel names the opening ring.
function buttonsFor(kind, hasHandler) {
    var out = ["cancel"]
    if (kind === "script")
        out.push("text")
    if (kind === "appimage" && hasHandler === true)
        out.push("handler")
    return out.concat(["run", "terminal"])
}

// A tweak naming a button the card did not draw falls back to the default, never to nothing.
function startFocus(buttons, tweak) {
    if (buttons.indexOf(tweak) >= 0)
        return tweak
    var fallback = defaultButton(buttons.indexOf("handler") >= 0 ? "appimage" : "script", buttons.indexOf("handler") >= 0)
    return buttons.indexOf(fallback) >= 0 ? fallback : buttons[0]
}

// h and l stop at the ends like TrashConfirm's pair; Tab and Backtab come round.
function moved(buttons, focus, key, modifiers) {
    var at = buttons.indexOf(focus)
    if (at < 0)
        at = buttons.indexOf(defaultButton(buttons.indexOf("handler") >= 0 ? "appimage" : "script", buttons.indexOf("handler") >= 0))
    if (at < 0)
        at = 0
    var last = buttons.length - 1
    if (key === Qt.Key_H || key === Qt.Key_Left)
        return buttons[Math.max(0, at - 1)]
    if (key === Qt.Key_L || key === Qt.Key_Right)
        return buttons[Math.min(last, at + 1)]
    // Shift+Tab reaches a Keys handler as Backtab or as Tab with Shift held, depending on the input path.
    if (key === Qt.Key_Backtab || key === Qt.Key_Tab && (modifiers & Qt.ShiftModifier))
        return buttons[(at + last) % buttons.length]
    if (key === Qt.Key_Tab)
        return buttons[(at + 1) % buttons.length]
    return buttons[at]
}

// The handler button is the application's own Name= from its desktop entry, one whole string.
function labelFor(button, handlerName) {
    return button === "handler" ? String(handlerName) : LABELS[button]
}

function activates(key) {
    return key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space
}

// The name row's own mark: the board draws the code glyph beside a script, and a binary takes the mark its listed row draws.
var KIND_GLYPHS = { script: "code", elf: "terminal", appimage: "app-window" }

function glyphFor(kind, listed) {
    if (kind !== "script" && listed)
        return listed
    return KIND_GLYPHS[kind] || KIND_GLYPHS.elf
}

// The mark the listing draws for the row the ask was opened from, or "" when no listed row names that path.
function listedGlyph(pane, path) {
    if (!pane || !pane.rows || typeof pane.rowFor !== "function")
        return ""
    var at = Anchor.matchListed(pane, path)
    var row = at >= 0 ? pane.rowFor(at) : null
    return row ? Icons.glyphForRow(row.i, row.p) : ""
}

// Every user-facing string is one whole template filled by Format.fill, never fragments joined with +.

// The card's title names the program; the name row carries its kind and its size.
var TITLE_PROGRAM = "%1 is a program"
function titleFor(name) {
    return Format.fill(TITLE_PROGRAM, escapeName(name))
}

// R4: control and bidi characters are shown escaped, never raw, and a clean name passes through byte for byte.
var SPOOFED = /[\0-\x1F\x7F-\x9F\u061C\u200E\u200F\u2028\u2029\u202A-\u202E\u2066-\u2069\uFEFF]/g
function escapeName(name) {
    return String(name).replace(SPOOFED, function (ch) {
        var point = ch.codePointAt(0).toString(16).toUpperCase()
        return "<U+" + ("0000" + point).slice(-4) + ">"
    })
}

var SUBTITLE_PROGRAM = "%1 · %2"
function subtitleFor(kind, bytes) {
    return Format.fill(SUBTITLE_PROGRAM, KIND_LABELS[kind] || KIND_LABELS.elf, Format.size(bytes))
}

function leafOf(path) {
    var text = String(path)
    var cut = text.lastIndexOf("/")
    return cut < 0 ? text : text.substring(cut + 1)
}

// Sample input: {"ask":"run","kind":"script","size":9420,"handlerId":"","handlerName":"","dev":"8","ino":"9","mtimeS":11,"mtimeNs":12,"target":"/real/tool.sh"}.
function parseAsk(text) {
    var message = null
    try {
        message = JSON.parse(String(text))
    } catch (e) {
        return null
    }
    if (!message || message.ask !== "run" || KINDS.indexOf(message.kind) < 0)
        return null
    if (typeof message.dev !== "string" || typeof message.ino !== "string" || typeof message.target !== "string")
        return null
    var handlerId = typeof message.handlerId === "string" ? message.handlerId : ""
    var handlerName = typeof message.handlerName === "string" ? message.handlerName : ""
    return { kind: message.kind, size: Number(message.size) || 0,
             handlerId: handlerId, handlerName: handlerName,
             hasHandler: handlerId.length > 0 && handlerName.trim().length > 0,
             dev: message.dev, ino: message.ino,
             mtimeS: Number(message.mtimeS) || 0, mtimeNs: Number(message.mtimeNs) || 0,
             target: message.target }
}

// The card's choice on the path it asked about, carrying the R3 identity the ask named, and the handler the id the card drew.
function choose(pane, card, choice) {
    if (choice === "run") card.run(card.path, card.dev, card.ino, card.size, card.mtimeS, card.mtimeNs)
    else if (choice === "terminal") card.runTerminal(card.path, card.dev, card.ino, card.size, card.mtimeS, card.mtimeNs)
    else if (choice === "text") card.openText(card.path, pane)
    else if (choice === "handler") card.openHandler(card.path, card.handlerId, card.dev, card.ino, card.size, card.mtimeS, card.mtimeNs)
}
