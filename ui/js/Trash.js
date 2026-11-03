.pragma library

.import "KeyName.js" as KeyName
.import "Format.js" as Format
.import "Ops.js" as Ops

// Whole sentences with "%1" for the key that arms and "%2" for the key that acts on its own, filled by Format.fill.
var WORDS = {
    trash: "Press %1 again to move it to Trash, or %2 on its own.",
    review: "Press %1 again to review permanent deletion, or %2 on its own.",
    trashAlone: "Press %1 again to move it to Trash.",
    trashMany: "Press %1 again to move them to Trash, or %2 on its own.",
    trashManyAlone: "Press %1 again to move them to Trash.",
    reviewAlone: "Press %1 again to review permanent deletion.",
    deleteOne: "Delete 1 item permanently?",
    deleteMany: "Delete %1 items permanently?"
}

// The keys come from the running preset: the arming key, and the key that acts at once when the preset binds one; the count of rows the pair would trash picks it or them.
function trashPrompt(count) {
    var alone = KeyName.keyOf("trash", "none"), many = count > 1
    if (alone.length > 0) return Format.fill(many ? WORDS.trashMany : WORDS.trash, KeyName.keyFor("trash"), alone)
    return Format.fill(many ? WORDS.trashManyAlone : WORDS.trashAlone, KeyName.keyFor("trash"))
}
function reviewPrompt() {
    var alone = KeyName.keyOf("trash", "none")
    return alone.length > 0 ? Format.fill(WORDS.review, KeyName.keyFor("trash"), alone) : Format.fill(WORDS.reviewAlone, KeyName.keyFor("trash"))
}

// The dd pair. A single d used to trash, and it sat in the middle of the letters a name is typed
// with, so the third keystroke of "Vid" trashed the row (issue 7). Delete and Ctrl+Delete are not
// letters and still go on one press, through Ops.trash directly.

// How long the first d stays armed. Long enough to be a deliberate pair, short enough that an arm
// nobody finished cannot be completed by a d typed minutes later.
var ARM_MS = 1500

// ui/js/Focus.js clears pane.trashArmedAt for every other action, so an arm never survives the key
// after it; this reads the stamp before it writes one, which is what makes the second press the pair.
function arm(pane) {
    if (pane.trashArmedAt > 0 && Date.now() - pane.trashArmedAt < ARM_MS) {
        pane.trashArmedAt = 0
        Ops.trash(pane)
        return
    }
    pane.trashArmedAt = Date.now()
    pane.armPrompted(trashPrompt(Ops.targetIndices(pane).length))
}

// Window-level keys the Trash view borrows: "direct" skips pane.act as Focus.handleKey does, "act" goes through it, "trash" stays here.
function route(action) {
    if (action === "keymapSheet" || action === "pathBar") return "direct"
    if (action.indexOf("textSize") === 0) return "direct"
    if (action === "settings" || action === "sidebar") return "act"
    if (action.indexOf("tab") === 0) return "act"
    return "trash"
}

// The delete card's words come from a filled snapshot only (R0: the whole filled card or nothing), so an unfilled one says no word at all.
function filled(snapshot) {
    return typeof snapshot.count === "number"
}

// "Empty Trash?", or one whole sentence per count; Format.fill takes the grouped count into the placeholder.
function confirmTitle(snapshot) {
    if (!filled(snapshot)) return ""
    if (snapshot.all) return "Empty Trash?"
    return snapshot.count === 1 ? WORDS.deleteOne : Format.fill(WORDS.deleteMany, Format.count(snapshot.count))
}

function confirmBody(snapshot, scope) {
    if (!filled(snapshot)) return ""
    return snapshot.all ? Ops.deleteAllLine(snapshot.count, Format.size(snapshot.bytes || 0)) : Ops.deleteScopeLine(scope, snapshot.count)
}

// Where m opens: the cursor row's menu when no row is marked or the only mark is the cursor row, the marked rows' menu otherwise, the whole-Trash menu when nothing is listed.
function menuTarget(total, markedCount, cursorMarked) {
    if (total === 0) return "strip"
    if (markedCount === 0 || (markedCount === 1 && cursorMarked)) return "cursor"
    return "marked"
}
