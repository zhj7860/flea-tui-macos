.pragma library

.import "Format.js" as Format

// The model behind ui/FlashView.qml, checked headless; every string is a whole template filled by one function.

// One pass over the placeholders, so a value that holds a placeholder is never read twice.
function fill(template, values) {
    return String(template).replace(/\{(\w+)\}/g, function (whole, key) {
        return Object.prototype.hasOwnProperty.call(values, key) ? String(values[key]) : whole
    })
}

function leaf(path) {
    var cut = String(path || "").lastIndexOf("/")
    return cut >= 0 ? String(path).substring(cut + 1) : String(path)
}

// A drive fits when the backend refused it for no reason.
function fits(drive) {
    return !drive || drive.refused === ""
}

// An SD card reports through mmcblk, so its read-only row names the lock switch.
function isCard(dev) {
    return String((dev || "")).indexOf("mmcblk") === 0
}

// Refusal hints, each one whole sentence.
var HINT_SMALL = "It is too small for the image."
var HINT_LOCK = "Its lock switch is on. Slide the switch off and plug the card in again."
var HINT_READONLY = "It is read-only, so Flea cannot write to it."
var HINT_HOLDS_IMAGE = "The image is on this drive. Copy it elsewhere first."
var HINT_MEMBER = "It is part of a RAID or volume group."
var HINT_NOT_IMAGE = "This file is not a disk image."

// The refusal hint under a refused drive row, the boards' own wording.
function refusedHint(drive) {
    var refused = drive ? drive.refused : ""
    if (refused === "small")
        return HINT_SMALL
    if (refused === "readonly")
        return isCard(drive.dev) ? HINT_LOCK : HINT_READONLY
    if (refused === "holdsimage")
        return HINT_HOLDS_IMAGE
    if (refused === "member")
        return HINT_MEMBER
    return ""
}

// The label, or the model where no volume label names it; a repeated label gains the kernel name.
function driveName(drive, drives) {
    var label = drive.label && drive.label.length > 0 ? drive.label : drive.model
    var twins = 0
    for (var i = 0; i < (drives || []).length; i++) {
        var other = drives[i].label && drives[i].label.length > 0 ? drives[i].label : drives[i].model
        if (other === label)
            twins += 1
    }
    return twins > 1 ? fill("{label} ({dev})", { label: label, dev: drive.dev }) : label
}

// The detail column, empty when it would repeat the label.
function driveDetail(drive, drives) {
    var model = drive.model || ""
    return model === driveName(drive, drives) ? "" : model
}

// The compressed image's unpacked size in the detail column.
function unpackedLine(bytes) {
    return fill("{size} unpacked", { size: Format.size(bytes) })
}

// One drive that fits is chosen for you; with two or more none is.
function preselect(drives) {
    var found = -1
    for (var i = 0; i < (drives || []).length; i++) {
        if (!fits(drives[i]))
            continue
        if (found >= 0)
            return -1
        found = i
    }
    return found
}

// Cursor positions: 0 is the image, 1 to n the drives, n + 1 the Flash step.
function flashPos(driveCount) {
    return 1 + (driveCount || 0)
}

// The cursor walk skips refused rows, so a refused drive is never the choice.
function step(cursor, delta, drives, hasImage, flashLive) {
    var count = flashPos((drives || []).length) + 1
    var at = cursor + delta
    while (at >= 0 && at < count) {
        if (at === 0 && hasImage)
            return at
        if (at > 0 && at <= (drives || []).length && fits(drives[at - 1]))
            return at
        if (at === flashPos((drives || []).length) && flashLive)
            return at
        at += delta
    }
    return cursor
}

// Flash is live only when an image and a fitting drive are both chosen.
function flashLive(imageOk, drive) {
    return imageOk === true && !!drive && fits(drive)
}

// The greyed row names the chosen drive, or the drive in general when none is chosen.
var ERASE_NAMED = "Erases everything on {drive}"
var ERASE_BARE = "Erases everything on the drive"
var FLASH_NAMED = "Flash {drive}"
var FLASH_BARE = "Flash"

function flashWords(imageOk, drive, drives) {
    var name = drive ? driveName(drive, drives) : ""
    if (!imageOk || !name)
        return { erase: ERASE_BARE, action: FLASH_BARE }
    return { erase: fill(ERASE_NAMED, { drive: name }), action: fill(FLASH_NAMED, { drive: name }) }
}

// Ending headlines and hints live in ui/js/FlashEndings.js, beside the table they serve.

// The card's heads and byte lines: one template each, {f:key} spans ink as figures.
var FLASH_HEAD_WRITING = "Flashing {drive}"
var FLASH_HEAD_VERIFYING = "Verifying {drive}"
var FLASH_WAIT_PASSWORD = "waiting for your password"
var FLASH_FILE_KNOWN = "{name} · {size}"
var FLASH_FLUSH_LINE = "{f:bytes} written · waiting for the drive"
var FLASH_KNOWN_LINE = "{f:moved} of {f:total} · {f:rate}{f:unit} · {f:left} left"
var FLASH_KNOWN_STALLED = "{f:moved} of {f:total} · {f:rate}{f:unit}"
var FLASH_UNKNOWN_LINE = "{f:moved} written · {f:rate}{f:unit} · {f:left} left"
var FLASH_UNKNOWN_STALLED = "{f:moved} written · {f:rate}{f:unit}"

// The status bar counts the pane's drives, never the covered folder: whole-sentence variants.
var DRIVES_LINE = "{count} drives"
var ONE_DRIVE_LINE = "1 drive"

// A second pane cannot take the host while a flash runs.
var ALREADY_RUNNING = "A flash is already running. Wait for it to finish."

function drivesLine(n) {
    return n === 1 ? ONE_DRIVE_LINE : fill(DRIVES_LINE, { count: Format.count(n) })
}

function alreadyRunning() {
    return ALREADY_RUNNING
}

// A rail volume names its whole disk: sda1 is sda, sdp1 is sdp, nvme0n1p2 is nvme0n1, and mmcblk0 names itself.
function railDisk(device) {
    var name = leaf(device)
    var numbered = /^(.*[0-9])p[0-9]+$/.exec(name)
    if (numbered)
        return numbered[1]
    var lettered = /^((?:sd|vd|hd|xvd)[a-z]+)[0-9]+$/.exec(name)
    return lettered ? lettered[1] : name
}

// The unpacked size shows only for a compressed image whose file records it; a raw image's size is its own.
function imageDetail(image) {
    var raw = !image || image.kind === "iso" || image.kind === "img"
    return !raw && image.known === true && image.unpacked > 0 ? unpackedLine(image.unpacked) : ""
}

// The card's image from a flashimage reply, or null when the reply answers another file's probe, such as the pane's zip check.
function imageFrom(current, message) {
    if (!current || !message || message.path !== current.path)
        return null
    var kind = message.kind || ""
    return { path: current.path, kind: kind, bytes: message.bytes || 0, unpacked: message.unpacked || 0,
             known: message.known === true, member: message.member || "", refused: kind === "" }
}

// The Flash row's label ink: the erase line wears the warning's red with its triangle, the running head the foreground.
function stepRole(running, ending) {
    if (ending)
        return ending.role
    return running ? "foreground" : "error"
}
