.pragma library

// Sample input: read(window, window.contentItem, /^(DialogButton)_QML/, {}) === {focus: {kind: "DialogButton", via: "owner", ...}, controls: [{kind: "DialogButton", name: "Open", x: 900, ...}]}.
// The cohesion captures' reader, shared by the window and the picker: every visible control that draws focus, its window box and its states.
function read(quick, top, kinds, alias) {
    var out = []
    function kindOf(item) { var m = String(item).match(kinds); return m ? (alias[m[1]] || m[1]) : "" }
    function pointerFlag(item, name) {
        if (item[name] !== undefined) return item[name]
        var handler = name === "hovered" ? "QQuickHoverHandler" : "QQuickTapHandler"
        var data = item.data || []
        for (var i = 0; i < data.length; i++)
            if (data[i] && String(data[i]).indexOf(handler) === 0) return data[i][name]
        return undefined
    }
    function entry(item, kind, via) {
        var p = item.mapToItem(null, 0, 0)
        var hovered = pointerFlag(item, "hovered"), pressed = pointerFlag(item, "pressed")
        return {kind: kind, name: String(item.label || item.accessName || item.title || item.objectName || item.name || item.glyph || ""),
            x: Math.round(p.x), y: Math.round(p.y), w: Math.round(item.width), h: Math.round(item.height),
            focused: !!(item.activeFocus || item.focused === true || item.keyboardFocused === true),
            hovered: hovered === true, pressed: pressed === true,
            hoverable: hovered !== undefined, pressable: pressed !== undefined,
            enabled: !!item.enabled && item.available !== false && item.inputLive !== false,
            value: item.value !== undefined ? String(item.value) : "",
            primary: item.primary === true, destructive: item.destructive === true, member: item.setMember === true, via: via}
    }
    function walk(item) {
        if (!item || !item.visible || item.opacity <= 0) return
        var kind = kindOf(item)
        if (kind) out.push(entry(item, kind, ""))
        for (var i = 0; i < item.children.length; i++) walk(item.children[i])
    }
    walk(top)
    var item = quick ? quick.activeFocusItem : null, owner = item
    while (owner && !kindOf(owner)) owner = owner.parent
    // A dialog that keeps the keyboard on its own scope names its focused control through that control's focused flag.
    var focus = owner ? entry(owner, kindOf(owner), "owner") : null
    for (var j = 0; !focus && j < out.length; j++) if (out[j].focused) focus = Object.assign({}, out[j], {via: "flag"})
    if (!focus && item) focus = entry(item, String(item).split("(")[0], "item")
    return JSON.stringify({focus: focus, controls: out})
}
