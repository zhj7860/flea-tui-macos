.import "../../ui/js/Format.js" as Format
.import "../../ui/js/RunFile.js" as RunFile
.import "../../ui/js/Menu.js" as Menu
.import "../../ui/js/Nav.js" as Nav
.import "../../ui/js/Kinds.js" as Kinds
.import "../../ui/js/Focus.js" as Focus
.import "../../ui/js/Tap.js" as Tap
.import "sourcefixture.js" as Source

function menuState(changes) {
    var value = { hasRow: true, selectionCount: 1, rowMode: 0o100644, clipboardAvailable: false,
        rowIsSymlink: false,
        hiddenActions: ["delete", "openTerminal", "moveto", "copyto", "properties", "permissions",
            "copyAs", "pasteAs", "invertSelection"],
        archiveFormats: ["zip"], canExtract: true, rowIsArchive: false, rowIsImage: true, canConvert: true,
        taildropInstalled: true, taildropPeers: [{ id: "box", label: "Box" }],
        dropboxInstalled: true, dropboxPath: "/tmp/Dropbox", rowInDropbox: false }
    for (var key in changes) value[key] = changes[key]
    return value
}
function menuEntry(rows, action) { return rows.filter(function (r) { return r.action === action })[0] || {} }
function run(check) {
    check("a script draws Cancel, Open as text, Run and Run in terminal",
          RunFile.buttonsFor("script", false).join(","), "cancel,text,run,terminal")
    check("an ELF leaves Open as text off, which is not text",
          RunFile.buttonsFor("elf", false).join(","), "cancel,run,terminal")
    check("an AppImage leaves Open as text off, which is not text",
          RunFile.buttonsFor("appimage", false).join(","), "cancel,run,terminal")
    check("an AppImage the desktop names is offered first",
          RunFile.buttonsFor("appimage", true).join(","), "cancel,handler,run,terminal")
    check("a script the desktop names keeps the board's four",
          RunFile.buttonsFor("script", true).join(","), "cancel,text,run,terminal")
    check("no kind draws a Make executable button, which the menu owns",
          ["script", "elf", "appimage"].some(function (k) { return RunFile.buttonsFor(k, true, true).indexOf("make") >= 0 }), false)
    check("the handler button is the app's own name, one whole string",
          RunFile.labelFor("handler", "AppImage Manager") + "|" + RunFile.labelFor("run", "AppImage Manager"), "AppImage Manager|Run")
    check("the ring opens on Run in terminal",
          RunFile.startFocus(RunFile.buttonsFor("script", false), "terminal"), "terminal")
    check("with no tweak a script opens on Run in terminal too",
          RunFile.startFocus(RunFile.buttonsFor("script", false), ""), "terminal")
    check("but on the handler where the desktop names one for an AppImage",
          RunFile.startFocus(RunFile.buttonsFor("appimage", true), ""), "handler")
    check("and the default answers the same way",
          RunFile.defaultButton("appimage", true) + "|" + RunFile.defaultButton("script", false), "handler|terminal")
    check("a tweak naming a drawn button moves it",
          RunFile.startFocus(RunFile.buttonsFor("script", false), "run"), "run")
    check("a tweak naming a button the card did not draw falls back to the default",
          RunFile.startFocus(RunFile.buttonsFor("appimage", false), "text"), "terminal")
    check("h and l stop at the ends",
          RunFile.moved(["cancel", "text", "run", "terminal"], "cancel", Qt.Key_H)
          + "|" + RunFile.moved(["cancel", "text", "run", "terminal"], "terminal", Qt.Key_L),
          "cancel|terminal")
    check("Tab comes round",
          RunFile.moved(["cancel", "text", "run", "terminal"], "terminal", Qt.Key_Tab), "cancel")
    check("Backtab, and Tab with Shift held, come round the other way",
          RunFile.moved(["cancel", "text", "run", "terminal"], "cancel", Qt.Key_Backtab)
          + "|" + RunFile.moved(["cancel", "text", "run", "terminal"], "cancel", Qt.Key_Tab, Qt.ShiftModifier),
          "terminal|terminal")
    check("an unknown focus starts from the default",
          RunFile.moved(["cancel", "text", "run", "terminal"], "bogus", Qt.Key_L), "terminal")
    check("Return, Enter and Space all activate",
          [Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space].every(function (key) { return RunFile.activates(key) }), true)
    check("and no other key does", RunFile.activates(Qt.Key_H), false)
    check("the name row draws the code glyph beside a script",
          RunFile.glyphFor("script"), "code")
    check("and the app glyph beside an AppImage the listing has not drawn",
          RunFile.glyphFor("appimage", ""), "app-window")
    check("a binary takes the mark the listing draws for it",
          RunFile.glyphFor("elf", "terminal") + "|" + RunFile.glyphFor("appimage", "file"), "terminal|file")
    check("a script keeps the board's code glyph whatever the listing draws",
          RunFile.glyphFor("script", "terminal"), "code")
    check("the title names the program",
          RunFile.titleFor("flea-field-bench"), "flea-field-bench is a program")
    check("shown strings are whole templates filled in order, never joined fragments",
          Format.fill("%1 · %2", "a", "b") + "|" + RunFile.TITLE_PROGRAM + "|" + RunFile.SUBTITLE_PROGRAM,
          "a · b|%1 is a program|%1 · %2")
    check("the script row carries its kind and its size",
          RunFile.subtitleFor("script", 9420), "Shell script · 9.4 kB")
    check("the AppImage row carries its own kind",
          RunFile.subtitleFor("appimage", 96000000), "AppImage application bundle · 96.0 MB")
    check("an unknown kind reads as a program",
          RunFile.subtitleFor("bogus", 10), "Program · 10 B")
    check("a path's leaf is its last segment",
          RunFile.leafOf("/home/gm/flea-field-bench"), "flea-field-bench")
    var ask = RunFile.parseAsk('{"ask":"run","kind":"script","size":9420,"handlerId":"","handlerName":"","dev":"8","ino":"9","mtimeS":11,"mtimeNs":12,"target":"/d/tool.sh"}')
    check("the ask line parses to its kind and size",
          ask && ask.kind + "|" + ask.size + "|" + ask.hasHandler, "script|9420|false")
    var named = RunFile.parseAsk('{"ask":"run","kind":"appimage","size":8,"handlerId":"a.desktop","handlerName":"AppImage Manager","dev":"8","ino":"9","mtimeS":11,"mtimeNs":12,"target":"/d/app"}')
    check("an AppImage ask carries its handler's id and own name",
          named && named.hasHandler + "|" + named.handlerId + "|" + named.handlerName, "true|a.desktop|AppImage Manager")
    check("a handler with no name offers no handler",
          RunFile.parseAsk('{"ask":"run","kind":"appimage","size":8,"handlerId":"a.desktop","handlerName":"","dev":"8","ino":"9","mtimeS":11,"mtimeNs":12,"target":"/d/app"}').hasHandler, false)
    check("an open-with ask is not a run ask",
          RunFile.parseAsk('{"ask":"openWith"}'), null)
    check("junk is not a run ask either", RunFile.parseAsk("hello"), null)
    check("and neither is a kind the board never drew",
          RunFile.parseAsk('{"ask":"run","kind":"mach-o","size":8}'), null)
    runMenu(check)
    runFixR1(check)
}

