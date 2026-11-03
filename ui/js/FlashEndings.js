.pragma library

.import "Flash.js" as Flash
.import "Format.js" as Format

// Every ending is a row in the Flash step with its fix in a hint; only the mark reads error.

// Ending headlines and hints, each one whole sentence with placeholders.
var DONE_HEADLINE = "Flashed {image} to {drive}"
var CANCELLED_HEADLINE = "Flash cancelled at {at} of {total}"
var CANCELLED_HINT = "{drive} is blank now. Flash again, or format it in Disks."
var CANCELLED_UNKNOWN_HEADLINE = "Flash cancelled at {at}"
var PREWRITE_CANCELLED_HINT = "The flash was cancelled before it started. Flash again when ready."
var VERIFY_CANCELLED_HEADLINE = "Verify cancelled"
var VERIFY_CANCELLED_HINT = "{image} is on {drive}, not verified."
var NOTHING_WRITTEN = "Nothing was written"
var PASSWORD_CLOSED_HINT = "The password prompt was closed. Flash again to be asked once more."
var UNMOUNT_HEADLINE = "{drive} could not be unmounted"
var BUSY_HINT = "Nothing was written. Close what is using it, then flash again."
var CHANGED_HEADLINE = "{drive} changed since you chose it"
var CHOOSE_AGAIN_HINT = "Nothing was written. Choose the drive again."
var UNPLUGGED_HEADLINE = "{drive} was unplugged"
var LEFT_AT_HINT = "It left at {at}. Plug it in again and flash again."
var IO_HEADLINE = "Could not flash {drive}"
var BLANK_STOP_HINT = "It stopped answering at {at} and is blank now. Plug it in again."
var PARTIAL_STOP_HINT = "It stopped answering at {at} and holds part of the image. Plug it in again and flash again."
var TOO_BIG_HEADLINE = "{image} is larger than {drive}"
var UNPACKED_PAST_HINT = "It unpacked past {size}. Use a larger drive."
var NOT_VERIFY_HEADLINE = "{drive} did not verify"
var VERIFY_HINT = "It read back different data at {at}. Flash again, or use another drive."
var NO_UNPACK_HEADLINE = "Could not unpack {image}"
var NEED_BUBBLE_HEADLINE = "Compressed images need bubblewrap"
var INSTALL_BUBBLE_HINT = "Install bubblewrap, then flash again."
var NO_OPEN_HEADLINE = "Could not open {drive}"

