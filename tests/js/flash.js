.import "../../ui/js/Archive.js" as Archive
.import "../../ui/js/Flash.js" as Flash
.import "../../ui/js/FlashCard.js" as FlashCard
.import "../../ui/js/FlashEndings.js" as FlashEndings
.import "../../ui/js/Menu.js" as Menu
.import "../../ui/js/Settings.js" as Settings
.import "../../ui/js/Transfer.js" as Transfer

// The flasher's model, every ending and the card's flash branch, driven through the real Flash.js and Transfer.js.

function drives() {
    return [
        { dev: "sda", seq: 2, serial: "2003007157171692", label: "128GB",
          model: "General USB Flash Disk", bytes: 124623257600, volumes: ["128GB"], refused: "" },
        { dev: "sdb", seq: 3, serial: "001122334455", label: "SanDisk",
          model: "SanDisk Cruzer Blade", bytes: 2000000000, volumes: ["SanDisk"], refused: "small" }
    ]
}

function run(check) {
    // The ledger's image kinds, by name.
    check("iso is a disk image", Archive.isDiskImage("debian-13.iso", ""), true)
    check("img is a disk image", Archive.isDiskImage("disk.img", ""), true)
    check("raw is a disk image", Archive.isDiskImage("disk.raw", ""), true)
    check("img.xz is a disk image", Archive.isDiskImage("raspios-arm64.img.xz", ""), true)
    check("img.gz is a disk image", Archive.isDiskImage("archlinuxarm.img.gz", ""), true)
    check("img.zst is a disk image", Archive.isDiskImage("disk.img.zst", ""), true)
    check("img.bz2 is a disk image", Archive.isDiskImage("disk.img.bz2", ""), true)
    check("matching is case-insensitive", Archive.isDiskImage("DEBIAN-13.ISO", ""), true)
    check("a text file is not", Archive.isDiskImage("notes.txt", ""), false)
    check("an archive is not", Archive.isDiskImage("bundle.zip", ""), false)
    check("a zip with one image member is", Archive.isDiskImage("bundle.zip", "disk.img"), true)
    check("a zip with a text member is not", Archive.isDiskImage("bundle.zip", "notes.txt"), false)
    check("a zip with no member named is not", Archive.isDiskImage("bundle.zip", ""), false)
    check("a zip of a zip is not", Archive.isDiskImage("bundle.zip", "inner.zip"), false)

    // Refusal hints, the boards' own wording.
    check("a fitting drive fits", Flash.fits(drives()[0]), true)
    check("a refused drive does not", Flash.fits(drives()[1]), false)
    check("too small says so", Flash.refusedHint(drives()[1]), "It is too small for the image.")
    check("a card's lock switch says so",
        Flash.refusedHint({ dev: "mmcblk0", refused: "readonly" }),
        "Its lock switch is on. Slide the switch off and plug the card in again.")
    check("any other read-only drive says so",
        Flash.refusedHint({ dev: "sda", refused: "readonly" }),
        "It is read-only, so Flea cannot write to it.")
    check("the image's own drive says so",
        Flash.refusedHint({ dev: "sda", refused: "holdsimage" }),
        "The image is on this drive. Copy it elsewhere first.")
    check("a RAID member says so",
        Flash.refusedHint({ dev: "sda", refused: "member" }),
        "It is part of a RAID or volume group.")

    // Names: the label, the model where no label names it, the kernel name on a repeat.
    check("a labelled drive keeps its label", Flash.driveName(drives()[0], drives()), "128GB")
    check("its detail is the model", Flash.driveDetail(drives()[0], drives()), "General USB Flash Disk")
    var twins = [{ dev: "sda", label: "128GB", model: "General USB Flash Disk", refused: "" },
                 { dev: "sdb", label: "128GB", model: "Kingston DataTraveler", refused: "" }]
    check("a repeated name gains the kernel name", Flash.driveName(twins[1], twins), "128GB (sdb)")
    check("a model-named drive keeps an empty detail",
        Flash.driveDetail({ dev: "sdc", label: "", model: "Seagate Expansion" },
            [{ dev: "sdc", label: "", model: "Seagate Expansion" }]), "")
    check("two volumes name both",
        Flash.driveName({ dev: "sda", label: "bootfs, rootfs", model: "Generic STORAGE DEVICE" },
            [{ dev: "sda", label: "bootfs, rootfs", model: "Generic STORAGE DEVICE" }]), "bootfs, rootfs")

    // Preselection: one fitting drive is chosen for you, two choose none.
    check("one fitting drive is preselected", Flash.preselect(drives()), 0)
    check("two fitting drives preselect none",
        Flash.preselect([drives()[0], { dev: "sdc", label: "Backup", model: "WD Elements",
            bytes: 500000000000, volumes: [], refused: "" }]), -1)
    check("no fitting drive preselects none", Flash.preselect([drives()[1]]), -1)

    // The cursor walk skips refused rows.
    check("down from the image lands on the fitting drive", Flash.step(0, 1, drives(), true, true), 1)
    check("down again skips the refused drive for Flash", Flash.step(1, 1, drives(), true, true), 3)
    check("up from Flash lands back on the fitting drive", Flash.step(3, -1, drives(), true, true), 1)
    check("a held Flash row keeps the cursor", Flash.step(3, 1, drives(), true, true), 3)
    check("no image starts the walk on a drive", Flash.step(0, 1, drives(), false, true), 1)

    // Flash availability and the greyed row's wording.
    check("an image and a fitting drive arm Flash", Flash.flashLive(true, drives()[0]), true)
    check("no image greys it", Flash.flashLive(false, drives()[0]), false)
    check("a refused drive greys it", Flash.flashLive(true, drives()[1]), false)
    check("no drive greys it", Flash.flashLive(true, null), false)
    var words = Flash.flashWords(true, drives()[0], drives())
    check("the row names what it erases", words.erase, "Erases everything on 128GB")
    check("and the action names the drive", words.action, "Flash 128GB")
    var bare = Flash.flashWords(false, null, drives())
    check("with nothing chosen the row names the drive in general", bare.erase, "Erases everything on the drive")
    check("and the action names nothing", bare.action, "Flash")

    // Every ending is a row with its fix in a hint.
    var done = FlashEndings.endingFor("", { image: "debian-13.iso", drive: "128GB" })
    check("done names the image and the drive", done.headline, "Flashed debian-13.iso to 128GB")
    check("done carries no hint", done.hint, "")
    check("done offers Eject", done.eject, true)
    check("done brings no Flash back", done.flashBack, false)
    check("an image named like a placeholder is never filled twice",
        FlashEndings.endingFor("", { image: "{drive}.iso", drive: "128GB" }).headline, "Flashed {drive}.iso to 128GB")
    check("a drive label named like a placeholder is never filled twice",
        Flash.driveName({ dev: "sdb", label: "{dev}", model: "A" }, [{ dev: "sda", label: "{dev}", model: "B" }, { dev: "sdb", label: "{dev}", model: "A" }]),
        "{dev} (sdb)")
    var cancelled = FlashEndings.endingFor("cancelled",
        { image: "debian-13.iso", drive: "128GB", at: 1200000000, total: 4000000000 })
    check("a cancelled flash names where it stopped", cancelled.headline, "Flash cancelled at 1.2 GB of 4.0 GB")
    check("and says the drive is blank now", cancelled.hint, "128GB is blank now. Flash again, or format it in Disks.")
    check("and brings Flash back", cancelled.flashBack, true)
    var unknownTotal = FlashEndings.endingFor("cancelled",
        { image: "debian-13.iso", drive: "128GB", at: 1200000000, total: 0 })
    check("a cancel with an unknown total names where it stopped", unknownTotal.headline, "Flash cancelled at 1.2 GB")
    check("and keeps the blank-drive hint", unknownTotal.hint, "128GB is blank now. Flash again, or format it in Disks.")
    check("and brings Flash back", unknownTotal.flashBack, true)
    var preWrite = FlashEndings.endingFor("cancelled",
        { image: "debian-13.iso", drive: "128GB", at: 0, total: 4000000000, phase: "password" })
    check("a cancel before the write wrote nothing", preWrite.headline, "Nothing was written")
    check("and says it ended before it started", preWrite.hint, "The flash was cancelled before it started. Flash again when ready.")
    check("with the cancelled mark and Flash back", preWrite.mark + "|" + preWrite.eject + "|" + preWrite.flashBack, "x|false|true")
    // A stale offset beside the prepare phase shows the phase alone decides the pre-write ending.
    var prepare = FlashEndings.endingFor("cancelled",
        { image: "debian-13.iso", drive: "128GB", at: 1200000000, total: 4000000000, phase: "prepare" })
    check("a cancel while preparing wrote nothing", prepare.headline, "Nothing was written")
    check("and says it ended before it started", prepare.hint, "The flash was cancelled before it started. Flash again when ready.")
    var verifyCancel = FlashEndings.endingFor("cancelled", { image: "debian-13.iso", drive: "128GB", phase: "verify" })
    check("a cancelled verify names itself", verifyCancel.headline, "Verify cancelled")
    check("with the image left on the drive", verifyCancel.hint, "debian-13.iso is on 128GB, not verified.")
    check("and Eject alone", verifyCancel.eject && !verifyCancel.flashBack, true)
    check("a dismissed prompt wrote nothing",
        FlashEndings.endingFor("denied", { drive: "128GB" }).headline, "Nothing was written")
    check("a busy drive names itself",
        FlashEndings.endingFor("busy", { drive: "128GB" }).headline, "128GB could not be unmounted")
    check("a swapped drive names the change",
        FlashEndings.endingFor("changed", { drive: "128GB" }).headline, "128GB changed since you chose it")
    check("an unplugged drive names itself",
        FlashEndings.endingFor("gone", { drive: "128GB", at: 1200000000 }).headline, "128GB was unplugged")
    var ioBlank = FlashEndings.endingFor("io", { drive: "128GB", at: 1200000000, blank: true })
    check("a dead drive names where it stopped", ioBlank.headline, "Could not flash 128GB")
    check("and says it is blank now", ioBlank.hint,
        "It stopped answering at 1.2 GB and is blank now. Plug it in again.")
    check("a failed wipe keeps the partial image",
        FlashEndings.endingFor("io", { drive: "128GB", at: 1200000000, blank: false }).hint,
        "It stopped answering at 1.2 GB and holds part of the image. Plug it in again and flash again.")
    check("an overgrown stream names both sides",
        FlashEndings.endingFor("nospace", { image: "archlinuxarm.img.gz", drive: "128GB", driveBytes: 124623257600 }).headline,
        "archlinuxarm.img.gz is larger than 128GB")
    check("a verify miss names the offset",
        FlashEndings.endingFor("verify", { drive: "128GB", at: 2300000000 }).hint,
        "It read back different data at 2.3 GB. Flash again, or use another drive.")
    check("a failed unpack names the image",
        FlashEndings.endingFor("decompress", { image: "raspios-arm64.img.xz", tool: "xz: unexpected end" }).headline,
        "Could not unpack raspios-arm64.img.xz")
    check("a missing sandbox names itself",
        FlashEndings.endingFor("sandbox", {}).headline, "Compressed images need bubblewrap")

    // The status line while the listing shows, as a copy's.
    check("done reports in the status line",
        FlashEndings.statusFor("", { image: "debian-13.iso", drive: "128GB" }).text, "Flashed debian-13.iso to 128GB.")
    check("a verify miss reports as an error",
        FlashEndings.statusFor("verify", { drive: "128GB" }).text, "128GB did not verify; flash it again.")
    check("and it is an error", FlashEndings.statusFor("verify", { drive: "128GB" }).isError, true)
    check("a cancel reports without error",
        FlashEndings.statusFor("cancelled", { drive: "128GB", at: 1, total: 2 }).isError, false)

    // A rail volume names its whole disk.
    check("a partition names its disk", Flash.railDisk("/dev/sda1"), "sda")
    check("an NVMe namespace names itself", Flash.railDisk("/dev/nvme0n1p2"), "nvme0n1")
    check("a card partition names its card", Flash.railDisk("/dev/mmcblk0p1"), "mmcblk0")
    check("a whole disk names itself", Flash.railDisk("/dev/sda"), "sda")

    // The card's flash lines are pre-rendered by ui/js/FlashCard.js, so Transfer.js never names the job.
    var flashing = { flash: true, phase: "write", drive: "128GB", name: "debian-13.iso",
                     bytes: 1200000000, total: 4000000000, known: true, permille: 300, running: true }
    var drawn = FlashCard.render(flashing, 38200000)
    function texts(parts) { return parts.map(function (p) { return p.text }).join("") }
    check("flashing headlines the drive", drawn.headText, "Flashing 128GB")
    check("a known total reads as a copy's",
        texts(drawn.byteText), "1.2 GB of 4.0 GB · 38.2 MB/s · 1:13 left")
    check("the bar fills against the known total", Math.round(drawn.share * 1000) / 1000, 0.3)
    check("Cancel runs while writing", drawn.noCancel, false)
    check("verifying headlines the phase",
        FlashCard.render(Object.assign({}, flashing, { phase: "verify" }), 0).headText, "Verifying 128GB")
    var unknown = Object.assign({}, flashing, { total: 0, known: false, bytes: 2100000000, permille: 500 })
    var drawnUnknown = FlashCard.render(unknown, 36400000)
    check("an unknown total counts what the device took",
        texts(drawnUnknown.byteText), "2.1 GB written · 36.4 MB/s · 0:57 left")
    check("and against the permille for the bar", drawnUnknown.share, 0.5)
    var stalled = FlashCard.render(unknown, 0)
    check("a stall keeps its bytes and drops the estimate",
        texts(stalled.byteText), "2.1 GB written · 0 B/s")
    check("the password wait names itself",
        texts(FlashCard.render(Object.assign({}, flashing, { phase: "password", bytes: 0 }), 0).byteText),
        "waiting for your password")
    var flushed = FlashCard.render(Object.assign({}, flashing, { phase: "flush", bytes: 4000000000 }), 0)
    check("the final flush names the wait",
        texts(flushed.byteText), "4.0 GB written · waiting for the drive")
    check("and dims Cancel there because every byte is on the device", flushed.noCancel, true)
    check("the file line is the name alone when the size is unknown",
        FlashCard.render({ name: "archlinuxarm.img.gz", total: 0, bytes: 1 }, 0).fileText, "archlinuxarm.img.gz")
    // And the shipped card draws the pre-rendered answer through its own setters alone.
    var carried = Object.assign({}, flashing, FlashCard.render(flashing, 38200000))
    check("the card headlines finished text", Transfer.head(carried), "Flashing 128GB")
    check("the card draws the finished byte line",
        texts(Transfer.byteParts(carried, 0)), "1.2 GB of 4.0 GB · 38.2 MB/s · 1:13 left")
    check("the card fills the finished share", Math.round(Transfer.fraction(carried) * 1000) / 1000, 0.3)
    check("the card offers Cancel while writing", Transfer.cancelEnabled(carried), true)
    check("the eject line is the rail's own", FlashEndings.ejectDoneLine("128GB"), "Ejected 128GB. It is safe to unplug.")
    check("a busy eject names what is still mounted", FlashEndings.ejectBusyLine("128GB"),
          "128GB is still mounted; close what is using it.")
    check("a failed eject names the drive", FlashEndings.ejectFailedLine("128GB"), "Could not eject 128GB.")
    // Ruling 16: whole sentences with placeholders, never joined fragments.
    check("the unpacked size is one label", Flash.unpackedLine(5900000000), "5.9 GB unpacked")
    check("one drive stays singular", Flash.drivesLine(1), "1 drive")
    check("two drives take the whole plural", Flash.drivesLine(2), "2 drives")
    check("and the count groups", Flash.drivesLine(1204), "1,204 drives")

    // The two menu rows, present or absent by kind.
    function menuState(changes) {
        var value = { hasRow: true, selectionCount: 1, rowMode: 0o100644, clipboardAvailable: false,
            rowIsSymlink: false, rowName: "debian-13.iso", flashZipMember: "",
            hiddenActions: ["delete", "openTerminal", "moveto", "copyto", "properties", "permissions",
                "copyAs", "pasteAs", "invertSelection"],
            archiveFormats: ["zip"], canExtract: true, rowIsArchive: false, rowIsImage: true, canConvert: true,
            taildropInstalled: true, taildropPeers: [{ id: "box", label: "Box" }],
            dropboxInstalled: true, dropboxPath: "/tmp/Dropbox", rowInDropbox: false }
        for (var key in changes) value[key] = changes[key]
        return value
    }
    function menuActions(rows) { return rows.filter(function (r) { return !r.separator }).map(function (r) { return r.action }).join(",") }
    function menuEntry(rows, action) { return rows.filter(function (r) { return r.action === action })[0] || {} }
    var file = Menu.listingEntries(menuState({}))
    check("an iso offers Flash to drive with the drive mark",
          menuEntry(file, "flashDrive").label + "|" + menuEntry(file, "flashDrive").glyph, "Flash to drive|drive")
    check("a text file never offers it",
          menuEntry(Menu.listingEntries(menuState({ rowName: "notes.txt" })), "flashDrive").action, undefined)
    check("two selected images never offer it",
          menuEntry(Menu.listingEntries(menuState({ selectionCount: 2 })), "flashDrive").action, undefined)
    check("a zip with one image member offers it",
          menuEntry(Menu.listingEntries(menuState({ rowName: "bundle.zip", flashZipMember: "disk.img" })), "flashDrive").action,
          "flashDrive")
    check("a zip with no member named never offers it",
          menuEntry(Menu.listingEntries(menuState({ rowName: "bundle.zip" })), "flashDrive").action, undefined)
    function railLabels(rows) { return rows.filter(function (r) { return !r.separator }).map(function (r) { return r.label }).join("|") }
    var stick = { group: "device", kind: "volume", device: "/dev/sda1", mounted: true, removable: true, volumeMenu: true }
    check("a mounted volume offers Flash image last, in a group of its own",
          railLabels(Menu.railEntries(stick)), "Open|Unmount|Eject|Flash image")
    check("and it sits behind its own separator",
          Menu.railEntries(stick).filter(function (r) { return r.separator === true }).length, 2)
    check("a read-only removable volume never offers it",
          railLabels(Menu.railEntries(
              { group: "device", kind: "volume", device: "/dev/sda1", mounted: true, removable: true, volumeMenu: true, readOnly: true })),
          "Open|Unmount|Eject")
    check("an internal volume never offers it either",
          railLabels(Menu.railEntries(
              { group: "device", kind: "volume", device: "/dev/nvme0n1p2", mounted: true, removable: false, volumeMenu: true })),
          "Open|Unmount")
    check("an unmounted removable stick offers Mount and Flash image",
          railLabels(Menu.railEntries(
              { group: "device", kind: "volume", device: "/dev/sda1", mounted: false, removable: true, volumeMenu: true })),
          "Mount|Flash image")

    // A flashimage reply lands on the card only when it answers the card's own image.
    var shown = { path: "/d/a.img.xz", kind: "", bytes: 0, unpacked: 0, known: false, member: "", refused: false }
    var mine = Flash.imageFrom(shown, { path: "/d/a.img.xz", kind: "xz", bytes: 10, unpacked: 20, known: true, member: "" })
    check("the card's own reply fills its image", mine.kind + "|" + mine.unpacked + "|" + mine.refused, "xz|20|false")
    check("a reply for the pane's zip check leaves the card's image",
          Flash.imageFrom(shown, { path: "/d/other.zip", kind: "zip", bytes: 5, member: "disk.img" }), null)
    check("a reply with no image asked for is not taken", Flash.imageFrom(null, { path: "/d/other.zip", kind: "zip" }), null)
    check("a refused reply marks the card's image refused", Flash.imageFrom(shown, { path: "/d/a.img.xz", kind: "" }).refused, true)

    // Settings, Menus lists the row switchable in Extras after Convert, switched on.
    var extras = Settings.MENU_GROUPS.filter(function (g) { return g.id === "extras" })[0].ids
    check("Flash to drive sits in Extras after Convert",
          extras.slice(extras.indexOf("convert"), extras.indexOf("convert") + 2).join(","), "convert,flashDrive")
    check("wearing the file menu row's own wording and mark",
          Settings.label("flashDrive") + "|" + Settings.GLYPHS.flashDrive, "Flash to drive|drive")
}
