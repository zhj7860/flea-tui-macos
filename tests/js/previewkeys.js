.import "../../ui/js/Focus.js" as Focus
.import "../../ui/js/PreviewKeys.js" as PreviewKeys
.import "../../ui/js/Keymap.js" as Keymap
.import "sourcefixture.js" as Source
.import "documentview.js" as DocumentView

function run(check) {
    var activated = []
    var viewer = { pdfControlIndex: -1, pdfControls: [], turnPage: function() {},
        zoomBy: function() {}, toggleExpand: function() {}, scrollPage: function() {} }
    for (var i = 0; i < 6; i++) {
        (function(index) {
            viewer.pdfControls.push({enabled: index !== 0 && index !== 2, visible: true,
                activated: function() { activated.push(index) }})
        })(i)
    }
    PreviewKeys.pdfAction("focusNext", viewer)
    check("PDF focus enters first enabled control", viewer.pdfControlIndex, 1)
    PreviewKeys.pdfAction("preview", viewer)
    PreviewKeys.pdfAction("focusPrevious", viewer)
    check("PDF reverse focus wraps to Close", viewer.pdfControlIndex, 5)
    PreviewKeys.pdfAction("open", viewer)
    check("Space and Enter activate the focused PDF controls", activated.join(","), "1,5")
    viewer.pdfControls[5].enabled = false
    PreviewKeys.pdfAction("preview", viewer)
    check("a control disabled after focus never activates", activated.join(","), "1,5")
    viewer.pdfControls[5].visible = false
    PreviewKeys.pdfAction("focusNext", viewer)
    check("forward wrap skips disabled Previous", viewer.pdfControlIndex, 1)
    PreviewKeys.pdfAction("trash", viewer)
    check("listing actions do nothing in PDF context", activated.join(","), "1,5")

    // The column's PDF has no strip and no controls: pages scroll, and Space, Return and e open Quick Look at the page in view.
    for (var colPreset of ["default", "vim", "mac", "windows"]) {
        var colLog = []
        var column = { turnPage: function (delta) { colLog.push("turn " + delta) }, scrollPage: function (delta) { colLog.push("scroll " + delta) },
            toggleExpand: function () { colLog.push("expand") } }
        var keys = [[Qt.Key_Space, " "], [Qt.Key_Return, "\r"], [Qt.Key_E, "e"], [Qt.Key_Right, ""], [Qt.Key_Left, ""], [Qt.Key_L, "l"], [Qt.Key_H, "h"],
                    [Qt.Key_Down, ""], [Qt.Key_Up, ""], [Qt.Key_Plus, "+"], [Qt.Key_Tab, ""]]
        keys.forEach(function (k) { PreviewKeys.pdfAction(Keymap.lookupFor(colPreset, k[0], k[1], Qt.NoModifier, "pdf", "gui"), column) })
        check(colPreset + ": the column's PDF opens Quick Look, turns and scrolls, and ignores zoom and focus keys",
            colLog.join(","), "expand,expand,expand,turn 1,turn -1,turn 1,turn -1,scroll 1,scroll -1")
    }

    // Quick Look's PDF viewer opens with no control picked (-1): its keys act on the document, Return activates nothing, Shift+Tab enters at Close.
    for (var preset of ["default", "vim", "mac", "windows"]) {
        var log = []
        var idle = { pdfControlIndex: -1, pdfControls: [], turnPage: function (delta) { log.push("turn " + delta) },
            zoomBy: function (steps) { log.push("zoom " + steps) }, toggleExpand: function () { log.push("expand") }, scrollPage: function () {} }
        for (var c = 0; c < 6; c++) {
            (function (index) {
                idle.pdfControls.push({ enabled: index !== 0 && index !== 2, visible: true, activated: function () { log.push("activate " + index) } })
            })(c)
        }
        var press = function (key, text, modifiers) {
            var action = Keymap.lookupFor(preset, key, text, modifiers, "pdf", "gui")
            PreviewKeys.pdfAction(action, idle)
            return action
        }
        var actions = [press(Qt.Key_Return, "\r", Qt.NoModifier), press(Qt.Key_L, "l", Qt.NoModifier), press(Qt.Key_Plus, "+", Qt.NoModifier)]
        check(preset + ": with no PDF control picked, Return activates nothing, l turns the page and + zooms in",
            actions.join(",") + " | " + log.join(",") + " | " + idle.pdfControlIndex, "open,pageForward,zoomIn | turn 1,zoom 1 | -1")
        press(Qt.Key_Backtab, "", Qt.ShiftModifier)
        check(preset + ": Shift+Tab with no PDF control picked enters the strip at Close", idle.pdfControlIndex, 5)
    }

    // Decided 2026-09-11: pressing Space a second time closes the preview, the way Finder
    // does. It closes on every kind, media included, which reverses Task 22's play/pause on space.
    function previewPane(kind) {
        var pane = { closed: 0, played: 0 }
        pane.preview = {
            isMedia: kind === "audio" || kind === "video",
            isPdf: kind === "pdf",
            revealStrip: function () {},
            close: function () { pane.closed += 1 },
            togglePlay: function () { pane.played += 1 }
        }
        return pane
    }
    for (var kind of ["text", "image", "pdf", "archive", "audio", "video"]) {
        var open = previewPane(kind)
        PreviewKeys.act("preview", open)
        check("space closes a " + kind + " preview", open.closed, 1)
        check("and plays nothing on a " + kind + " preview", open.played, 0)
    }
    // Escape still closes, because a preview must never need a particular key to leave it.
    var escaped = previewPane("video")
    PreviewKeys.act("escape", escaped)
    check("escape still closes a media preview", escaped.closed, 1)

    // Space no longer plays, so p does, and only where there is something to play.
    var tune = previewPane("audio")
    PreviewKeys.act("playPause", tune)
    check("p plays and pauses a media preview", tune.played, 1)
    check("and closes nothing", tune.closed, 0)
    var still = previewPane("image")
    PreviewKeys.act("playPause", still)
    check("p does nothing to a still preview", still.played + still.closed, 0)
    check("space maps to preview in the pdf context", Keymap.lookupFor("default", Qt.Key_Space, " ", Qt.NoModifier, "pdf", "gui"), "preview")
    var viewerSrc = Source.source("ui/PdfViewer.qml")
    var keysBody = Source.slice(viewerSrc, "Keys.onPressed", "readonly property int page")
    check("the pdf viewer closes on the preview action", keysBody.indexOf('|| action === "preview") root.closed()') >= 0, true)

    // Rendered document kinds share r; the flip is transient and forgotten on close.
    function markPane(markdown, html) {
        var pane = { switched: 0 }
        pane.preview = {
            isMarkdown: markdown,
            isHtml: html === true,
            isDocument: markdown || html === true,
            revealStrip: function () {},
            toggleMarkdownView: function () { pane.switched += 1 }
        }
        return pane
    }
    var notes = markPane(true)
    PreviewKeys.act("markdownView", notes)
    check("r switches a Markdown preview", notes.switched, 1)
    var page = markPane(false, true)
    PreviewKeys.act("markdownView", page)
    check("r switches an HTML preview", page.switched, 1)
    var photo = markPane(false)
    PreviewKeys.act("markdownView", photo)
    check("r does nothing to a non-document preview", photo.switched, 0)
    check("r maps to markdownView in the preview context",
        Keymap.lookupFor("default", 0, "r", Qt.NoModifier, "preview", "gui"), "markdownView")
    var quickSrc = Source.source("ui/Preview.qml")
    DocumentView.run(check, quickSrc, Source.source("ui/ViewState.qml"), Source.block)
    check("r stays rename in the listing",
        Keymap.lookupFor("default", 0, "r", Qt.NoModifier, "listing", "gui"), "rename")
    // ButtonSystem040: Tab and Shift+Tab put the keyboard on the Markdown bar's close mark and take it off; Return or Space on it closes.
    function closePane(drawsBar) {
        var pane = { closed: 0 }
        pane.preview = {
            hasBar: drawsBar,
            markdownCloseFocused: false,
            revealStrip: function () {},
            toggleMarkdownClose: function () { pane.preview.markdownCloseFocused = !pane.preview.markdownCloseFocused },
            close: function () { pane.closed += 1 }
        }
        return pane
    }
    var bar = closePane(true)
    PreviewKeys.act("focusNext", bar)
    check("Tab focuses the bar's close mark", bar.preview.markdownCloseFocused, true)
    PreviewKeys.act("focusPrevious", bar)
    check("Shift+Tab takes the focus off it", bar.preview.markdownCloseFocused, false)
    PreviewKeys.act("open", bar)
    check("Return on a close mark that holds no focus closes nothing", bar.closed, 0)
    PreviewKeys.act("focusPrevious", bar)
    check("Shift+Tab also reaches the close mark", bar.preview.markdownCloseFocused, true)
    PreviewKeys.act("open", bar)
    check("Return on the focused close mark closes", bar.closed, 1)
    PreviewKeys.act("preview", bar)
    check("Space still closes", bar.closed, 2)
    PreviewKeys.act("escape", bar)
    check("Escape still closes", bar.closed, 3)
    var plain = closePane(false)
    PreviewKeys.act("focusNext", plain)
    PreviewKeys.act("focusPrevious", plain)
    PreviewKeys.act("open", plain)
    check("Tab and Return mean nothing to a preview with no bar", plain.preview.markdownCloseFocused + plain.closed, 0)
    check("Tab maps to focusNext in the preview context",
        Keymap.lookupFor("default", Qt.Key_Tab, "\t", Qt.NoModifier, "preview", "gui"), "focusNext")
    check("Shift+Tab maps to focusPrevious in the preview context",
        Keymap.lookupFor("default", Qt.Key_Backtab, "", Qt.ShiftModifier, "preview", "gui"), "focusPrevious")
    check("Return maps to open in the preview context",
        Keymap.lookupFor("default", Qt.Key_Return, "\r", Qt.NoModifier, "preview", "gui"), "open")
    // Real pane dispatch must enter Compare even though it does not draw the text bar.
    var compareSteps = []
    var comparison = { stepFocus: function(back) { compareSteps.push(back) } }
    var comparePane = { focusView: "list", viewMode: "list", searchMode: "", recentMode: "",
        path: "/w", cursorIndex: 0, selectionVersion: 0, renameEditor: function() { return null },
        preview: { active: true, isCompare: true, hasBar: false, revealStrip: function() {},
            surfaceItem: function() { return comparison } } }
    var comparePreset = Keymap.preset
    for (var compareKeyPreset of ["default", "vim", "mac", "windows"]) {
        Keymap.setPreset(compareKeyPreset)
        compareSteps = []
        check(compareKeyPreset + ": pane consumes Compare Tab", Focus.handleKey({ key: Qt.Key_Tab, text: "\t", modifiers: Qt.NoModifier }, comparePane, null), true)
        check(compareKeyPreset + ": pane consumes Compare Shift+Tab", Focus.handleKey({ key: Qt.Key_Backtab, text: "", modifiers: Qt.ShiftModifier }, comparePane, null), true)
        check(compareKeyPreset + ": Compare receives both focus directions", compareSteps.join(","), "false,true")
    }
    Keymap.setPreset(comparePreset)
    comparison = null
    check("Tab while Compare is still loading is consumed safely", Focus.handleKey({ key: Qt.Key_Tab, text: "\t", modifiers: Qt.NoModifier }, comparePane, null), true)
    var paneSrc = Source.source("ui/MarkdownPane.qml")
    var barSrc = Source.source("ui/QuickLookBar.qml")
    check("the close mark takes its keyboard state from the bar",
        Source.slice(barSrc, "id: barClose", "onActivated").indexOf("keyboardFocused: root.closeFocused") >= 0, true)
    check("the pane hands the bar the keyboard state", paneSrc.indexOf("closeFocused: root.closeFocused") >= 0, true)
    check("previewCloseState reports focused", barSrc.indexOf("focused: barClose.keyboardFocused") >= 0, true)
    check("the Quick Look hands the toggle to the pane",
        quickSrc.indexOf("function toggleMarkdownClose()") >= 0 && quickSrc.indexOf("readonly property bool markdownCloseFocused") >= 0, true)
    check("the close focus belongs to every pane that draws the bar, not to Markdown alone",
        quickSrc.indexOf("root.active && root.hasBar && root.markdownCloseFocus") >= 0 && quickSrc.indexOf("readonly property bool hasBar: root.kind === \"text\"") >= 0, true)
    check("the code pane hands the bar the keyboard state and closes on the bar's request",
        quickSrc.indexOf("closeFocused: root.markdownCloseFocused\n                onCloseRequested: root.close()") >= 0, true)
    check("the swap reads the code pane's first screen",
        quickSrc.indexOf("(root.isCodeText && textPane.firstScreen)") >= 0, true)
    runWrapKeys(check)
    runThumbThreading(check)
    runImageZoom(check)
}

