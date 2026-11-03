.import "../../ui/js/Archive.js" as Archive
.import "../../ui/js/ArchiveOps.js" as ArchiveOps
.import "../../ui/js/ArchiveCard.js" as ArchiveCard
.import "../../ui/js/Errors.js" as Errors
.import "../../ui/js/Anchor.js" as Anchor
.import "../../ui/js/Nav.js" as Nav
.import "../../ui/js/Swap.js" as Swap
.import "../../ui/js/Ops.js" as Ops
.import "archivefixture.js" as Fixture
.import "sourcefixture.js" as Source

// The password cards, the backend's queue and the done line driven through the real QML, so a reworded source cannot pass.
var CANARY = "S3cr3t-canary-1006"
var CARDS_STATE_KEYS = "opened|compressOpened|extractOpened|compressCount|compressFormat|compressError|compressFocus"
    + "|canCompress|compressCapture|extractLeaf|extractError|extractFocus|extractCapture|canExtract"

// A call that throws is one failed check, not a harness that dies without a tally.
function attempt(call) {
    try { return call() } catch (e) { return "threw: " + e }
}

// Whether any value of a cards state reply holds the canary, a nested capture state included.
function leaks(state) {
    var parsed = JSON.parse(state)
    return Object.keys(parsed).filter(function (key) { return JSON.stringify(parsed[key]).indexOf(CANARY) >= 0 })
}

