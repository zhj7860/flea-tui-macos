.pragma library

.import "Format.js" as Format

// The archive cards' own sentences and leaves, built with the first compress or password card so a launch compiles none of it.

// One whole sentence per count for the compress card's title, so no caller joins a fragment.
function compressTitle(count) {
    if (count === 1) return "Compress 1 item"
    return "Compress %1 items".replace("%1", Format.count(count))
}

// The extract card's title, from the same template rule.
function encryptedTitle(leaf) {
    return "%1 is encrypted".replace("%1", leaf)
}

// The card's sentence for a wrong answer, one template filled once.
function wrongPasswordSentence(leaf) {
    return "That password did not open %1.".replace("%1", leaf)
}

// The leaf of one path, the one cut every leaf reader shares.
function leafOf(path) {
    var text = String(path)
    var cut = text.lastIndexOf("/")
    return cut >= 0 ? text.substring(cut + 1) : text
}

// The leaf of the archive a card was opened over.
function sourceLeaf(source) {
    return leafOf(source && source.path ? source.path : "")
}

// The leaf of each resolved path, for a card opened over more than one file.
function pathLeaves(paths) {
    var out = []
    var list = paths || []
    for (var i = 0; i < list.length; i++) out.push(leafOf(list[i]))
    return out
}

// What a second password request is told while a card is open, one sentence for compress and extract alike.
var CARD_BUSY = "Another archive is waiting for its password. Enter it, then try again."
