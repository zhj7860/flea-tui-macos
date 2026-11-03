//@ pragma ShellId flea-menu-contents-test

import QtQuick
import Quickshell
import "flea" as Flea

// tests/menu-contents.sh's harness: Properties on a folder counts in place under fed replies, whole from its first frame.
ShellRoot {
    id: shell

    readonly property int settleTicks: 3
    readonly property var fullFolder: ["Path", "Type", "Size", "Contains", "Modified", "Permissions", "Owner", "Group"]
    readonly property var labels: ["Path", "Type", "Size", "Contains", "Modified", "Permissions", "Owner", "Group", "Tags", "Link target", "Codecs", "Bit rate", "Camera", "Lens", "Exposure", "Taken"]
    readonly property var plainFile: ["Path", "Type", "Size", "Modified", "Permissions", "Owner", "Group"]
    readonly property var videoFile: ["Path", "Type", "Size", "Codecs", "Bit rate", "Modified", "Permissions", "Owner", "Group"]
    readonly property var photoFile: ["Path", "Type", "Size", "Camera", "Lens", "Exposure", "Taken", "Modified", "Permissions", "Owner", "Group"]
    readonly property string tail: " · counting…"
    property int checks: 0
    property var failures: []
    property var sent: []
    property var plan: []
    property int at: 0
    property int wait: 0
    // Every pair signature seen at a settled tick or straight after a reply, so a half-drawn card shows up as a stray signature.
    property var signatures: ({})
    property real cardHeight: 0
    property var before: []

    function log(line) { console.log("MENUCONTENTS " + line) }
    // Keys in sorted order: Qt 6.12 hands a signal's object argument over as a QVariantMap, which sorts its keys.
    function canon(value) {
        return JSON.stringify(value, function (key, v) {
            return v && typeof v === "object" && !Array.isArray(v)
                ? Object.keys(v).sort().reduce(function (o, k) { o[k] = v[k]; return o }, {}) : v
        })
    }
    function check(name, actual, expected) {
        shell.checks += 1
        if (shell.canon(actual) === shell.canon(expected)) { shell.log("PASS " + name); return }
        shell.failures.push(name)
        shell.log("FAIL " + name + ": got " + shell.canon(actual) + ", expected " + shell.canon(expected))
    }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function isText(o) { return o.text !== undefined && o.textFormat !== undefined && o.contentWidth !== undefined }

    // The delegate Columns, a label Text over a value Text, in the order the Repeater made them; the title is no pair.
    function pairs() {
        var out = [], queue = [dialog.cardItem]
        while (queue.length > 0) {
            var o = queue.shift()
            var kids = (o && o.children !== undefined) ? o.children : []
            if ((kids.length === 2 || kids.length === 3) && shell.isText(kids[0]) && shell.isText(kids[1]) && shell.labels.indexOf(kids[0].text) >= 0) out.push({label: kids[0], value: kids[1]})
            for (var i = 0; i < kids.length; i++) queue.push(kids[i])
        }
        return out
    }
    // Where they sit once the layout has run: top to bottom.
    function drawn() {
        return shell.pairs().sort(function (a, b) { return a.label.mapToItem(null, 0, 0).y - b.label.mapToItem(null, 0, 0).y })
            .map(function (p) { return p.label.text })
    }
    function shown(t) {
        return t.textFormat === Text.StyledText
            ? t.text.replace(/<[^>]*>/g, "").replace(/&gt;/g, ">").replace(/&lt;/g, "<").replace(/&amp;/g, "&") : t.text
    }
    // Every item under a root that the test accepts, in tree order.
    function under(root, accept) {
        var out = [], queue = [root]
        while (queue.length > 0) {
            var o = queue.shift()
            if (accept(o)) out.push(o)
            var kids = (o && o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) queue.push(kids[i])
        }
        return out
    }
    function names() { return shell.pairs().map(function (p) { return p.label.text }) }
    function pair(label) {
        var all = shell.pairs()
        for (var i = 0; i < all.length; i++) if (all[i].label.text === label) return all[i].value
        return null
    }
    function labelOf(label) {
        var all = shell.pairs()
        for (var i = 0; i < all.length; i++) if (all[i].label.text === label) return all[i].label
        return null
    }
    function line(label) { var t = shell.pair(label); return t ? shell.shown(t) : null }
    // The muted run: what sits inside the font element, and the colour it asks for.
    function mutedRun(label) {
        var t = shell.pair(label)
        var m = t ? /<font color="([^"]*)">([^<]*)<\/font>/.exec(t.text) : null
        return m ? {color: m[1], text: m[2].replace(/&gt;/g, ">")} : null
    }
    function sample() { shell.signatures[shell.names().join(",")] = true }
    function feed(message) { dialog.receive(message); shell.sample() }
    function lastRequest() { return shell.sent[shell.sent.length - 1] }
    function reply(extra) {
        return Object.assign({t: "menuaction", id: 7, op: "properties", ok: true, path: "/fixture/Music", kind: "Directory", directory: true,
            symlink: false, target: "", bytes: 4096, modified: 1758835200, mode: "0755", owner: "gm", uid: 1000, gid: 1000, tags: []}, extra || {})
    }
    function filed(id, path, extra) { return shell.reply(Object.assign({id: id, path: path, kind: "File", directory: false, bytes: 48300000}, extra || {})) }
    function factsReply(id, extra) {
        return Object.assign({t: "menuaction", id: id, op: "facts", ok: true, vcodec: "", acodec: "", bps: 0, make: "", model: "", lens: "", shutter: [0, 0], fnumber: [0, 0], iso: 0, taken: ""}, extra || {})
    }
    function factsAsked(id) { return shell.sent.filter(function (m) { return m.op === "facts" && m.id === id }) }
    function progress(extra) { return Object.assign({t: "menuaction", id: 7, op: "contents", ok: true, bytes: 4096, items: 0, partial: false, done: false}, extra) }

    Connections {
        target: dialog
        function onRequested(message) { shell.sent.push(message) }
    }

    FloatingWindow {
        implicitWidth: 1000
        implicitHeight: 900
        color: Flea.Theme.color.background
        Item {
            anchors.fill: parent
            Flea.MenuActionDialog { id: dialog }
            Item { id: parking; focus: true; width: 10; height: 10 }
            // The same visible string as plain text, so the styled run's width shows whether the tail's spaces survived.
            Text { id: plain; visible: false; textFormat: Text.PlainText; font { family: Flea.Theme.font.family; pixelSize: Flea.Theme.font.body } }
        }
    }

    function folderSteps() {
        return [
            function () {
                dialog.open("properties", 7, "/fixture", parking)
                shell.check("Properties asks for the facts", shell.lastRequest(), {c: "menuaction", op: "properties", id: 7})
                shell.check("it keeps Working until the reply, with no pair drawn", [shell.names(), dialog.busy], [[], true])
            },
            function () {
                shell.feed(shell.reply())
                // Read in the same turn as the reply, which is the first frame the pairs can draw in.
                shell.check("the first frame draws every pair whole, in the board's order", shell.names(), shell.fullFolder)
                shell.check("Size opens on the folder's own entry as a floor", shell.line("Size"), "> 4.1 kB (4096 bytes) · counting…")
                shell.check("Contains opens at zero as a floor", shell.line("Contains"), "> 0 items · counting…")
                shell.check("the count is asked for once, under the same id", shell.sent.filter(function (m) { return m.op === "contents" }), [{c: "menuaction", op: "contents", id: 7}])
                shell.check("Working is gone with the reply", dialog.busy, false)
            },
            function () {
                shell.check("laid out, the pairs run top to bottom as the board has them", shell.drawn(), shell.fullFolder)
                shell.cardHeight = dialog.cardItem.height
                shell.check("the tail is the muted colour on the value's own line", [shell.mutedRun("Size"), shell.mutedRun("Contains")],
                    [{color: String(Flea.Theme.color.muted), text: shell.tail}, {color: String(Flea.Theme.color.muted), text: shell.tail}])
                shell.check("the value is foreground at the body size and drawn as one run",
                    [shell.pair("Size").color, shell.pair("Size").font.pixelSize, shell.pair("Size").textFormat === Text.StyledText],
                    [Flea.Theme.color.foreground, Flea.Theme.font.body, true])
                plain.text = shell.line("Size")
                shell.check("the styled run is as wide as the same string in plain text, so the tail keeps its spaces", Math.abs(shell.pair("Size").contentWidth - plain.contentWidth) <= 1, true)
                shell.check("the label stays muted at the caption size", [shell.labelOf("Size").color, shell.labelOf("Size").font.pixelSize], [Flea.Theme.color.muted, Flea.Theme.font.caption])
            },
            function () {
                shell.before = shell.pairs().map(function (p) { return p.value })
                shell.feed(shell.progress({bytes: 2104332800, items: 812}))
                shell.check("a progress reply moves Size in place", shell.line("Size"), "> 2.1 GB (2104332800 bytes) · counting…")
                shell.check("and Contains", shell.line("Contains"), "> 812 items · counting…")
                shell.check("the same rows hold, none added or dropped", shell.names(), shell.fullFolder)
                shell.check("the same Text items change, none are rebuilt", shell.pairs().map(function (p) { return p.value }).every(function (v, i) { return v === shell.before[i] }), true)
            },
            function () {
                shell.check("after the layout the rows and the card height hold", [shell.drawn(), dialog.cardItem.height], [shell.fullFolder, shell.cardHeight])
                shell.feed(shell.progress({bytes: 4224, items: 1}))
                shell.check("one entry reads item while it counts", shell.line("Contains"), "> 1 item · counting…")
                shell.feed(shell.progress({bytes: 7404118016, items: 1204, done: true}))
                shell.check("the final reply ends Size as the exact value", shell.line("Size"), "7.4 GB (7404118016 bytes)")
                shell.check("and Contains as the grouped count", shell.line("Contains"), "1,204 items")
                shell.check("no muted run is left once it is done", [shell.mutedRun("Size"), shell.mutedRun("Contains")], [null, null])
                shell.check("a cancelled reply after done changes nothing", (function () { shell.feed(shell.progress({cancelled: true, bytes: 1, items: 9, done: false})); return shell.line("Contains") })(), "1,204 items")
            },
            function () {
                shell.check("done, the rows and the card height are still the same", [shell.drawn(), dialog.cardItem.height], [shell.fullFolder, shell.cardHeight])
                shell.check("every frame drew either nothing or the whole folder", Object.keys(shell.signatures).sort(), ["", shell.fullFolder.join(",")].sort())
                dialog.close()
                shell.check("closing the card sends menuaction close", shell.lastRequest(), {c: "menuaction", op: "close", id: 7})
                shell.check("and the card is gone", dialog.opened, false)
                shell.feed(shell.progress({bytes: 1, items: 9, done: true}))
                shell.check("a count that lands after the close changes nothing", [dialog.opened, shell.line("Contains")], [false, "1,204 items"])
            }
        ]
    }
    function otherSteps() {
        return [
            function () {
                dialog.open("properties", 8, "/fixture", parking)
                shell.feed(shell.reply({id: 8, bytes: 8192}))
                shell.feed(shell.progress({id: 8, bytes: 9000, items: 3, partial: true, done: true}))
                shell.check("a walk that ends partial stays a floor for Size", shell.line("Size"), "> 9.0 kB (9000 bytes)")
                shell.check("and for Contains", shell.line("Contains"), "> 3 items")
                shell.check("with no counting tail", [shell.mutedRun("Size"), shell.mutedRun("Contains")], [null, null])
                dialog.close()
            },
            function () {
                dialog.open("properties", 9, "/fixture", parking)
                shell.feed(shell.reply({id: 9, bytes: 8192}))
                shell.feed({t: "menuaction", id: 9, op: "contents", ok: false, error: "Selected items changed; reopen the menu."})
                shell.check("a refused count ends as the floor with no tail and no error line", [shell.line("Size"), shell.line("Contains"), dialog.errorText], ["> 8.2 kB (8192 bytes)", "> 0 items", ""])
                dialog.close()
            },
            function () {
                dialog.open("properties", 10, "/fixture", parking)
                shell.feed(shell.reply({id: 10, path: "/fixture/note.txt", kind: "File", directory: false, bytes: 13}))
                shell.check("a file has no Contains", shell.names(), shell.fullFolder.filter(function (n) { return n !== "Contains" }))
                shell.check("a file's Size is its own", shell.line("Size"), "13 B (13 bytes)")
                shell.check("and no count is asked for", shell.sent.filter(function (m) { return m.op === "contents" && m.id === 10 }).length, 0)
                shell.check("a file asks for its facts once, under the same id", shell.factsAsked(10), [{c: "menuaction", op: "facts", id: 10}])
                dialog.close()
            },
            function () {
                dialog.open("properties", 11, "/fixture", parking)
                shell.feed(shell.reply({id: 11, path: "/fixture/link", kind: "Symbolic link", directory: false, symlink: true, target: "/fixture/Music", bytes: 14}))
                shell.check("a link to a folder is the link, with its own size and no Contains", [shell.line("Type"), shell.line("Size"), shell.names().indexOf("Contains")], ["Symbolic link", "14 B (14 bytes)", -1])
                shell.check("and its link target is a pair", shell.line("Link target"), "/fixture/Music")
                shell.check("and no count is asked for", shell.sent.filter(function (m) { return m.op === "contents" && m.id === 11 }).length, 0)
                shell.check("a link and a folder ask for no facts", [shell.factsAsked(11).length, shell.factsAsked(7).length], [0, 0])
                dialog.close()
            },
            function () {
                // The harness fills no theme tags, so the menu colours are set here and told apart from the listing's.
                Flea.Theme.tag = {colors: {Red: "#ff0000", Blue: "#0000ff"}, menuColors: {Red: "#aa0000", Blue: "#0000aa"}, fallback: false}
                dialog.open("properties", 12, "/fixture", parking)
                shell.feed(shell.reply({id: 12, path: "/fixture/notes.md", kind: "File", directory: false, bytes: 4096, tags: ["Red", "Blue", "work"]}))
            },
            function () {
                var colors = Flea.Theme.tag.menuColors
                var marks = shell.under(dialog.cardItem, function (o) { return o.tagColors !== undefined && o.visible })
                var words = shell.under(dialog.cardItem, function (o) { return shell.isText(o) && o.visible && ["Red", "Blue", "work"].indexOf(o.text) >= 0 })
                shell.check("a tagged file draws Tags right after Size, as the board's Tagged file does", shell.drawn(), ["Path", "Type", "Size", "Tags", "Modified", "Permissions", "Owner", "Group"])
                shell.check("the Tags value is not drawn as one plain string", shell.pair("Tags").visible, false)
                shell.check("each own tag draws one swatch in the menu colour, a foreign word draws none", marks.map(function (o) { return [o.swatch, String(o.color)] }),
                    [["Red", String(colors.Red)], ["Blue", String(colors.Blue)]])
                shell.check("every name is foreground at the body size, in the tag's order", words.map(function (o) { return [o.text, String(o.color), o.font.pixelSize] }),
                    [["Red", String(Flea.Theme.color.foreground), Flea.Theme.font.body], ["Blue", String(Flea.Theme.color.foreground), Flea.Theme.font.body], ["work", String(Flea.Theme.color.foreground), Flea.Theme.font.body]])
                shell.check("the tags run left to right on one line", words.map(function (o) { return o.mapToItem(null, 0, 0).x }).every(function (x, i, all) { return i === 0 || x > all[i - 1] }), true)
                if (marks.length === 2 && words.length === 3) shell.check("a swatch sits 6 px left of its name at text size 14 and the next tag starts 16 px on, as Properties040 draws",
                    [words[0].mapToItem(null, 0, 0).x - marks[0].mapToItem(null, 0, 0).x - marks[0].width,
                     marks[1].mapToItem(null, 0, 0).x - words[0].mapToItem(null, 0, 0).x - words[0].width,
                     words[2].mapToItem(null, 0, 0).x - words[1].mapToItem(null, 0, 0).x - words[1].width],
                    [Flea.Theme.space(5), Flea.Theme.space(14), Flea.Theme.space(14)])
                if (marks.length > 0) shell.check("the Properties swatch is the board's 10 px square, smaller than the 14 px rail swatch", [marks[0].width, marks[0].height], [10, 10])
                if (marks.length > 0) shell.check("the Tags value starts at the label's left edge", Math.round(marks[0].mapToItem(null, 0, 0).x - shell.labelOf("Tags").mapToItem(null, 0, 0).x), 0)
                dialog.close()
            }
        ]
    }
    // The Video and RAW photo cards of Properties040: new pairs between Size and Modified, arriving with the facts reply and only for what the file has.
    function factSteps() {
        return [
            function () {
                dialog.open("properties", 12, "/fixture", parking)
                shell.feed(shell.filed(12, "/fixture/panel-demo.mp4"))
                shell.check("a video opens on the pairs the listing knows, before its facts", shell.names(), shell.plainFile)
                shell.feed(shell.factsReply(12, {vcodec: "h264", acodec: "aac", bps: 8100000}))
                shell.check("its facts add Codecs and Bit rate between Size and Modified", shell.names(), shell.videoFile)
                shell.check("Codecs is the board's string", shell.line("Codecs"), "H.264 · AAC")
                shell.check("Bit rate is the board's string", shell.line("Bit rate"), "8.1 Mb/s")
                shell.check("they are plain foreground values like every other pair", [shell.pair("Codecs").color, shell.pair("Bit rate").textFormat === Text.PlainText], [Flea.Theme.color.foreground, true])
            },
            function () {
                shell.check("laid out, the video pairs run top to bottom as the board has them", shell.drawn(), shell.videoFile)
                dialog.close()
            },
            function () {
                dialog.open("properties", 13, "/fixture", parking)
                shell.feed(shell.filed(13, "/fixture/IMG_0412.jpg", {bytes: 31200000}))
                shell.feed(shell.factsReply(13, {make: "Canon", model: "Canon EOS R6", lens: "RF35mm F1.8 MACRO IS STM", shutter: [1, 250], fnumber: [28, 10], iso: 400, taken: "2026:09:12 18:31:07"}))
                shell.check("a photo's facts add Camera, Lens, Exposure and Taken before Modified", shell.names(), shell.photoFile)
                shell.check("Camera is the board's string", shell.line("Camera"), "Canon EOS R6")
                shell.check("Lens is the board's string", shell.line("Lens"), "RF35mm F1.8 MACRO IS STM")
                shell.check("Exposure is the board's string", shell.line("Exposure"), "1/250 s · f/2.8 · ISO 400")
                shell.check("Taken is the board's string", shell.line("Taken"), "2026-09-12 18:31")
            },
            function () {
                shell.check("laid out, the photo pairs run top to bottom as the board has them", shell.drawn(), shell.photoFile)
                dialog.close()
            },
            function () {
                dialog.open("properties", 14, "/fixture", parking)
                shell.feed(shell.filed(14, "/fixture/IMG_0413.jpg"))
                shell.feed(shell.factsReply(14, {make: "FUJIFILM", model: "X100V", shutter: [1, 500], iso: 160}))
                shell.check("a photo without a lens or a time leaves no empty pair", shell.names(), ["Path", "Type", "Size", "Camera", "Exposure", "Modified", "Permissions", "Owner", "Group"])
                shell.check("and a missing aperture leaves the rest of the exposure", shell.line("Exposure"), "1/500 s · ISO 160")
                dialog.close()
            },
            function () {
                dialog.open("properties", 15, "/fixture", parking)
                shell.feed(shell.filed(15, "/fixture/notes.md"))
                shell.feed(shell.factsReply(15))
                shell.check("a file with no facts keeps the plain card", shell.names(), shell.plainFile)
                shell.feed({t: "menuaction", id: 15, op: "facts", ok: false, error: "Menu selection expired; reopen the menu."})
                shell.check("a refused facts reply adds nothing and shows no error", [shell.names(), dialog.errorText, dialog.busy], [shell.plainFile, "", false])
                shell.feed(shell.factsReply(15, {id: 99, vcodec: "h264"}))
                shell.check("a facts reply for another card changes nothing", shell.names(), shell.plainFile)
                dialog.close()
                shell.feed(shell.factsReply(15, {vcodec: "h264", acodec: "aac", bps: 8100000}))
                shell.check("a facts reply that lands after the close changes nothing", [dialog.opened, shell.names().length], [false, shell.plainFile.length])
            },
            function () {
                dialog.open("properties", 16, "/fixture", parking)
                shell.feed(shell.filed(16, "/fixture/clip.mp4"))
                shell.feed(shell.factsReply(16, {vcodec: "h264", acodec: "aac", bps: 8100000}))
                dialog.close()
                dialog.open("properties", 17, "/fixture", parking)
                shell.feed(shell.filed(17, "/fixture/other.txt"))
                shell.check("a new card starts without the last card's facts", shell.names(), shell.plainFile)
                dialog.close()
            }
        ]
    }
    readonly property var photo: ({make: "Canon", model: "Canon EOS R6", lens: "RF35mm F1.8 MACRO IS STM", exp: [1, 250], fnum: [28, 10], iso: 400, focal: [35, 1], taken: "2026:09:12 18:31:00"})
    // Properties040: a photo's Camera, Lens, Exposure and Taken sit before Modified, drawn whole in the reply's own frame.
    function photoSteps() {
        return [
            function () {
                dialog.open("properties", 12, "/fixture", parking)
                shell.feed(shell.reply({id: 12, path: "/fixture/IMG_0412.CR3", kind: "File", directory: false, bytes: 31200000, photo: shell.photo}))
                shell.check("a CR3 draws its photo pairs before Modified in the first frame", shell.names(), shell.photoFile)
                shell.check("and words them as the board does", ["Camera", "Lens", "Exposure", "Taken"].map(shell.line),
                    ["Canon EOS R6", "RF35mm F1.8 MACRO IS STM", "1/250 s \u00b7 f/2.8 \u00b7 ISO 400", "2026-09-12 18:31"])
                shell.check("the photo value is foreground at the body size on a muted caption label",
                    [shell.pair("Camera").color, shell.pair("Camera").font.pixelSize, shell.labelOf("Camera").color, shell.labelOf("Camera").font.pixelSize],
                    [Flea.Theme.color.foreground, Flea.Theme.font.body, Flea.Theme.color.muted, Flea.Theme.font.caption])
                shell.feed(shell.factsReply(12, {make: shell.photo.make, model: shell.photo.model, lens: shell.photo.lens, shutter: shell.photo.exp, fnumber: shell.photo.fnum, iso: shell.photo.iso, taken: shell.photo.taken}))
                shell.check("a deferred facts reply keeps each photo pair once", shell.names(), shell.photoFile)
                shell.check("equal immediate and deferred facts keep every approved value once", ["Camera", "Lens", "Exposure", "Taken"].map(shell.line),
                    ["Canon EOS R6", "RF35mm F1.8 MACRO IS STM", "1/250 s \u00b7 f/2.8 \u00b7 ISO 400", "2026-09-12 18:31"])
                shell.check("a file asks for no count", shell.sent.filter(function (m) { return m.op === "contents" && m.id === 12 }).length, 0)
            },
            function () {
                shell.check("laid out, the photo pairs keep the board's order", shell.drawn(), shell.photoFile)
                dialog.close()
            },
            function () {
                dialog.open("properties", 13, "/fixture", parking)
                shell.feed(shell.reply({id: 13, path: "/fixture/shot.png", kind: "File", directory: false, bytes: 2100, photo: null}))
                shell.check("a PNG draws none of the four", shell.names(), shell.photoFile.filter(function (n) { return ["Camera", "Lens", "Exposure", "Taken"].indexOf(n) < 0 }))
                dialog.close()
            },
            function () {
                dialog.open("properties", 14, "/fixture", parking)
                shell.feed(shell.reply({id: 14, path: "/fixture/bare.NEF", kind: "File", directory: false, bytes: 2100, photo: {taken: "2026:09:12 18:31:00", iso: 0}}))
                shell.check("a photo that names one fact draws that pair only, and nothing reads Unknown", [shell.names(), shell.line("Taken")],
                    [shell.photoFile.filter(function (n) { return ["Camera", "Lens", "Exposure"].indexOf(n) < 0 }), "2026-09-12 18:31"])
                shell.feed(shell.factsReply(14, {make: "FUJIFILM", model: "X100V", shutter: [1, 500], iso: 160}))
                shell.check("deferred facts fill missing photo pairs in board order", shell.names(), ["Path", "Type", "Size", "Camera", "Exposure", "Taken", "Modified", "Permissions", "Owner", "Group"])
                shell.check("the initial Taken pair survives while missing camera facts arrive", [shell.line("Camera"), shell.line("Exposure"), shell.line("Taken")], ["FUJIFILM X100V", "1/500 s \u00b7 ISO 160", "2026-09-12 18:31"])
                dialog.close()
            }
        ]
    }
    function mergedPhotoSteps() {
        return [function () {
            var cases = [
                ["partial ISO", {iso: 400}, {shutter: [1, 250], fnumber: [28, 10], iso: 400},
                    [["Exposure", "1/250 s \u00b7 f/2.8 \u00b7 ISO 400"]]],
                ["partial camera", {make: "Canon", iso: 400}, {make: "Canon", model: "Canon EOS R6", shutter: [1, 250], fnumber: [28, 10], iso: 400},
                    [["Camera", "Canon EOS R6"], ["Exposure", "1/250 s \u00b7 f/2.8 \u00b7 ISO 400"]]],
                ["complementary fields", {make: "Canon", lens: shell.photo.lens, exp: [1, 250], taken: shell.photo.taken}, {model: "Canon EOS R6", fnumber: [28, 10], iso: 400},
                    [["Camera", "Canon EOS R6"], ["Lens", shell.photo.lens], ["Exposure", "1/250 s \u00b7 f/2.8 \u00b7 ISO 400"], ["Taken", "2026-09-12 18:31"]]],
                ["conflicting fields", shell.photo, {make: "SONY", model: "ILCE-7M4", lens: "FE 35mm F1.8", shutter: [1, 500], fnumber: [4, 1], iso: 800, taken: "2026:10:12 09:15:00"},
                    [["Camera", "SONY ILCE-7M4"], ["Lens", "FE 35mm F1.8"], ["Exposure", "1/500 s \u00b7 f/4 \u00b7 ISO 800"], ["Taken", "2026-10-12 09:15"]]]
            ]
            cases.forEach(function (test) {
                dialog.open("properties", 15, "/fixture", parking)
                shell.feed(shell.filed(15, "/fixture/shot.CR3", {photo: test[1]}))
                shell.feed(shell.factsReply(15, test[2]))
                var observed = ["Camera", "Lens", "Exposure", "Taken"].filter(function (name) { return shell.pair(name) !== null }).map(function (name) { return [name, shell.line(name)] })
                shell.check(test[0] + " merges photo fields before formatting", observed, test[3])
                shell.check(test[0] + " draws each pair once in board order", shell.names(), shell.plainFile.slice(0, 3).concat(test[3].map(function (pair) { return pair[0] })).concat(shell.plainFile.slice(3)))
                dialog.close()
            })
        }]
    }
    function buildPlan() { shell.plan = shell.folderSteps().concat(shell.otherSteps()).concat(shell.factSteps()).concat(shell.photoSteps()).concat(shell.mergedPhotoSteps()) }

    Timer {
        interval: 16
        repeat: true
        running: true
        onTriggered: {
            if (shell.wait > 0) { shell.wait -= 1; shell.sample(); return }
            if (shell.plan.length === 0) { shell.buildPlan(); return }
            if (shell.at === shell.plan.length) {
                running = false
                shell.log("DONE checks=" + shell.checks + " failed=" + shell.failures.length)
                shell.quit()
                return
            }
            shell.plan[shell.at]()
            shell.at += 1
            shell.wait = shell.settleTicks
        }
    }
}
