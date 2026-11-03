.pragma library

// Foreign-drop paths and its one refusal sentence; own drags keep their marker and never re-read text/plain.
function usePlain(marker, shelf) {
    return !marker && !shelf
}

// Sample input "file:///d/a%20b.txt" answers "/d/a b.txt"; anything else answers null.
function filePath(url) {
    var text = String(url)
    if (text.indexOf("file://") !== 0) return null
    var rest = text.substring(7)
    var path
    if (rest.charAt(0) === "/") {
        path = rest
    } else {
        var slash = rest.indexOf("/")
        if (slash < 0 || rest.substring(0, slash) !== "localhost") return null
        path = rest.substring(slash)
    }
    try {
        return decodeURIComponent(path)
    } catch (error) {
        return null
    }
}

function filePaths(urls) {
    var paths = []
    if (!urls) return paths
    for (var i = 0; i < urls.length; i++) {
        var path = filePath(urls[i])
        if (path) paths.push(path)
    }
    return paths
}

// Sample input "/a/x.txt\nhttp://e/y\n" answers ["/a/x.txt"]; a line not starting with "/" is left behind.
function plainPaths(plain) {
    var paths = []
    if (!plain) return paths
    var lines = String(plain).split("\n")
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i]
        if (line.charAt(line.length - 1) === "\r") line = line.substring(0, line.length - 1)
        if (line.charAt(0) === "/") paths.push(line)
    }
    return paths
}

function sources(urls, plain, marker, shelf) {
    var paths = filePaths(urls)
    if (!usePlain(marker, shelf)) return paths
    var extra = plainPaths(plain)
    for (var i = 0; i < extra.length; i++) {
        if (paths.indexOf(extra[i]) < 0) paths.push(extra[i])
    }
    return paths
}

// Checked in this order: a folder inside the drag, a file already in the destination, then nothing local.
function refusal(paths, dest, marker, shelf) {
    var i
    for (i = 0; i < paths.length; i++) {
        if (dest === paths[i] || dest.indexOf(paths[i] + "/") === 0)
            return "That folder is inside the drag."
    }
    for (i = 0; i < paths.length; i++) {
        var slash = paths[i].lastIndexOf("/")
        var parent = slash <= 0 ? "/" : paths[i].substring(0, slash)
        if (parent === dest) return "Already in this folder."
    }
    if (paths.length === 0 && usePlain(marker, shelf)) return "That drag has no local files."
    return ""
}

function askAllowed(pathsPending, clipPending) {
    return !pathsPending && clipPending === null
}

// Floor refuses while a listing is out; a hovered tab keeps its stored folder, an unlanded one refuses with the floor.
function refuseLoading(listInFlight, hoverTab, currentTab) {
    if (listInFlight !== true) return false
    if (hoverTab !== true) return true
    return currentTab === true
}

function searchTabEnabled(searchMode, current) {
    return !(searchMode && current)
}

// The top (-1) or bottom (1) band of a listing, which scrolls it with the hover-open setting on or off; 0 elsewhere.
var BAND_PX = 37
function band(y, height) {
    if (height < BAND_PX * 2)
        return 0
    if (y < BAND_PX)
        return -1
    if (y > height - BAND_PX)
        return 1
    return 0
}
// Resting on a folder this long opens it when the setting is on; a move restarts the rest.
var OPEN_MS = 700
function shouldOpen(hoverMs, settingOn, moved) {
    return settingOn && !moved && hoverMs >= OPEN_MS
}

// #259: the drag's modifier transitions, kept here so a launch builds no store; each key is 1 held, 0 released, -1 unseen.
var keys = {
    liftMime: "application/x-flea-lift",
    lifts: 0,
    marker: "",
    lift: "",
    ctrl: -1,
    shift: -1,
    leaving: false,

    // Every drag this window starts carries its own lift number, so two drags of the same rows are never one drag here.
    stamped: function (mime) {
        var out = {}
        for (var key in mime) out[key] = mime[key]
        keys.lifts += 1
        out[keys.liftMime] = String(keys.lifts)
        return out
    },

    // Another drag resets the pair; the same drag keeps what was seen, and an own lift keeps it across gaps between targets.
    enter: function (seen, lifted) {
        var number = lifted || ""
        keys.leaving = false
        if (keys.marker !== seen || keys.lift !== number) {
            keys.marker = seen
            keys.lift = number
            keys.ctrl = -1
            keys.shift = -1
        }
    },

    // A drag with no lift, another app's or an older Flea's, ends at a leave that no enter follows in the same turn.
    leave: function () {
        if (keys.lift !== "") return
        keys.leaving = true
        Qt.callLater(keys.settle)
    },

    settle: function () {
        if (keys.leaving) keys.clear()
    },

    // A drop consumes the drag; taps before any drag never arm tracking because it gates on a marker.
    clear: function () {
        keys.leaving = false
        keys.marker = ""
        keys.lift = ""
        keys.ctrl = -1
        keys.shift = -1
    },

    // The pane funnels its press and release here; the lift bits stay the baseline, so a key held since the lift still counts.
    track: function (event, pressed) {
        if (keys.marker === "") return
        if (event.key === Qt.Key_Control) keys.ctrl = pressed ? 1 : 0
        else if (event.key === Qt.Key_Shift) keys.shift = pressed ? 1 : 0
    }
}