// Advloop round 1: the card acts on its own path, spoofed names stay visible, and the ask keeps dev and ino as strings with the resolved target.
function runFixR1(check) {
    check("U+061C shows escaped", RunFile.escapeName("a\u061Cb"), "a<U+061C>b")
    check("U+2028 shows escaped", RunFile.escapeName("a\u2028b"), "a<U+2028>b")
    check("U+2029 shows escaped", RunFile.escapeName("a\u2029b"), "a<U+2029>b")
    var ask = RunFile.parseAsk('{"ask":"run","kind":"script","size":8,"handlerId":"","handlerName":"","dev":"8","ino":"9","mtimeS":"11","mtimeNs":"12","target":"/real.sh"}')
    check("dev and ino stay strings end to end",
          ask && typeof ask.dev + "|" + typeof ask.ino, "string|string")
    check("the ask names the resolved target", ask && ask.target, "/real.sh")
    check("the card carries the ask identity to its launches",
          ["card.run(card.path, card.dev, card.ino, card.size, card.mtimeS, card.mtimeNs)",
           "card.runTerminal(card.path, card.dev, card.ino, card.size, card.mtimeS, card.mtimeNs)"
           ].every(function (needle) { return Source.source("ui/js/RunFile.js").indexOf(needle) >= 0 })
          && ['"--run", path, dev, ino, size, mtimeS, mtimeNs',
              '"--run-terminal", path, dev, ino, size, mtimeS, mtimeNs'
              ].every(function (needle) { return cardSource().indexOf(needle) >= 0 }), true)
    check("the wire routes an ask to the card",
          Source.source("ui/PaneWire.qml").indexOf("askRunCard") >= 0, true)
    check("every product pane names its overlay parent", paneParents(), "2|2")
}

