.import "../../ui/js/Places.js" as Places
.import "userdirsfixture.js" as UserDirsFixture

function run(check) {
    var home = {group: "home", kind: "home", path: "/home/test"}
    var trash = {group: "trash", kind: "trash", path: "trash:///", count: 1}
    var network = {group: "network", kind: "share", uri: "smb://host/data", mounted: false}
    var device = {group: "device", kind: "disk", device: "/dev/nvme0n1", path: "/"}
    var a = {group: "favourite", kind: "favourite", original: {label: "A", path: "/a"}}
    var b = {group: "favourite", kind: "favourite", original: {label: "B", path: "/a"}}
    var oldRail = [home, trash, a, network, device]
    var expandedRail = [home, trash, a, b, network, device]
    check("a Favorite addition preserves the Network target", Places.railCursorAfter(oldRail, expandedRail, 3), 4)
    check("a Favorite removal preserves the Device target", Places.railCursorAfter(expandedRail, oldRail, 5), 4)
    check("reordering Favorites keeps their distinct original labels", Places.railCursorAfter([a, b], [b, a], 0), 1)
    check("an unchanged duplicate occurrence stays selected", Places.railCursorAfter([a, a, b], [b, a, a], 1), 2)
    check("removing an identical duplicate invalidates its ambiguous selection", Places.railCursorAfter([a, a, b], [a, b], 0), -1)
    check("adding an identical duplicate does not guess an occurrence", Places.railCursorAfter([a, b], [a, a, b], 0), -1)
    check("removing the selected row clears the rail cursor", Places.railCursorAfter(oldRail, [home, trash, a, device], 3), -1)
    check("a cleared cursor stays cleared through another refresh", Places.railCursorAfter([], oldRail, -1), -1)
    check("the first arriving rail retains its initial Home cursor", Places.railCursorAfter([], oldRail, 0), 0)
    check("mount state and count changes do not change identity", Places.railCursorAfter([trash, network],
        [{group: "trash", kind: "trash", path: "trash:///", count: 2},
         {group: "network", kind: "share", uri: network.uri, mounted: true, path: "/run/gvfs/data"}], 1), 1)
    check("a moved rename target no longer has its old index", Places.railCursorAfter(oldRail, expandedRail, 3) === 3, false)
    var records = [{ label: "A", path: "/a" }, { label: "Again", path: "/a" }, 17, { label: "", path: "bad" }]
    var stored = Places.storedEntries(records, "/home/test")
    check("Flea keeps duplicate paths", stored.length, 4)
    check("Flea preserves each duplicate label", stored[1].label, "Again")
    check("invalid favourite remains identifiable", stored[2].original, 17)
    check("invalid favourite is marked", stored[2].error.length > 0, true)
    check("an invalid original value keeps its identifying label", stored[2].label, "17")
    check("empty invalid Favorite label follows the ruled spelling", stored[3].label, "Invalid favorite")
    check("invalid Favorite refusal follows the ruled spelling", stored[2].error, "invalid favorite record")
    check("new favourites starts empty", Places.storedEntries([], "/home/test").length, 0)
    check("sidebar width clamps low", Places.sidebarWidth(0), 160)
    check("sidebar width clamps high", Places.sidebarWidth(999), 256)
    check("sidebar width snaps to nearer stop", Places.sidebarWidth(231), 224)
    check("bad width type falls back", Places.sidebarWidth("224"), 192)
    check("tilde expands only for consumption", Places.storedEntries([{label:"Home",path:"~/docs"}], "/home/test")[0].path, "/home/test/docs")
    check("stored tilde stays intact", Places.storedEntries([{label:"Home",path:"~/docs"}], "/home/test")[0].storedPath, "~/docs")

    var sent = []
    var ports = { message: function (text, bad) { sent.push(text) } }
    Places.openEntry({ kind: "favourite", label: "50%2 off", path: "/x", original: 17 }, ports)
    check("a label holding %2 stays literal in the refusal", sent[0], "Could not open 50%2 off \u00b7 invalid favorite record")
    Places.openEntry({ kind: "favourite", label: "a$&b", path: "/x", original: 17 }, ports)
    check("a label holding $& stays literal in the refusal", sent[1], "Could not open a$&b \u00b7 invalid favorite record")

    var dirs = 'XDG_DESKTOP_DIR="$HOME/"\n'
             + 'XDG_DOWNLOAD_DIR="$HOME/Downloads"\n'
             + 'XDG_DOCUMENTS_DIR="$HOME/Documents"\n'
             + '# a comment line\n'
             + 'XDG_PROJECTS_DIR="/srv/projects"\n'
    var got = Places.userDirs(dirs, "/home/gm")
    check("home itself is not a favourite", got.length, 3)
    check("a relative entry expands", got[0].path, "/home/gm/Downloads")
    check("the label is the leaf", got[0].label, "Downloads")
    check("an absolute entry survives", got[2].path, "/srv/projects")
    for (var i = 0; i < UserDirsFixture.cases.length; i++) {
        var sample = UserDirsFixture.cases[i]
        check("rail user dirs: " + sample[0],
              JSON.stringify(Places.userDirs(UserDirsFixture.body(sample[1]), "/home/test").map(function (entry) { return entry.path })),
              JSON.stringify(sample[2] === null ? [] : [sample[2]]))
    }
    check("an absent rail role creates no conventional entry",
          Places.userDirs('XDG_PICTURES_DIR="$HOME"\nXDG_VIDEOS_DIR="$HOME"', "/home/test").length, 0)

    var marks = 'file:///home/gm/Downloads Downloads\n'
              + 'file:///home/gm/My%20Files\n'
              + 'smb://192.168.1.10/ NAS\n'
    var b = Places.bookmarks(marks)
    check("a non-file bookmark is skipped", b.length, 2)
    check("the trailing label wins", b[0].label, "Downloads")
    check("a percent escape decodes", b[1].path, "/home/gm/My Files")
    check("no label falls back to the leaf", b[1].label, "My Files")

    // The operator's own real NAS bookmark, on a three-line fixture.
    var netFile = 'file:///home/gm/Downloads Downloads\n'
                + 'smb://192.168.1.10/data NAS\n'
                + 'smb://10.0.0.9/backups Backups\n'
    check("only the matched line's label changes", Places.relabel(netFile, "smb://192.168.1.10/data", "Homelab"),
        'file:///home/gm/Downloads Downloads\n'
        + 'smb://192.168.1.10/data Homelab\n'
        + 'smb://10.0.0.9/backups Backups\n')

    // gio's own live-mount uri carries a trailing slash the written bookmark line never had.
    check("a trailing-slash uri still matches the bookmarked line",
        Places.relabel(netFile, "smb://192.168.1.10/data/", "Homelab"),
        'file:///home/gm/Downloads Downloads\n'
        + 'smb://192.168.1.10/data Homelab\n'
        + 'smb://10.0.0.9/backups Backups\n')

    // No existing line for this uri: a mounted-but-never-bookmarked entry gains one on rename.
    check("an unmatched uri is appended rather than dropped",
        Places.relabel(netFile, "smb://192.168.1.10/isos/", "ISOs"),
        netFile + 'smb://192.168.1.10/isos ISOs\n')

    check("appending onto an empty file needs no leading blank line", Places.relabel("", "smb://host/share", "Share"),
        "smb://host/share Share\n")

    check("appending onto a body missing its trailing newline still starts a new line",
        Places.relabel("smb://a/b Existing", "smb://host/share", "Share"),
        "smb://a/b Existing\nsmb://host/share Share\n")

    check("a blank submitted name is a no-op", Places.relabel(netFile, "smb://192.168.1.10/data", "   "), netFile)

    // A hand-edited file can carry two lines for the same normalized uri; both must rewrite.
    var dupes = 'smb://192.168.1.10/data NAS\n'
              + 'file:///home/gm/Downloads Downloads\n'
              + 'smb://192.168.1.10/data/ Old NAS\n'
    // Each line's own uri text survives untouched (line 3 keeps its trailing slash); only the label changes.
    check("every matching line rewrites, not just the first", Places.relabel(dupes, "smb://192.168.1.10/data", "Homelab"),
        'smb://192.168.1.10/data Homelab\n'
        + 'file:///home/gm/Downloads Downloads\n'
        + 'smb://192.168.1.10/data/ Homelab\n')

    // The asymmetry ui/js/Mounts.js "removeBookmark" does not have: it reads each line off the
    // trimmed text, so an indented bookmark is one Remove can drop and Rename could only duplicate.
    check("an indented line is the line that rewrites, not a second line appended",
        Places.relabel("  smb://192.168.1.10/data NAS\n", "smb://192.168.1.10/data", "Homelab"),
        "smb://192.168.1.10/data Homelab\n")

    // relabel is a trust boundary of its own: an embedded newline must not split one line into two.
    check("an embedded newline in the name cannot fork a new line", Places.relabel(netFile, "smb://192.168.1.10/data", "Home\nlab"),
        'file:///home/gm/Downloads Downloads\n'
        + 'smb://192.168.1.10/data Homelab\n'
        + 'smb://10.0.0.9/backups Backups\n')
    // A bookmarks line is arbitrary text, and decodeURIComponent throws on a malformed escape, which
    // would take the whole rail rebuild with it; a parse failure answers a shape instead.
    check("a malformed escape in a bookmark falls back to the raw path",
        Places.bookmarks("file:///home/gm/bad%zz Bad")[0].path, "/home/gm/bad%zz")
    check("a well-formed escape still decodes",
        Places.bookmarks("file:///home/gm/My%20Files Mine")[0].path, "/home/gm/My Files")

    // The FAVORITES merge the rail used to do inline. Home leads whatever either file says, and a
    // path named twice keeps the position it was first given rather than moving to the later one.
    var favDirs = 'XDG_DOWNLOAD_DIR="$HOME/Downloads"\n'
                + 'XDG_DOCUMENTS_DIR="$HOME/Documents"\n'
    var favMarks = 'file:///home/gm/Downloads Grabbed\n'
                 + 'file:///srv/media Media\n'
                 + 'smb://192.168.1.10/data NAS\n'
    var favs = Places.favorites("/home/gm", favDirs, favMarks, function (label) { return "mark:" + label })
    check("Home leads the rail and is never parsed out of a file", favs[0].path + "|" + favs[0].label, "/home/gm|Home")
    check("the XDG dirs follow in file order", favs[1].label + "," + favs[2].label, "Downloads,Documents")
    check("a path already placed keeps its first position and its first label",
          favs.map(function (e) { return e.label }).join(","), "Home,Downloads,Documents,Media")
    check("a non-file bookmark never reaches FAVORITES", favs.length, 4)
    check("every row is tagged as a favourite", favs[3].group + "/" + favs[3].kind, "favorite/favorite")
    check("the mark is resolved by the caller, so the rail keeps its own Icons import", favs[1].glyph, "mark:Downloads")
    check("a box with neither file still gets Home", Places.favorites("/home/gm", "", "", function () { return "m" }).length, 1)
    // Issue 21, TomFaulkner: the saved line is rewritten where it sits, so the rail's order holds and
    // the place keeps its identity; an address nothing saved appends instead of rewriting a stranger.
    var saved = "file:///home/gm/Downloads Downloads\nsmb://nas:445/isos NAS isos\nsmb://other/data Other\n"
    check("the edited line is rewritten in place, and every other line is untouched",
          Places.replace(saved, "smb://nas/isos", "sftp://nas2/isos", "NAS isos"),
          "file:///home/gm/Downloads Downloads\nsftp://nas2/isos NAS isos\nsmb://other/data Other\n")
    check("the default port the bookmark carried is matched the way a rename matches it",
          Places.replace(saved, "smb://nas:445/isos/", "smb://nas/plates", "Plates"),
          "file:///home/gm/Downloads Downloads\nsmb://nas/plates Plates\nsmb://other/data Other\n")
    check("an address nothing saved is appended rather than rewriting another line",
          Places.replace(saved, "smb://absent/", "smb://nas/new", "New"),
          saved + "smb://nas/new New\n")
    check("a label nobody typed falls back to the share's own name",
          Places.replace("", "", "smb://nas/plates", ""), "smb://nas/plates plates\n")
    check("and an empty new address rewrites nothing at all",
          Places.replace(saved, "smb://nas/isos", "", "NAS"), saved)

    heldByCases(check)
}