function run(check) {
    var parent = Qt.createComponent("QtQuick", "Item").createObject(null)
    var sent = []
    var said = []
    var paneA = Fixture.pane("a", sent, said)
    var paneB = Fixture.pane("b", sent, said)
    var cards = Fixture.cards(parent)

    // B F20: the Extract button's accepted(source, password) reaches ArchiveOps.submitExtractPassword through the host.
    cards.openExtractPassword({ path: "/a/backup.7z", dest: "/a/backup" }, paneA, "")
    cards.extractItem.takeSecretForTest("s3cret")
    cards.extractItem.submitItem.activated()
    check("F20: Extract sends the archive, destination and password the card was opened over",
          sent.join(","), "a|extract|/a/backup.7z|/a/backup|s3cret|0")
    check("F20: and the card closes with its field cleared",
          [cards.extractItem.opened, cards.extractItem.password, cards.extractItem.source].join("|"), "false||")

    // B F22: one card at a time; a second pane's open is refused and the first card's submit stays with the first pane.
    sent.length = 0
    cards.askCompressPassword(paneA, ["/a/x", "/a/y"], 4)
    cards.askCompressPassword(paneB, ["/b/z"], 9)
    check("F22: a second pane's compress is refused with the busy sentence",
          said.join(","), "b:" + ArchiveCard.CARD_BUSY)
    check("F22: and the open card stays the first pane's",
          [cards.compressOwner === paneA, cards.compressItem.count, cards.cardBusy(paneB)].join("|"), "true|2|true")
    cards.compressItem.takeSecretForTest("s3cret")
    cards.compressItem.submitItem.activated()
    check("F22: the first card's Compress still goes to the first pane",
          sent.join(","), "a|compress|/a/x,/a/y|/a/a.7z|7z|s3cret|true|4")
    // B F22: an empty pair never compresses; Compress names the missing password and the card stays open.
    sent.length = 0
    cards.askCompressPassword(paneA, ["/a/x"], 5)
    cards.compressItem.submitItem.activated()
    check("F22: Compress with no password sends nothing and asks for one",
          [sent.length, cards.compressItem.canCompress, cards.compressItem.errorText, cards.compressItem.opened].join("|"),
          "0|false|Type a password first.|true")
    cards.compressItem.close()
    // B F22: a With-password compress whose selection resolved to no paths says so and opens no card.
    said.length = 0
    var emptyPane = Fixture.pane("e", sent, said)
    emptyPane.cursorIndex = -1
    ArchiveOps.compressPasswordResolved(cards, emptyPane, [], 3)
    check("F22: an empty resolved selection says there is nothing to act on and opens no card",
          said.join(",") + "|" + cards.compressItem.opened, "e:There is nothing to act on.|false")

    // B F23: the IPC reader returns its fixed keys and never a typed secret, whichever card holds it.
    var ipcText = Source.source("ui/Ipc.qml")
    var stateBody = Source.block(ipcText, "function archiveCardsState()", "ui/Ipc.qml")
    var cardsState = eval("(function (root) {" + stateBody + "})")
    cards.askCompressPassword(paneA, ["/a/x"], 0)
    cards.compressItem.takeSecretForTest(CANARY)
    var compressState = attempt(function () { return cardsState({ archiveCards: cards }) })
    check("F23: the cards state names exactly its keys", attempt(function () { return Object.keys(JSON.parse(compressState)).join("|") }),
          CARDS_STATE_KEYS)
    check("F23: and no value holds the compress card's typed secret", attempt(function () { return leaks(compressState).join("|") }), "")
    cards.compressItem.close()
    cards.openExtractPassword({ path: "/a/backup.7z", dest: "/a/backup" }, paneA, "")
    cards.extractItem.takeSecretForTest(CANARY)
    check("F23: nor the extract card's", attempt(function () { return leaks(cardsState({ archiveCards: cards })).join("|") }), "")
    cards.extractItem.close()
    check("F23: the IPC seam reads no password or confirm property anywhere",
          JSON.stringify(ipcText.match(/\.(password|confirm)\b/gi)) + "|" + /password|confirm/i.test(stateBody), "null|false")

    // B F21: while the child starts, a plain request waits and a password request fails at once, never parked.
    var backend = Fixture.backend(parent)
    var child = Fixture.child(backend)
    var failed = []
    backend.failed.connect(function (where, input, message) { failed.push(where + ":" + message) })
    // The shipped PaneWire handler is the one consumer, so the user reads the sentence only if that real code routes it.
    var failedBody = Source.block(Source.source("ui/PaneWire.qml"), "function onFailed(where, input, message, mode)", "ui/PaneWire.qml")
    var consume = eval("(function (pane, root) { return function (where, input, message, mode) {" + failedBody + "} })")
    var shown = { path: "/a", listInFlight: false, listedSeen: true, pendingMenu: false, pendingBackground: "", pendingBackgroundAt: null,
        total: 5, held: 0, rows: [], cursorIndex: 0, renamingIndex: -1, renameRequest: null, transfer: Ops.emptyTransfer(),
        listingState: "ready", stateMessage: "", lockedMode: 0, said: [], stuck: [] }
    shown.message = function (text, error) { shown.said.push(text + "|" + error) }
    shown.sticky = function (text) { shown.stuck.push(text) }
    shown.swap = { phase: Swap.idle(), drop: function () {}, landParked: function () { return false } }
    var windowRoot = { renameOnArrival: "", stale: false, anchor: null, retrySelectionText: "" }
    var wired = consume(shown, windowRoot)
    backend.failed.connect(function (where, input, message, mode) {
        attempt(function () { wired.call(null, where, input, message, mode) })
    })
    backend.dirsizecancel()
    backend.extractPassword("/a/backup.7z", "/a/backup", CANARY, 0)
    check("F21: a password request before the child starts fails as an archive operation, never as a dead backend",
          failed.join(","), "archive:the backend is not running")
    check("F21: and PaneWire.onFailed shows that sentence as the pane's error message",
          shown.said.join(","), "backup.7z could not be opened because the Flea backend stopped; reopen Flea and try again.|true")
    check("F21: without blanking the pane the way a dead backend does", [shown.total, shown.listingState, shown.stuck.length].join("|"), "5|ready|0")
    check("F21: and only the plain request waits, without the secret",
          backend.pending.length + "|" + (backend.pending.join("").indexOf(CANARY) >= 0), "1|false")
    child.started()
    check("F21: the started child is sent the waiting request after its own two",
          child.written.map(function (line) { return JSON.parse(line).c }).join(","), "formats,clipWatch,dirsizecancel")
    check("F21: and the queue is empty after it", backend.pending.length, 0)

    // contracts F1: the encrypted done line, as src/backend/archivepass.rs writes it, opens the extract card for its archive.
    var done = []
    backend.archiveDone.connect(function (id, ok, verified, err, path, dest) { done.push([id, ok, err, path, dest].join("|")) })
    var routeBody = Source.block(Source.source("ui/WindowBody.qml"), "onExtractPasswordRequested: function (path, dest, err)", "ui/WindowBody.qml")
    var route = eval("(function (view, primaryPane) { return function (path, dest, err) {" + routeBody + "} })")
    var wirePane = { transfer: Ops.emptyTransfer(), sticky: function () {}, refresh: function () {}, message: function (text) { said.push(text) },
        extractPasswordRequested: route({ openArchiveCards: function () { return cards } }, paneA) }
    var wireBody = Source.block(Source.source("ui/PaneWire.qml"), "function onArchiveDone(id, ok, verified, err, path, dest)", "ui/PaneWire.qml")
    backend.archiveDone.connect(eval("(function (pane) { return function (id, ok, verified, err, path, dest) {" + wireBody + "} })")(wirePane))
    backend.receive('{"t":"archivedone","id":7,"ok":false,"verified":true,"err":"encrypted","path":"/a/backup.7z","dest":"/a/backup"}')
    check("F1: the done line arrives as archiveDone with its path and dest", done.join(","), "7|false|encrypted|/a/backup.7z|/a/backup")
    check("F1: and the window opens the extract card over that archive for the pane",
          [cards.extractItem.opened, cards.extractItem.leaf, JSON.stringify(cards.extractItem.source), cards.extractOwner === paneA].join("|"),
          'true|backup.7z|{"path":"/a/backup.7z","dest":"/a/backup"}|true')
    cards.extractItem.close()
    backend.receive('{"t":"archivedone","id":8,"ok":false,"verified":true,"err":"wrong-password","path":"/a/backup.7z","dest":"/a/backup"}')
    check("F1: a wrong-password line reopens it with its sentence",
          cards.extractItem.opened + "|" + cards.extractItem.errorText, "true|" + ArchiveCard.wrongPasswordSentence("backup.7z"))
    cards.extractItem.close()
    parent.destroy()
}
