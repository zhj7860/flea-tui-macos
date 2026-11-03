.pragma library

.import "Mounts.js" as Mounts
.import "Format.js" as Format
.import "Protocols.js" as Protocols
.import "NetFs.js" as NetFs

// Whole sentences with "%1" for the drive and "%2" for the drives still mounted under it, filled by Format.fill; the first three are what Ctrl+E answers with when it releases nothing.
var WORDS = {
    systemDrive: "%1 is the system drive, which Flea never unmounts",
    systemVolume: "This folder is on a system volume, which Flea never unmounts",
    noVolume: "This folder is not on a volume Flea can unmount",
    safe: "Ejected %1. It is safe to unplug.",
    safeImage: "Ejected %1.",
    stillMounted: "%1 is still mounted; close what is using it.",
    blockedOne: "%1 could not be ejected because %2 on the same drive is still mounted. Eject that instead.",
    blockedMany: "%1 could not be ejected because %2 on the same drive are still mounted. Eject those instead.",
    unconfirmed: "Could not confirm %1 was ejected; do not unplug it yet."
}

// Sample input: the lsblk --json body ui/js/Mounts.js "parseDevices" reads, taken again after
// gio mount -e returned for /dev/sda1:
// {"blockdevices":[
//   {"name":"sda","path":"/dev/sda","label":null,"mountpoints":[null],"rm":true,"size":"116.1G","type":"disk","model":"USB Flash Disk",
//    "children":[{"name":"sda1","path":"/dev/sda1","label":"128GB","mountpoints":[null],"rm":true,"size":"116.1G","type":"part","model":null}]}]}
// The sda entry is then either gone, or still listed with every mountpoint under it null.
// gio's exit code is never the witness: it has been 0 over a volume that stayed mounted.
// "safe" when nothing under the disk that carries the device is mounted, "mounted" when anything
// under it still is, "unknown" when the body is not a listing this can judge.
function verdict(body, device) {
    var disk = diskOf(body, device)
    if (disk === undefined)
        return "unknown"
    if (disk === null)
        return "safe"
    return anyMounted(disk) ? "mounted" : "safe"
}

// The top-level lsblk node that holds the device: undefined when the body is not a listing, null
// when no node holds it, which is the powered-off shape. The whole disk is what gets judged: gvfs
// ejects the drive, so a sibling partition or a crypt child still mounted means still in use.
function diskOf(body, device) {
    var tree
    try {
        tree = JSON.parse(String(body || ""))
    } catch (e) {
        return undefined
    }
    var nodes = tree && tree.blockdevices
    // A box with no block devices at all is not running, so an empty listing is a broken one.
    if (!Array.isArray(nodes) || nodes.length === 0)
        return undefined
    var name = kernelName(device)
    if (name.length === 0)
        return undefined
    for (var i = 0; i < nodes.length; i++) {
        if (holds(nodes[i], name))
            return nodes[i]
    }
    return null
}

// Both sides of every comparison here come from lsblk's own NAME column. volumeRow carries lsblk's
// PATH now, and a device-mapper volume's path is /dev/mapper/<name>, so the leaf is what is read.
function kernelName(device) {
    var text = String(device || "")
    var cut = text.lastIndexOf("/")
    return cut < 0 ? text : text.substring(cut + 1)
}

function holds(node, name) {
    if (String(node.name) === name)
        return true
    var kids = node.children || []
    for (var i = 0; i < kids.length; i++) {
        if (holds(kids[i], name))
            return true
    }
    return false
}

// lsblk writes "[SWAP]" as a mountpoint of active swap, which is in use like any other mount. This
// asks whether anything holds the volume at all, which is not Mounts.js mountOf's question: that one
// answers where to browse, and swap is nowhere.
function inUse(node) {
    var points = node.mountpoints || []
    for (var i = 0; i < points.length; i++) {
        if (points[i] !== null && String(points[i]).length > 0)
            return true
    }
    return false
}

function anyMounted(node) {
    if (inUse(node))
        return true
    var kids = node.children || []
    for (var i = 0; i < kids.length; i++) {
        if (anyMounted(kids[i]))
            return true
    }
    return false
}

// What the refusal has to name. Empty when the row itself is still mounted, because a re-press on
// it is then the right next step; otherwise the labels of what is still mounted under the same disk,
// because a re-press on a row lsblk now shows unmounted would silently do nothing.
function blockers(body, device) {
    var disk = diskOf(body, device)
    if (!disk)
        return []
    var mounted = []
    collectMounted(disk, mounted)
    var name = kernelName(device)
    for (var i = 0; i < mounted.length; i++) {
        if (mounted[i].name === name)
            return []
    }
    return mounted.map(function (m) { return m.label })
}