// The cached thumbnail rides into Quick Look in memory, with zero new file work.
function thumbRoot(thumbValue) {
    var calls = []
    var root = { cursorIndex: 5, path: "/d", shown: null, thumbState: { file: {}, order: [] },
        kindNames: ["Kind"],
        preview: { open: function (p, i, s, k, t) { calls.push(["open", p, t]) },
            follow: function (p, i, s, k, t) { calls.push(["follow", p, t]) } } }
    root.thumbState.file[5] = thumbValue
    root.quickLook = function () { return root.preview }
    root.rowFor = function (i) { return i === 5 ? { n: "b.jpg", d: false, i: "image-x-generic", s: 10, k: 0 } : null }
    root.join = function (b, n) { return b + "/" + n }
    return { root: root, calls: calls }
}

function runThumbThreading(check) {
    var held = thumbRoot("/cache/5.png")
    PreviewKeys.open(held.root)
    check("Space hands the held cache file to Quick Look", held.calls.join(";"), "open,/d/b.jpg,/cache/5.png")
    PreviewKeys.follow(held.root)
    check("a cursor move hands it to follow too", held.calls.join(";"),
        "open,/d/b.jpg,/cache/5.png;follow,/d/b.jpg,/cache/5.png")
    var missed = thumbRoot(undefined)
    PreviewKeys.open(missed.root)
    check("a row with nothing held opens with no interim", missed.calls.join(";"), "open,/d/b.jpg,")
    var dirRoot = thumbRoot("/cache/5.png")
    dirRoot.root.rowFor = function () { return { n: "sub", d: true, i: "folder", s: 0, k: 0 } }
    PreviewKeys.open(dirRoot.root)
    check("a directory opens nothing at all", dirRoot.calls.length, 0)
    var hidden = thumbRoot("/cache/5.png")
    hidden.root.shown = []
    PreviewKeys.open(hidden.root)
    PreviewKeys.follow(hidden.root)
    check("Space with zero matches opens nothing hidden", hidden.calls.length, 0)
}

