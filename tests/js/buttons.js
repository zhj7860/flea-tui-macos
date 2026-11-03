.import "../../ui/js/Buttons.js" as Buttons
.import "../../ui/js/Collide.js" as Collide
.import "sourcefixture.js" as Source

// The braced block holding a marker, found by brace depth so a renamed id or a moved line fails loudly.
// Sample input: blockOf("A { id: x; B { y: 1 } } C { z: 2 }", "id: x") answers "{ id: x; B { y: 1 } }".
function blockOf(text, marker) {
    var at = text.indexOf(marker)
    if (at < 0)
        throw new Error("buttons: missing marker " + marker)
    var open = at - 1
    for (var back = 0; open >= 0; open--) {
        if (text[open] === "}")
            back++
        else if (text[open] === "{" && back-- === 0)
            break
    }
    if (open < 0)
        throw new Error("buttons: no block holds " + marker)
    var depth = 0
    for (var end = open; end < text.length; end++) {
        if (text[end] === "{")
            depth++
        else if (text[end] === "}" && --depth === 0)
            return text.substring(open, end + 1)
    }
    throw new Error("buttons: the block holding " + marker + " never closes")
}
// Sample input: valuesOf("A { border.width: 1; border.color: Theme.color.accent }", "border.color") answers ["Theme.color.accent"]; it reads every `name:` in the text, at a line's start or after a `;` or `{`, so a one-line item cannot hide one.
function valuesOf(block, name) {
    var out = []
    var pattern = new RegExp("(?:^|[\\s;{])" + name.replace(/\./g, "\\.") + "\\s*:\\s*([^;\\n}]+)", "g")
    var hit
    while ((hit = pattern.exec(block)) !== null)
        out.push(hit[1].trim())
    return out
}

// QML text with its comments blanked and its strings kept, so a pin reads code and never a comment that names it.
// Sample input: codeOf('a: "//x" // b: 1') answers 'a: "//x" ' with the comment gone.
function codeOf(text) {
    var out = ""
    var quote = ""
    for (var i = 0; i < text.length; i++) {
        var ch = text[i]
        if (quote !== "") {
            out += ch
            if (ch === "\\" && i + 1 < text.length)
                out += text[++i]
            else if (ch === quote)
                quote = ""
        } else if (ch === "/" && text[i + 1] === "/") {
            while (i + 1 < text.length && text[i + 1] !== "\n")
                i++
        } else if (ch === "/" && text[i + 1] === "*") {
            var close = text.indexOf("*/", i + 2)
            i = close < 0 ? text.length : close + 1
            out += " "
        } else {
            if (ch === '"' || ch === "'")
                quote = ch
            out += ch
        }
    }
    return out
}
// Each Flea.ChromeButton a file declares, named by its id (its glyph where it has none), with only its own lines: comments and nested blocks are left out.
// Sample input: marksOf("Flea.ChromeButton { id: a; glyph: \"x\"; B { glyph: \"y\" } }") answers [{ name: "a", own: " id: a; glyph: \"x\"; B  " }].
function marksOf(text) {
    var code = codeOf(text)
    var marker = "Flea.ChromeButton {"
    var out = []
    for (var at = code.indexOf(marker); at >= 0; at = code.indexOf(marker, at + marker.length)) {
        var own = ""
        var depth = 0
        var i = at + marker.length - 1
        for (; i < code.length; i++) {
            var ch = code[i]
            if (ch === "{")
                depth++
            else if (ch === "}" && --depth === 0)
                break
            else if (depth === 1 && ch !== "}")
                own += ch
        }
        if (i >= code.length)
            throw new Error("buttons: a ChromeButton block never closes")
        out.push({ name: valuesOf(own, "id")[0] || valuesOf(own, "glyph")[0] || "#" + out.length, own: own })
    }
    return out
}

// Variant A (Buttons040, decided 2026-09-24): one control at Theme.rowHeight minus its padding, fixed primary per dialog, destructive as error ink, disabled 0.55.

