.import "../../ui/js/Tags.js" as Tags
.import "../../ui/js/Filter.js" as Filter
.import "../../ui/js/Search.js" as Search
.import "../../ui/js/Filter.js" as Filter
.import "../../ui/js/Menu.js" as Menu
.import "menu.js" as MenuSuite
.import "../../ui/js/Messages.js" as Messages
.import "sourcefixture.js" as Source

function run(check) {
    var routed = []
    var tagRoot = {settagged: function (m) { routed.push("settagged:" + m.ok) },
                   tagStatesResult: function (m) { routed.push("tagStatesResult:" + m.id) }}
    Messages.route(tagRoot, {t: "settagged", ok: 2, op: "remove"})
    Messages.route(tagRoot, {t: "tagstates", id: 3, applied: ["Red"], mixed: [], listing: 7})
    check("each tag message reaches its own Backend signal", routed.join(","), "settagged:2,tagStatesResult:3")
    check("seven names in menu order", Tags.NAMES.join(","), "Red,Orange,Yellow,Green,Blue,Purple,Gray")
    check("a tag on every file is applied", Tags.stateFor([["Red"], ["Red", "Blue"]], "Red"), "applied")
    check("a tag on some files is mixed", Tags.stateFor([["Red"], ["Blue"]], "Red"), "mixed")
    check("a tag on no file is absent", Tags.stateFor([["Red"], ["Blue"]], "Green"), "absent")
    check("an empty selection is absent, not applied", Tags.stateFor([], "Red"), "absent")
    check("statesFor reports every name", Tags.statesFor([["Red"], ["Blue"]]).Red, "mixed")
    check("statesFor reports an untouched name absent", Tags.statesFor([["Red"], ["Blue"]]).Green, "absent")
    check("one item is singular", Tags.statusLine(1, "Red"), "Tagged 1 item Red \u00b7 z undoes")
    check("three items are plural", Tags.statusLine(3, "Red"), "Tagged 3 items Red \u00b7 z undoes")
    check("clearing one item is singular", Tags.clearedLine(1), "Removed all tags from 1 item \u00b7 z undoes")
    check("clearing three items is plural", Tags.clearedLine(3), "Removed all tags from 3 items \u00b7 z undoes")
    check("removing from one item is singular", Tags.removedLine(1, "Red"), "Removed Red from 1 item \u00b7 z undoes")
    check("removing from three items is plural", Tags.removedLine(3, "Red"), "Removed Red from 3 items \u00b7 z undoes")
    check("an add answer says Tagged", Tags.changedLine("add", 2, "Blue"), "Tagged 2 items Blue \u00b7 z undoes")
    check("a remove answer says Removed", Tags.changedLine("remove", 2, "Blue"), "Removed Blue from 2 items \u00b7 z undoes")
    check("a clear answer says all tags", Tags.changedLine("clear", 1, ""), "Removed all tags from 1 item \u00b7 z undoes")
    check("one skipped row counts one item", Tags.skippedLine(["c.lnk"]), "1 item skipped")
    check("many skipped rows count items", Tags.skippedLine(["a.lnk", "b.lnk"]), "2 items skipped")
    check("a skip beside a change joins the fragment ahead of the undo hint", Tags.doneLine("add", 2, "Blue", ["c.lnk"]),
        "Tagged 2 items Blue \u00b7 1 item skipped \u00b7 z undoes")
    check("two skips beside a change count items", Tags.doneLine("add", 3, "Red", ["a.lnk", "b.lnk"]),
        "Tagged 3 items Red \u00b7 2 items skipped \u00b7 z undoes")
    check("a skip with no change says only the skip", Tags.doneLine("add", 0, "Blue", ["c.lnk"]), "1 item skipped")
    check("a change with no skip says only the change", Tags.doneLine("remove", 2, "Blue", []), "Removed Blue from 2 items \u00b7 z undoes")
    check("an absent skip list says only the change", Tags.doneLine("add", 1, "Red", undefined), "Tagged 1 item Red \u00b7 z undoes")
    check("no change and no skip says nothing", Tags.doneLine("add", 0, "Red", undefined), "")
    var read = Tags.statesFrom(["Red"], ["Blue"])
    check("a backend read gives each name its state", [read.Red, read.Blue, read.Green].join(","), "applied,mixed,absent")
    check("the flyout names seven tags then remove-all", Tags.tagEntries({Red: "absent"}).map(function (e) { return e.separator === true ? "sep" : e.id }).join(","),
        "Red,Orange,Yellow,Green,Blue,Purple,Gray,sep,__clear__")
    check("the flyout carries each tag digit", Tags.tagEntries({}).filter(function (e) { return e.tagRow }).map(function (e) { return e.tagRow.digit }).join(""), "1234567")
    check("the flyout carries the mixed bar", Tags.tagEntries({Red: "mixed"}).filter(function (e) { return e.id === "Red" })[0].tagRow.state, "mixed")
    check("the flyout keys swatches by name", Tags.tagEntries({}).filter(function (e) { return e.id === "Red" })[0].tagRow.swatch, "Red")
    check("the flyout hints each row with its digit", Tags.tagEntries({}).filter(function (e) { return e.keyHint }).map(function (e) { return e.keyHint }).join(""), "1234567")
    check("the rail lists only tags in use, in menu order", Tags.railEntries({Blue: true, Red: true}).map(function (e) { return e.tag }).join(","), "Red,Blue")
    check("the rail rows carry their digit", Tags.railEntries({Gray: true}).map(function (e) { return e.digit }).join(","), "7")
    var file = Menu.listingEntries(MenuSuite.state({ tagSubmenu: Tags.tagEntries({Red: "absent"}, false) }))
    check("Tags follows Add to Favorites with its flyout", MenuSuite.entry(file, "tags").submenu.length, 9)
    check("the flyout spans seven tags, a separator and remove-all",
          MenuSuite.entry(file, "tags").submenu.map(function (r) { return r.separator === true ? "sep" : r.id }).join(","), "Red,Orange,Yellow,Green,Blue,Purple,Gray,sep,__clear__")
    var states = Tags.statesFor([["Red", "Blue"], ["Red"]])
    check("the flyout carries each state", Tags.tagEntries(states).filter(function (r) { return r.id === "Red" || r.id === "Blue" }).map(function (r) { return r.tagRow.state }).join(","), "applied,mixed")
    check("Tags row follows Add to Favorites", MenuSuite.actions(file).split(",").slice(-4).join(","), "addFavourite,tags,toggleHidden,toggleLangMarks")
    check("a menu with no flyout offers no Tags row, as where the filesystem cannot store tags", MenuSuite.entry(Menu.listingEntries(MenuSuite.state({})), "tags").action, undefined)
    var window = [{ n: "a", tg: ["Red", "Blue"] }, { n: "b" }]
    var use = {}
    var seen = Tags.stamp(window, false, use, true)
    check("a tagged row latches the slot for every row of the reply", seen.latched + "|" + window[0].shown + "|" + window[1].shown, "true|true|true")
    check("the tags seen are recorded", Object.keys(use).join(","), "Red,Blue")
    check("a first sighting reports growth", seen.grew, true)
    var later = [{ n: "c" }]
    check("the slot stays for a later reply of the same folder", Tags.stamp(later, true, use, false).latched + "|" + later[0].shown, "true|true")
    check("a fresh listing without a tagged row drops the slot", Tags.stamp(later, true, use, true).latched + "|" + later[0].shown, "false|false")
    check("a folder with no tagged row never draws the slot", Tags.stamp([{ n: "d" }], false, {}, false).latched, false)
    check("a tag already seen reports no growth", Tags.stamp([{ n: "e", tg: ["Red"] }], false, use, false).grew, false)
    // Ruling A: the shipped setTaggedDone gates the line on ok, so a write that changed nothing stays silent.
    var doneBody = Source.block(Source.source("ui/TagState.qml"), "function setTaggedDone(message)", "ui/TagState.qml")
    function landed(pending, message) {
        var pane = { held: 0, windowSize: 1, backend: { window: function () {} },
            said: "", message: function (t) { this.said = t } }
        var root = { pending: pending, asked: null, asking: null, pane: pane }
        new Function("root", "Tags", "return function (message) {" + doneBody + "}")(root, Tags)(message)
        return pane.said
    }
    check("a no-op clear prints no z line", landed([{ tag: "" }], { ok: 0, op: "clear" }), "")
    check("a clear that changed rows prints the z line", landed([{ tag: "" }], { ok: 2, op: "clear" }),
        "Removed all tags from 2 items \u00b7 z undoes")
    check("a real toggle still says what it did", landed([{ tag: "Blue" }], { ok: 2, op: "add" }),
        "Tagged 2 items Blue \u00b7 z undoes")
    // A rail tag row click walks for that tag: the session opens first, then its tag query sends.
    var openBody = Source.block(Source.source("ui/TagState.qml"), "function openTag(name)", "ui/TagState.qml")
    var openSent = []
    var openPane = { searchHere: true, searchQuery: "", searchMode: "", searchGen: 0, searchOpenedGen: 0,
        path: "/h/d", home: "/h", cursorIndex: 0, recentMode: "", recentFrom: "", recentPaths: [],
        searchFrom: "", searchBase: "", searchRunning: false, searchCancelled: false, searchScanned: 0,
        windowSize: 200, pendingSelect: "", filterQuery: "x", filterTyping: true,
        rowFor: function () { return null },
        join: function (base, name) { return base + "/" + name },
        restoreRecentSort: function () {},
        backend: { searchOpen: function (scope) { openSent.push("searchopen " + scope) },
                   searchQuery: function (query) { openSent.push("searchquery " + query) } } }
    new Function("root", "Search", "Filter", "return function (name) {" + openBody + "}")({ pane: openPane }, Search, Filter)("Red")
    check("a tag row click opens a session at home, not the pane's folder, then sends its tag query",
        openSent.join(","), "searchopen /h,searchquery tag:Red")
    // The shared swatch and heading name their constants and leave Qt's Item.palette alone.
    var swatchSrc = Source.source("ui/TagSwatch.qml")
    check("TagSwatch takes its colour map as tagColors, not as Item.palette",
        swatchSrc.indexOf("required property var tagColors") >= 0 && swatchSrc.indexOf("palette") < 0, true)
    check("TagSwatch names its fallback border", swatchSrc.indexOf("readonly property int fallbackBorder: 2") >= 0 && swatchSrc.indexOf("? root.fallbackBorder : 0") >= 0, true)
    check("every caller passes tagColors", ["TagSlot", "TagMenuMark", "TagRailSection"].every(function (f) {
        var src = Source.source("ui/" + f + ".qml")
        return src.indexOf("tagColors: Theme.tag.") >= 0 && src.indexOf("palette:") < 0 }), true)
    var headingSrc = Source.source("ui/RailHeading.qml")
    check("RailHeading names its lead and tracking", headingSrc.indexOf("headingLead: 0.15") >= 0 && headingSrc.indexOf("headingTracking: 1") >= 0
        && headingSrc.indexOf("* root.headingLead") >= 0 && headingSrc.indexOf("letterSpacing: root.headingTracking") >= 0, true)
    check("and it closes a standing filter first, so the red files without the filter's letter still list",
        openPane.filterQuery + "|" + openPane.filterTyping + "|" + Filter.shown([{ n: "apple.txt" }, { n: "box.txt" }], 0, openPane.filterQuery), "|false|null")

    // Nav.js drops canTag at the request and only the fs line brings it back; under a loading mark that line meets the old path.
    var fsBody = Source.block(Source.source("ui/PaneWire.qml"), "function onFsInfo(fs, free, path, storageClass, tagable, systemVolume)", "ui/PaneWire.qml")
    var fsLine = new Function("pane", "root", "ExtThumbs", "ViewState", "return function (fs, free, path, storageClass, tagable, systemVolume) {" + fsBody + "}")
    function fsLineAt(listInFlight, path, panePath) {
        var out = { path: panePath || "", listingPath: "/fx/v/work", listInFlight: listInFlight, recentMode: "", fsName: "", fsFree: 0,
                    storageClass: "", storageKnown: false, systemVolume: false, canTag: false, extVerdict: "", listArea: null }
        fsLine(out, { pane: out }, { verdict: function () { return "" } }, { preview: "" })("tmpfs", 64100000, path, "", true, false)
        return out.canTag + "|" + out.storageKnown
    }
    check("the fs line of the listing still out brings the tag verdict, so the Tags row is offered at the first menu",
          fsLineAt(true, "/fx/v/work"), "true|true")
    check("the fs line of a listing no longer out is refused, so a late answer for a settled listing path brings no verdict",
          fsLineAt(false, "/fx/v/work"), "false|false")
    check("the fs line for a path that is neither the pane's nor the listing's is refused even while a listing is out",
          fsLineAt(true, "/fx/v/other"), "false|false")
    check("the fs line for the settled pane's own path is accepted with no listing out",
          fsLineAt(false, "/fx/v/work", "/fx/v/work"), "true|true")
}