// Quick Look's image zoom: the PDF's ladder (fit is 1, a quarter a press, 4 at most), + and - on it, 0 back to fit, and nothing but an image or a PDF takes the keys; e expands a PDF only.
function runImageZoom(check) {
    var rung = 1
    var up = []
    for (var i = 0; i < 14; i++) { rung = PreviewKeys.zoomStep(rung, 1); up.push(rung) }
    check("+ climbs from fit in quarter steps and stops at 4", up.join(","), "1.25,1.5,1.75,2,2.25,2.5,2.75,3,3.25,3.5,3.75,4,4,4")
    var down = []
    for (i = 0; i < 14; i++) { rung = PreviewKeys.zoomStep(rung, -1); down.push(rung) }
    check("- steps back down and stops at fit", down.join(","), "3.75,3.5,3.25,3,2.75,2.5,2.25,2,1.75,1.5,1.25,1,1,1")
    check("the PDF keeps its own three constants",
        PreviewKeys.PDF_ZOOM_MIN + "," + PreviewKeys.PDF_ZOOM_MAX + "," + PreviewKeys.PDF_ZOOM_STEP, "1,4,0.25")

    var log = []
    var preview = { revealStrip: function () {}, zoomBy: function (steps) { log.push("by " + steps) }, zoomFit: function () { log.push("fit") } }
    PreviewKeys.act("zoomIn", { preview: preview })
    PreviewKeys.act("zoomOut", { preview: preview })
    PreviewKeys.act("zoomFit", { preview: preview })
    check("zoomIn, zoomOut and zoomFit reach the preview as one step up, one step down and fit", log.join(","), "by 1,by -1,fit")

    var viewer = { pdfControlIndex: -1, pdfControls: [], zoomBy: function (steps) { log.push("pdf " + steps) }, zoomFit: function () { log.push("pdf fit") } }
    log = []
    PreviewKeys.pdfAction("zoomIn", viewer)
    PreviewKeys.pdfAction("zoomOut", viewer)
    PreviewKeys.pdfAction("zoomFit", viewer)
    check("a PDF still zooms by its ladder and has no fit key", log.join(","), "pdf 1,pdf -1")

    var none = Qt.NoModifier
    var plus = { key: Qt.Key_Plus, text: "+", modifiers: Qt.ShiftModifier }
    var minus = { key: Qt.Key_Minus, text: "-", modifiers: none }
    var zero = { key: Qt.Key_0, text: "0", modifiers: none }
    var expand = { key: Qt.Key_E, text: "e", modifiers: none }
    var kinds = [
        ["an image", { active: true, isMedia: false, isPdf: false, isImage: true }, "zoomIn,zoomOut,zoomFit,"],
        ["a PDF", { active: true, isMedia: false, isPdf: true, isImage: false }, "zoomIn,zoomOut,,expand"],
        ["a text file", { active: true, isMedia: false, isPdf: false, isImage: false }, ",,,"],
        ["a Markdown file", { active: true, isMedia: false, isPdf: false, isImage: false, isMarkdown: true }, ",,,"],
        ["an archive", { active: true, isMedia: false, isPdf: false, isImage: false, isArchive: true }, ",,,"],
        ["a video", { active: true, isMedia: true, isPdf: false, isImage: false }, ",,,"],
        ["no preview", { active: false, isMedia: false, isPdf: false, isImage: false }, ",,,"]
    ]
    var wasPreset = Keymap.preset
    for (var preset of Keymap.PRESETS) {
        Keymap.setPreset(preset)
        for (var kind of kinds) {
            var pane = { focusView: "list", shown: null, viewMode: "list", searchMode: "", recentMode: "", preview: kind[1] }
            check(preset + ": +, -, 0 and e over " + kind[0] + " mean " + kind[2],
                [Focus.lookup(plus, pane), Focus.lookup(minus, pane), Focus.lookup(zero, pane), Focus.lookup(expand, pane)].join(","), kind[2])
        }
    }
    Keymap.setPreset(wasPreset)

    // The map binds e in a PDF only, so Focus.lookup's own gate is what keeps expand off every other kind should a row ever bind it wider: bind it into the preview context here and ask.
    var bound = Keymap.PRESET_KEYS.filter(function (row) { return row.action === "expand" && row.context === "pdf" })[0]
    var wide = {}
    for (var field in bound) wide[field] = bound[field]
    wide.context = "preview,pdf"
    Keymap.PRESET_KEYS.push(wide)
    try {
        for (kind of kinds) {
            pane = { focusView: "list", shown: null, viewMode: "list", searchMode: "", recentMode: "", preview: kind[1] }
            var want = kind[1].isPdf ? "expand" : ""
            check("e bound into the preview context still means \"" + want + "\" over " + kind[0], Focus.lookup(expand, pane), want)
        }
    } finally {
        Keymap.PRESET_KEYS.pop()
    }
    check("the widened e row is gone again", Keymap.PRESET_KEYS.indexOf(wide), -1)
}

