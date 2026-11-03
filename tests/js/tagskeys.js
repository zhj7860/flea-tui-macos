.import "../../ui/js/Keymap.js" as Keymap

// T opens the Tags flyout from the listing, 1 to 7 toggle while it is open, and 8 answers nothing.
function run(check) {
    var none = Qt.NoModifier, shift = Qt.ShiftModifier
    function key(preset, name, text, mods, expected, context) {
        check(preset + " " + context + " " + name + " " + text + " " + mods,
              Keymap.lookupFor(preset, Qt["Key_" + name] || 0, text, mods, context, "all"), expected)
    }
    for (var i = 0; i < Keymap.PRESETS.length; i++) {
        var preset = Keymap.PRESETS[i]
        key(preset, "T", "T", shift, "tags", "listing")
        for (var g = 1; g <= 7; g++) key(preset, String(g), String(g), none, "tag" + g, "menu")
        key(preset, "8", "8", none, "", "menu")
    }
}
