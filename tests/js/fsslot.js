.import "../../ui/js/Nav.js" as Nav
.import "../../ui/js/Messages.js" as Messages
.import "nav.js" as NavSuite
.import "sourcefixture.js" as Source

// The status bar's filesystem slot: a folder's first frame carries its fs facts or an empty slot, never unknown.

var onFsInfoBody = Source.block(Source.source("ui/PaneWire.qml"),
    "function onFsInfo(fs, free, path, storageClass, tagable, systemVolume)", "ui/PaneWire.qml")

// A pane as ui/Pane.qml starts it: no path, nothing answered.
function fresh(listing) {
    return { path: "", listingPath: listing || "", listInFlight: listing !== undefined, recentMode: "", fsName: "", fsFree: 0,
             fsAnswered: false, storageClass: "", storageKnown: false, systemVolume: false, canTag: false, extVerdict: "", listArea: null }
}

// Sample output, src/backend/fsinfo.rs: {"t":"fsinfo","fs":"tmpfs","free":64100000,"path":"/fx/v/work","class":"","tagable":true}
function answer(pane, path, fs) {
    var onFsInfo = new Function("root", "pane", "ExtThumbs", "ViewState",
        "return function (fs, free, path, storageClass, tagable, systemVolume) {" + onFsInfoBody + "}")(
        { pane: pane }, pane, { verdict: function () { return "" } }, { preview: "" })
    Messages.route({ fsInfo: onFsInfo }, { t: "fsinfo", fs: fs, free: fs ? 64100000 : 0, path: path, "class": "", tagable: true })
}

function run(check) {
    // The line follows its listing's, and a drawn loading mark keeps the rows, and so pane.path, behind it.
    var marked = fresh("/fx/v/work")
    answer(marked, "/fx/v/work", "tmpfs")
    check("a line for the listing out lands while the mark still holds the rows", marked.fsName + "|" + marked.fsAnswered + "|" + marked.storageKnown, "tmpfs|true|true")

    var other = fresh("/fx/v/work")
    answer(other, "/elsewhere", "ext4")
    check("a late line for a superseded folder leaves the slot pending while the listing is out", other.fsName + "|" + other.fsAnswered + "|" + other.storageKnown, "|false|false")
    other.listInFlight = false
    answer(other, "/elsewhere", "ext4")
    check("with no listing out, a line for another folder is answered empty", other.fsName + "|" + other.fsAnswered + "|" + other.storageKnown, "|true|false")

    var settled = fresh()
    settled.path = "/fx/v/work"
    answer(settled, "/fx/v/work", "tmpfs")
    check("a line for the folder shown lands as it always did", settled.fsName + "|" + settled.storageKnown, "tmpfs|true")

    var refused = fresh("/gone")
    refused.path = "/fx/v/work"
    answer(refused, "/fx/v/work", "tmpfs")
    check("a failed hop keeps the figures of the folder never left", refused.fsName + "|" + refused.fsAnswered, "tmpfs|true")

    var recent = fresh("/")
    recent.recentMode = "results"
    // tests/js/recentmode.js pins that Recent opens with its empty slot answered.
    recent.fsAnswered = true
    answer(recent, "/", "btrfs")
    check("Recent refuses a line and keeps its empty slot answered", recent.fsName + "|" + recent.fsAnswered, "|true")

    // A request for another folder takes the answered mark back, a re-read of the one shown keeps it.
    var moving = NavSuite.pane()
    moving.fsAnswered = true
    Nav.openWithoutHistory(moving, "/home/gm", {})
    check("a re-read of the folder shown keeps its answer", moving.fsAnswered, true)
    moving.listInFlight = false
    Nav.openWithoutHistory(moving, "/home/gm/Work", {})
    check("a request for another folder waits for that folder's line", moving.fsAnswered, false)

    var strip = Source.source("ui/StatusBar.qml")
    check("the slot is empty while pending and unknown only once answered",
          Source.slice(strip, "function fsText()", "function slot()").indexOf('root.fsPending ? "" : "unknown"') >= 0, true)
    check("the window body hands the strip its pane's pending state",
          Source.source("ui/WindowBody.qml").indexOf("fsPending: !view.currentPane.fsAnswered") >= 0, true)
}
