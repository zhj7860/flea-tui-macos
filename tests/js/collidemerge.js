.import "../../ui/js/Collide.js" as Collide
.import "../../ui/js/Ops.js" as Ops
.import "../../ui/js/Status.js" as Status
.import "sourcefixture.js" as Source
.import "collidefixture.js" as Fixture

// Merge holds its transfer across two cards: the first answer walks, the second sends.

function run(check) {
    // Merge: one walk after the first card, one answer on the second, and the transfer carries both.
    var folderPaste = { c: "transfer", op: "copy", paths: ["/s/trip"], dest: "/d/Pictures" }
    check("a Merge asks the walk about the same paths",
          JSON.stringify(Collide.mergeQuestion(folderPaste, null, 7)),
          JSON.stringify({ c: "mergecollisions", id: 7, dest: "/d/Pictures", paths: ["/s/trip"] }))
    var folderRows = { c: "transfer", op: "move", rows: [2], dest: "/d/Pictures", listing: 4 }
    check("a Merge of rows asks about its rows in their numbering",
          JSON.stringify(Collide.mergeQuestion(Collide.waiting(folderRows, 4), null, 7)),
          JSON.stringify({ c: "mergecollisions", id: 7, dest: "/d/Pictures", rows: [2], listing: 4 }))
    check("the merge transfer carries the second card's answer",
          JSON.stringify(Collide.mergeTransfer(folderPaste, "keep", 7)),
          JSON.stringify({ c: "transfer", op: "copy", paths: ["/s/trip"], dest: "/d/Pictures", collide: "merge", collideId: 7, inner: "keep" }))
    check("the second card names the one merging folder",
          Collide.mergeDest(folderPaste, [{ n: "trip", d: true }]), "/d/Pictures/trip")
    check("several merging folders name the destination instead",
          Collide.mergeDest(folderPaste, [{ n: "a", d: true }, { n: "b", d: true }]), "/d/Pictures")
    check("a trailing slash never doubles one", Collide.mergeDest({ dest: "/d/" }, [{ n: "trip", d: true }]), "/d/trip")
    check("a refused merge walk drops the wait, so the next paste may ask again",
          Collide.droppedPending("stale", "mergecollisions"), true)

    // The board's own line after a merge, word for word.
    check("a merge names what landed and where",
          Collide.merged(212, 0, "trip", 0, 0, false),
          "Merged 212 items into trip · z undoes")
    check("one merged item reads as its own sentence",
          Collide.merged(1, 0, "trip", 0, 0, false),
          "Merged 1 item into trip · z undoes")
    check("kept both rides beside it",
          Collide.merged(212, 3, "trip", 0, 0, false),
          "Merged 212 items into trip · 3 kept both · z undoes")
    check("a partial merge reports both halves and is still undoable",
          Collide.merged(210, 3, "trip", 2, 0, false),
          "Merged 210 items into trip · 3 kept both · 2 failed · z undoes")
    check("a merge that landed nothing offers no undo",
          Collide.merged(0, 0, "trip", 1, 0, false),
          "Merged 0 items into trip · 1 failed")
    check("a cancelled merge says so and keeps what it landed",
          Collide.merged(40, 0, "trip", 0, 5, true),
          "Merged 40 items into trip · 5 skipped · cancelled · z undoes")

    // The done line is decided by the transferdone line itself: into rides only on a merge.
    var copy = { moving: false, n: 2 }
    check("one merging folder names itself",
          Collide.doneLine(copy, { into: "trip", merged: 212, keptBoth: 0, ok: 1, failed: 0, skipped: 0, cancelled: false }),
          "Merged 212 items into trip · z undoes")
    check("several merging folders name the destination they folded into",
          Collide.doneLine(copy, { into: "Pictures", merged: 40, keptBoth: 3, ok: 2, failed: 0, skipped: 0, cancelled: false }),
          "Merged 40 items into Pictures · 3 kept both · z undoes")
    check("an ordinary copy after an unanswered merge reads as a copy",
          Collide.doneLine(copy, { into: "", merged: 0, keptBoth: 0, ok: 2, failed: 0, skipped: 0, cancelled: false }),
          "Copied 2 items · z undoes")
    check("and it keeps the verdict note the drive carried",
          Collide.doneLine(copy, { into: "", merged: 0, keptBoth: 0, ok: 2, failed: 0, skipped: 0, cancelled: false,
                               durable: false, note: "rclone uploads them in the background" }),
          "Copied 2 items · rclone uploads them in the background · z undoes")

    // A merge onto a drive that reports still says so beside the counts.
    check("a merge onto rclone keeps the drive's verdict",
          Collide.doneLine(copy, { into: "trip", merged: 212, keptBoth: 0, ok: 1, failed: 0, skipped: 0, cancelled: false,
                                   durable: false, note: "rclone uploads them in the background" }),
          "Merged 212 items into trip · rclone uploads them in the background · z undoes")

    // The journaled op "merge" reaches the bar as whole sentences.
    check("undo words a merge whole", Ops.undone("merge"), "Undid the merge")
    // The shipped redo handler runs under doubles, so a rewording for one op goes red.
    var redone = eval("(function (pane, Ops, Status, op, ok) {"
        + Source.block(Source.source("ui/PaneWire.qml"), "function onRedone(op, ok)", "ui/PaneWire.qml") + "})")
    function redoneRun(op) {
        var run = { said: "", refreshed: null }
        var pane = { transfer: null,
            sticky: function () {},
            refresh: function (path, changed) { run.refreshed = changed },
            message: function (text) { run.said = text } }
        redone(pane, Ops, Status, op, true)
        return run
    }
    check("redo words a copy beside the undo hint", redoneRun("copy").said, "Redid the copy" + Status.undoHint())
    check("redo words a move beside the undo hint", redoneRun("move").said, "Redid the move" + Status.undoHint())
    check("redo words a merge beside the undo hint", redoneRun("merge").said, "Redid the merge" + Status.undoHint())
    check("redo refreshes the listing only after permissions", redoneRun("permissions").refreshed, true)
    check("and not after an ordinary op", redoneRun("copy").refreshed, false)

    mergeFlow(check)

    // A hidden Merge never holds the ring: h, l, Tab and Backtab skip it.
    check("a hidden Merge is skipped to the right", Collide.moved("keep", Qt.Key_L), "replace")
    check("a shown Merge takes it", Collide.moved("keep", Qt.Key_L, true), "merge")
    check("a hidden Merge is skipped on Tab round", Collide.moved("keep", Qt.Key_Tab), "replace")
}

