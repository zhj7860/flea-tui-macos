.import "../../ui/js/Flash.js" as Flash
.import "../../ui/js/FlashCard.js" as FlashCard
.import "../../ui/js/FlashEndings.js" as FlashEndings
.import "../../ui/js/FlashPane.js" as FlashPane
.import "../../ui/js/Menu.js" as Menu
.import "../../ui/js/Transfer.js" as Transfer

// The flash pane's decisions: the chosen drive held by identity, the poll, the host's pane mark and the endings' figures.

function stick(dev, seq, serial, label, refused) {
    return { dev: dev, seq: seq, serial: serial, label: label, model: label + " Disk", bytes: 124623257600,
             volumes: [label], refused: refused || "" }
}

var A = stick("sda", 2, "AAA", "Alpha")
var B = stick("sdb", 3, "BBB", "Bravo")
var C = stick("sdc", 4, "CCC", "Charlie")

function run(check) {
    // The chosen drive is held by identity, so a reordered list never moves Flash or Eject onto another disk.
    var reordered = FlashPane.reconcile({ selected: 1, chosen: B, cursor: 3, drives: [A, B] }, [A, C, B])
    check("a stick plugged in ahead of the chosen drive leaves it chosen", reordered.selected, 2)
    check("and Flash still names its disk", reordered.chosen ? reordered.chosen.dev : "", "sdb")
    var swapped = FlashPane.reconcile({ selected: 1, chosen: B, cursor: 3, drives: [A, B] },
        [A, stick("sdb", 9, "ZZZ", "Zulu")])
    check("a new disk under the chosen kernel name is not the chosen drive", swapped.selected === 1 && swapped.chosen.serial !== "BBB", false)
    check("a new disk under the chosen kernel name leaves no chosen drive", swapped.chosen === null, true)
    var gone = FlashPane.reconcile({ selected: 1, chosen: B, cursor: 3, drives: [A, B] }, [A, C])
    check("a chosen drive that left is chosen no longer, and none takes its place unasked", gone.chosen === null, true)
    var lone = FlashPane.reconcile({ selected: 1, chosen: B, cursor: 3, drives: [A, B] }, [A])
    check("nor does the one fitting drive left when the chosen one goes", lone.chosen === null, true)
    var later = FlashPane.reconcile({ selected: lone.selected, chosen: lone.chosen, held: lone.held, cursor: lone.cursor, drives: [A] }, [A])
    check("and the next poll leaves the choice empty too", later.chosen === null, true)
    var onDrive = FlashPane.reconcile({ selected: 0, chosen: A, held: true, cursor: 2, drives: [A, B] }, [B])
    var onDriveLater = FlashPane.reconcile({ selected: onDrive.selected, chosen: onDrive.chosen, held: onDrive.held, cursor: onDrive.cursor, drives: [B] }, [B])
    check("with the cursor on a drive row the mark holds across both polls", [onDrive.held, onDrive.chosen === null, onDriveLater.chosen === null].join(), "true,true,true")
    var reopened = FlashPane.reconcile({ selected: -1, chosen: null, held: true, cursor: 0, drives: [], first: true }, [A])
    check("a new opening chooses the one fitting drive again", reopened.chosen === A, true)
    var view = { pendingDrive: "/dev/sdb1", chosen: null, held: false, cursor: 0 }
    FlashPane.land(view, { chosen: A, held: true, cursor: 1 })
    check("an answer lands its choice, mark and cursor and spends the rail's disk", [view.pendingDrive, view.chosen === A, view.held, view.cursor].join(), ",true,true,1")

    // The poll keeps the cursor on what it named and moves the keyboard only when that changed.
    var onFlash = FlashPane.reconcile({ selected: 0, chosen: A, cursor: 3, drives: [A, B] }, [A, B])
    check("a poll leaves the cursor on Flash", onFlash.cursor, 3)
    check("and leaves the keyboard where it is", onFlash.moved, false)
    var onImage = FlashPane.reconcile({ selected: 0, chosen: A, cursor: 0, drives: [A, B] }, [A, B])
    check("a poll leaves the cursor on the image", onImage.cursor, 0)
    var onDrive = FlashPane.reconcile({ selected: 0, chosen: A, cursor: 2, drives: [A, B] }, [C, A, B])
    check("a poll keeps the cursor on its drive when the list grows ahead of it", onDrive.cursor, 3)
    var grown = FlashPane.reconcile({ selected: 0, chosen: A, cursor: 3, drives: [A, B] }, [A, B, C])
    check("Flash moves down with the list it closes", grown.cursor, 4)
    var first = FlashPane.reconcile({ selected: -1, chosen: null, cursor: 0, drives: [], first: true }, [A, stick("sdb", 3, "BBB", "Bravo", "small")])
    check("the first answer chooses the one fitting drive", first.selected, 0)
    check("and puts the cursor on it", first.cursor + "|" + first.moved, "1|true")
    var rail = FlashPane.reconcile({ selected: -1, chosen: null, cursor: 0, drives: [], first: true, pendingDisk: "/dev/mmcblk0" },
        [A, stick("mmcblk0", 5, "SD1", "Card")])
    check("a rail menu on a partitionless card chooses the card", rail.selected, 1)

    // The host's pane mark follows the pane it covers.
    var left = { flashActive: false }, right = { flashActive: false }
    var host = { coverPane: null }
    FlashPane.cover(host, left)
    FlashPane.uncover(host)
    check("leaving through the view's own Back clears the pane's mark", left.flashActive, false)
    FlashPane.cover(host, left)
    FlashPane.cover(host, right)
    check("opening on the other pane clears the first pane's mark", left.flashActive + "|" + right.flashActive, "false|true")

    // Reopening onto a running flash takes the card back from the pane; a copy's card stays.
    var paneWithFlash = { transfer: { id: 7, flash: true, running: true }, said: "1.2 GB of 4.0 GB",
                          sticky: function (line) { this.said = line } }
    FlashPane.reclaim(paneWithFlash)
    check("the reopened pane no longer draws the flash's card", paneWithFlash.transfer.running === true, false)
    check("nor its sticky line", paneWithFlash.said, "")
    var paneWithCopy = { transfer: { id: 8, flash: false, running: true }, said: "copying",
                         sticky: function (line) { this.said = line } }
    FlashPane.reclaim(paneWithCopy)
    check("a copy's card is left alone", paneWithCopy.transfer.id + "|" + paneWithCopy.said, "8|copying")

    // A refusal answered before any flashstarted releases the press.
    var waiting = { running: false, transferId: 0, pressSent: true, pendingId: 5 }
    check("a probe refusal for the press just sent is that press's answer",
        FlashPane.doneFor(waiting, { id: 5, ok: false, phase: "probe", err: "io" }), "refused")
    check("an answer for an older press is not",
        FlashPane.doneFor(waiting, { id: 4, ok: false, phase: "probe", err: "io" }), "ignore")
    check("a running flash's own answer finishes it",
        FlashPane.doneFor({ running: true, transferId: 6, pressSent: false, pendingId: 6 }, { id: 6, ok: true }), "finished")

    // Callout 4: moving onto a drive chooses it, never a refused row, the image or Flash.
    var smallB = stick("sdb", 3, "BBB", "Bravo", "small")
    check("moving onto a usable drive chooses it", FlashPane.driveAt(1, [A, B]) === A, true)
    check("moving onto a refused drive chooses nothing", FlashPane.driveAt(2, [A, smallB]), null)
    check("moving onto the image chooses nothing", FlashPane.driveAt(0, [A, B]), null)
    check("moving onto Flash chooses nothing", FlashPane.driveAt(3, [A, B]), null)
    var hasKept = typeof FlashPane.chooseKept === "function"
    check("a move landing on a drive chooses it", hasKept && FlashPane.chooseKept(1, [A, B], null) === A, true)
    check("a move landing on Flash keeps the kept choice", hasKept && FlashPane.chooseKept(3, [A, B], A) === A, true)
    check("a move landing on Flash keeps the other kept choice", hasKept && FlashPane.chooseKept(3, [A, B], B) === B, true)

    // The ending's figures: where the drive stood, against the total the card drew.
    var known = { bytes: 1200000000, total: 4000000000, known: true, permille: 300 }
    var cancelled = FlashPane.endingContext(known, { err: "cancelled", phase: "write", at: 0 })
    check("a cancel reports the bytes the drive took, the backend's at being 0 there",
        FlashEndings.endingFor("cancelled", cancelled).headline, "Flash cancelled at 1.2 GB of 4.0 GB")
    var packed = { bytes: 1200000000, total: 400000000, known: false, permille: 300 }
    check("an unknown total reads as the card's own estimate, never the packed file's size",
        FlashEndings.endingFor("cancelled", FlashPane.endingContext(packed, { err: "cancelled", at: 0 })).headline,
        "Flash cancelled at 1.2 GB of 4.0 GB")
    check("a verify miss keeps the backend's offset",
        FlashPane.endingContext(known, { err: "verify", at: 2300000000 }).at, 2300000000)
    check("an unplugged drive left where its bytes stood",
        FlashEndings.endingFor("gone", Object.assign({ drive: "128GB" }, FlashPane.endingContext(known, { err: "gone", at: 0 }))).hint,
        "It left at 1.2 GB. Plug it in again and flash again.")

    // The image row's detail names an unpacked size only for a compressed image (Flasher callout 7).
    check("a raw image shows its size alone",
        Flash.imageDetail({ kind: "iso", bytes: 4294967296, unpacked: 4294967296, known: true }), "")
    check("a compressed image with a recorded size shows it unpacked",
        Flash.imageDetail({ kind: "xz", bytes: 1200000000, unpacked: 5900000000, known: true }), "5.9 GB unpacked")
    check("a compressed image without one shows nothing",
        Flash.imageDetail({ kind: "gz", bytes: 812400000, unpacked: 0, known: false }), "")

    // The Flash row's label ink: the erase line is the warning's red, as its triangle is.
    check("the erase line draws in the warning red", Flash.stepRole(false, null), "error")
    check("the running head draws in the foreground", Flash.stepRole(true, null), "foreground")
    check("a failure ending draws in red", Flash.stepRole(false, { role: "error" }), "error")
    check("done draws in the foreground", Flash.stepRole(false, { role: "foreground" }), "foreground")

    // A rail volume names its whole disk, partitioned or not.
    check("a partitionless card names itself", Flash.railDisk("/dev/mmcblk0"), "mmcblk0")
    check("an NVMe namespace names itself", Flash.railDisk("/dev/nvme0n1"), "nvme0n1")
    check("a loop device names itself", Flash.railDisk("/dev/loop0"), "loop0")
    check("a partition of a disk lettered p names that disk", Flash.railDisk("/dev/sdp1"), "sdp")
    check("an NVMe partition names its namespace", Flash.railDisk("/dev/nvme0n1p2"), "nvme0n1")
    check("a loop partition names its loop", Flash.railDisk("/dev/loop0p1"), "loop0")
    check("a partition names its disk", Flash.railDisk("/dev/sdb12"), "sdb")

    // The card's flash branches, each pinned so deleting it goes red.
    var flushing = Object.assign({ flash: true, running: true, writing: false, phase: "flush", drive: "128GB",
        name: "debian-13.iso", bytes: 4000000000, total: 4000000000, known: true, permille: 1000 })
    var drawnFlush = Object.assign({}, flushing, FlashCard.render(flushing, 0))
    check("the card dims Cancel in the final flush", Transfer.cancelEnabled(drawnFlush), false)
    var writing = Object.assign({}, flushing, { phase: "write", bytes: 1200000000, permille: 300 })
    var drawnWrite = Object.assign({}, writing, FlashCard.render(writing, 0))
    check("the card draws the flash's own file line", Transfer.fileLine(drawnWrite), "debian-13.iso · 4.0 GB")
    check("a pre-rendered file line wins over the copy's own", Transfer.fileLine({ fileText: "Flashing", name: "copy.txt", total: 10 }), "Flashing")
    check("with no image the walk up from the first drive stays on it",
        Flash.step(1, -1, [A], false, true), 1)

    function flxMenu(member) {
        return Menu.listingEntries({ hasRow: true, selectionCount: 1, rowMode: 0o100644, clipboardAvailable: false,
            rowIsSymlink: false, rowName: "bundle.zip", flashZipMember: member,
            hiddenActions: ["delete", "openTerminal", "moveto", "copyto", "properties", "permissions",
                "copyAs", "pasteAs", "invertSelection"],
            archiveFormats: ["zip"], canExtract: false, rowIsArchive: true, rowIsImage: false, canConvert: false,
            taildropInstalled: false, taildropPeers: [], dropboxInstalled: false, dropboxPath: "", rowInDropbox: false })
    }
    function flxHas(rows) { return rows.filter(function (r) { return r.action === "flashDrive" }).length > 0 }
    check("Flash to drive shows on the kept member", flxHas(flxMenu("disk.img")), true)
    check("two members show no row", flxHas(flxMenu("")), false)
    check("a non-image member shows no row", flxHas(flxMenu("notes.txt")), false)
}