// Which rail row holds the folder or view the pane shows.
function heldByCases(check) {
    var dir = { kind: "dir" }
    var homeRow = { group: "home", kind: "home", path: "/home/gm" }
    var recent = { group: "recent", kind: "recent", path: "flea:recent" }
    var documents = { group: "home", kind: "home", path: "/home/gm/Documents" }
    var trashRow = { group: "trash", kind: "trash", path: "trash:///" }
    var fav = { group: "favourite", kind: "favourite", path: "/home/gm/Work", original: { label: "Work", path: "~/Work" } }
    var favTwin = { group: "favourite", kind: "favourite", path: "/home/gm/Documents", original: { label: "Docs", path: "~/Documents" } }
    var tagRed = { label: "Red", kind: "tag", tag: "Red" }
    var tagBlue = { label: "Blue", kind: "tag", tag: "Blue" }
    var share = { group: "network", kind: "share", path: "", uri: "smb://nas/data", mounted: true }
    var sleeping = { group: "network", kind: "share", path: "", uri: "smb://nas/idle", mounted: false }
    var kernel = { group: "network", kind: "share", path: "/mnt/nas", uri: "/mnt/nas", mounted: true }
    var disk = { group: "device", kind: "disk", path: "/", mounted: true }
    var usb = { group: "device", kind: "volume", path: "/run/media/gm/USB", mounted: true }
    var ejected = { group: "device", kind: "volume", path: "", mounted: false }
    var rail = [homeRow, recent, documents, trashRow, fav, tagRed, tagBlue, share, sleeping, kernel, disk, usb, ejected]
    var at = function (path) { return Places.heldBy(rail, path, { kind: "dir" }) }
    check("Documents lights while the pane stands in ~/Documents/claude", at("/home/gm/Documents/claude"), 2)
    check("a folder that is exactly a row's folder lights that row", at("/home/gm/Documents"), 2)
    check("Home lights in ~/Work/field when no favourite holds Work", Places.heldBy([homeRow, documents, disk], "/home/gm/Work/field", dir), 0)
    check("the deepest row wins over Home for ~/Work/field", at("/home/gm/Work/field"), 4)
    check("Home lights for a folder no other row holds", at("/home/gm/Pictures"), 0)
    check("a sibling that only shares a name prefix is not held", at("/home/gm/Documents2"), 0)
    check("slash holds every local path nothing else holds", at("/fx/v/work"), 10)
    check("slash is the whole of the internal disk's reach, even for slash itself", at("/"), 10)
    check("a volume wins over slash for a folder on it", at("/run/media/gm/USB/photos"), 11)
    check("a kernel share wins over slash for its mountpoint", at("/mnt/nas"), 9)
    check("a tie goes to the first row in rail order", Places.heldBy([favTwin, documents], "/home/gm/Documents/x", dir), 0)
    check("an unmounted volume never lights", Places.heldBy([{ kind: "volume", path: "/run/media/gm/USB", mounted: false }, disk], "/run/media/gm/USB/photos", dir), 1)
    check("a row with an invalid record never lights", Places.heldBy([{ kind: "favourite", path: "/a", error: "bad" }], "/a", dir), -1)
    check("nothing holding the folder answers -1", Places.heldBy([homeRow, documents], "/srv/x", dir), -1)
    check("an empty rail answers -1", Places.heldBy([], "/a", dir), -1)
    check("no rail at all answers -1", Places.heldBy(undefined, "/a", dir), -1)
    check("no path answers -1", Places.heldBy(rail, "", dir), -1)
    check("Recent lights its own row and no folder", Places.heldBy(rail, "/", { kind: "recent" }), 1)
    check("Trash lights its own row", Places.heldBy(rail, "/home/gm", { kind: "trash" }), 3)
    check("a view whose row is absent lights nothing", Places.heldBy([homeRow, disk], "/", { kind: "recent" }), -1)
    check("a tag view lights the tag of that name", Places.heldBy(rail, "/home/gm", { kind: "tag", tag: "Blue" }), 6)
    check("a tag view with no row for its tag lights nothing", Places.heldBy(rail, "/home/gm", { kind: "tag", tag: "Green" }), -1)
    var gvfs = "/run/user/1000/gvfs/smb-share:server=nas,share=data/photos"
    check("a gvfs path lights the mounted share opened under it, never the disk",
          Places.heldBy(rail, gvfs, { kind: "dir", shareKey: "smb://nas/data" }), 7)
    check("a gvfs path with no remembered share lights nothing, not the disk",
          Places.heldBy(rail, gvfs, { kind: "dir" }), -1)
    check("a gvfs path whose share is unmounted lights nothing",
          Places.heldBy(rail, gvfs, { kind: "dir", shareKey: "smb://nas/idle" }), -1)
    check("a gvfs path never lights a row by folder prefix",
          Places.heldBy([disk, homeRow], gvfs, { kind: "dir", shareKey: "smb://other/x" }), -1)
    check("a pathless share with no mountUri and another address is passed over for the share that holds the folder",
          Places.heldBy([{ kind: "share", path: "", uri: "smb://nas/a", mounted: true }, share], gvfs, { kind: "dir", shareKey: "smb://nas/data" }), 1)
    check("a share row also answers by the address it is mounted under",
          Places.heldBy([{ kind: "share", path: "", uri: "smb://nas/alias", mountUri: "smb://nas/data", mounted: true }], gvfs, { kind: "dir", shareKey: "smb://nas/data" }), 0)

    check("an open Trash is the Trash view, whatever else the pane holds", JSON.stringify(Places.litView(true, "results", "results", "tag:Red", null)), JSON.stringify({ kind: "trash" }))
    check("Recent mode is the Recent view", JSON.stringify(Places.litView(false, "results", "", "", null)), JSON.stringify({ kind: "recent" }))
    check("a walk whose landed query is a tag is that tag's view", JSON.stringify(Places.litView(false, "", "results", "tag:Red", null)), JSON.stringify({ kind: "tag", tag: "Red" }))
    check("a tag query with no walk on screen is not a tag view", JSON.stringify(Places.litView(false, "", "", "tag:Red", null)), JSON.stringify({ kind: "dir", shareKey: "" }))
    check("an ordinary walk is a folder view", JSON.stringify(Places.litView(false, "", "typing", "report", null)), JSON.stringify({ kind: "dir", shareKey: "" }))
    check("a folder view carries the remembered share's key", JSON.stringify(Places.litView(false, "", "", "", { key: "smb://nas/data" })), JSON.stringify({ kind: "dir", shareKey: "smb://nas/data" }))
}
