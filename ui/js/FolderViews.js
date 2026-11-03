.pragma library

// The three layouts a directory can own. Dual pane is a window shape, not a folder view.
var MODES = ["list", "columns", "grid"]
var MAX = 500

function get(views, path) {
    var mode = views ? views[path] : ""
    return MODES.indexOf(mode) >= 0 ? mode : ""
}

function has(views, path) {
    return get(views, path).length > 0
}

// A re-selection moves its folder to the most recent end; past the cap the oldest goes.
function set(views, path, mode) {
    var next = {}
    if (views) {
        for (var key in views) {
            if (key !== path)
                next[key] = views[key]
        }
    }
    next[path] = mode
    var keys = Object.keys(next)
    while (keys.length > MAX)
        delete next[keys.shift()]
    return next
}

// A stored folder preference is opt-in. With it off, the existing global view remains the fallback.
function viewFor(views, path, fallback, remember) {
    if (remember === true) {
        var own = get(views, path)
        if (own)
            return own
    }
    return MODES.indexOf(fallback) >= 0 ? fallback : "list"
}

function shouldRemember(remember, path) {
    return remember === true && !!path
}
