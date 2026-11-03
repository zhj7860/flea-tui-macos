.pragma library

.import "Format.js" as Format
.import "Ops.js" as Ops

// The sentences that carry a name or a reason, each filled by Format.fill.
var WORDS = {
    sending: "Sending %1 to %2 with LocalSend",
    reason: "LocalSend · %1"
}

// Directive 71's three sentences, kept out of the QML so the wording is tested rather than read off
// a screenshot. The dispatch, the verdict the CLI came back with, and the one refusal Flea itself
// can hit: a row whose binary left between the menu opening and the peer being chosen.
// The one call ui/Pane.qml makes: the service either took the send or the CLI is gone.
function send(pane, service, provider, peer, paths) {
    // A refusal is one of two things and they are not the same sentence: nothing to send, or no CLI
    // to send it with. Blaming the CLI for an empty pick told the user a binary was gone while it sat on PATH.
    if (paths.length === 0) { pane.message("There is nothing to send.", true); return }
    if (!service.send(peer, paths)) { pane.message(missing(provider), true); return }
    pane.message(sending(peer, paths), false)
}

function sending(peer, paths) {
    if (paths.length === 1)
        return Format.fill(WORDS.sending, Ops.leaf(paths[0]), peer)
    return Format.fill(WORDS.sending, Ops.items(paths.length), peer)
}

// The CLI ends its own run when the transfer does, so this is the only result Flea ever knows.
function verdict(ok, reason) {
    if (ok) return "LocalSend finished the transfer."
    return reason && reason.length > 0 ? Format.fill(WORDS.reason, reason) : "LocalSend could not finish the transfer."
}

function missing(provider) {
    return provider && provider.reason ? Format.fill(WORDS.reason, provider.reason)
                                       : "localsend-cli is no longer installed."
}
