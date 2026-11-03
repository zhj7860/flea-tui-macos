.pragma library

.import "Format.js" as Format

// Every user-facing string is one whole template with %1 slots, filled in one place, with no qsTr.
var WORDS = {
    footerPair: "%1 renamed · %2 unchanged",
    footerInvalid: "%1 renamed · %2 unchanged · %3 invalid",
    renameButton: "Rename %1",
    cardTitle: "Rename %1 items",
    sameLine: "same as line %1"
}
function applyFindReplace(oldNames, find, replace) {
    var out = []
    for (var i = 0; i < oldNames.length; i++) {
        if (!find) out.push(oldNames[i])
        else out.push(String(oldNames[i]).split(find).join(replace))
    }
    return out
}

// Linux filename components hold at most 255 bytes of UTF-8, the bound the backend refuses past.
var NAME_BYTES = 255

// Sample input: "\u00e9" counts 2, and a surrogate pair counts 4, as UTF-8 does.
function utf8Bytes(text) {
    var bytes = 0
    for (var i = 0; i < text.length; i++) {
        var code = text.charCodeAt(i)
        if (code < 0x80) bytes += 1
        else if (code < 0x800) bytes += 2
        else if (code >= 0xd800 && code <= 0xdbff && (text.charCodeAt(i + 1) & 0xfc00) === 0xdc00) { bytes += 4; i += 1 }
        else bytes += 3
    }
    return bytes
}

// Sample input: "trip/4123.HEIC" at line 4 names "contains /".
function reasons(newNames) {
    var out = new Array(newNames.length)
    var seen = new Map()
    for (var i = newNames.length - 1; i >= 0; i--) {
        var text = String(newNames[i])
        var r = ""
        if (text.length === 0) r = "empty"
        else if (text.indexOf("/") >= 0) r = "contains /"
        else if (text === "." || text === ".." || text.indexOf("\u0000") >= 0 || text.indexOf("\r") >= 0 || text.indexOf("\n") >= 0) r = "invalid"
        else if (utf8Bytes(text) > NAME_BYTES) r = "too long"
        else if (seen.has(text)) r = WORDS.sameLine.replace("%1", seen.get(text) + 1)
        out[i] = r
        seen.set(text, i)
    }
    return out
}

// Counts split renamed, unchanged and invalid over the live rules alone; the backend refuses a name taken outside the batch.
function counts(oldNames, newNames, reasons) {
    var renamed = 0, unchanged = 0, invalid = 0
    for (var i = 0; i < newNames.length; i++) {
        if (reasons[i] !== "") invalid += 1
        else if (String(newNames[i]) === String(oldNames[i])) unchanged += 1
        else renamed += 1
    }
    return { renamed: renamed, unchanged: unchanged, invalid: invalid }
}

// Sample input: 5, 1, 0 names "5 renamed \u00b7 1 unchanged".
function footer(renamed, unchanged, invalid) {
    if (invalid > 0)
        return WORDS.footerInvalid.replace("%1", Format.count(renamed)).replace("%2", Format.count(unchanged)).replace("%3", Format.count(invalid))
    return WORDS.footerPair.replace("%1", Format.count(renamed)).replace("%2", Format.count(unchanged))
}

// The Rename button label carries the live renamed count.
function renameLabel(renamed) {
    return WORDS.renameButton.replace("%1", Format.count(renamed))
}

// The card names its count once; it only opens over several rows, so one plural form holds.
function title(count) {
    return WORDS.cardTitle.replace("%1", Format.count(count))
}

// A short newNames reads "" past its end; open()'s two assignments cross for one synchronous turn only, so no frame ever paints it.
function nameAt(newNames, index) {
    return index < newNames.length ? String(newNames[index]) : ""
}

// The card's Tab order, pure so tests/js pins the walk both ways.
function focusStops(lines) {
    var stops = ["find", "replace"]
    for (var i = 0; i < lines; i++) stops.push("line " + (i + 1))
    return stops.concat(["edit", "cancel", "rename"])
}
function nextStop(current, back, lines) {
    var stops = focusStops(lines)
    var at = stops.indexOf(current)
    if (at < 0) return back ? stops[stops.length - 1] : stops[0]
    return stops[(at + (back ? -1 : 1) + stops.length) % stops.length]
}
