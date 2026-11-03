.pragma library
.import "Format.js" as Format
.import "Facts.js" as Facts

// The Properties card's Size and Contains lines for a folder: the walk's floor while it counts, the whole once it is done.
var TAIL = " · counting…"
var SIZE = {exact: "%1 (%2 bytes)", floor: "> %1 (%2 bytes)"}
var CONTAINS = {exact: ["%1 item", "%1 items"], floor: ["> %1 item", "> %1 items"]}

// Sample input: {bytes: 4096} from the properties reply; the walk's first floor is the folder's own entry.
function begin(facts) {
    return {bytes: facts.bytes, items: 0, partial: false, done: false}
}

// A progress or final reply folded into the walk; a cancelled or refused walk ends as the floor already counted, so the card never counts forever.
function next(walk, reply) {
    if (reply.cancelled)
        return walk.done ? walk : {bytes: walk.bytes, items: walk.items, partial: true, done: true}
    if (!reply.ok)
        return {bytes: walk.bytes, items: walk.items, partial: true, done: true}
    return {bytes: reply.bytes, items: reply.items, partial: reply.partial === true, done: reply.done === true}
}

// Sample input: size(13, null) is a file's own; size(0, walk) reads the walk. A partial walk stays a floor when done.
function size(bytes, walk) {
    var shown = walk ? walk.bytes : bytes
    var template = walk && (!walk.done || walk.partial) ? SIZE.floor : SIZE.exact
    return {value: template.arg(Format.size(shown)).arg(String(shown)), tail: walk && !walk.done ? TAIL : ""}
}

function contains(walk) {
    if (!walk)
        return null
    var forms = !walk.done || walk.partial ? CONTAINS.floor : CONTAINS.exact
    return {value: forms[walk.items === 1 ? 0 : 1].arg(Format.count(walk.items)), tail: walk.done ? "" : TAIL}
}

function escape(text) {
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

// StyledText: the value in the Text's own colour and only the tail in `muted`, on the value's line.
function styled(line, muted) {
    if (!line.tail)
        return escape(line.value)
    return "%1<font color=\"%2\">%3</font>".arg(escape(line.value)).arg(muted).arg(escape(line.tail))
}

// The names ffprobe prints for the codecs a card is likely to meet; one it does not know is shown upper-cased, as ffprobe says it.
var CODECS = {h264: "H.264", hevc: "H.265", vp8: "VP8", vp9: "VP9", av1: "AV1", mpeg4: "MPEG-4", mpeg2video: "MPEG-2", mpeg1video: "MPEG-1",
              aac: "AAC", mp3: "MP3", opus: "Opus", vorbis: "Vorbis", flac: "FLAC", ac3: "AC-3", eac3: "E-AC-3", dts: "DTS", alac: "ALAC"}

function codecName(name) {
    if (!name)
        return ""
    if (name.indexOf("pcm_") === 0)
        return "PCM"
    return CODECS[name] || name.toUpperCase()
}

// Sample input: codecs("h264", "aac") reads "H.264 · AAC"; a file with one stream names that one.
function codecs(video, audio) {
    return [codecName(video), codecName(audio)].filter(function (name) { return name !== "" }).join(" · ")
}

// Sample input: 8100000 reads "8.1 Mb/s"; ffprobe's bits per second, decimal prefixes, whole kb/s below a megabit.
function bitRate(bps) {
    if (!(bps > 0))
        return ""
    if (bps < 1000)
        return Math.round(bps) + " b/s"
    var kilo = Math.round(bps / 1000)
    return kilo < 1000 ? kilo + " kb/s" : (bps / 1000000).toFixed(1) + " Mb/s"
}

// A camera writes the make's first word into the model on its own (Canon EOS R6, NIKON CORPORATION and NIKON Z 6) or not (SONY, ILCE-7M4).
function camera(make, model) {
    if (!make || !model)
        return model || make || ""
    var brand = make.toLowerCase().split(/\s+/)[0]
    return model.toLowerCase().indexOf(brand) === 0 ? model : make + " " + model
}

// A rational as [numerator, denominator], zero when the file named none or a zero denominator.
function ratio(pair) {
    return pair && pair[0] > 0 && pair[1] > 0 ? pair[0] / pair[1] : 0
}

// Sample input: [1, 250] reads "1/250 s", [10, 600] "1/60 s", [6, 10] "0.6 s", [13, 10] "1.3 s"; a fraction whose numerator divides its denominator stays a 1/n.
function shutterText(pair, seconds) {
    var num = pair[0], den = pair[1], tenths = Math.round(seconds * 10)
    // A shutter that rounds to a whole second reads like one, so 0.96 s and 1 s both read "1 s".
    if (tenths >= 10)
        return String(tenths / 10) + " s"
    if (den % num === 0 || num === 1)
        return "1/" + (num === 1 ? den : den / num) + " s"
    return tenths > 0 ? (tenths / 10).toFixed(1) + " s" : "1/" + Math.round(1 / seconds) + " s"
}

// Sample input: ([1, 250], [28, 10], 400) reads "1/250 s · f/2.8 · ISO 400"; a part the file lacks is left out.
function exposure(shutter, fnumber, iso) {
    var seconds = ratio(shutter), stop = ratio(fnumber), parts = []
    if (seconds > 0)
        parts.push(shutterText(shutter, seconds))
    if (stop > 0)
        parts.push("f/" + String(Math.round(stop * 10) / 10))
    if (iso > 0)
        parts.push("ISO " + iso)
    return parts.join(" · ")
}

// Sample input: "2026:09:12 18:31:07", EXIF's own stamp, reads "2026-09-12 18:31" like every other date on the card.
function taken(stamp) {
    var m = /^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):\d{2}/.exec(stamp || "")
    return m && m[1] !== "0000" ? m[1] + "-" + m[2] + "-" + m[3] + " " + m[4] + ":" + m[5] : ""
}

// Empty strings, zero ISO and zero rationals are absent; present deferred EXIF fields win a disagreement.
function mergePhoto(photo, reply) {
    var p = photo || {}, r = reply || {}
    return {
        make: r.make || p.make || "",
        model: r.model || p.model || "",
        lens: r.lens || p.lens || "",
        shutter: ratio(r.shutter) > 0 ? r.shutter : p.exp,
        fnumber: ratio(r.fnumber) > 0 ? r.fnumber : p.fnum,
        iso: r.iso > 0 ? r.iso : p.iso,
        taken: r.taken || p.taken || ""
    }
}

// One merged photo, formatted once in the existing card language; codecs and bit rate stay with the facts reply.
function extraPairs(reply, photo) {
    if (!reply || !reply.ok)
        return []
    var merged = mergePhoto(photo, reply)
    var shown = photo ? Facts.photoFacts(Object.assign({}, merged, {exp: merged.shutter, fnum: merged.fnumber})) : {
        camera: camera(merged.make, merged.model), lens: merged.lens,
        exposure: exposure(merged.shutter, merged.fnumber, merged.iso), taken: taken(merged.taken)
    }
    return [["Codecs", codecs(reply.vcodec, reply.acodec)], ["Bit rate", bitRate(reply.bps)],
            ["Camera", shown.camera], ["Lens", shown.lens], ["Exposure", shown.exposure], ["Taken", shown.taken]]
        .filter(function (pair) { return pair[1] !== "" })
}
