.pragma library

// The unlock probe's reader: pure, over the dialog's items themselves.

// Returns the Passphrase field under item, the one control with takeFocus, text and that label, or null.
function findField(item) {
    if (!item) return null
    if (typeof item.takeFocus === "function" && item.text !== undefined
            && String(item.label || "") === "Passphrase") return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) {
        var found = findField(kids[i])
        if (found) return found
    }
    return null
}