function run(check) {
    // The reader itself: a missing file throws naming it, so a renamed tree file fails loudly.
    var said = ""
    try {
        Source.source("ui/NoSuchFile-qml")
    } catch (e) {
        said = String((e && e.message) || e)
    }
    check("a missing file throws naming it", said.indexOf("ui/NoSuchFile-qml") >= 0, true)
    // indexOf coerces undefined to "undefined", so the guard runs before any search.
    var omitted = ""
    try {
        Source.slice("ab function f() {} undefined tail", "function f")
    } catch (e) {
        omitted = String((e && e.message) || e)
    }
    check("slice with an omitted marker throws its guard", omitted.indexOf("needs non-empty") >= 0, true)
    var emptyTo = ""
    try {
        Source.slice("ab function f() {} function g() {}", "function f", "")
    } catch (e) {
        emptyTo = String((e && e.message) || e)
    }
    check("slice with an empty toMarker throws its guard", emptyTo.indexOf("needs non-empty") >= 0, true)
    var emptyFrom = ""
    try {
        Source.slice("ab function f() {} function g() {}", "", "function g")
    } catch (e) {
        emptyFrom = String((e && e.message) || e)
    }
    check("slice with an empty fromMarker throws its guard", emptyFrom.indexOf("needs non-empty") >= 0, true)
    // One geometry for every dialog, card and picker button; the label follows Theme.font.body.
    var buttonSource = Source.source("ui/DialogButton.qml")
    check("a button pads with the theme's gap", buttonSource.indexOf("property real horizontalPadding: Theme.spacing.gap") >= 0, true)
    check("set members sit four hairlines apart", Buttons.SET_GAP, 4)
    check("settings segments sit two hairlines apart", Buttons.SEGMENT_GAP, 2)
    check("the segments read that gap", Source.source("ui/SettingsSegment.qml").indexOf("spacing: Theme.spacing.hairline * Buttons.SEGMENT_GAP") >= 0, true)
    check("the thick focus frame is 2 px", Buttons.RING, 2)
    check("a disabled control dims", Buttons.DISABLED_OPACITY, 0.55)
    check("hover is 8 percent of the ink", Buttons.WASH_HOVER, 0.08)
    check("press is 14 percent of the ink", Buttons.WASH_PRESS, 0.14)
    check("a primary rests in the press wash's weight of accent", Buttons.WASH_PRIMARY, Buttons.WASH_PRESS)
    check("a press shrinks to 0.96 over 150 ms", [Buttons.PRESS_SCALE, Buttons.PRESS_MS].join(" "), "0.96 150")
    // The label follows the body's text stop, so text size moves the buttons with the rows.
    check("the label follows the body's text stop, or the caption in a strip", buttonSource.indexOf("font.pixelSize: root.inStrip ? Theme.font.caption : Theme.font.body") >= 0, true)
    // Theme's wash and dim names read these numbers, so the two names cannot drift apart.
    var theme = Source.source("ui/Theme.qml")
    check("Theme's washes and dim read Buttons.js",
        ["washHover: Buttons.WASH_HOVER", "washActive: Buttons.WASH_PRESS", "disabledOpacity: Buttons.DISABLED_OPACITY"].map(function (line) { return theme.indexOf(line) >= 0 }).join(" "), "true true true")
    var pressers = ["ui/ChromeButton.qml", "ui/DialogButton.qml"]
    for (var p = 0; p < pressers.length; p++) {
        var presser = codeOf(Source.source(pressers[p]))
        check(pressers[p] + " presses with the shared scale and duration, no literal",
            [presser.indexOf("Buttons.PRESS_SCALE") >= 0, presser.indexOf("Buttons.PRESS_MS") >= 0, /\b0\.96\b|duration:\s*150\b/.test(presser)].join(" "), "true true false")
    }

    // The primary is fixed per dialog, the safe or asked-for action.
    check("trash opens on Cancel", Buttons.primaryFor("trash"), "cancel")
    check("collide opens on Keep both", Buttons.primaryFor("collide"), "keep")
    check("open-with opens on Open", Buttons.primaryFor("openWith"), "open")
    check("convert opens on Convert", Buttons.primaryFor("convert"), "convert")
    check("a new file opens on Create", Buttons.primaryFor("newFile"), "create")
    check("move opens on Move", Buttons.primaryFor("moveTo"), "move")
    check("copy opens on Copy", Buttons.primaryFor("copyTo"), "copy")
    check("network opens on its action", Buttons.primaryFor("network"), "action")
    check("permissions opens on Apply", Buttons.primaryFor("permissions"), "apply")
    check("the picker answers with Open", Buttons.primaryFor("picker"), "accept")
    check("an unknown dialog has no primary", Buttons.primaryFor("nope"), "")

    // A destructive action rests as the error label in a muted frame, never primary.
    check("delete is destructive", Buttons.isDestructive("trash", "delete"), true)
    check("cancel is not", Buttons.isDestructive("trash", "cancel"), false)
    check("replace is destructive", Buttons.isDestructive("collide", "replace"), true)
    check("keep both is not", Buttons.isDestructive("collide", "keep"), false)
    check("the picker's replace is destructive", Buttons.isDestructive("picker", "replace"), true)
    check("the picker's save is not", Buttons.isDestructive("picker", "accept"), false)

    // Focus is the control's own frame and never a ring: a hairline in the foreground, a set member's hairline in the accent where it has hue, and the frame RING wide in the foreground ("thick") where a foreground hairline would match the rest.
    check("a plain button marks focus in its foreground frame", Buttons.focusFrame(true, false, false), "foreground")
    check("a set member marks focus in the accent frame", Buttons.focusFrame(true, true, false), "accent")
    check("a set member without hue thickens its own frame", Buttons.focusFrame(false, true, false), "thick")
    check("a plain button takes foreground with or without hue", Buttons.focusFrame(false, false, false), "foreground")
    check("a primary whose rest frame is the foreground thickens its own frame with hue", Buttons.focusFrame(true, false, true), "thick")
    check("a primary whose rest frame is the foreground thickens its own frame without hue", Buttons.focusFrame(false, false, true), "thick")
    check("a set member keeps the accent frame when the rest is foreground", Buttons.focusFrame(true, true, true), "accent")
    var looks = []
    for (var combo = 0; combo < 8; combo++)
        looks.push(Buttons.focusFrame((combo & 1) === 1, (combo & 2) === 2, (combo & 4) === 4))
    check("every focus look is the frame itself, never a ring", looks.filter(function (look) { return ["foreground", "accent", "thick"].indexOf(look) < 0 }).join(","), "")
    // The thick frame is the button's own buttonFrame drawn wider inward, so nothing grows or moves, and the wash inset follows the width.
    var dialogButton = codeOf(Source.source("ui/DialogButton.qml"))
    check("a dialog button holds no ring item", dialogButton.indexOf("buttonRing"), -1)
    check("a dialog button draws nothing outside its own box", /margins:\s*-/.test(dialogButton), false)
    check("the frame width is RING only for the thick focus look", valuesOf(blockOf(dialogButton, 'objectName: "buttonFrame"'), "border.width").join("|"), "root.frameWidth")
    check("the wash lies inside the frame at its width", valuesOf(blockOf(dialogButton, 'objectName: "buttonWash"'), "anchors.margins").join("|"), "root.frameWidth")
    check("the thick look is the one reader of RING in the control", (dialogButton.match(/Buttons\.RING/g) || []).length, 1)

    // The card's keyboard opening and its primary agree, so Enter is safe.
    check("the card still opens on Keep both", Collide.START, Buttons.primaryFor("collide"))

    // The height lives in ui/DialogButton.qml as Theme.rowHeight minus its padding, or the strip's chromeHeight when hosted, so no constant here can drift from it.
    check("buttons draw the theme height, not a constant",
        Source.source("ui/DialogButton.qml").indexOf("implicitHeight: root.inStrip ? Theme.chromeHeight : Theme.rowHeight - Theme.spacing.rowPaddingY") >= 0, true)
    check("a hosted control draws the strip's control height, not a constant",
        Source.source("ui/DialogButton.qml").indexOf("root.inStrip ? Theme.chromeControlHeight : root.height") >= 0, true)

    // Decided 2026-10-03: a field's focus is its own hairline frame in the accent, as 0.3.6 drew it; the 2 px ring is the buttons' alone.
    var accentFrame = "border.color: field.activeFocus ? Theme.color.accent : Theme.color.mutedFrame"
    // A refused passphrase is the one frame that changes, to the error role.
    var accentErrorFrame = "border.color: root.error ? Theme.color.error : (field.activeFocus ? Theme.color.accent : Theme.color.mutedFrame)"
    var fields = {
        "ui/DialogField.qml": accentErrorFrame,
        "ui/MenuActionDialog.qml": accentFrame,
        "ui/OpenWithDialog.qml": accentFrame,
        "ui/PickerSave.qml": accentFrame,
        "ui/PermissionsDialog.qml": "border.color: octal.activeFocus ? (errorLabel.visible && !root.busy ? Theme.color.error : Theme.color.accent) : Theme.color.mutedFrame",
        "ui/RenameField.qml": "border.color: root.errorText.length > 0 ? Theme.color.error : Theme.color.accent"
    }
    for (var file in fields) {
        var text = Source.source(file)
        check(file + " frames a focused field in the accent", text.indexOf(fields[file]) >= 0, true)
        check(file + " draws no thick button frame around a field", text.indexOf("Buttons.RING") < 0, true)
    }
    // The chrome path field is the editFrame block alone: one accent hairline, no ring, and no sibling draws a border around it. The strip is the bar and the entry it holds.
    var chrome = Source.source("ui/ChromeBar.qml") + Source.source("ui/PathEntry.qml")
    var edit = blockOf(chrome, "id: editFrame")
    check("the path frame's border colour is the accent", valuesOf(edit, "border.color").join("|"), "Theme.color.accent")
    check("the path frame's border is one hairline", valuesOf(edit, "border.width").join("|"), "Theme.spacing.hairline")
    check("the path frame draws no ring or focus clearance", /Buttons\.RING|focusClearance|margins:\s*-/.test(edit), false)
    check("the strip draws no border but hairlines", valuesOf(chrome, "border.width").join("|"), "Theme.spacing.hairline")
    check("the strip never reads a ring width or focus clearance", /Buttons\.RING|focusClearance/.test(chrome), false)
    check("the strip groups no border properties, where a width would hide from the reader", /\bborder\s*\{/.test(chrome), false)
    check("the reader sees a border width inside a one-line item", valuesOf("Rectangle { border.width: 2; color: x }", "border.width").join("|"), "2")
    check("the block reader finds a nested block whole", blockOf("A { id: x; B { y: 1 } } C { z: 2 }", "id: x"), "{ id: x; B { y: 1 } }")

    // A ChromeButton under a strip rule takes the rule's row off its frame; MarkdownPane delegates its mark to QuickLookBar, and PreviewColumn draws no mark.
    var ruled = { "ui/PdfViewer.qml": 6, "ui/QuickLookBar.qml": 1, "ui/MarkdownPane.qml": 0, "ui/PermissionsDialog.qml": 1, "ui/PreviewColumn.qml": 0, "ui/ChromeBar.qml": 6, "ui/ChromeModes.qml": 1, "ui/PickerChrome.qml": 1, "ui/TrashView.qml": 2 }
    for (var host in ruled) {
        var hostText = Source.source(host)
        var wanted = ruled[host]
        var drawn = hostText.split("Flea.ChromeButton {").length - 1
        check(host + " gives every strip rule's row to its mark frame", hostText.split("ruleRows: Theme.spacing.hairline").length - 1, wanted)
        check(host + " hosts the buttons the pin counts", drawn === wanted, true)
    }

    // Every chrome mark frames itself in the foreground hairline for the keyboard; no host gives a mark an accent focus line.
    var hosts = ["ui/PdfViewer.qml", "ui/QuickLookBar.qml", "ui/ChromeBar.qml", "ui/ChromeModes.qml",
        "ui/PermissionsDialog.qml", "ui/PickerChrome.qml", "ui/TrashView.qml"]
    for (var h = 0; h < hosts.length; h++) {
        var hostCode = codeOf(Source.source(hosts[h]))
        check(hosts[h] + " hosts marks to name", marksOf(hostCode).length > 0, true)
        check(hosts[h] + " gives no mark a focus line", /\bfocusLine\b/.test(hostCode), false)
    }
    check("the mark reader keeps a mark's own line and drops a comment's and a nested block's",
        JSON.stringify(marksOf("Flea.ChromeButton { id: a // glyph: \"y\"\n B { glyph: \"z\" } }\nFlea.ChromeButton { glyph: \"x\" }")
            .map(function (mark) { return mark.name + "=" + valuesOf(mark.own, "glyph").join("|") })), JSON.stringify(["a=", "\"x\"=\"x\""]))
    var chromeButton = codeOf(Source.source("ui/ChromeButton.qml"))
    check("a chrome mark has no focus line to give", /\bfocusLine\b/.test(chromeButton), false)
    var markFrame = blockOf(chromeButton, "id: ring")
    check("a chrome mark's own frame is one hairline", valuesOf(markFrame, "border.width").join("|"), "Theme.spacing.hairline")
    check("a chrome mark's own frame is the foreground", valuesOf(markFrame, "border.color").join("|"), "Theme.color.foreground")
    check("no chrome mark reads the accent for its frame", /accent/.test(markFrame), false)
    // Quick Look's PDF viewer opens on the document; Tab or Shift+Tab is what enters its strip, so the key handler is the only caller and -1 the only index it writes.
    var viewerCode = codeOf(Source.source("ui/PdfViewer.qml"))
    var keyHandler = Source.block(viewerCode, "Keys.onPressed:", "ui/PdfViewer.qml")
    check("Quick Look's PDF viewer moves its pick only from the key handler, with the key's own action",
        [(viewerCode.match(/pdfAction/g) || []).length, keyHandler.indexOf("PreviewKeys.pdfAction(action, root)") >= 0,
         keyHandler.indexOf('var action = Keymap.lookup(event.key, event.text, event.modifiers, "pdf")') >= 0].join(" "), "1 true true")
    var writes = []
    // Sample input: "property int pdfControlIndex: -1\n root.pdfControlIndex = -1;" answers ": -1|= -1".
    var write = /\bpdfControlIndex\s*(\+\+|--|[-+*\/]?=(?!=)|:)\s*([^;\n}]*)/g
    for (var hit = write.exec(viewerCode); hit !== null; hit = write.exec(viewerCode))
        writes.push(hit[1] + " " + hit[2].trim())
    check("Quick Look's PDF viewer picks no control by itself: it declares the pick at -1 and resets it to -1, nothing more", writes.join("|"), ": -1|= -1")
}
