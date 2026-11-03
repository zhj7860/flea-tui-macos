.import "../../ui/js/Taildrop.js" as Taildrop
.import "../../ui/js/Dropbox.js" as Dropbox

function run(check) {
    // The `tailscale status --json` shape, five branches; every name and id here is synthetic.
    var status = JSON.stringify({
        Self: { UserID: 1000000000000001 },
        Peer: {
            "nodekey:offline": { HostName: "mediabox", Online: false, TaildropTarget: 5, UserID: 1000000000000001 },
            "nodekey:owned": { HostName: "laptop", Online: true, TaildropTarget: 1, UserID: 1000000000000001 },
            "nodekey:sameowner": { HostName: "DEVICE-A", Online: true, TaildropTarget: 1, UserID: 1000000000000001 },
            "nodekey:otherowner": { HostName: "OTHER-TENANT", Online: true, TaildropTarget: 9, UserID: 2000000000000002 },
            "nodekey:relay": { HostName: "", DNSName: "foo.mullvad.ts.net.", Online: true, TaildropTarget: 1, UserID: 1000000000000001 }
        }
    })
    var peers = Taildrop.parsePeers(status)
    check("only the reachable, eligible peers survive", peers.length, 2)
    check("sorted by label", peers[0].label + "," + peers[1].label, "DEVICE-A,laptop")
    check("the id is the peer's own map key", peers[0].id, "nodekey:sameowner")

    check("empty input parses to no peers", Taildrop.parsePeers("").length, 0)
    check("garbage input parses to no peers rather than throwing", Taildrop.parsePeers("not json").length, 0)
    check("a body with no Peer object parses to no peers", Taildrop.parsePeers('{"Self":{}}').length, 0)

    // isTaildropTarget's own two branches, read off the real OEM Model.js.
    check("TaildropTarget 1 is always a target", Taildrop.isTaildropTarget({ TaildropTarget: 1 }, "u"), true)
    check("a nonzero TaildropTarget other than 1 is never a target", Taildrop.isTaildropTarget({ TaildropTarget: 9 }, "u"), false)
    check("TaildropTarget 0 falls back to the same-owner check", Taildrop.isTaildropTarget({ TaildropTarget: 0, UserID: "u" }, "u"), true)
    check("a different owner with TaildropTarget 0 is not a target", Taildrop.isTaildropTarget({ TaildropTarget: 0, UserID: "u" }, "other"), false)

    check("DNSName wins as the send address", Taildrop.peerAddress({ DNSName: "host.ts.net." }), "host.ts.net")
    check("HostName is the fallback", Taildrop.peerAddress({ HostName: "host" }), "host")
    check("a tailnet IPv4 is the last resort", Taildrop.peerAddress({ TailscaleIPs: ["100.1.2.3", "fd7a::1"] }), "100.1.2.3")
    check("no usable address at all is empty", Taildrop.peerAddress({}), "")

    check("a localhost HostName falls back to the DNS name", Taildrop.displayHostName("localhost", "example.ts.net."), "example")

    var found = Taildrop.byId(peers, "nodekey:owned")
    check("byId finds the right peer", found.label, "laptop")
    check("byId misses cleanly", Taildrop.byId(peers, "nope"), null)
    check("JSON null is not a peer list", Taildrop.parsePeers("null").length, 0)
    check("failed status keeps its diagnostic", Taildrop.status("", 1, "Permission denied").reason, "Permission denied")
    check("malformed status is distinct from no peers", Taildrop.status("not json", 0, "").reason, "invalid status")
    check("signed out is retained as a reason", Taildrop.status('{"BackendState":"NeedsLogin"}', 0, "").reason, "signed out")
    check("stopped is retained as a reason", Taildrop.status('{"BackendState":"Stopped"}', 0, "").reason, "stopped")
    check("running without file sharing cannot send", Taildrop.status('{"BackendState":"Running","Self":{}}', 0, "").peers.length, 0)
    var ready = JSON.parse(status)
    ready.BackendState = "Running"
    ready.Self.Capabilities = ["https://tailscale.com/cap/file-sharing"]
    check("ready status carries real eligible targets", Taildrop.status(JSON.stringify(ready), 0, "").peers.length, 2)
    ready.Peer = {}
    check("empty installed provider names the empty state", Taildrop.status(JSON.stringify(ready), 0, "").reason, "no peers")
    check("missing Dropbox account is signed out", Dropbox.account("", "").reason, "Dropbox is signed out")
    check("Dropbox account read errors are preserved", Dropbox.account("", "Permission denied").reason, "Permission denied")
    check("invalid account JSON is an explicit error", Dropbox.account("{", "").reason, "Dropbox account details could not be read")
    check("personal Dropbox precedes business", Dropbox.account('{"personal":{"path":"/custom/personal/"},"business":{"path":"/custom/business"}}', "").path, "/custom/personal")
    check("business-only Dropbox keeps its actual path", Dropbox.account('{"business":{"path":"/custom/business"}}', "").path, "/custom/business")
    check("relative account path is refused", Dropbox.account('{"personal":{"path":"relative"}}', "").path, "")
    check("invalid first account does not silently switch accounts", Dropbox.account('{"personal":{},"business":{"path":"/other"}}', "").path, "")
    check("Dropbox account root is eligible", Dropbox.contains("/custom/Dropbox", "/custom/Dropbox"), true)
    check("a direct Dropbox child is eligible", Dropbox.contains("/custom/Dropbox", "/custom/Dropbox/file.txt"), true)
    check("an ancestor Search result retains Dropbox membership", Dropbox.contains("/custom/Dropbox", "/custom" + "/Dropbox/nested/file.txt"), true)
    check("a prefix sibling is outside Dropbox", Dropbox.contains("/custom/Dropbox", "/custom/Dropbox-old/file.txt"), false)
    check("the Dropbox ancestor is outside the account", Dropbox.contains("/custom/Dropbox", "/custom"), false)
    check("an absent account grants no membership", Dropbox.contains("", "/custom/file.txt"), false)
    check("a relative account grants no membership", Dropbox.contains("custom/Dropbox", "custom/Dropbox/file.txt"), false)
    check("a missing cursor grants no membership", Dropbox.contains("/custom/Dropbox", ""), false)
    check("normal Dropbox status is ready", Dropbox.status("Up to date", 0, "").reason, "")
    check("Dropbox exit-zero stopped text is not readiness", Dropbox.status("Dropbox isn't running!", 0, "").reason, "Dropbox isn't running!")
    check("Dropbox CLI Idle is a ready daemon response", Dropbox.status("Idle", 0, "").reason, "")
    check("Dropbox CLI exit-zero unresponsive error is not readiness", Dropbox.status("Dropbox isn't responding!", 0, "").reason, "Dropbox isn't responding!")
    check("Dropbox CLI exit-zero daemon EOF is not readiness", Dropbox.status("Dropbox daemon stopped.", 0, "").reason, "Dropbox daemon stopped.")
    check("Dropbox CLI command error is not readiness", Dropbox.status("Couldn't get status: daemon isn't responding", 0, "").reason, "Couldn't get status: daemon isn't responding")
    check("empty Dropbox status is explicit", Dropbox.status("", 0, "").reason, "Dropbox did not report its status")
    check("failed Dropbox status preserves stderr", Dropbox.status("", 1, "Permission denied").reason, "Permission denied")
    // The code is what logic reads (StateWords keys its words by it), one case per code of each provider.
    check("Taildrop failed status has code statusFailed", Taildrop.status("", 1, "Permission denied").code, "statusFailed")
    check("Taildrop malformed status has code invalid", Taildrop.status("not json", 0, "").code, "invalid")
    check("Taildrop non-object status has code invalid", Taildrop.status("7", 0, "").code, "invalid")
    check("Taildrop signed out has code signedOut", Taildrop.status('{"BackendState":"NeedsLogin"}', 0, "").code, "signedOut")
    check("Taildrop stopped has code stopped", Taildrop.status('{"BackendState":"Stopped"}', 0, "").code, "stopped")
    check("Taildrop without file sharing has code disabled", Taildrop.status('{"BackendState":"Running","Self":{}}', 0, "").code, "disabled")
    check("Taildrop with no peers has code noPeers", Taildrop.status(JSON.stringify(ready), 0, "").code, "noPeers")
    ready.Peer = JSON.parse(status).Peer
    check("Taildrop ready has an empty code", Taildrop.status(JSON.stringify(ready), 0, "").code, "")
    check("Dropbox read error has code readFailed", Dropbox.account("", "Permission denied").code, "readFailed")
    check("Dropbox missing account has code signedOut", Dropbox.account("", "").code, "signedOut")
    check("Dropbox account with no entry has code signedOut", Dropbox.account("{}", "").code, "signedOut")
    check("Dropbox invalid JSON has code invalid", Dropbox.account("{", "").code, "invalid")
    check("Dropbox non-object account has code invalid", Dropbox.account("[]", "").code, "invalid")
    check("Dropbox invalid folder has code invalid", Dropbox.account('{"personal":{"path":"relative"}}', "").code, "invalid")
    check("Dropbox ready account has an empty code", Dropbox.account('{"personal":{"path":"/custom/personal"}}', "").code, "")
    check("Dropbox failed status has code statusFailed", Dropbox.status("", 1, "Permission denied").code, "statusFailed")
    check("Dropbox empty status has code statusFailed", Dropbox.status("", 0, "").code, "statusFailed")
    check("Dropbox stderr beside output has code statusFailed", Dropbox.status("Up to date", 0, "warning").code, "statusFailed")
    check("Dropbox not running has code notRunning", Dropbox.status("Dropbox isn't running!", 0, "").code, "notRunning")
    check("Dropbox ready status has an empty code", Dropbox.status("Up to date", 0, "").code, "")
}