// The card's own source, or "" when it is reverted: the card pins below fail instead of aborting the suite.
function cardSource() {
    try {
        return Source.source("ui/RunCard.qml")
    } catch (e) {
        return ""
    }
}

// Every Flea.Pane block in the window names overlayParent within its first lines, so no product pane has a null one.
function paneParents() {
    var text = Source.source("ui/WindowBody.qml")
    var parts = text.split("Flea.Pane {")
    var named = 0
    for (var i = 1; i < parts.length; i++) {
        if (parts[i].substring(0, 2000).indexOf("overlayParent:") >= 0) named++
    }
    return (parts.length - 1) + "|" + named
}

function runMenu(check) {
    var file = Menu.listingEntries(menuState({}))
    check("Run and Open as text name the run card and the text editor",
          menuEntry(file, "run").label + "|" + menuEntry(file, "openAsText").label, "Run|Open as text")
    check("a directory is not offered the run rows",
          menuEntry(Menu.listingEntries(menuState({ rowMode: 0o040755 })), "run").action + "|"
          + menuEntry(Menu.listingEntries(menuState({ rowMode: 0o040755 })), "openAsText").action, "undefined|undefined")
    check("and neither is a multi-selection",
          menuEntry(Menu.listingEntries(menuState({ hiddenActions: [], selectionCount: 2 })), "run").action, undefined)
    runActivation(check)
    runNames(check)
    runEntrances(check)
}

// R1: Enter, double click and menu Open all funnel through Nav.openCursor; a file row of any program kind leaves it through opener.open, never pane.open or quickLook. The exit-4 ask and the no-spawn half live below this seam and are pinned by rb7_open_ask in src/runfile_tests.rs.
function cursorPane(row) {
    return {
        listInFlight: false, cursorIndex: 3, path: "/d",
        rowFor: function () { return row },
        join: function (dir, name) { return dir + "/" + name },
        open: function (path) { this.opened.push(path) },
        opened: [],
        message: function (text) { this.said.push(text) },
        said: [],
        quickLook: function () { var self = this; return { open: function () { self.qlOpened.push("ql") } } },
        qlOpened: [],
        kindNames: {}, thumbState: null, shown: null
    }
}

