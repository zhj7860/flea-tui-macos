.import "../../ui/js/Focus.js" as Focus
.import "../../ui/js/ChromeKeys.js" as ChromeKeys

// Tab walks list, rail, chrome bar and tab strip as one ring, the stops answer their keys raw, and Right Arrow reaches a rail row's eject mark.

var none = Qt.NoModifier

function key(code, mods, text) {
    return { key: code, text: text === undefined ? "" : text, modifiers: mods === undefined ? none : mods }
}

// A chrome bar with the named glyphs drawn and live; pressed records what activated() was asked.
function bar(glyphs) {
    var b = { visible: true, inputLive: true, focusedGlyph: "", pressed: [] }
    b.buttonFor = function (glyph) {
        var live = glyphs.indexOf(glyph) >= 0
        return { visible: live, enabled: live, activated: function () { b.pressed.push(glyph) } }
    }
    return b
}

function strip(tabs) {
    return { open: tabs > 1, tabCount: tabs, currentIndex: 0, focusedIndex: -1 }
}

// How many times a step asked the window to hand the keyboard to the left pane's rail.
var railAsks = 0

// The pane Focus.handleKey reads, with the log of what the ring asked of it.
function pane(view, bars, tabs) {
    var p = {
        focusView: view, viewMode: "list", searchMode: "", recentMode: "", filterTyping: false, shown: null,
        inputAt: 0, rowsAt: 0, trashArmedAt: 0, said: "", dualMode: false, listOnly: false, switched: 0,
        preview: { active: false }, shareBrowser: { active: false },
        chromeBar: bar(bars === undefined ? ChromeKeys.ORDER : bars), tabStrip: strip(tabs === undefined ? 2 : tabs),
        cursorIndex: 0, pathBars: 0,
        rowFor: function () { return null },
        pathBarRequested: function () { this.pathBars += 1 },
        message: function (text) { this.said = text },
        renameEditor: function () { return null },
        switchPane: function () { this.switched += 1 },
        switchToRail: function () { railAsks += 1 },
        act: function (action) { Focus.act(action, this) }
    }
    return p
}

function rail(entries) {
    return { entries: entries, cursorIndex: 0, markFocused: false, focusOnOpen: false, released: [], activated: [],
             activate: function (index) { this.activated.push(index) },
             renameEditor: function () { return null },
             releaseChosen: function (action, key) { this.released.push(action) } }
}

function walk(root, sidebar, code, mods, times) {
    var seen = []
    for (var i = 0; i < times; i++) {
        Focus.handleKey(key(code, mods), root, sidebar)
        seen.push(root.focusView + (root.focusView === "chrome" ? ":" + root.chromeBar.focusedGlyph : root.focusView === "strip" ? ":" + root.tabStrip.focusedIndex : ""))
    }
    return seen.join(" ")
}

