.pragma library

.import "Mounts.js" as Mounts

// A drop target's device is the backend's stat of it, symlinks followed; this keeps the answers and runs no stat.

// Sample input: normalize("/run/media/gm/USB/") is "/run/media/gm/USB".
function normalize(path) {
    var p = String(path || "").replace(/\/+$/, "")
    return p.length > 0 ? p : (String(path || "").charAt(0) === "/" ? "/" : "")
}

// Sample input: askPaths("/home/u/docs") is ["/", "/home", "/home/u"]; a listing under a gvfs mount asks nothing, so its crumbs copy.
function askPaths(listing) {
    var p = normalize(listing)
    if (p.charAt(0) !== "/" || p === "/" || Mounts.underGvfs(p)) return []
    var out = ["/"]
    for (var at = p.indexOf("/", 1); at > 0; at = p.indexOf("/", at + 1)) out.push(p.substring(0, at))
    return out
}

// Sample input: merged({"/": 5}, {"/home": 6}) is {"/": 5, "/home": 6}; past 256 paths the older answers go whole.
function merged(known, answered) {
    var out = {}
    var old = known || {}
    if (Object.keys(old).length <= 256) for (var path in old) out[path] = old[path]
    for (var key in (answered || {})) out[key] = answered[key]
    return out
}

// Sample input: without({"/": 5, "/home": 6}, ["/home"]) is {"/": 5}; an asked path reads unknown, and so copies, until its new answer lands.
function without(known, paths) {
    var out = {}
    var old = known || {}
    for (var path in old) out[path] = old[path]
    for (var i = 0; i < (paths || []).length; i++) delete out[normalize(paths[i])]
    return out
}

// Sample input: devFor({"/home": 66306}, "/home/") is 66306, and 0 for a path nobody answered, which makes the plain drop copy.
function devFor(known, path) {
    var dev = known ? Number(known[normalize(path)]) : 0
    return dev > 0 ? dev : 0
}

// Sample input: folderAsks([{n: "deep", d: true}, {n: "a.txt", d: false}, {n: "big", d: true, v: 5}], "/home/u", 0, 2, pane) is ["/home/u/deep"]; a file, a row with its own device and a row out of view ask nothing.
function folderAsks(rows, dir, first, last, pane) {
    var out = []
    for (var i = Math.max(0, first); i <= last && i < (rows || []).length; i++)
        if (rows[i].d === true && !rows[i].v) out.push(pane.join(dir, rows[i].n))
    return out
}
