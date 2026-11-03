.import "../../ui/js/Format.js" as Format
.import "../../ui/js/Picker.js" as Picker
.import "../../ui/js/Sort.js" as Sort
.import "../../ui/js/Keymap.js" as Keymap
.import "sourcefixture.js" as Source

.import "pickerkeys.js" as PickerKeys
.import "pickerhidden.js" as PickerHidden

function run(check) {
    PickerKeys.run(check)
    PickerHidden.run(check)
    // The shape tools/flea-portal writes for an OpenFile with two filters, taken from its request_for().
    var asked = JSON.stringify({
        mode: "open", title: "Send to unraid", app: "", accept: "Send", multiple: true,
        directory: false, folder: "/home/gm/Pictures", file: "", name: "", files: [],
        filters: [{ label: "Images", globs: ["*.png", "*.jpg"], mimes: [] },
                  { label: "Any text", globs: [], mimes: ["text/plain"] }],
        current: "Images"
    })
    var req = Picker.request(asked)
    check("the mode is read", req.mode, "open")
    check("the caller's title is read", req.title, "Send to unraid")
    check("multiple is read", req.multiple, true)
    check("the starting folder is read", req.folder, "/home/gm/Pictures")

    var empty = Picker.request("not json")
    check("a request that is not JSON still opens a window", empty.mode, "open")
    check("a request with nothing in it has no filters", empty.filters.length, 0)
    check("a request with nothing in it is not multiple", empty.multiple, false)
    check("an absent mode is never save", Picker.request('{"mode":"nonsense"}').mode, "open")

    check("the caller's title wins", Picker.title(req), "Send to unraid")
    check("a titleless open says what the window is for", Picker.title(Picker.request("{}")), "Choose file")
    check("a titleless directory request says folder", Picker.title(Picker.request('{"directory":true}')), "Choose folder")
    check("a titleless save says save", Picker.title(Picker.request('{"mode":"save"}')), "Save file")

    // A host application has no portal identity, and nothing else may be shown as one.
    check("no app id draws no requester line", Picker.subtitle(req), "")
    check("an app id is named", Picker.subtitle(Picker.request('{"app":"org.gnome.gedit"}')), "Requested by org.gnome.gedit")
    check("the requester is one template with the caller's text kept whole", Picker.subtitle(Picker.request('{"app":"a%1b"}')), "Requested by a%1b")

    check("the accept label carries the count", Picker.acceptLabel(req, 3), "Send 3")

    // The collision review: one template, the name kept whole, and the stem the field selects.
    check("the collision line is one template", Picker.collisionLine("report.txt"), "report.txt already exists here.")
    check("a name holding a placeholder is kept whole", Picker.collisionLine("a%1b.txt"), "a%1b.txt already exists here.")
    check("the stem ends at the last dot", Picker.stemEnd("Downloading the Source.html"), 22)
    check("a double extension keeps its first part in the stem", Picker.stemEnd("a.tar.gz"), 5)
    check("a name with no dot is all stem", Picker.stemEnd("README"), 6)
    check("a leading dot is part of the stem", Picker.stemEnd(".bashrc"), 7)
    check("an empty name has an empty stem", Picker.stemEnd(""), 0)

    // Callout 12: Back, Up, the rail, the list, Filename, the filter, Cancel and the answer; a hidden or disabled stop is skipped.
    function stop(name, off) { return { name: name, visible: off !== "hidden", enabled: off !== "disabled", activeFocusOnTab: true } }
    function walk(over) {
        var filter = stop("Filter", over.filter)
        var stops = { chrome: [stop("Back", over.back), stop("Up")], rail: stop("Rail"), view: stop(over.view || "List"),
            save: over.save ? [stop("Filename")] : [], answers: [filter, stop("Cancel"), stop("Answer", over.answer)] }
        return Picker.tabOrder(stops).map(function(item) { return item.name }).join(",")
    }
    check("an open walks the chrome, rail, list, filter, Cancel, answer", walk({}), "Back,Up,Rail,List,Filter,Cancel,Answer")
    check("an open with no filters has no filter stop", walk({ filter: "hidden" }), "Back,Up,Rail,List,Cancel,Answer")
    check("a save puts Filename after the list and before the filter", walk({ save: true }), "Back,Up,Rail,List,Filename,Filter,Cancel,Answer")
    check("a save with no filters goes from Filename to Cancel", walk({ save: true, filter: "hidden" }), "Back,Up,Rail,List,Filename,Cancel,Answer")
    check("a disabled Back is skipped", walk({ back: "disabled" }), "Up,Rail,List,Filter,Cancel,Answer")
    check("an answer that cannot be taken is skipped", walk({ answer: "disabled" }), "Back,Up,Rail,List,Filter,Cancel")
    check("the grid takes the list's place", walk({ view: "Grid", save: true }), "Back,Up,Rail,Grid,Filename,Filter,Cancel,Answer")
    check("and groups a four-figure one", Picker.acceptLabel(req, 1204), "Send 1,204")
    check("one file does not carry a count", Picker.acceptLabel(req, 1), "Send")
    check("a caller's label is substituted once and never re-scanned", Picker.acceptLabel(Picker.request('{"accept":"Se%2nd","multiple":true}'), 3), "Se%2nd 3")
    check("no accept label falls back to Open", Picker.acceptLabel(Picker.request("{}"), 0), "Open")
    check("a folder request falls back to Choose folder", Picker.acceptLabel(Picker.request('{"directory":true}'), 0), "Choose folder")

    // Recent is a location and not a directory: no path this window ever holds can equal its token,
    // and a row inside it is identified by its own path under the listing base "/".
    check("Recent is not a path", Picker.RECENT.charAt(0) === "/", false)
    check("the location is recognised", Picker.isRecent(Picker.RECENT), true)
    check("a real directory is not Recent", Picker.isRecent("/home/gm"), false)
    check("a row in a directory joins onto it", Picker.rowPath("/home/gm", "a.png"), "/home/gm/a.png")
    check("a row in Recent is its own path", Picker.rowPath(Picker.RECENT, "home/gm/Pictures/a.png"), "/home/gm/Pictures/a.png")
    check("a row at the root still joins once", Picker.rowPath("/", "etc"), "/etc")
    check("a symlink directory remains navigable without changing link identity", Picker.directory({d:false,p:0o120777,i:"folder"}), true)
    check("a regular file with a folder-like name stays a file", Picker.directory({d:false,p:0o100644,i:"folder"}), false)

    check("nothing checked says so", Picker.statusLine(0, 0), "0 selected")
    check("what is checked and what it weighs", Picker.statusLine(3, 2100000), "3 selected · 2.1 MB")
    check("and a four-figure check groups", Picker.statusLine(1204, 2100000), "1,204 selected · 2.1 MB")
    check("the open hints name Space and Enter", Picker.hints(req), "Space select · Enter open/send · Esc cancel")
    check("one-file hints advertise no marking", Picker.hints(Picker.request("{}")), "Enter open · Esc cancel")
    check("the save hints name neither", Picker.hints(Picker.request('{"mode":"save"}')), "Enter save · Esc cancel")

    var chips = Picker.chips(req)
    check("every filter gets a chip, and All files after them", chips.length, 3)
    check("the first chip is the caller's first filter", chips[0].label, "Images")
    check("All files is last and is not a filter", chips[2].label + " " + chips[2].index, "All files -1")
    check("no filters means no chip row at all", Picker.chips(Picker.request("{}")).length, 0)
    check("current_filter chooses the active chip", Picker.currentChip(req), 0)
    check("an unknown current_filter falls back to the first", Picker.currentChip(Picker.request('{"filters":[{"label":"A"}],"current":"Z"}')), 0)
    check("no filters has no active chip", Picker.currentChip(Picker.request("{}")), -1)
    check("duplicate filter labels keep the caller's rule identity", Picker.currentChip(Picker.request('{"filters":[{"label":"A"},{"label":"A"}],"current":"A","currentIndex":1}')), 1)

    var marks = Picker.reviewedMarks([], [{path: "/x/a #.png", bytes: 10}, {path: "/x/b.png", bytes: 20}])
    check("reviewed marks retain order", Picker.paths(marks).join(","), "/x/a #.png,/x/b.png")
    check("reviewed byte totals are live", Picker.totalBytes(marks), 30)
    check("a mark is found by its path", Picker.marked(marks, "/x/b.png"), true)
    check("a reviewed path gets one URI encoding", marks[0].uri, "file:///x/a%20%23.png")
    marks = Picker.reviewedMarks(marks, [{path: "/x/a #.png", bytes: 15}])
    check("removed identities leave the result", marks.length, 1)
    check("review updates the bytes", marks[0].bytes, 15)
    check("review preserves the original URI", marks[0].uri, "file:///x/a%20%23.png")
    check("reply carries retained URI and selected filter", Picker.reply(0, marks, 1),
          '{"response":0,"uris":["file:///x/a%20%23.png"],"filter":1}')

    // The save name is a client string, and the answer it builds must stay inside the folder the
    // user was shown. Same cases as src/backend/ops.rs's own valid_name test, so a drift shows here.
    check("an ordinary name is a name", Picker.validName("ordinary.txt"), true)
    check("a dotfile is a name", Picker.validName(".bashrc"), true)
    check("spaces are a name", Picker.validName("a name with spaces"), true)
    check("an empty name would answer with the directory", Picker.validName(""), false)
    check("a single dot is the directory itself", Picker.validName("."), false)
    check("two dots climb out of the directory", Picker.validName(".."), false)
    check("a separator moves the answer out of the folder", Picker.validName("../escape"), false)
    check("a leading separator is an absolute path", Picker.validName("/etc/passwd"), false)
    check("a subdirectory is still a separator", Picker.validName("sub/child"), false)
    check("the reviewer's own exploit is refused", Picker.validName("../../.config/autostart/pwn.desktop"), false)
    check("an interior NUL truncates the path at the syscall", Picker.validName("nul\0byte"), false)
    // tools/flea-portal reads current_name verbatim, so a traversal reaches Picker.request() intact
    // and the window has to be the thing that refuses it.
    check("a traversal survives the request unchanged", Picker.request('{"name":"../../pwn"}').name, "../../pwn")
    check("and the request's own name is then refused", Picker.validName(Picker.request('{"name":"../../pwn"}').name), false)

    // The save card's lines are whole templates; each rendered line equals today's string except for the zero-width joints.
    check("the refused line is one whole sentence",
        Format.fill(Picker.SAVE_REFUSED, "export.txt", Picker.NAME_REFUSED),
        "export.txt cannot be used: a name cannot be empty, . or .., or contain /")
    check("the collision line is one whole sentence",
        Format.fill(Picker.SAVE_EXISTS, Picker.jointName("export.txt")),
        "export.\u200btxt already exists here. Review it before you continue.")

    check("a path joins under its directory", Picker.join("/home/gm", "a.txt"), "/home/gm/a.txt")
    check("the root does not double its slash", Picker.join("/", "etc"), "/etc")
    check("the parent of a path is its directory", Picker.parentOf("/home/gm/a.txt"), "/home/gm")
    check("the root is its own parent, so Parent stops there", Picker.parentOf("/"), "/")

    check("a picked path leaves as a file URI", Picker.uris(["/home/gm/a.txt"])[0], "file:///home/gm/a.txt")
    check("a space is encoded, because GLib refuses a bad one", Picker.uris(["/home/gm/my file.txt"])[0], "file:///home/gm/my%20file.txt")
    check("a hash is encoded rather than read as a fragment", Picker.uris(["/home/gm/a#b.txt"])[0], "file:///home/gm/a%23b.txt")

    check("a pick answers with its URIs", Picker.reply(0, ["/home/gm/a.txt"]),
          '{"response":0,"uris":["file:///home/gm/a.txt"]}')
    check("a refusal answers with no URI at all", Picker.reply(1, ["/home/gm/a.txt"]), '{"response":1}')

    // The chooser sorts by the columns it draws and inherits kind silently, so kind is pinned by order, not by mark.
    function order(o) { return o ? o.key + (o.desc ? " desc" : " asc") : "none" }
    check("the chooser offers the three columns it draws", Picker.SORT_ORDERS.join(","), "name,size,mtime")
    check("a click on another column starts it ascending",
          order(Sort.columnOrder(Picker.SORT_ORDERS, "name", true, "size")), "size asc")
    check("a click on the sorted column reverses it",
          order(Sort.columnOrder(Picker.SORT_ORDERS, "size", false, "size")), "size desc")
    check("and a second click puts it back",
          order(Sort.columnOrder(Picker.SORT_ORDERS, "size", true, "size")), "size asc")
    check("a column the chooser does not offer asks for nothing",
          order(Sort.columnOrder(Picker.SORT_ORDERS, "name", false, "kind")), "none")
    check("s steps from name to size", order(Sort.nextOrder(Picker.SORT_ORDERS, "name")), "size asc")
    check("s steps from size to modified", order(Sort.nextOrder(Picker.SORT_ORDERS, "size")), "mtime asc")
    check("s wraps from modified to name, never onto kind",
          order(Sort.nextOrder(Picker.SORT_ORDERS, "mtime")), "name asc")
    check("s from an inherited kind order starts over at name",
          order(Sort.nextOrder(Picker.SORT_ORDERS, "kind")), "name asc")
    check("S reverses the order the listing is in", order(Sort.reverseOrder("mtime", false)), "mtime desc")
    check("S reverses an inherited kind order rather than refusing it",
          order(Sort.reverseOrder("kind", true)), "kind asc")

    // One-file double clicks accept; several-file double clicks toggle the file's mark.
    var single = Picker.request('{"mode":"open","multiple":false}')
    var multi = Picker.request('{"mode":"open","multiple":true}')
    var file = {d: false, p: 0, s: 1, m: 1, i: "text"}
    var folder = {d: true, p: 0, s: 0, m: 1, i: "folder"}
    check("a double click on an unmarked file marks then sends it", Picker.doubleAction(single, file, "/a/b.txt", "/a/b.txt", []), "markAccept")
    check("a double click on a marked file sends it", Picker.doubleAction(single, file, "/a/b.txt", "/a/b.txt", [{path: "/a/b.txt", bytes: 3}]), "accept")
    check("a multiple double click on an unmarked file toggles its mark", Picker.doubleAction(multi, file, "/a/c.txt", "/a/c.txt", [{path: "/a/b.txt", bytes: 3}]), "mark")
    check("a multiple double click on a marked file toggles its mark", Picker.doubleAction(multi, file, "/a/b.txt", "/a/b.txt", [{path: "/a/b.txt", bytes: 3}]), "mark")
    check("a double click on a folder still opens it", Picker.doubleAction(single, folder, "/a/sub", "/a/sub", []), "open")
    check("a multiple double click on a folder still opens it", Picker.doubleAction(multi, folder, "/a/sub", "/a/sub", []), "open")
    check("a multiple second tap on another path changes nothing", Picker.doubleAction(multi, file, "/a/b.txt", "/a/c.txt", []), "none")
    check("a folder request never sends on double click", Picker.doubleAction(Picker.request('{"directory":true}'), file, "/a/b.txt", "/a/b.txt", []), "none")
    check("save mode never sends on double click", Picker.doubleAction(Picker.request('{"mode":"save"}'), file, "/a/b.txt", "/a/b.txt", []), "none")
    check("savefiles mode never sends on double click", Picker.doubleAction(Picker.request('{"mode":"savefiles","multiple":true}'), file, "/a/b.txt", "/a/b.txt", []), "none")
    check("a second tap on another row sends nothing", Picker.doubleAction(single, file, "/a/b.txt", "/a/c.txt", []), "none")
    check("a double click with no first tap sends nothing", Picker.doubleAction(single, file, "/a/b.txt", "", []), "none")
    check("a double click on no row sends nothing", Picker.doubleAction(single, null, "/a/b.txt", "/a/b.txt", []), "none")

    // Issue #191: the picker reopens in the last used view, and only a moving switch owes a write.
    check("a remembered grid reopens as grid", Picker.rememberedView("grid"), "grid")
    check("a remembered list reopens as list", Picker.rememberedView("list"), "list")
    check("a word the picker cannot draw opens the list", Picker.rememberedView("columns"), "list")
    check("an empty stored view opens the list", Picker.rememberedView(""), "list")
    check("a switch to the other view is owed", Picker.viewSwitch("list", "grid"), "grid")
    check("a switch back is owed too", Picker.viewSwitch("grid", "list"), "list")
    check("a repeat press owes nothing", Picker.viewSwitch("grid", "grid"), "")
    check("a word the picker cannot draw owes nothing", Picker.viewSwitch("list", "columns"), "")

    // Issue #221: a second tap on another path is a single tap.
    check("a second tap on the same path counts as a double", Picker.sameTap("/a/b.txt", "/a/b.txt"), true)
    check("a second tap on another path is a single tap", Picker.sameTap("/a/b.txt", "/a/c.txt"), false)
    check("a second tap with no first tap is a single tap", Picker.sameTap("", "/a/b.txt"), false)
    check("a second tap with no path is a single tap", Picker.sameTap("/a/b.txt", ""), false)
    // The chip row is gone, so its width helper and the path minimum it kept leave with it.
    check("the chip strip width helper is gone", typeof Picker.chipStripWidth, "undefined")
    check("the chip path minimum is gone", typeof Picker.CHIP_PATH_MIN, "undefined")

    // Issue #225: the Mac preset's Return/Enter looks up as rename yet still activates.
    var none = Qt.NoModifier
    function looked(preset, key, text) {
        return Keymap.lookupFor(preset, key, text, none, "listing", "gui")
    }
    check("default Return looks up as open", looked("default", Qt.Key_Return, ""), "open")
    check("default Enter looks up as open", looked("default", Qt.Key_Enter, ""), "open")
    check("default Return activates", Picker.activates(looked("default", Qt.Key_Return, ""), Qt.Key_Return), true)
    check("default Enter activates", Picker.activates(looked("default", Qt.Key_Enter, ""), Qt.Key_Enter), true)
    check("default r looks up as rename", looked("default", 0, "r"), "rename")
    check("default r does not activate", Picker.activates("rename", 0), false)
    check("default F2 looks up as rename", looked("default", Qt.Key_F2, ""), "rename")
    check("default F2 does not activate", Picker.activates("rename", Qt.Key_F2), false)
    check("mac Return looks up as rename", looked("mac", Qt.Key_Return, ""), "rename")
    check("mac Enter looks up as rename", looked("mac", Qt.Key_Enter, ""), "rename")
    check("mac Return activates", Picker.activates(looked("mac", Qt.Key_Return, ""), Qt.Key_Return), true)
    check("mac Enter activates", Picker.activates(looked("mac", Qt.Key_Enter, ""), Qt.Key_Enter), true)
    check("mac r does not activate", Picker.activates(looked("mac", 0, "r"), 0), false)
    check("mac r looks up as rename", looked("mac", 0, "r"), "rename")
    check("mac F2 does not activate", Picker.activates(looked("mac", Qt.Key_F2, ""), Qt.Key_F2), false)
    check("mac F2 looks up as rename", looked("mac", Qt.Key_F2, ""), "rename")
    check("open activates", Picker.activates("open", Qt.Key_Return), true)
    check("pageForward activates", Picker.activates("pageForward", Qt.Key_Right), true)
    check("parent never activates", Picker.activates("parent", Qt.Key_Left), false)
    check("escape never activates", Picker.activates("escape", Qt.Key_Escape), false)

    // Issue #191: single grid steps past an end stay; page steps clamp through pageTarget.
    check("a down step moves one tile row", Picker.gridTarget(5, 5, 5, 12), 10)
    check("an up step moves one tile row", Picker.gridTarget(7, -5, 5, 12), 2)
    check("a left step off its row stays", Picker.gridTarget(5, -1, 5, 12), 5)
    check("a right step off its row stays", Picker.gridTarget(9, 1, 5, 12), 9)
    check("a step inside its row moves", Picker.gridTarget(6, 1, 5, 12), 7)
    check("a step past the end stays", Picker.gridTarget(11, 5, 5, 12), 11)
    check("a step past the top stays", Picker.gridTarget(1, -5, 5, 12), 1)
    check("a page past the end clamps to the last tile", Picker.pageTarget(85, 20, 100), 99)
    check("a page past the top clamps to the first tile", Picker.pageTarget(11, -20, 12), 0)
    check("a page inside the listing lands", Picker.pageTarget(5, 20, 100), 25)

    // The grid's visible tiles as listing rows: the tile-row viewport times the column count.
    var range = Picker.tileRange(0, 198, 4, 5, 100)
    check("a settled grid starts at its first tile", range.first, 0)
    check("a settled grid ends at its last visible tile", range.last, 19)
    var scrolled = Picker.tileRange(198, 198, 4, 5, 100)
    check("a scrolled grid starts one tile row down", scrolled.first, 5)
    var tail = Picker.tileRange(0, 198, 4, 5, 12)
    check("a short listing clamps to its last row", tail.last, 11)
    check("the shared window covers the wider grid screen", Picker.windowSize(10, 4, 5), 100)
    check("a wide list still sizes the window", Picker.windowSize(30, 2, 5), 120)
    check("a 160-tile screen fits inside its window lead", Picker.windowSize(37, 10, 16) * 0.75 > 160, true)
    // Sample input: Source.source("ui/PickerWindow.qml") holds the windowSize binding.
    var winSrc = Source.source("ui/PickerWindow.qml")
    check("the window sizes through the shared function",
        winSrc.indexOf("Picker.windowSize(list.visibleRows, grid.visibleTileRows, grid.columns)") >= 0, true)
    check("a view switch reshows the grid", winSrc.indexOf('if (next === "grid") grid.reshow(') >= 0, true)
    check("and the list", winSrc.indexOf("else list.reshow(") >= 0, true)

    // Sample input: function paths(rows, request) queues local tokens before writing protocol requests.
    var listingSrc = Source.source("ui/PickerListing.qml")
    var pathsSrc = Source.slice(listingSrc, "    function paths(rows", "    // Storage class")
    var requestPaths = new Function("current", "quitting", "rows", "request",
        pathsSrc.slice(pathsSrc.indexOf("{") + 1, pathsSrc.lastIndexOf("}")))
    var worker = {running: true, obsolete: false, pathRequests: [], writes: [],
        write: function(line) { this.writes.push(JSON.parse(line)) }}
    check("F33 first paths request starts", requestPaths(worker, false, [0], 1), true)
    check("F33 retry paths request starts", requestPaths(worker, false, [1], 2), true)
    check("F33 worker retains reply tokens in order", JSON.stringify(worker.pathRequests), "[1,2]")
    check("F33 local tokens do not change backend protocol", JSON.stringify(worker.writes),
        '[{"c":"paths","rows":[0]},{"c":"paths","rows":[1]}]')
    // Sample input: onRead receives {"t":"paths","paths":["/b/late"]} before the retry's paths reply.
    var parserMarker = "                onRead: function(line) {"
    var parserSrc = Source.slice(listingSrc, parserMarker, "                }\n            }\n            onExited:")
    var readReply = new Function("root", "process", "line", parserSrc.slice(parserMarker.length))
    var listing = {current: worker, quitting: false, replies: [], messages: [],
        pathsResolved: function(paths, request) { this.replies.push([request, paths]) },
        message: function(message) { this.messages.push(message) },
        failed: function(reason) { throw new Error(reason) }}
    readReply(listing, worker, '{"t":"paths","paths":["/b/late"]}')
    readReply(listing, worker, '{"t":"paths","paths":["/b/fresh"]}')
    check("F33 late and fresh replies keep their own tokens", JSON.stringify(listing.replies),
        '[[1,["/b/late"]],[2,["/b/fresh"]]]')
    readReply(listing, worker, '{"t":"paths","paths":["/b/unsolicited"]}')
    check("F33 unsolicited reply gets no selection token", listing.replies.length, 2)
    readReply(listing, worker, '{"t":"listed","n":2}')
    check("F33 other listing messages still forward", JSON.stringify(listing.messages), '[{"t":"listed","n":2}]')
    // Queue a live request so only the obsolete guard can block its late reply.
    var obsoleteRequest = 3
    check("F43 paths request starts before worker becomes obsolete", requestPaths(worker, false, [0], obsoleteRequest), true)
    check("F43 obsolete reply has a queued token", JSON.stringify(worker.pathRequests), JSON.stringify([obsoleteRequest]))
    worker.obsolete = true
    readReply(listing, worker, '{"t":"paths","paths":["/b/obsolete"]}')
    check("F43 obsolete worker forwards nothing", listing.replies.length, 2)
    check("F33 obsolete worker accepts no paths request", requestPaths(worker, false, [0], obsoleteRequest), false)

    // Picker sort persistence: requesting sort remembers folder sort and updates default sort leaf
    var sortSlice = Source.slice(winSrc, "function requestSort(order) {", "function filterRequest()").trim()
    var factory = new Function("win", "backend", "ViewState", "listing", "return (" + sortSlice + ")")
    var remembered = [], leafChanges = []
    var winMock = { sortable: true, recent: false, path: "/home/gm/Downloads", windowSize: 100, pendingListings: 0,
                    clearListing: function() {}, actionFocus: function() {},
                    restoreActionFocus: function() {} }
    var backendMock = { sortBy: "name", sortDesc: false,
                        rememberFolderSort: function(path, key, desc) { remembered.push({ path: path, key: key, desc: desc }) } }
    var viewMock = { state: { foldersFirst: true, groupByKind: false },
                     changeLeaf: function(key, leaf) { leafChanges.push({ key: key, leaf: leaf }) } }
    var listMock = { sort: function() {}, window: function() {} }
    var runSort = factory(winMock, backendMock, viewMock, listMock)
    runSort({ key: "mtime", desc: true })
    check("picker sort remembers folder sort", JSON.stringify(remembered),
          JSON.stringify([{ path: "/home/gm/Downloads", key: "mtime", desc: true }]))
    check("picker sort updates ViewState sort leaf", JSON.stringify(leafChanges),
          JSON.stringify([{ key: "sort", leaf: { key: "date", reverse: true } }]))
    // With remembering off the folder entry stays unwritten while the default still follows.
    var rememberedOff = [], leafOff = []
    var viewOff = { state: { foldersFirst: true, groupByKind: false, rememberSort: false },
                    changeLeaf: function(key, leaf) { leafOff.push({ key: key, leaf: leaf }) } }
    var backendOff = { sortBy: "name", sortDesc: false,
                       rememberFolderSort: function(path, key, desc) { rememberedOff.push(path) } }
    var runOff = factory({ sortable: true, recent: false, path: "/home/gm/Downloads", windowSize: 100, pendingListings: 0,
                           clearListing: function() {}, actionFocus: function() {},
                           restoreActionFocus: function() {} }, backendOff, viewOff, listMock)
    runOff({ key: "size", desc: false })
    check("picker sort with remembering off writes no folder entry", JSON.stringify(rememberedOff), "[]")
    check("picker sort with remembering off still writes default leaf", JSON.stringify(leafOff),
          JSON.stringify([{ key: "sort", leaf: { key: "size", reverse: false } }]))
    // One builder shapes the Recent, empty path and control sort cases.
    function sortCase(recent, path) {
        var remembered = []
        var backend = { sortBy: "name", sortDesc: false,
                        rememberFolderSort: function(p, k, d) { remembered.push({ path: p, key: k, desc: d }) } }
        var view = { state: { foldersFirst: true, groupByKind: false }, changeLeaf: function() {} }
        var win = { sortable: true, recent: recent, path: path, windowSize: 100, pendingListings: 0,
                    clearListing: function() {}, actionFocus: function() {},
                    restoreActionFocus: function() {} }
        return { backend: backend, remembered: remembered, run: factory(win, backend, view, listMock) }
    }
    // Recent has no folder to remember, but the window sort still changes.
    var recentCase = sortCase(true, "/home/gm/Downloads")
    recentCase.run({ key: "size", desc: true })
    check("picker sort in Recent writes no folder entry and still changes window sort",
          recentCase.backend.sortBy + ":" + recentCase.backend.sortDesc + ":" + JSON.stringify(recentCase.remembered), "size:true:[]")
    // The same shape with a folder remembers its sort, so the Recent and empty path cases fail only on their guard.
    var control = sortCase(false, "/home/gm/Downloads")
    control.run({ key: "size", desc: true })
    check("picker sort control of the same shape remembers one folder entry", JSON.stringify(control.remembered),
          JSON.stringify([{ path: "/home/gm/Downloads", key: "size", desc: true }]))
    // An empty path has no folder to remember, but the window sort still changes.
    var emptyCase = sortCase(false, "")
    emptyCase.run({ key: "size", desc: true })
    check("picker sort with empty path writes no folder entry and still changes window sort",
          emptyCase.backend.sortBy + ":" + emptyCase.backend.sortDesc + ":" + JSON.stringify(emptyCase.remembered), "size:true:[]")
    remembered = []; leafChanges = []
    runSort({ key: "mtime", desc: true })
    check("picker sort asked for the order it has writes nothing", remembered.length + leafChanges.length, 0)
    runSort({ key: "size", desc: false })
    check("picker sort hands a key the schema shares through as is", JSON.stringify(leafChanges),
          JSON.stringify([{ key: "sort", leaf: { key: "size", reverse: false } }]))
    remembered = []; leafChanges = []
    winMock.recent = true
    runSort({ key: "name", desc: false })
    check("picker sort in Recent remembers no folder", remembered.length, 0)
    check("picker sort in Recent still moves the default sort", JSON.stringify(leafChanges),
          JSON.stringify([{ key: "sort", leaf: { key: "name", reverse: false } }]))
    remembered = []; leafChanges = []
    winMock.recent = false
    winMock.path = ""
    runSort({ key: "size", desc: true })
    check("picker sort with no folder remembers none", remembered.length, 0)
    check("picker sort with no folder still moves the default sort", JSON.stringify(leafChanges),
          JSON.stringify([{ key: "sort", leaf: { key: "size", reverse: true } }]))
}