// w wraps code, text and Markdown Source; the remembered choice belongs to ui.json.
function runWrapKeys(check) {
    var w = { key: 0, text: "w", modifiers: Qt.NoModifier }
    function pane(preview) { return { focusView: "list", viewMode: "list", searchMode: "", recentMode: "", preview: preview } }
    function open(kind) {
        return { active: true, isMedia: kind === "audio" || kind === "video", isPdf: kind === "pdf",
            isCodeText: kind === "code" || kind === "text", isMarkdown: kind === "markdown" || kind === "markdown-source",
            isHtml: kind === "html" || kind === "html-source", isDocument: /^(markdown|html)(-source)?$/.test(kind),
            markdownShown: { shownView: /-source$/.test(kind) ? "source" : "rendered" } }
    }
    var kept = Keymap.preset
    for (var preset of ["default", "vim", "mac", "windows"]) {
        Keymap.setPreset(preset)
        for (var kind of ["code", "text", "markdown-source", "html-source"])
            check(preset + ": w reaches a " + kind + " Quick Look", Focus.lookup(w, pane(open(kind))), "toggleWrap")
        for (var other of ["markdown", "html", "pdf", "image", "archive", "audio", "video"])
            check(preset + ": w reaches nothing on a " + other + " Quick Look", Focus.lookup(w, pane(open(other))), "")
        check(preset + ": w stays close tab in the listing", Focus.lookup(w, pane({ active: false, isMedia: false, isPdf: false })), "tabClose")
        check(preset + ": r reaches the Markdown view in the preview context", Keymap.lookupFor(preset, 0, "r", Qt.NoModifier, "preview", "gui"), "markdownView")
        check(preset + ": r in the listing is never the Markdown view", Keymap.lookupFor(preset, 0, "r", Qt.NoModifier, "listing", "gui") !== "markdownView", true)
    }
    Keymap.setPreset(kept)
    var wrapped = { preview: { toggled: 0, revealStrip: function () {}, toggleWrap: function () { this.toggled += 1 } } }
    PreviewKeys.act("toggleWrap", wrapped)
    check("the toggleWrap action asks the Quick Look to flip the wrap", wrapped.preview.toggled, 1)
    var quickSrc = Source.source("ui/Preview.qml")
    var toggle = new Function("root", "ViewState", Source.block(quickSrc, "function toggleWrap()", "ui/Preview.qml"))
    for (var kind of ["code", "text", "markdown-source", "html-source", "markdown", "html", "pdf", "image", "archive", "audio", "video"]) {
        var changes = []
        toggle(open(kind), { previewWrap: false, changeLeaf: function (leaf, patch) { changes.push([leaf, patch.wrap]) } })
        check(kind + ": only a wrappable Quick Look writes preview.wrap", JSON.stringify(changes),
            ["code", "text", "markdown-source", "html-source"].indexOf(kind) >= 0 ? '[["preview",true]]' : "[]")
    }
    check("the pane draws the remembered wrap", quickSrc.indexOf("wrap: ViewState.previewWrap") >= 0, true)
}
