.import "../../ui/js/Messages.js" as Messages
.import "../../ui/js/SlowOp.js" as SlowOp
.import "sourcefixture.js" as Source

function run(check) {
    var calls = []
    var root = { slowOp: function(op, path, msg) { calls.push([op, path, msg]) },
        renamed: function() {}, made: function() {}, linked: function() {} }
    Messages.route(root, {t: "slow", op: "rename", path: "/hung/a.txt", msg: "/hung is slow. The rename will finish on its own."})
    check("a slow line reaches the slow handler with its op, path and sentence",
          JSON.stringify(calls),
          JSON.stringify([["rename", "/hung/a.txt", "/hung is slow. The rename will finish on its own."]]))
    calls = []
    Messages.route(root, {t: "slow"})
    check("a slow line with no fields still reaches the handler rather than throwing",
          JSON.stringify(calls), JSON.stringify([["", "", ""]]))
    var renamed = [], made = [], linked = []
    root.renamed = function(ok, path) { renamed.push([ok, path]) }
    root.made = function(ok, path) { made.push([ok, path]) }
    root.linked = function(ok, failed, skipped) { linked.push([ok, failed, skipped]) }
    Messages.route(root, {t: "renamed", ok: true, path: "/hung/b.txt"})
    Messages.route(root, {t: "made", ok: true, path: "/hung/New Folder"})
    Messages.route(root, {t: "linked", ok: 2, failed: 0, skipped: 0})
    check("the late replies still reach their own handlers after the slow branch lands",
          JSON.stringify([renamed, made, linked]),
          JSON.stringify([[[true, "/hung/b.txt"]], [[true, "/hung/New Folder"]], [[2, 0, 0]]]))

    // The shipped handler only posts the sentence, so the request it leaves open is the one the late reply closes.
    var wire = Source.source("ui/PaneWire.qml")
    check("the slow line shows its sentence as information, never as an error, and leaves the rename request open",
          wire.indexOf("function onSlowOp(op, path, msg) { pane.message(msg, false) }") >= 0, true)
    var request = {source: "/hung/a.txt", destination: "/hung/b.txt", folder: "/hung"}
    check("a renamed line for that destination closes it",
          SlowOp.closesRename(request, "/hung/b.txt"), true)
    check("and any other path leaves it open",
          SlowOp.closesRename(request, "/hung/c.txt"), false)
    check("with no request open nothing closes",
          SlowOp.closesRename(null, "/hung/b.txt"), false)

    // The pdfcopied lines src/backend/pdfcopy.rs pins in its own test reach the viewer with stalled set only by the wait that ran out.
    var copies = []
    root.pdfCopied = function (id, path, err, stalled) { copies.push([id, path, err, stalled]) }
    var rust = Source.source("src/backend/pdfcopy.rs")
    var wire = /r#"(\{"t":"pdfcopied".*?)"#/g
    var line
    while ((line = wire.exec(rust)) !== null)
        Messages.route(root, JSON.parse(line[1]))
    check("a copy, a refusal and a stalled wait route with only the wait marked stalled", JSON.stringify(copies),
          JSON.stringify([[3, "/x/doc.pdf", "", false], [3, "", "permission denied", false], [3, "", "that file is not responding", true]]))
}
