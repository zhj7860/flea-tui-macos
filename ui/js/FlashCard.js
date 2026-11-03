.pragma library

.import "Flash.js" as Flash
.import "Format.js" as Format

// The flash card's rendering, imported only by the lazy flasher so no startup file compiles it.

// One template fill into inked parts: {f:key} spans become figures, the rest words.
function lined(template, values) {
    var parts = [], text = "", at = 0
    while (at < template.length) {
        var open = template.indexOf("{f:", at)
        if (open < 0) {
            text += template.substring(at)
            break
        }
        text += template.substring(at, open)
        var close = template.indexOf("}", open)
        if (text.length > 0) {
            parts.push({ text: text, figure: false })
            text = ""
        }
        parts.push({ text: String(values[template.substring(open + 3, close)]), figure: true })
        at = close + 1
    }
    if (text.length > 0)
        parts.push({ text: text, figure: false })
    return parts
}

function head(t) {
    return Flash.fill(t.phase === "verify" ? Flash.FLASH_HEAD_VERIFYING : Flash.FLASH_HEAD_WRITING,
        { drive: t.drive })
}

function file(t) {
    return t.total > 0 ? Flash.fill(Flash.FLASH_FILE_KNOWN, { name: t.name, size: Format.size(t.total) }) : t.name
}

// The total a flash measures against: the known size, else the share the unpacker reports scaled up, else 0.
function total(t) {
    if (t.known === true && t.total > 0)
        return t.total
    var moved = t.bytes || 0
    return (t.permille || 0) > 0 && moved > 0 ? Math.round(moved * 1000 / t.permille) : 0
}

function parts(t, rate) {
    if (t.phase === "prepare" || t.phase === "password")
        return [{ text: Flash.FLASH_WAIT_PASSWORD, figure: false }]
    if (t.phase === "flush")
        return t.bytes > 0 ? lined(Flash.FLASH_FLUSH_LINE, { bytes: Format.size(t.bytes) }) : []
    var moved = t.bytes || 0
    if (moved <= 0)
        return []
    var whole = total(t)
    var values = { moved: Format.size(moved), rate: Format.size(rate), unit: "/s" }
    if (whole > 0)
        values.total = Format.size(whole)
    if (whole > 0 && rate > 0)
        values.left = Format.duration(Math.max(0, whole - moved) / rate * 1000)
    if (t.known === true && t.total > 0)
        return lined(values.left !== undefined ? Flash.FLASH_KNOWN_LINE : Flash.FLASH_KNOWN_STALLED, values)
    return lined(values.left !== undefined ? Flash.FLASH_UNKNOWN_LINE : Flash.FLASH_UNKNOWN_STALLED, values)
}

function share(t) {
    if (t.known === true && t.total > 0)
        return (t.bytes || 0) / t.total
    return (t.permille || 0) / 1000
}

// One render of every line a flash draws, stored on the transfer by the runner.
function render(t, rate) {
    var lines = parts(t, rate)
    var at = share(t)
    return { headText: head(t), fileText: file(t), byteText: lines,
             share: at < 0 ? 0 : (at > 1 ? 1 : at), noCancel: t.phase === "flush" }
}
