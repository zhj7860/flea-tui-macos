.import "../../ui/js/PropertyFacts.js" as PropertyFacts

function run(check) {
    // Every string below is the board's own (Properties040, "Folder, counting" and "Folder, done"), value then muted tail.
    function drawn(line) { return line.value + line.tail }
    var counting = {bytes: 2104332800, items: 812, partial: false, done: false}
    check("Size while counting is the floor with the tail", drawn(PropertyFacts.size(0, counting)), "> 2.1 GB (2104332800 bytes) · counting…")
    check("Contains while counting is the floor with the tail", drawn(PropertyFacts.contains(counting)), "> 812 items · counting…")
    check("the tail is its own run, so it can wear the muted colour", PropertyFacts.size(0, counting).tail, " · counting…")
    var done = {bytes: 7404118016, items: 1204, partial: false, done: true}
    check("Size done is exact with no prefix and no tail", drawn(PropertyFacts.size(0, done)), "7.4 GB (7404118016 bytes)")
    check("Contains done is grouped", drawn(PropertyFacts.contains(done)), "1,204 items")

    // The first frame: the folder's own entry, nothing counted below it yet.
    var first = PropertyFacts.begin({bytes: 4096})
    check("the first frame counts the entry's own size", drawn(PropertyFacts.size(4096, first)), "> 4.1 kB (4096 bytes) · counting…")
    check("and nothing below it", drawn(PropertyFacts.contains(first)), "> 0 items · counting…")
    check("one entry reads item, not items", drawn(PropertyFacts.contains({bytes: 4096, items: 1, partial: false, done: true})), "1 item")
    check("one entry while counting is still a floor", drawn(PropertyFacts.contains({bytes: 4096, items: 1, partial: false, done: false})), "> 1 item · counting…")
    check("an empty folder done reads 0 items", drawn(PropertyFacts.contains({bytes: 4096, items: 0, partial: false, done: true})), "0 items")

    // A walk that met a directory it could not read ends partial: still a floor, with no counting tail.
    var cut = {bytes: 5000, items: 3, partial: true, done: true}
    check("a partial done Size stays a floor", drawn(PropertyFacts.size(0, cut)), "> 5.0 kB (5000 bytes)")
    check("a partial done Contains stays a floor", drawn(PropertyFacts.contains(cut)), "> 3 items")
    check("a partial done floor has no tail", PropertyFacts.size(0, cut).tail + PropertyFacts.contains(cut).tail, "")

    // A file has no walk: Size is its own, Contains does not exist.
    check("a file's Size is unchanged", drawn(PropertyFacts.size(13, null)), "13 B (13 bytes)")
    check("a file's Size has no tail", PropertyFacts.size(13, null).tail, "")
    check("a file has no Contains", PropertyFacts.contains(null), null)

    // Replies fold into the walk the card holds.
    var progress = PropertyFacts.next(first, {ok: true, bytes: 9000, items: 5, partial: false, done: false})
    check("a progress reply moves both numbers and keeps counting", JSON.stringify(progress), JSON.stringify({bytes: 9000, items: 5, partial: false, done: false}))
    var last = PropertyFacts.next(progress, {ok: true, bytes: 9500, items: 6, partial: false, done: true})
    check("the final reply ends the count", last.done, true)
    check("a cancelled walk settles as the floor already counted", JSON.stringify(PropertyFacts.next(progress, {ok: true, cancelled: true, bytes: 1, items: 1, partial: false, done: false})), JSON.stringify({bytes: 9000, items: 5, partial: true, done: true}))
    check("a cancelled reply after done changes nothing", PropertyFacts.next(last, {ok: true, cancelled: true, bytes: 1, items: 1, partial: false, done: false}), last)
    var refused = PropertyFacts.next(progress, {ok: false, error: "Selected items changed; reopen the menu."})
    check("a refused request ends as the floor already counted", JSON.stringify(refused), JSON.stringify({bytes: 9000, items: 5, partial: true, done: true}))

    // The value is plain text with a coloured tail, so the markup carries only the tail's colour.
    check("the counting form wears the tail in the given colour",
          PropertyFacts.styled(PropertyFacts.size(0, counting), "#565f89"),
          "&gt; 2.1 GB (2104332800 bytes)<font color=\"#565f89\"> · counting…</font>")
    check("the done form carries no markup beyond escaping", PropertyFacts.styled(PropertyFacts.contains(done), "#565f89"), "1,204 items")
    check("a markup character in a value is escaped", PropertyFacts.styled({value: "a<b&c", tail: ""}, "#565f89"), "a&lt;b&amp;c")

    function same(name, actual, expected) { check(name, JSON.stringify(actual), JSON.stringify(expected)) }
    // The video and photo pairs the board draws (Properties040, "Video" and "RAW photo"), each string the board's own.
    check("H.264 and AAC read as the board has them, joined by a spaced middle dot", PropertyFacts.codecs("h264", "aac"), "H.264 · AAC")
    check("a video with no audio stream names its one codec", PropertyFacts.codecs("hevc", ""), "H.265")
    check("an audio-only container names its one codec", PropertyFacts.codecs("", "opus"), "Opus")
    check("no stream names no Codecs value", PropertyFacts.codecs("", ""), "")
    check("a codec the table does not know is upper-cased as ffprobe names it", PropertyFacts.codecs("prores", "pcm_s24le"), "PRORES · PCM")
    check("VP9 and AV1 keep their own names", PropertyFacts.codecs("vp9", "vorbis") + "|" + PropertyFacts.codecs("av1", "mp3"), "VP9 · Vorbis|AV1 · MP3")
    check("a bit rate over a megabit is one decimal of Mb/s", PropertyFacts.bitRate(8100000), "8.1 Mb/s")
    check("the megabit edge rounds up into Mb/s and never reads 1000 kb/s", [PropertyFacts.bitRate(999499), PropertyFacts.bitRate(999500), PropertyFacts.bitRate(1000000)].join("|"), "999 kb/s|1.0 Mb/s|1.0 Mb/s")
    same("a bit rate under a megabit is whole kb/s", [PropertyFacts.bitRate(640000), PropertyFacts.bitRate(1000), PropertyFacts.bitRate(128400)], ["640 kb/s", "1 kb/s", "128 kb/s"])
    same("under a kilobit it is b/s", [PropertyFacts.bitRate(999), PropertyFacts.bitRate(8)], ["999 b/s", "8 b/s"])
    same("an unknown or zero bit rate names no value", [PropertyFacts.bitRate(0), PropertyFacts.bitRate(undefined), PropertyFacts.bitRate(-5)], ["", "", ""])
    check("a Canon model already carries its make, so it is not said twice", PropertyFacts.camera("Canon", "Canon EOS R6"), "Canon EOS R6")
    check("a model without its make gets it in front", PropertyFacts.camera("SONY", "ILCE-7M4"), "SONY ILCE-7M4")
    same("a make alone and a model alone each stand", [PropertyFacts.camera("Canon", ""), PropertyFacts.camera("", "X100V")], ["Canon", "X100V"])
    check("the exposure is shutter, aperture and ISO as the board writes it", PropertyFacts.exposure([1, 250], [28, 10], 400), "1/250 s · f/2.8 · ISO 400")
    check("a shutter that is not one over a whole number reads as the nearest 1/n", PropertyFacts.exposure([10, 600], [0, 0], 0), "1/60 s")
    check("a fast shutter no whole n divides reads as the nearest 1/n", PropertyFacts.exposure([3, 1000], [0, 0], 0), "1/333 s")
    same("a shutter that rounds to a second reads as one", [PropertyFacts.exposure([96, 100], [0, 0], 0), PropertyFacts.exposure([99, 100], [0, 0], 0)], ["1 s", "1 s"])
    same("a shutter of a second or more is seconds", [PropertyFacts.exposure([2, 1], [0, 0], 0), PropertyFacts.exposure([13, 10], [0, 0], 0)], ["2 s", "1.3 s"])
    same("a shutter under a second keeps its stored rational", [0.4, 0.5, 0.6, 0.8].map(function (s) { return PropertyFacts.exposure([Math.round(s * 10), 10], [0, 0], 0) }), ["0.4 s", "1/2 s", "0.6 s", "0.8 s"])
    same("a numerator of one reads 1/den and a numerator that divides den reads 1/n", [PropertyFacts.exposure([1, 3], [0, 0], 0), PropertyFacts.exposure([1, 250], [0, 0], 0), PropertyFacts.exposure([2, 500], [0, 0], 0)], ["1/3 s", "1/250 s", "1/250 s"])
    check("2.5 s reads one decimal of seconds", PropertyFacts.exposure([5, 2], [0, 0], 0), "2.5 s")
    same("a make with a company suffix is not said twice when the model repeats its first word", [PropertyFacts.camera("NIKON CORPORATION", "NIKON Z 6"), PropertyFacts.camera("OM Digital Solutions", "OM-1"), PropertyFacts.camera("OLYMPUS IMAGING CORP.", "OLYMPUS E-M1")],
         ["NIKON Z 6", "OM-1", "OLYMPUS E-M1"])
    same("a make whose model never repeats its first word still leads", [PropertyFacts.camera("SONY", "ILCE-7M4"), PropertyFacts.camera("OM Digital Solutions", "TG-7")], ["SONY ILCE-7M4", "OM Digital Solutions TG-7"])
    check("a whole f-number drops the decimal", PropertyFacts.exposure([0, 0], [4, 1], 0), "f/4")
    same("an exposure missing parts keeps the rest in order", [PropertyFacts.exposure([0, 0], [18, 10], 100), PropertyFacts.exposure([1, 60], [0, 0], 3200)], ["f/1.8 · ISO 100", "1/60 s · ISO 3200"])
    same("no exposure fact names no value", [PropertyFacts.exposure([0, 0], [0, 0], 0), PropertyFacts.exposure(undefined, undefined, undefined)], ["", ""])
    check("a shutter with a zero denominator is no shutter", PropertyFacts.exposure([1, 0], [0, 0], 0), "")
    check("Taken is the card's own stamp, minutes only", PropertyFacts.taken("2026:09:12 18:31:07"), "2026-09-12 18:31")
    same("a camera's blank or malformed stamp names no value", [PropertyFacts.taken("0000:00:00 00:00:00"), PropertyFacts.taken("yesterday"), PropertyFacts.taken(""), PropertyFacts.taken(undefined)], ["", "", "", ""])

    // The pairs in the board's slot: after Size and before Modified, only those the file has.
    function labels(reply) { return PropertyFacts.extraPairs(reply).map(function (pair) { return pair[0] }).join(",") }
    var video = {ok: true, vcodec: "h264", acodec: "aac", bps: 8100000}
    check("a video gets Codecs then Bit rate", JSON.stringify(PropertyFacts.extraPairs(video)), JSON.stringify([["Codecs", "H.264 · AAC"], ["Bit rate", "8.1 Mb/s"]]))
    check("a video with no bit rate gets Codecs alone", labels({ok: true, vcodec: "h264", acodec: "", bps: 0}), "Codecs")
    var photo = {ok: true, make: "Canon", model: "Canon EOS R6", lens: "RF35mm F1.8 MACRO IS STM", shutter: [1, 250], fnumber: [28, 10], iso: 400, taken: "2026:09:12 18:31:07"}
    check("a photo gets Camera, Lens, Exposure, Taken in the board's order", JSON.stringify(PropertyFacts.extraPairs(photo)),
          JSON.stringify([["Camera", "Canon EOS R6"], ["Lens", "RF35mm F1.8 MACRO IS STM"], ["Exposure", "1/250 s · f/2.8 · ISO 400"], ["Taken", "2026-09-12 18:31"]]))
    check("a photo with no lens leaves no empty pair", labels({ok: true, make: "FUJIFILM", model: "X100V", shutter: [1, 500], fnumber: [56, 10], iso: 160, taken: "2026:01:02 03:04:05"}), "Camera,Exposure,Taken")
    same("a file with no facts adds nothing", [labels({ok: true}), labels(undefined), labels({})], ["", "", ""])
    check("a refused facts reply adds nothing", labels({ok: false, error: "Menu selection expired; reopen the menu."}), "")
    var immediate = {make: "Canon", model: "Canon EOS R6", lens: "RF35mm F1.8 MACRO IS STM", exp: [1, 2], fnum: [4, 1], iso: 400, taken: "2026:09:12 18:31:07"}
    var absent = {ok: true, make: "", model: "", lens: "", shutter: [0, 0], fnumber: [1, 0], iso: 0, taken: ""}
    same("absent deferred fields preserve immediate photo values and exposure language", PropertyFacts.extraPairs(absent, immediate),
         [["Camera", "Canon EOS R6"], ["Lens", "RF35mm F1.8 MACRO IS STM"], ["Exposure", "0.5 s · f/4 · ISO 400"], ["Taken", "2026-09-12 18:31"]])
    same("deferred-only photos retain their existing exposure language", PropertyFacts.extraPairs({ok: true, shutter: [1, 2]}), [["Exposure", "1/2 s"]])
}