function runActivation(check) {
    var opener = { opened: [], open: function (path) { this.opened.push(path) } }
    var script = cursorPane({ d: false, i: "text-x-script", n: "tool.sh", s: 8 })
    Nav.openCursor(script, opener)
    check("a file row leaves openCursor through the card entrance",
          opener.opened.join("|") + "|" + script.opened.length + "|" + script.qlOpened.length, "/d/tool.sh|0|0")
    var elf = cursorPane({ d: false, i: "application-x-executable", n: "prog", s: 8 })
    Nav.openCursor(elf, opener)
    var app = cursorPane({ d: false, i: "application-x-executable", n: "bundle", s: 8 })
    Nav.openCursor(app, opener)
    check("program rows of every kind reach the opener, never the preview",
          opener.opened.slice(1).join("|") + "|" + (elf.qlOpened.length + app.qlOpened.length) + "|" + (elf.opened.length + app.opened.length),
          "/d/prog|/d/bundle|0|0")
    var folder = cursorPane({ d: true, i: "folder", n: "sub", s: 0 })
    Nav.openCursor(folder, opener)
    check("a directory row navigates instead", folder.opened.join("|"), "/d/sub")
    var archiveOpener = { opened: [], open: function (path) { this.opened.push(path) } }
    var archive = cursorPane({ d: false, i: "package-x-generic", n: "b.zip", s: 8 })
    Nav.openCursor(archive, archiveOpener)
    check("an archive row previews instead of asking",
          archive.qlOpened.length + "|" + archiveOpener.opened.length, "1|0")
    // 7z lists an AppImage, but Enter on one still asks on the run card (RunFile #60).
    var bundle = cursorPane({ d: false, i: "application-x-executable", n: "Obsidian-1.9.AppImage", s: 8 })
    check("the preview's classifier calls that row an archive, so only the AppImage guard keeps it off Quick Look",
          Kinds.quickLookKind(bundle.rowFor(0).i, "/d/Obsidian-1.9.AppImage"), Kinds.ARCHIVE)
    Nav.openCursor(bundle, archiveOpener)
    check("an AppImage row asks on the run card, never the archive preview",
          bundle.qlOpened.length + "|" + archiveOpener.opened.join("|"), "0|/d/Obsidian-1.9.AppImage")
    // An extensionless program reaches the card whichever mark its row carries: the open predicate never reads the icon.
    var named = { opened: [], open: function (path) { this.opened.push(path) } }
    var plain = cursorPane({ d: false, i: "text-x-generic", n: "PinyonShiftLauncher", s: 8 })
    var program = cursorPane({ d: false, i: "application-x-executable", n: "PinyonShiftLauncher", s: 8 })
    Nav.openCursor(plain, named)
    Nav.openCursor(program, named)
    check("an extensionless program reaches the card under either mark",
          named.opened.join("|") + "|" + plain.qlOpened.length + program.qlOpened.length, "/d/PinyonShiftLauncher|/d/PinyonShiftLauncher|00")
    var keyed = { opened: false, openCursor: function () { this.opened = true } }
    Focus.act("open", keyed)
    check("the menu Open reaches the same cursor", keyed.opened, true)
    var tapped = { singleClick: false, searchMode: "", commitOpenRename: function () {}, path: "/d",
        rowFor: function () { return { d: false, n: "tool.sh" } },
        selectOnly: function () {}, act: function (action) { this.acted.push(action) }, acted: [] }
    Tap.tapped(3, 2, 0, tapped)
    check("a double click reaches the same open", tapped.acted.join(","), "open")
    check("the picker answers requests and never executes",
          ["opener.open", "opener.run", "--run", "RunCard", "askRun"].every(function (needle) {
              return Source.source("ui/PickerWindow.qml").indexOf(needle) < 0
          }), true)
    check("a drag carries paths and never executes",
          ["opener.open", "opener.run", "--run", "RunCard", "askRun"].every(function (needle) {
              return Source.source("ui/FileDrag.qml").indexOf(needle) < 0
                  && Source.source("ui/RowDrag.qml").indexOf(needle) < 0
          }), true)
}

