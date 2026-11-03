.pragma library

.import "Tabs.js" as Tabs

// The chrome bar's and tab strip's keys while Tab holds the keyboard there, read raw so no preset shadows them (as ui/js/RailKeys.js).

// The chrome's controls in the order Tab and the arrows walk them, named by glyph as ui/ChromeBar.qml names them.
var ORDER = ["arrow-left", "arrow-up", "search", "filter", "sort", "list", "columns", "grid", "dual", "sliders"]
// A press on these hands the keyboard to the surface it opens, as the pointer's press does; the rest keep it on the mark.
var HANDS_OFF = ["search", "filter", "sliders"]
var BLOCKING = Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier

// The controls that are drawn and live, in order; a hidden or disabled one is never a stop.
function controls(bar) {
    if (!bar || !bar.visible || bar.inputLive === false) return []
    return ORDER.filter(function (glyph) {
        var mark = bar.buttonFor(glyph)
        return mark !== null && mark.visible && mark.enabled
    })
}

// How many stops the strip holds: each tab, then New tab; none while one tab leaves the strip closed.
function tabStops(strip) {
    return strip && strip.open ? strip.tabCount + 1 : 0
}

// Which of the ring's stops are drawn, keyed by the view name Focus.js gives each.
function drawn(root, railAvailable) {
    return {
        rail: !!railAvailable,
        chrome: controls(root.chromeBar).length > 0,
        strip: tabStops(root.tabStrip) > 0
    }
}

// Entering a stop forward lands on its first control (the strip: the current tab), backward on its last.
function enter(root, view, forward) {
    if (view === "chrome") {
        var glyphs = controls(root.chromeBar)
        root.chromeBar.focusedGlyph = glyphs[forward ? 0 : glyphs.length - 1]
    } else if (view === "strip") {
        root.tabStrip.focusedIndex = forward ? root.tabStrip.currentIndex : root.tabStrip.tabCount
    }
}

function press(event) {
    return event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space
}

// Where an arrow, Home or End lands among count stops from at, without wrapping; -1 when the key is none of those.
function target(event, at, count) {
    if (event.key === Qt.Key_Home) return 0
    if (event.key === Qt.Key_End) return count - 1
    if (event.key === Qt.Key_Left) return Math.max(0, at - 1)
    if (event.key === Qt.Key_Right) return Math.min(count - 1, at + 1)
    return -1
}

// The live control nearest in ORDER to a glyph that went disabled or hidden; unknown names land on the first stop.
function nearestLive(glyph, glyphs) {
    var home = glyphs[0]
    var want = ORDER.indexOf(glyph)
    if (want < 0) return home
    var best = Infinity
    for (var i = 0; i < glyphs.length; i++) {
        var dist = Math.abs(ORDER.indexOf(glyphs[i]) - want)
        if (dist < best) { best = dist; home = glyphs[i] }
    }
    return home
}

function chromeKey(event, root) {
    var bar = root.chromeBar
    var glyphs = controls(bar)
    var at = glyphs.indexOf(bar.focusedGlyph)
    if (press(event)) {
        // A stop that went disabled or hidden re-homes to the nearest live control and presses nothing, so Enter never acts on a control the user did not see focused.
        if (at < 0) {
            if (glyphs.length > 0) bar.focusedGlyph = nearestLive(bar.focusedGlyph, glyphs)
            return
        }
        bar.buttonFor(glyphs[at]).activated()
        if (HANDS_OFF.indexOf(glyphs[at]) >= 0) root.focusView = "list"
        return
    }
    var to = target(event, at, glyphs.length)
    if (to >= 0) bar.focusedGlyph = glyphs[to]
}

function stripKey(event, root) {
    var strip = root.tabStrip
    var at = Math.min(strip.focusedIndex, strip.tabCount)
    if (press(event)) {
        root.focusView = "list"
        if (at < strip.tabCount) Tabs.selectAt(root, at)
        else Tabs.openNew(root)
        return
    }
    var to = target(event, at, strip.tabCount + 1)
    if (to >= 0) strip.focusedIndex = to
}

// Every key a stop holds is answered here and the rest do nothing; a stop that is no longer drawn gives the key back to the list.
function act(event, root) {
    var chrome = root.focusView === "chrome"
    if (chrome ? controls(root.chromeBar).length === 0 : tabStops(root.tabStrip) === 0) {
        root.focusView = "list"
        return false
    }
    if ((event.modifiers & BLOCKING) !== 0) return true
    if (event.key === Qt.Key_Escape) root.focusView = "list"
    else if (chrome) chromeKey(event, root)
    else stripKey(event, root)
    return true
}