function collectMounted(node, out) {
    if (inUse(node))
        out.push({ name: String(node.name), label: node.label ? String(node.label) : String(node.name) })
    var kids = node.children || []
    for (var i = 0; i < kids.length; i++)
        collectMounted(kids[i], out)
}

// Only a real drive's safe verdict may claim it is safe to unplug; an image has nothing to unplug.
// Other verdicts keep their warnings and name a next step only when pressing it does something.
function sentence(v, label, others, loop) {
    if (v === "safe")
        return { text: Format.fill(loop === true ? WORDS.safeImage : WORDS.safe, label), isError: false }
    if (v === "attached") // A loop row unmounted, but its loop device could not be detached.
        return { text: "Unmounted " + label + ", but its loop device is still attached.", isError: true }
    if (v === "mounted") {
        var rest = others || []
        if (rest.length === 0)
            return { text: Format.fill(WORDS.stillMounted, label), isError: true }
        return { text: Format.fill(rest.length > 1 ? WORDS.blockedMany : WORDS.blockedOne, label, rest.join(", ")), isError: true }
    }
    return { text: Format.fill(WORDS.unconfirmed, label), isError: true }
}

// Only a releasable mounted row draws the mark in place of the square.
// Sample input: {label:"NAS", group:"network", kind:"share", uri:"smb://h/data/", mounted:true}.
function releasable(entry) {
    if (!entry || entry.mounted !== true)
        return false
    if (entry.group === "device" && entry.kind === "volume")
        return entry.removable === true || entry.loop === true
    if (entry.group === "device" && entry.kind === "phone")
        return true
    if (entry.group === "network" && entry.kind === "share") {
        // A kernel row names its fstype for the mark split; a gvfs share's scheme decides it.
        if (entry.fstype)
            return NetFs.isCifsFstype(entry.fstype)
        return Protocols.schemeOf(entry.uri) !== "nfs"
    }
    return false
}

// The one-click release mirrors the rows Mounts.railMenu offers.
function releaseAction(entry) {
    if (!releasable(entry))
        return ""
    if (entry.group === "device" && entry.kind === "phone")
        return "unmountPhone"
    return entry.group === "device" ? "eject" : "unmount"
}

// Picked by name, never position (a volume or phone row leads with Open): Eject, else the row's unmount, else "".
function releaseFromRows(rows) {
    var list = rows || []
    for (var i = 0; i < list.length; i++) {
        if (list[i].action === "eject")
            return "eject"
    }
    for (var j = 0; j < list.length; j++) {
        if (list[j].action === "unmount" || list[j].action === "unmountVolume" || list[j].action === "unmountPhone")
            return list[j].action
    }
    return ""
}

// Finder's Cmd+E with Cmd read as Ctrl: from the rail it releases the cursor row, from a listing the
// mounted volume the directory is inside, so the key can never release a volume the operator is
// not looking at. The verdict is Mounts.railMenu's either way, off the lsblk poll, and the release
// goes through the same releaseChosen a chosen menu row takes, carrying the row's key. A hidden rail
// unloads the Sidebar with its poll, verdict state and releaseChosen, so there is nothing to read
// and nothing to release through: the pane spins a transient DeviceMounts for one one-shot listing
// (ui/PaneRail.qml), which completes through this same function with its own entries and
// releaseChosen. A null rail therefore never answers from silence; it hands the key to that flow.
function release(root, rail, fromRail) {
    if (!rail) {
        root.ejectHidden()
        return
    }
    var entry = fromRail ? rail.entries[rail.cursorIndex] : Mounts.holding(rail.entries, root.path)
    if (fromRail && entry && entry.group === "device" && entry.kind === "disk") {
        root.message(Format.fill(WORDS.systemDrive, entry.label), false)
        return
    }
    if (!entry) {
        // The backend alone names a system volume, off the listing's own device; a Recent history spans mounts, so it names none.
        root.message(root.systemVolume === true && root.recentMode === "" ? WORDS.systemVolume : WORDS.noVolume, false)
        return
    }
    var rows = Mounts.railMenu(entry)
    var pick = releaseFromRows(rows)
    if (pick === "") {
        root.message(Format.fill(Mounts.WORDS.nothingToRelease, entry.label), false)
        return
    }
    rail.releaseChosen(pick, Mounts.railKey(entry))
}