// The menu Run entrances share openableRow's guards through Nav.runCursor and always reach the opener: a refused row says why, anything else opens.
function runEntrances(check) {
    var opener = { opened: [], open: function (path) { this.opened.push(path) },
        textOpened: [], openText: function (path) { this.textOpened.push(path) } }
    function entrance() {
        return { listInFlight: false, cursorIndex: 3, path: "/d", shown: null,
            rowFor: function () { return { d: false, i: "text-x-script", n: "tool.sh", s: 8 } },
            join: function (dir, name) { return dir + "/" + name },
            message: function (text) { this.said.push(text) }, said: [],
            opener: opener, runText: function (path) { opener.textOpened.push(path) },
            openCursor: function () { this.said.push("plain open route") } }
    }
    var run = entrance()
    Focus.act("run", run)
    check("the menu Run reaches the opener and not the plain open route", opener.opened.join("|") + "|" + run.said.join("|"), "/d/tool.sh|")
    var text = entrance()
    Focus.act("openAsText", text)
    check("and Open as text reaches the text editor", opener.textOpened.join("|"), "/d/tool.sh")
    var refused = { opened: [], open: function (path) { this.opened.push(path) } }
    var hidden = entrance()
    hidden.shown = []
    hidden.opener = refused
    Nav.runCursor(hidden, refused, "open")
    check("a hidden row refuses with its reason",
          hidden.said.join("|") + "|" + refused.opened.length,
          "That row is hidden by the filter.|0")
    var loading = entrance()
    loading.listInFlight = true
    loading.opener = refused
    var textBefore = opener.textOpened.length
    Nav.runCursor(loading, refused, "open")
    Nav.runCursor(loading, refused, "openText")
    check("Run while a listing is in flight refuses with its reason",
          loading.said.join("|") + "|" + refused.opened.length + "|" + (opener.textOpened.length - textBefore),
          "A directory is already loading.|A directory is already loading.|0|0")
    // A waiting listing keeps its drawn rows until they land, so Run reads the drawn row through the drawn base.
    var waiting = entrance()
    waiting.listInFlight = true
    waiting.listingState = "waiting"
    waiting.listingPath = "/d/next"
    waiting.pendingSelect = ""
    waiting.opener = { opened: [], open: function (path) { this.opened.push(path) }, textOpened: [], openText: function (path) { this.textOpened.push(path) } }
    waiting.ranText = []
    waiting.runText = function (path) { waiting.ranText.push(path) }
    Nav.runCursor(waiting, waiting.opener, "open")
    check("Run past the wait reaches the opener on the drawn row", waiting.opener.opened.join("|"), "/d/tool.sh")
    check("Run past the wait keeps the wait, the cursor and the asked path", waiting.listingState + "|" + waiting.listInFlight + "|" + waiting.cursorIndex + "|" + waiting.listingPath + "|" + waiting.pendingSelect + "|" + waiting.said.length, "waiting|true|3|/d/next||0")
    Nav.runCursor(waiting, waiting.opener, "openText")
    check("Open as text past the wait goes through the window's run lane, not the opener", waiting.ranText.join("|") + "|" + waiting.opener.textOpened.length, "/d/tool.sh|0")
    runLane(check)
}

// The card owns the window's one single-flight run lane: every choice leaves through it with the ask's identity, the handler with the id the card named.
function runLane(check) {
    function drive(kind) {
        var calls = []
        var lane = { path: "/d/tool.sh", listedPath: "/listed/link.sh", kind: kind, dev: "8", ino: "9", size: 10, mtimeS: 11, mtimeNs: 12,
            handlerId: "a.desktop",
            run: function (path, dev, ino, size, mtimeS, mtimeNs) {
                calls.push(["run", path, dev, ino, size, mtimeS, mtimeNs].join("|")) },
            runTerminal: function (path, dev, ino, size, mtimeS, mtimeNs) {
                calls.push(["terminal", path, dev, ino, size, mtimeS, mtimeNs].join("|")) },
            openHandler: function (path, id, dev, ino, size, mtimeS, mtimeNs) {
                calls.push(["handler", path, id, dev, ino, size, mtimeS, mtimeNs].join("|")) },
            openText: function (path) { calls.push("text|" + path) } }
        var pane = { makeExecutable: function (paths) { calls.push("make|" + (paths || []).join("|")) },
            showOpenWith: function (path) { calls.push("openwith|" + path) } }
        RunFile.choose(pane, lane, "run")
        RunFile.choose(pane, lane, "terminal")
        RunFile.choose(pane, lane, "text")
        RunFile.choose(pane, lane, "make")
        RunFile.choose(pane, lane, "handler")
        return calls.join(",")
    }
    check("every choice leaves through the card lane with the ask identity, and make is no choice at all",
          drive("appimage"), "run|/d/tool.sh|8|9|10|11|12,terminal|/d/tool.sh|8|9|10|11|12,"
          + "text|/d/tool.sh,handler|/d/tool.sh|a.desktop|8|9|10|11|12")
}

// R4: control and bidi characters show escaped; a clean name is untouched.
function runNames(check) {
    check("a bidi override shows escaped", RunFile.escapeName("a\u202Eb.sh"), "a<U+202E>b.sh")
    check("a tab shows escaped", RunFile.escapeName("a\tb"), "a<U+0009>b")
    check("a clean name passes through", RunFile.escapeName("plain.sh"), "plain.sh")
    check("and the title escapes what it names", RunFile.titleFor("x\u202Ey"), "x<U+202E>y is a program")
}