function endingFor(err, ctx) {
    var c = ctx || {}
    var image = c.image || "", drive = c.drive || ""
    var at = Format.size(c.at || 0)
    if (!err)
        return { headline: Flash.fill(DONE_HEADLINE, { image: image, drive: drive }), hint: "",
                 role: "foreground", mark: "check", eject: true, flashBack: false }
    if (err === "cancelled" && c.phase === "verify")
        return { headline: VERIFY_CANCELLED_HEADLINE,
                 hint: Flash.fill(VERIFY_CANCELLED_HINT, { image: image, drive: drive }),
                 role: "foreground", mark: "x", eject: true, flashBack: false }
    // A cancel before the write moved no byte, so no offset reads true.
    if (err === "cancelled" && (c.phase === "prepare" || c.phase === "password"))
        return { headline: NOTHING_WRITTEN, hint: PREWRITE_CANCELLED_HINT,
                 role: "foreground", mark: "x", eject: false, flashBack: true }
    // An unknown total names where it stopped, never the packed file's size.
    if (err === "cancelled" && !(c.total > 0))
        return { headline: Flash.fill(CANCELLED_UNKNOWN_HEADLINE, { at: at }),
                 hint: Flash.fill(CANCELLED_HINT, { drive: drive }),
                 role: "foreground", mark: "x", eject: false, flashBack: true }
    if (err === "cancelled")
        return { headline: Flash.fill(CANCELLED_HEADLINE, { at: at, total: Format.size(c.total || 0) }),
                 hint: Flash.fill(CANCELLED_HINT, { drive: drive }),
                 role: "foreground", mark: "x", eject: false, flashBack: true }
    if (err === "denied")
        return { headline: NOTHING_WRITTEN, hint: PASSWORD_CLOSED_HINT,
                 role: "error", mark: "alert", eject: false, flashBack: true }
    if (err === "busy")
        return { headline: Flash.fill(UNMOUNT_HEADLINE, { drive: drive }), hint: BUSY_HINT,
                 role: "error", mark: "alert", eject: false, flashBack: true }
    if (err === "changed")
        return { headline: Flash.fill(CHANGED_HEADLINE, { drive: drive }), hint: CHOOSE_AGAIN_HINT,
                 role: "error", mark: "alert", eject: false, flashBack: true }
    if (err === "gone")
        return { headline: Flash.fill(UNPLUGGED_HEADLINE, { drive: drive }),
                 hint: Flash.fill(LEFT_AT_HINT, { at: at }),
                 role: "error", mark: "alert", eject: false, flashBack: true }
    if (err === "io")
        return { headline: Flash.fill(IO_HEADLINE, { drive: drive }),
                 hint: Flash.fill(c.blank ? BLANK_STOP_HINT : PARTIAL_STOP_HINT, { at: at }),
                 role: "error", mark: "alert", eject: false, flashBack: true }
    if (err === "nospace")
        return { headline: Flash.fill(TOO_BIG_HEADLINE, { image: image, drive: drive }),
                 hint: Flash.fill(UNPACKED_PAST_HINT, { size: Format.size(c.driveBytes || 0) }),
                 role: "error", mark: "alert", eject: false, flashBack: true }
    if (err === "verify")
        return { headline: Flash.fill(NOT_VERIFY_HEADLINE, { drive: drive }),
                 hint: Flash.fill(VERIFY_HINT, { at: at }),
                 role: "error", mark: "alert", eject: false, flashBack: true }
    if (err === "decompress")
        return { headline: Flash.fill(NO_UNPACK_HEADLINE, { image: image }), hint: String(c.tool || ""),
                 role: "error", mark: "alert", eject: false, flashBack: true }
    if (err === "sandbox")
        return { headline: NEED_BUBBLE_HEADLINE, hint: INSTALL_BUBBLE_HINT,
                 role: "error", mark: "alert", eject: false, flashBack: true }
    return { headline: Flash.fill(NO_OPEN_HEADLINE, { drive: drive }), hint: String(c.tool || ""),
             role: "error", mark: "alert", eject: false, flashBack: true }
}

// A flash that ends while the listing shows reports in the status line as a copy does.
var DONE_LINE = "Flashed {image} to {drive}."
var VERIFY_AGAIN_LINE = "{drive} did not verify; flash it again."
var EJECTED_LINE = "Ejected {drive}. It is safe to unplug."
var STILL_MOUNTED_LINE = "{drive} is still mounted; close what is using it."
var EJECT_FAILED_LINE = "Could not eject {drive}."

function ejectDoneLine(drive) {
    return Flash.fill(EJECTED_LINE, { drive: drive })
}

function ejectBusyLine(drive) {
    return Flash.fill(STILL_MOUNTED_LINE, { drive: drive })
}

function ejectFailedLine(drive) {
    return Flash.fill(EJECT_FAILED_LINE, { drive: drive })
}

function statusFor(err, ctx) {
    var ending = endingFor(err, ctx)
    if (!err) {
        var c = ctx || {}
        return { text: Flash.fill(DONE_LINE, { image: c.image || "", drive: c.drive || "" }), isError: false }
    }
    if (err === "cancelled")
        return { text: Flash.fill("{headline}.", { headline: ending.headline }), isError: false }
    if (err === "verify")
        return { text: Flash.fill(VERIFY_AGAIN_LINE, { drive: (ctx || {}).drive || "" }), isError: true }
    return { text: Flash.fill("{headline}.", { headline: ending.headline }), isError: true }
}
