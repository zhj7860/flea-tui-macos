//@ pragma ShellId flea-chromering-test

import QtQuick
import Quickshell
import qs.Commons
import "flea" as Flea
import "button-probe.js" as Probe

// tests/chromering.sh's harness: the real ui/ChromeButton.qml, whose foreground hairline frame ButtonSystem040 A draws only for the keyboard, on every mark and every theme.
ShellRoot {
    id: root

    // Qt Quick needs the window mapped and a frame laid out before a size is read.
    readonly property int layoutMs: 300
    readonly property int ringBoard: 24
    // The text size stop the board draws its 24 square hit box and its inset-sized keyboard frame at.
    readonly property int boardStop: 14
    // Theme's own ratios: the strip is this share of a row, and a row is its line box (1.8 x bodySmall) plus the padding above and below.
    readonly property real chromeRowRatio: 0.72
    readonly property real lineBoxRatio: 1.8
    // Every stop the Display section offers, from the smallest strip to the largest.
    readonly property var stops: [9, 10, 11, 12, 14, 16, 20]
    // The answer row and the strip marks are measured after a settle tick, since Row and text relayout lag the size switch.
    readonly property var stripSizes: [9, 10, 11, 12, 14, 16, 20]
    // Each stop's glyph row inside its strip: the mark is centred in the strip above its rule, on Qt's whole pixel.
    readonly property var glyphRows: ({ 9: 2, 10: 3, 11: 4, 12: 4, 14: 5, 16: 5, 20: 6 })
    // The stops where the Flash strip must match the ruled sample.
    readonly property var flashSizes: [12, 14, 16]
    property int stripIdx: 0
    property bool stripSettled: false
    property int flashIdx: 0
    property bool flashSettled: false
    property int checks: 0
    property var failures: []

    function check(label, actual, expected) {
        root.checks += 1
        if (actual === expected) {
            console.log("CHROMERING ok " + label)
            return
        }
        root.failures.push(label)
        console.log("CHROMERING FAIL " + label + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function report() {
        if (root.failures.length === 0)
            console.log("CHROMERING PASS " + root.checks + " checks")
        root.quit()
    }

    FloatingWindow {
        implicitWidth: 320
        implicitHeight: 200
        color: Flea.Theme.color.background

        Row {
            spacing: 12
            Flea.ChromeButton { id: rest; glyph: "x" }
            Flea.ChromeButton { id: hot; glyph: "x"; keyboardFocused: true }
            // A strip DialogButton keeps the inset.
            Flea.DialogButton { id: answer; label: "Answer"; inStrip: true }
            Flea.ChromeButton { id: off; glyph: "x"; keyboardFocused: true; enabled: false }
            Flea.ChromeButton { id: muted; glyph: "x"; keyboardFocused: true; restingColor: Flea.Theme.color.mutedFrame }
            Flea.ChromeButton { id: lit; glyph: "x"; active: true; keyboardFocused: true }
        }

        // A strip that draws its rule in the hit box's last row, as the PDF and Markdown Quick Look strips do.
        Item {
            id: strip
            y: 60
            width: 120
            height: Flea.Theme.chromeHeight
            Rectangle { id: stripRule; anchors.bottom: parent.bottom; width: parent.width; height: Flea.Theme.spacing.hairline; color: Flea.Theme.color.foreground }
            Row {
                spacing: 12
                Flea.ChromeButton { id: ruled; glyph: "x"; keyboardFocused: true; ruleRows: Flea.Theme.spacing.hairline }
                Flea.ChromeButton { id: bare; glyph: "x"; keyboardFocused: true }
            }
        }

        // The real Flash strip, whose Back must match the ruled sample.
        Flea.FlashStrip {
            id: flashStrip
            y: 115
            width: 200
        }

        // A ruled strip mark beside the Network form's focused field, whose accent frame the mark must not take.
        Row {
            y: 100
            spacing: 12
            Flea.ChromeButton { id: lined; glyph: "x"; keyboardFocused: true; ruleRows: Flea.Theme.spacing.hairline }
            Flea.DialogField { id: field; width: 80; label: "Host" }
        }

        // The real window chrome and Trash strip, whose marks must keep their glyph row while the frame clears the rule.
        Flea.ChromeBar {
            id: chromeBar
            y: 320
            width: 600
            path: "/home/x/y"
            home: "/home/x"
            canGoBack: true
            canGoUp: true
        }
        Item {
            y: 380
            width: 800
            height: 300
            Flea.TrashView { id: trash; opened: true; total: 0 }
        }

        // The real picker chrome and the answer row under it, whose focused frames must stay inside the row.
        Item {
            id: pickerHost
            y: 140
            width: 800
            height: 160
            Flea.PickerChrome {
                id: pchrome
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                picker: mockPicker
            }
            Flea.PickerAnswers { id: panswers; anchors.top: pchrome.bottom; picker: mockPicker }
        }
    }

    // The picker's own face as PickerChrome reads it, copied from tests/button-members.qml.
    QtObject {
        id: mockPicker
        property var req: ({ mode: "open", title: "Choose file", app: "", accept: "", multiple: false, filters: [{ label: "Images" }] })
        property color edge: "#444444"
        property var marks: []
        property bool canAccept: true
        property var history: ["/a"]
        property bool backendUnavailable: false
        property bool submitting: false
        property bool recent: false
        property bool answered: false
        property string path: "/home/x/y"
        property string home: "/home/x"
        property bool showHidden: false
        property bool listingFailed: false
        property int filterIndex: 0
        property string viewMode: "list"
        function stepFocus(from, back) {}
        function control(name, item, available) { return { name: name } }
    }

    Timer {
        interval: root.layoutMs
        running: true
        repeat: false
        onTriggered: root.run()
    }

    Timer {
        id: pickerTimer
        interval: 200
        running: false
        repeat: true
        onTriggered: root.pickerStep()
    }

    Timer {
        id: flashTimer
        interval: 200
        running: false
        repeat: true
        onTriggered: root.flashStep()
    }

    // A button with no ring item answers "no ring" for every ring read, so the build before the ring fails on the board's words and not on a TypeError.
    function ringRead(button, read) { return button.ringItem ? read(button.ringItem) : "no ring" }
    function markRead(button, read) { return button.markItem ? read(button.markItem) : "no mark" }
    // What a stop must draw, from the Omarchy tokens the product scales: the icon token over the base size, and the strip off the row's line box.
    function wantMark(stop) { return Math.round(Style.font.icon * stop / Style.font.baseSize) }
    // Board stop 14: 27 band less two 3 insets leaves 21 room, trimmed to the 16 glyph parity is 20.
    readonly property string boardRing: "20x20"
    function wantStrip(stop) {
        var row = Math.round(Flea.Theme.font.bodySmall * root.lineBoxRatio) + 2 * Flea.Theme.spacing.rowPaddingY
        return Math.round(row * root.chromeRowRatio)
    }
    function stopState(stop) { Flea.ViewState.load(JSON.stringify({ display: { textSize: { mode: stop } } })) }

    // Every read is synchronous on the settled layout; hover and press have no reader here because the ring never depends on them.
    function run() {
        var shown = function (ring) { return ring.visible }
        root.stopState(root.boardStop)
        check("the hit box is at least the 24 board square", hot.implicitWidth >= root.ringBoard, true)
        check("a resting mark draws no ring", ringRead(rest, shown), false)
        check("a keyboard-focused mark draws its ring", ringRead(hot, shown), true)
        check("the ring is the inset-sized square at the board's size", ringRead(hot, function (ring) { return ring.width + "x" + ring.height }), root.boardRing)
        check("the frame is one hairline", ringRead(hot, function (ring) { return ring.border.width }), Flea.Theme.spacing.hairline)
        check("the frame is the foreground", ringRead(hot, function (ring) { return String(ring.border.color) }), String(Flea.Theme.color.foreground))
        check("the ring has no fill", ringRead(hot, function (ring) { return ring.color.a }), 0)
        check("a disabled mark draws no ring", ringRead(off, shown), false)
        check("a disabled mark mutes its glyph", markRead(off, function (mark) { return String(mark.color) }), String(Flea.Theme.color.mutedFrame))
        check("a muted resting mark inks in the foreground under the ring", markRead(muted, function (mark) { return String(mark.color) }), String(Flea.Theme.color.foreground))
        check("an active mark still takes the ring", ringRead(lit, shown), true)
        check("a resting mark inks in the foreground", markRead(rest, function (mark) { return String(mark.color) }), String(Flea.Theme.color.foreground))
        var marks = {}
        var strips = {}
        for (var i = 0; i < root.stops.length; i++) {
            root.stopState(root.stops[i])
            var tag = "stop " + root.stops[i] + " "
            var inside = function (ring) {
                return ring.x >= 0 && ring.y >= 0 && ring.x + ring.width <= hot.width && ring.y + ring.height <= hot.height }
            var centre = function (ring) {
                return (ring.x * 2 + ring.width) + "," + (ring.y * 2 + ring.height) }
            var markCentre = markRead(hot, function (mark) { return (mark.x * 2 + mark.width) + "," + (mark.y * 2 + mark.height) })
            check(tag + "the ring stays inside the hit box", ringRead(hot, inside), true)
            check(tag + "the ring keeps the control inset above and below", ringRead(hot, function (ring) { return ring.y >= Flea.Theme.chromeControlInset && hot.height - ring.y - ring.height >= Flea.Theme.chromeControlInset }), true)
            check(tag + "the ring shares the glyph's centre, so both sit on whole pixels together", ringRead(hot, centre), markCentre)
            check(tag + "the glyph keeps the chrome mark size under the ring", markRead(hot, function (mark) { return mark.width }), Flea.Theme.chromeMarkSize)
            check(tag + "the mark is the icon token scaled to the stop", markRead(hot, function (mark) { return mark.width }), root.wantMark(root.stops[i]))
            check(tag + "the hit box is as wide as the larger of the 24 floor and the mark", hot.width, Math.max(root.ringBoard, root.wantMark(root.stops[i])))
            check(tag + "the hit box is the strip's height off the row", hot.height, root.wantStrip(root.stops[i]))
            var ruledRing = ringRead(ruled, function (ring) { return ring.y + "," + (ring.y + ring.height) })
            var rows = ruledRing.split(",")
            check(tag + "a ring over a strip rule keeps the inset above it", Number(rows[0]) >= Flea.Theme.chromeControlInset, true)
            check(tag + "a ring over a strip rule keeps the inset between it and the rule", stripRule.y - Number(rows[1]) >= Flea.Theme.chromeControlInset, true)
            check(tag + "a strip answer keeps the inset above it", answer.frameY >= Flea.Theme.chromeControlInset, true)
            check(tag + "a strip answer keeps the inset between it and the rule", answer.height - Flea.Theme.spacing.hairline - answer.frameY - answer.frameHeight >= Flea.Theme.chromeControlInset, true)
            check(tag + "over a strip rule the ring and the glyph still share a centre", ringRead(ruled, centre), markRead(ruled, function (mark) { return (mark.x * 2 + mark.width) + "," + (mark.y * 2 + mark.height) }))
            marks[root.wantMark(root.stops[i])] = true
            strips[root.wantStrip(root.stops[i])] = true
        }
        root.stopState(root.boardStop)
        check("a ring over a strip rule is still the inset-sized square", ringRead(ruled, function (ring) { return ring.width + "x" + ring.height }), root.boardRing)
        check("the stops draw more than one mark size", Object.keys(marks).length > 1, true)
        check("the stops draw more than one hit box height", Object.keys(strips).length > 1, true)
        root.stripIdx = 0
        root.stripSettled = false
        pickerTimer.running = true
    }

    // One size per two ticks: switch, then read the settled answer row.
    function pickerStep() {
        if (root.stripIdx >= root.stripSizes.length) {
            pickerTimer.running = false
            stripMarks()
            flashStart()
            return
        }
        var size = root.stripSizes[root.stripIdx]
        if (!root.stripSettled) {
            root.stopState(size)
            root.stripSettled = true
            return
        }
        root.stripSettled = false
        root.stripIdx += 1
        root.pickerChecks(size)
    }

    // Each answer frame lies inside the answer row, below its rule.
    function pickerChecks(size) {
        var items = pchrome.focusItems()
        var answerItems = panswers.focusItems()
        var cancel = answerItems.filter(function (item) { return item.label === "Cancel" })[0]
        var accept = cancel ? Array.prototype.filter.call(cancel.parent.children, function (item) { return item.primary === true })[0] : null
        check("stop " + size + " the picker answer row holds the Cancel and primary answers", !!cancel && !!accept, true)
        if (!cancel || !accept)
            return
        var rule = Array.prototype.filter.call(panswers.children, function (c) { return c.height === Flea.Theme.spacing.hairline && c.width === panswers.width })[0]
        check("stop " + size + " the picker answer row draws its rule", !!rule, true)
        if (!rule)
            return
        var answers = [["cancel", cancel], ["accept", accept]]
        for (var k = 0; k < answers.length; k++) {
            var ans = answers[k][1]
            var tag = "stop " + size + " the picker " + answers[k][0] + " "
            var label = Probe.find(ans, "buttonLabel")
            check(tag + "label is the body size the board draws", label ? label.font.pixelSize : "no label", Flea.Theme.font.body)
            check(tag + "hit box is the board's control height", ans.height, Flea.Theme.rowHeight - Flea.Theme.spacing.rowPaddingY)
            var at = ans.mapToItem(panswers, 0, 0)
            check(tag + "hit box lies inside the answer row and below its rule", [at.y >= rule.y + rule.height, at.y + ans.height <= panswers.height].join(" "), "true true")
            check(tag + "focused frame lies inside the answer row and below its rule", root.focusedFrame(ans, panswers, rule.y + rule.height), "true true true")
        }
        var back = items.filter(function (item) { return item.glyph === "arrow-left" })[0]
        root.glyphChecks(size, "the picker path strip", back, back ? back.parent.parent : null)
        var barBack = chromeBar.buttonFor("arrow-left")
        root.glyphChecks(size, "the window chrome", barBack, chromeBar)
        root.glyphChecks(size, "the window chrome's settings mark", chromeBar.buttonFor("sliders"), chromeBar)
        root.glyphChecks(size, "the Trash strip", trash.backItem, trash.backItem.parent.parent)
    }

    // The answer's frame read with the keyboard on it: drawn, below the row's rule and above its bottom.
    function focusedFrame(answer, row, ruleBottom) {
        answer.focused = true
        var frame = Probe.find(answer, "buttonFrame")
        var box = frame.mapToItem(row, 0, 0, frame.width, frame.height)
        var read = [answer.focusShown, box.y >= ruleBottom, box.y + box.height <= row.height].join(" ")
        answer.focused = Qt.binding(function () { return answer.activeFocus })
        return read
    }

    // A strip mark centres its glyph in the strip above its rule and keeps the strip's rows as its hit box, and its keyboard frame keeps the inset.
    function glyphChecks(size, name, mark, strip) {
        var tag = "stop " + size + " " + name + " "
        if (!mark || !strip || !mark.markItem) {
            check(tag + "mark is found", false, true)
            return
        }
        var glyph = mark.markItem.mapToItem(strip, 0, 0, mark.markItem.width, mark.markItem.height)
        var hit = mark.mapToItem(strip, 0, 0, mark.width, mark.height)
        check(tag + "glyph row, glyph size and hit box rows sit where the strip centres them", [glyph.y, glyph.height, hit.y, hit.height].join(","),
            [root.glyphRows[size], Flea.Theme.chromeMarkSize, 0, Flea.Theme.chromeHeight].join(","))
        var ring = mark.ringItem.mapToItem(strip, 0, 0, mark.ringItem.width, mark.ringItem.height)
        check(tag + "focus frame keeps the inset from the strip top and from its rule",
            ring.y >= Flea.Theme.chromeControlInset && strip.height - Flea.Theme.spacing.hairline - ring.y - ring.height >= Flea.Theme.chromeControlInset, true)
    }

    // The Flash Back keeps the ruled sample's centre and the inset off the rule.
    function flashRow() {
        var rows = Array.prototype.filter.call(flashStrip.children, function (c) { return c.children && c.children.length > 0 })
        return rows.length > 0 ? rows[0] : null
    }
    function flashBack() {
        var row = root.flashRow()
        return row ? row.children[0] : null
    }
    function flashRule() {
        var bars = Array.prototype.filter.call(flashStrip.children, function (c) { return c.height === Flea.Theme.spacing.hairline })
        return bars.length > 0 ? bars[0] : null
    }
    // The Flash Back answers after its own settle tick, one size per two ticks.
    function flashStart() {
        var back = root.flashBack()
        var rule = root.flashRule()
        check("flash the strip holds its Back mark and its rule", !!back && !!rule, true)
        if (!back || !rule) {
            report()
            return
        }
        back.keyboardFocused = true
        root.flashIdx = 0
        root.flashSettled = false
        flashTimer.running = true
    }
    function flashStep() {
        if (root.flashIdx >= root.flashSizes.length) {
            flashTimer.running = false
            root.stopState(root.boardStop)
            report()
            return
        }
        var size = root.flashSizes[root.flashIdx]
        if (!root.flashSettled) {
            root.stopState(size)
            root.flashSettled = true
            return
        }
        root.flashSettled = false
        root.flashIdx += 1
        root.flashChecksFor(size)
    }
    function flashChecksFor(size) {
        var tag = "flash stop " + size + " "
        var back = root.flashBack()
        var rule = root.flashRule()
        check(tag + "the Flash Back mark and its rule are present", !!back && !!rule, true)
        if (!back || !rule)
            return
        var shown = function (ring) { return ring.visible }
        var centre = function (item) { return (item.x * 2 + item.width) + "," + (item.y * 2 + item.height) }
        check(tag + "the Flash Back draws its ring for the keyboard", ringRead(back, shown), true)
        check(tag + "the Flash Back glyph shares the ruled mark's centre", markRead(back, centre), markRead(ruled, centre))
        check(tag + "the Flash Back ring keeps the inset above it", ringRead(back, function (ring) { var at = ring.mapToItem(rule.parent, 0, 0); return at.y >= Flea.Theme.chromeControlInset }), true)
        check(tag + "the Flash Back ring keeps the inset off the strip rule", ringRead(back, function (ring) { var at = ring.mapToItem(rule.parent, 0, 0); return rule.y - at.y - ring.height >= Flea.Theme.chromeControlInset }), true)
    }

    // One theme's keyboard frame on a strip mark: the foreground hairline every mark draws, never the focused field's accent line.
    function stripReads(name) {
        // A stroke reads as "width colour", one string, because check compares with ===.
        var stroke = function (ring) { return ring.border.width + " " + Probe.rgba(ring.border.color) }
        var foregroundLine = Flea.Theme.spacing.hairline + " " + Probe.rgba(Flea.Theme.color.foreground)
        check(name + "a strip mark frames itself in the foreground hairline as every mark does", ringRead(lined, stroke), foregroundLine)
        check(name + "a strip mark frames itself as the bare mark beside it does", ringRead(lined, stroke), ringRead(bare, stroke))
        // The same mark read with the keyboard on it and at rest, so a frame drawn without the keyboard fails here on each theme.
        var shown = ringRead(lined, function (ring) { return ring.visible })
        lined.keyboardFocused = false
        var resting = ringRead(lined, function (ring) { return ring.visible })
        lined.keyboardFocused = true
        check(name + "a strip mark draws its frame only for the keyboard", shown + " " + resting, "true false")
        check(name + "a strip mark keeps the inset-sized square", ringRead(lined, function (ring) { return ring.width + "x" + ring.height }), root.boardRing)
        check(name + "a strip mark inks as every framed mark does", markRead(lined, function (mark) { return String(mark.color) }), markRead(ruled, function (mark) { return String(mark.color) }))
    }

    // The preview strips' marks frame themselves as every chrome mark does; no mark carries an accent focus line, whatever the field beside it draws.
    function stripMarks() {
        root.stopState(root.boardStop)
        check("a chrome mark has no focus line to set", lined.focusLine === undefined, true)
        field.takeFocus()
        Flea.Theme.applyColors(Probe.COLOURED_THEME)
        check("the pinned theme's accent has a hue", Flea.Theme.color.accentHasHue, true)
        var stroke = function (item) { return item.border.width + " " + Probe.rgba(item.border.color) }
        check("the field holds the keyboard, so its frame is the accent hairline", [field.focused, stroke(field.input.parent)].join(" "),
              "true " + Flea.Theme.spacing.hairline + " " + Probe.rgba(Flea.Theme.color.accent))
        check("a strip mark's frame is not the focused field's accent line", ringRead(lined, stroke) !== stroke(field.input.parent), true)
        stripReads("coloured: ")
        lined.enabled = false
        check("a disabled strip mark draws no frame", ringRead(lined, function (ring) { return ring.visible }), false)
        lined.enabled = true
        Flea.Theme.applyColors(Probe.KANAGAWA_THEME)
        check("the hueless theme's accent has no hue", Flea.Theme.color.accentHasHue, false)
        stripReads("hueless: ")
    }
}
