.pragma library

.import "Format.js" as Format
.import "CopyAs.js" as CopyAs
.import "Ops.js" as Ops

// The Compare overlay's text and rows: ui/CompareView.qml draws what these return and keeps no wording of its own.

// The board's sentences for a pair with no patch, by the backend's state (src/backend/compare.rs).
var SENTENCES = {
    identical: "The two files are identical.",
    binary: "These files are binary, so there is nothing to compare.",
    over: "These files are over 1 MiB, too large to compare.",
    failed: "These files could not be compared."
}

var HUNK = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/

function sentence(state) {
    return SENTENCES[state] || ""
}

// Fills %1, %2 ... in one pass, so a file name holding "%2" is never read as a placeholder.
function fill(template, values) {
    return template.replace(/%(\d)/g, function (whole, n) { return values[Number(n) - 1] })
}

// "notes-a.md and notes-b.md · 12 lines differ" with a patch; without one, the two names alone.
// Sample input: title("a.md", "b.md", 1) gives "a.md and b.md · 1 line differs".
function title(nameA, nameB, differing) {
    if (differing === undefined || differing === null)
        return fill("%1 and %2", [nameA, nameB])
    var count = fill(Ops.pluralWord(differing, "%1 line differs", "%1 lines differ"), [Format.count(differing)])
    return fill("%1 and %2 · %3", [nameA, nameB, count])
}

// What diff -u prints, as the rows the overlay draws; the --- and +++ lines are the copied patch's, not rows.
// Sample input: "--- a\n+++ b\n@@ -1,2 +1,2 @@\n x\n-y\n+z\n" gives a hunk row, a context row 1/1, a removed row 2/0 and an added row 0/2.
function rows(patch) {
    var out = [], oldAt = 0, newAt = 0, inHunk = false
    var lines = String(patch).split("\n")
    if (lines[lines.length - 1] === "")
        lines.pop()
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i], head = HUNK.exec(line)
        if (head) {
            oldAt = Number(head[1])
            newAt = Number(head[3])
            inHunk = true
            out.push({ kind: "hunk", oldNo: 0, newNo: 0, text: line })
        } else if (!inHunk) {
            continue
        } else if (line.charAt(0) === "-") {
            out.push({ kind: "removed", oldNo: oldAt++, newNo: 0, text: line.substring(1) })
        } else if (line.charAt(0) === "+") {
            out.push({ kind: "added", oldNo: 0, newNo: newAt++, text: line.substring(1) })
        } else if (line.charAt(0) === "\\") {
            out.push({ kind: "note", oldNo: 0, newNo: 0, text: line })
        } else {
            out.push({ kind: "context", oldNo: oldAt++, newNo: newAt++, text: line.substring(1) })
        }
    }
    return out
}

// The removed plus added lines, which is what the title counts.
function changed(rowList) {
    return rowList.filter(function (r) { return r.kind === "removed" || r.kind === "added" }).length
}

// The file name a title shows for a path.
function leaf(path) {
    return CopyAs.leaf(path)
}
