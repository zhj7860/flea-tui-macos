.import "../../ui/js/Clipboard.js" as Clipboard
.import "../../ui/js/Collide.js" as Collide
.import "../../ui/js/DragOut.js" as DragOut
.import "../../ui/js/Menu.js" as Menu
.import "../../ui/js/Messages.js" as Messages
.import "../../ui/js/Settings.js" as Settings
.import "clipboard.js" as ClipboardSuite
.import "raildrop.js" as RailDropSuite

// Drops callouts 2 to 4 as pure functions: the hover band and rest, the FAT card's words and answer, and the image paste.

function bands(check) {
    check("the top band scrolls up", DragOut.band(10, 400), -1)
    check("the bottom band scrolls down", DragOut.band(390, 400), 1)
    check("the middle rests", DragOut.band(200, 400), 0)
    check("the band is 37 px", DragOut.BAND_PX, 37)
    check("the last pixel of the top band still scrolls", DragOut.band(36, 400), -1)
    check("the first pixel under it does not", DragOut.band(37, 400), 0)
    check("the bottom band starts 37 px from the end", DragOut.band(363, 400) + "|" + DragOut.band(364, 400), "0|1")
    check("a list too short for two bands never scrolls", DragOut.band(10, 60), 0)
    check("a rest opens a folder at 0.7 s with the setting on", DragOut.shouldOpen(700, true, false), true)
    check("a shorter rest does not", DragOut.shouldOpen(699, true, false), false)
    check("the setting off never opens", DragOut.shouldOpen(5000, false, false), false)
    check("a move spends the rest", DragOut.shouldOpen(5000, true, true), false)
    check("the rest is 700 ms", DragOut.OPEN_MS, 700)
}

function setting(check) {
    var row = Settings.rows("view", { data: {} }).filter(function (r) { return r.id === "openFoldersWhileDragging" })[0] || {}
    check("Open folders while dragging ships off, a check with no mark", row.kind + "|" + row.label + "|" + row.on + "|" + row.glyph,
          "check|Open folders while dragging|false|undefined")
    var on = Settings.rows("view", { data: { openFoldersWhileDragging: true } }).filter(function (r) { return r.id === "openFoldersWhileDragging" })[0] || {}
    check("and a stored on reads back on", on.on, true)
    var ids = Settings.rows("view", { data: {} }).map(function (r) { return r.id || r.label })
    check("it is the last row of the View group, under no heading of its own", ids[ids.indexOf("Sorting") - 1], "openFoldersWhileDragging")
}

function fatCard(check) {
    check("the card names the count, the volume and its filesystem",
          Collide.cardTitle(3, "128GB", "exfat"), "3 names cannot exist on 128GB (exFAT)")
    check("one name reads singular", Collide.cardTitle(1, "128GB", "exfat"), "1 name cannot exist on 128GB (exFAT)")
    check("a count of four figures groups", Collide.cardTitle(1204, "128GB", "exfat"), "1,204 names cannot exist on 128GB (exFAT)")
    check("the note is the board's sentence", Collide.cardNote("exfat"), "exFAT refuses : ? * \" < > | and trailing dots or spaces.")
    check("vfat is FAT, never a width it may not have", Collide.filesystemLabel("vfat"), "FAT")
    check("ntfs reads in capitals", Collide.cardNote("ntfs3"), "NTFS refuses : ? * \" < > | and trailing dots or spaces.")
    check("a word the table lacks is shown as the machine gave it", Collide.filesystemLabel("zzfs"), "zzfs")
    check("a volume holding a placeholder or a dollar sign is shown as it is",
          Collide.cardTitle(2, "%1 $& $1", "exfat"), "2 names cannot exist on %1 $& $1 (exFAT)")
    check("Rename and copy is the default", Collide.FAT_DEFAULT, "rename")
    check("the three buttons are the board's", JSON.stringify(Collide.FAT_BUTTONS),
          JSON.stringify({ cancel: "Cancel", skip: "Skip them", rename: "Rename and copy" }))
}

function rides(check) {
    var fatted = { c: "transfer", op: "copy", paths: ["/s/a.txt"], dest: "/d", fat: "rename" }
    check("the answer rides the collisions question again",
          JSON.stringify(Collide.question(fatted, null, 7)),
          JSON.stringify({ c: "collisions", id: 7, dest: "/d", fat: "rename", paths: ["/s/a.txt"] }))
    check("and the transfer it releases", Collide.transfer(fatted, "refuse", 7).fat, "rename")
    check("and a link", Collide.link(fatted, "refuse", 7).fat, "rename")
    var plain = { c: "transfer", op: "copy", paths: ["/s/a.txt"], dest: "/d" }
    check("with no answer nothing rides along", "fat" in Collide.question(plain, null, 7) || "fat" in Collide.link(plain, "keep", 7), false)
}

function imagePaste(check) {
    check("the stamp is the board's, down to the dots in the time",
          Clipboard.imageName(new Date(2026, 8, 23, 10, 14, 32)), "Pasted image 2026-09-23 at 10.14.32.png")
    check("one-figure parts are padded", Clipboard.imageName(new Date(2026, 0, 2, 3, 4, 5)), "Pasted image 2026-01-02 at 03.04.05.png")
    var p = ClipboardSuite.pane()
    Clipboard.paste(p, "", false)
    check("an empty clipboard asks the backend for the image, once", p.sent.length, 1)
    var line = p.sent[0] || {}
    check("into this folder as a stamped png", line.c + "|" + line.dest + "|" + /^Pasted image \d{4}-\d{2}-\d{2} at \d{2}\.\d{2}\.\d{2}\.png$/.test(line.name),
          "pasteimage|/dest|true")
    check("and asks the card nothing", p.asked.length, 0)
    var links = ClipboardSuite.pane()
    Clipboard.paste(links, "relative", false)
    check("Paste as links has no image to make, so it says so itself", links.said.join("|") + "|" + links.sent.length,
          Menu.EMPTY_CLIPBOARD + "|0")
    // Row 148: the backend names the empty clipboard by code, and the pane shows the one sentence Menu owns.
    var failures = []
    var wire = { failed: function (where, path, msg) { failures.push([where, path, msg]) } }
    Messages.route(wire, { t: "error", where: "pasteimage", path: "a.png", msg: "the clipboard holds no image", code: "emptyclipboard" })
    Messages.route(wire, { t: "error", where: "pasteimage", path: "a.png", msg: "the clipboard could not be read" })
    check("an empty-clipboard code reads as the one sentence, any other error keeps its own",
          JSON.stringify(failures),
          JSON.stringify([["pasteimage", "a.png", Menu.EMPTY_CLIPBOARD], ["pasteimage", "a.png", "the clipboard could not be read"]]))
    var held = ClipboardSuite.pane()
    ClipboardSuite.changed(held, "copy", ["/s/a.txt"])
    Clipboard.paste(held, "", false)
    check("paths still paste as paths", JSON.stringify(held.asked) + "|" + held.sent.length,
          JSON.stringify([[{ c: "transfer", op: "copy", paths: ["/s/a.txt"], dest: "/dest" }, false]]) + "|0")
}

function run(check) {
    RailDropSuite.run(check)
    bands(check)
    setting(check)
    fatCard(check)
    rides(check)
    imagePaste(check)
}