// Merge holds its transfer across two cards: the first answer walks, the second sends.
function mergeFlow(check) {
    var at = Fixture.scene(7)
    var backend = at.backend, p = at.pane
    p.collide.ask({ c: "transfer", op: "copy", paths: ["/s/trip"], dest: "/d/Pictures" }, null, false)
    check("a paste asks first", Fixture.verbs(backend), "collisions")
    p.collide.decide("merge")
    check("Merge sends the walk, not the transfer",
          Fixture.verbs(backend), "collisions,mergecollisions")
    var walked = backend.sent[1] || {}
    check("the walk names the same sources in the same destination",
          walked.c + " " + JSON.stringify(walked.paths) + " " + walked.dest, "mergecollisions [\"/s/trip\"] /d/Pictures")
    check("and the transfer stays waiting on the second card", p.collide.pending !== null && p.collide.merging, true)
    p.collide.decideMerge("keep")
    var transfer = backend.sent[2] || {}
    check("Keep both sends the merge with the second answer on it",
          transfer.c + " " + transfer.collide + " " + transfer.inner + " " + transfer.collideId, "transfer merge keep 1")
    check("and lets go of the wait", p.collide.pending === null && p.collide.merging === false, true)
    p.collide.ask({ c: "transfer", op: "move", paths: ["/s/trip"], dest: "/d/Pictures" }, null, true)
    p.collide.decide("merge")
    p.collide.decideMerge("cancel")
    check("a Cancel on the second card writes only its two questions and keeps the cut",
          Fixture.verbs(backend) + "|" + (p.collide.pending === null) + "|" + p.clipboard.paths.length,
          "collisions,mergecollisions,transfer,collisions,mergecollisions|true|1")
    at.parent.destroy()
}