function run(check) {
    var shift = Qt.ShiftModifier
    var all = { rail: true, chrome: true, strip: true }
    // The ring, forward and back, with every stop and with each one missing.
    check("forward from the list goes to the rail", Focus.next("list", all, true), "rail")
    check("forward walks rail, chrome, strip and back to the list",
          [Focus.next("rail", all, true), Focus.next("chrome", all, true), Focus.next("strip", all, true)].join(","), "chrome,strip,list")
    check("backward walks the ring the other way",
          [Focus.next("list", all, false), Focus.next("strip", all, false), Focus.next("chrome", all, false), Focus.next("rail", all, false)].join(","), "strip,chrome,rail,list")
    check("no rail goes list to chrome", Focus.next("list", { chrome: true, strip: true }, true), "chrome")
    check("no chrome bar goes rail to strip", Focus.next("rail", { rail: true, strip: true }, true), "strip")
    check("one tab leaves no strip stop", Focus.next("chrome", { rail: true, chrome: true }, true), "list")
    check("nothing else drawn keeps the list", Focus.next("list", {}, false), "list")
    check("an unknown view falls back to the list", Focus.next("gone", all, true), "list")

    // Tab through the real handler, single view with the rail, the bar and two tabs.
    var one = pane("list")
    var line = walk(one, rail([]), Qt.Key_Tab, none, 5)
    check("Tab visits rail, chrome back, strip current tab, and the list", line, "rail chrome:arrow-left strip:0 list rail")
    check("Shift+Tab walks it backwards from the list", walk(pane("list"), rail([]), Qt.Key_Backtab, shift, 4), "strip:2 chrome:sliders rail list")
    check("Shift+Tab with Tab as the key reads the same", walk(pane("list"), rail([]), Qt.Key_Tab, shift, 1), "strip:2")
    check("without a rail the ring skips it", walk(pane("list"), null, Qt.Key_Tab, none, 4), "chrome:arrow-left strip:0 list chrome:arrow-left")
    check("a one tab window has no strip stop", walk(pane("list", undefined, 1), rail([]), Qt.Key_Tab, none, 4), "rail chrome:arrow-left list rail")
    var hidden = pane("list"); hidden.chromeBar.visible = false
    check("a hidden bar is skipped", walk(hidden, rail([]), Qt.Key_Tab, none, 3), "rail strip:0 list")
    var shielded = pane("list"); shielded.chromeBar.inputLive = false
    check("Quick Look over the bar skips it", walk(shielded, rail([]), Qt.Key_Tab, none, 3), "rail strip:0 list")
    check("a bar with no live control is skipped", walk(pane("list", []), rail([]), Qt.Key_Tab, none, 3), "rail strip:0 list")

    // The dual view: the two lists, the left pane's rail and the stops after it; the pane switch is the step between the lists, and a step onto the rail asks the window for it.
    var left = pane("list"); left.dualMode = true
    Focus.handleKey(key(Qt.Key_Tab), left, rail([]))
    check("dual: Tab from the left list switches to the right one", left.switched + "|" + left.focusView, "1|list")
    var right = pane("list"); right.dualMode = true; right.listOnly = true
    Focus.handleKey(key(Qt.Key_Tab), right, rail([]))
    check("dual: Tab from the right list reaches the left pane's rail", railAsks + "|" + right.focusView, "1|list")
    check("dual: with no rail Tab from the right list reaches the bar and the strip", walk(right, null, Qt.Key_Tab, none, 2), "chrome:arrow-left strip:0")
    right.focusView = "strip"
    Focus.handleKey(key(Qt.Key_Tab), right, null)
    check("dual: Tab from the strip returns to the left list", right.focusView + "|" + right.switched, "list|1")
    var railBar = pane("rail"); railBar.dualMode = true
    check("dual: Tab from the rail walks the bar, the strip and the left list", walk(railBar, rail([]), Qt.Key_Tab, none, 3), "chrome:arrow-left strip:0 list")
    railAsks = 0
    var barBack = pane("chrome"); barBack.dualMode = true; barBack.listOnly = true
    Focus.handleKey(key(Qt.Key_Backtab, shift), barBack, rail([]))
    check("dual: Shift+Tab from the bar on the right pane hands the left pane its rail", railAsks + "|" + barBack.focusView, "1|list")
    var back = pane("list"); back.dualMode = true
    check("dual: Shift+Tab from the left list reaches the strip", walk(back, rail([]), Qt.Key_Backtab, shift, 1), "strip:2")
    back.focusView = "chrome"
    Focus.handleKey(key(Qt.Key_Backtab, shift), back, null)
    check("dual: with no rail Shift+Tab from the bar returns to the right list", back.focusView + "|" + back.switched, "list|1")

    // The chrome stop's own keys.
    var chrome = pane("chrome")
    chrome.chromeBar.focusedGlyph = "arrow-left"
    var steps = []
    function go(code, mods) { Focus.handleKey(key(code, mods), chrome, rail([])); steps.push(chrome.chromeBar.focusedGlyph) }
    go(Qt.Key_Left)
    check("Left on the first control stays", steps.pop(), "arrow-left")
    go(Qt.Key_Right); go(Qt.Key_Right); go(Qt.Key_Right)
    check("Right walks back, up, search, filter in order", steps.join(","), "arrow-up,search,filter")
    go(Qt.Key_End)
    check("End goes to the last control", steps.pop(), "sliders")
    go(Qt.Key_Right)
    check("Right on the last control stays", steps.pop(), "sliders")
    go(Qt.Key_Home)
    check("Home goes to the first control", steps.pop(), "arrow-left")
    var limited = pane("chrome", ["arrow-left", "search", "list", "sliders"])
    limited.chromeBar.focusedGlyph = "arrow-left"
    Focus.handleKey(key(Qt.Key_Right), limited, rail([]))
    check("a control that is not live is skipped", limited.chromeBar.focusedGlyph, "search")
    var typed = pane("chrome")
    typed.chromeBar.focusedGlyph = "grid"
    for (var code of [Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space]) Focus.handleKey(key(code), typed, rail([]))
    check("Return, keypad Enter and Space press the control", typed.chromeBar.pressed.join(","), "grid,grid,grid")
    check("a view mark keeps the keyboard on itself", typed.focusView + "|" + typed.chromeBar.focusedGlyph, "chrome|grid")
    for (var name of ["search", "filter", "sliders"]) {
        var opens = pane("chrome")
        opens.chromeBar.focusedGlyph = name
        Focus.handleKey(key(Qt.Key_Return), opens, rail([]))
        check("a press on " + name + " hands the keyboard to what it opens", opens.focusView + "|" + opens.chromeBar.pressed.join(","), "list|" + name)
    }
    var stale = pane("chrome", ["search", "list"])
    stale.chromeBar.focusedGlyph = "arrow-left"
    Focus.handleKey(key(Qt.Key_Return), stale, rail([]))
    check("a stale stop re-homes to the nearest live control and presses nothing", stale.chromeBar.focusedGlyph + "|" + stale.chromeBar.pressed.join(","), "search|")
    var staleArrow = pane("chrome", ["search", "list"])
    staleArrow.chromeBar.focusedGlyph = "arrow-left"
    Focus.handleKey(key(Qt.Key_Right), staleArrow, rail([]))
    check("a stale stop's arrow still lands on the first live control", staleArrow.chromeBar.focusedGlyph, "search")
    // The first live stop is not the nearest one here, so a re-home that took glyphs[0] lands on arrow-left.
    var farEnd = pane("chrome", ["arrow-left", "search", "list", "sliders"])
    farEnd.chromeBar.focusedGlyph = "dual"
    Focus.handleKey(key(Qt.Key_Return), farEnd, rail([]))
    check("a stale stop re-homes to the nearest live control by ORDER, not the first", farEnd.chromeBar.focusedGlyph + "|" + farEnd.chromeBar.pressed.join(","), "sliders|")
    var farMiddle = pane("chrome", ["arrow-left", "list", "sliders"])
    farMiddle.chromeBar.focusedGlyph = "columns"
    Focus.handleKey(key(Qt.Key_Return), farMiddle, rail([]))
    check("a stale stop between two live ones lands on the closer, neither the first nor the last", farMiddle.chromeBar.focusedGlyph + "|" + farMiddle.chromeBar.pressed.join(","), "list|")
    var inert = pane("chrome")
    inert.chromeBar.focusedGlyph = "list"
    Focus.handleKey(key(Qt.Key_J, none, "j"), inert, rail([]))
    Focus.handleKey(key(Qt.Key_Return, Qt.ControlModifier), inert, rail([]))
    check("every other key does nothing there", inert.chromeBar.pressed.length + "|" + inert.focusView, "0|chrome")
    Focus.handleKey(key(Qt.Key_Escape), inert, rail([]))
    check("Escape returns to the list", inert.focusView, "list")
    var windowKey = pane("chrome")
    Focus.handleKey(key(Qt.Key_Colon, none, ":"), windowKey, rail([]))
    check("a window action still answers on the bar", windowKey.pathBars + "|" + windowKey.focusView, "1|chrome")

    // The strip stop.
    var tabs = pane("strip", undefined, 3)
    tabs.tabStrip.focusedIndex = 0
    Focus.handleKey(key(Qt.Key_Right), tabs, rail([]))
    Focus.handleKey(key(Qt.Key_End), tabs, rail([]))
    check("End lands on New tab, one past the last tab", tabs.tabStrip.focusedIndex, 3)
    Focus.handleKey(key(Qt.Key_Right), tabs, rail([]))
    check("Right on New tab stays", tabs.tabStrip.focusedIndex, 3)
    Focus.handleKey(key(Qt.Key_Home), tabs, rail([]))
    check("Home lands on the first tab", tabs.tabStrip.focusedIndex, 0)
    Focus.handleKey(key(Qt.Key_Escape), tabs, rail([]))
    check("Escape on the strip returns to the list", tabs.focusView, "list")

    // A window with one tab at the moment a key lands gives the key back to the list.
    var gone = pane("strip", undefined, 1)
    Focus.handleKey(key(Qt.Key_Right), gone, rail([]))
    check("a strip that closed hands the keyboard back", gone.focusView, "list")

    // Right Arrow to the eject mark.
    var stick = { label: "128GB", group: "device", kind: "volume", device: "/dev/sda1", path: "/run/media/user/128GB", mounted: true, removable: true }
    var home = { label: "Home", group: "place", kind: "home", path: "/home/u", mounted: true }
    var mounted = rail([home, stick])
    var rooted = pane("rail")
    rooted.sidebar = mounted
    rooted.focusView = "rail"
    Focus.handleKey(key(Qt.Key_Right), rooted, mounted)
    check("Right on a row with no mark leaves the mark alone and opens the row as before", mounted.markFocused + "|" + mounted.activated.join(","), "false|0")
    mounted.cursorIndex = 1
    Focus.handleKey(key(Qt.Key_Right), rooted, mounted)
    check("Right on a mounted removable row puts the keyboard on its mark", mounted.markFocused, true)
    Focus.handleKey(key(Qt.Key_Left), rooted, mounted)
    check("Left returns to the row", mounted.markFocused + "|" + rooted.focusView, "false|rail")
    Focus.handleKey(key(Qt.Key_Right), rooted, mounted)
    Focus.handleKey(key(Qt.Key_Escape), rooted, mounted)
    check("Escape returns to the row and keeps the rail", mounted.markFocused + "|" + rooted.focusView, "false|rail")
    Focus.handleKey(key(Qt.Key_Right), rooted, mounted)
    Focus.handleKey(key(Qt.Key_Right), rooted, mounted)
    check("Right on the mark does not open the row", mounted.markFocused + "|" + mounted.focusOnOpen, "true|false")
    for (var code of [Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space]) {
        mounted.markFocused = true
        Focus.handleKey(key(code), rooted, mounted)
    }
    check("Return, keypad Enter and Space on the mark release the row and return to it", mounted.released.length + "|" + mounted.markFocused, "3|false")
    for (var move of [Qt.Key_Up, Qt.Key_Down, Qt.Key_Home, Qt.Key_End]) {
        mounted.markFocused = true
        Focus.handleKey(key(move), rooted, mounted)
        check("a cursor key (" + move + ") leaves the mark", mounted.markFocused, false)
    }
    var unbound = pane("rail")
    var unboundSide = rail([])
    unbound.sidebar = unboundSide
    Focus.handleKey(key(Qt.Key_Q, none, "q"), unbound, unboundSide)
    check("an unbound key on the rail does not throw", unbound.focusView, "rail")
}
