//@ pragma ShellId flea-fontpane-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Format.js" as Format

// Real Quick Look over a stub backend that answers fontlook: the page whole in one turn, one ask per theme change, a stale answer dropped, a refusal drawn as the unsupported state.
ShellRoot {
    id: shell

    readonly property string dir: Quickshell.env("FONTPANE_DIR")
    readonly property string sentence: "This file cannot be previewed."
    readonly property string dot: " · "
    readonly property string fontA: shell.dir + "/Inter-Bold.ttf"
    readonly property string fontB: shell.dir + "/Slow-Light.ttf"
    readonly property string fontC: shell.dir + "/Hack-Regular.otf"
    readonly property string fontBroken: shell.dir + "/Broken.ttf"
    readonly property string facts: "Inter" + shell.dot + "Bold" + shell.dot + Format.size(312000) + shell.dot + "2,548 glyphs"

    property int stage: 0
    property int stageTicks: 0
    property int steps: 0
    property int frames: 0
    property bool done: false
    // Every ask the stub backend received, and one entry per answer it delivered with the page read just before and just after.
    property var asks: []
    property var landed: []
    property var frameBad: []
    // The answer the stub gives to the Nth ask; an ask with no entry gets the default one.
    property var script: ({})
    property string oldForeground: ""

    function log(line) { console.log("FONTPANE " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function fail(why) {
        if (shell.done) return
        shell.log("FAIL " + why)
        shell.done = true
        shell.quit()
    }
    function check(cond, why) { if (!cond && !shell.done) shell.fail(why); return cond }
    function step(what) { shell.steps++; shell.log("STEP " + shell.steps + " " + what) }
    function next() { shell.stage++; shell.stageTicks = 0 }

    // An item built in QML with its own properties prints as QQuickImage_QML_7(0x...), a plain one as QQuickImage(0x...).
    function typeIs(item, type) {
        return String(item).indexOf(type) === 0 || new RegExp("^QQuick" + type + "(_QML_\\d+)?\\(").test(String(item))
    }
    function find(item, type) {
        if (shell.typeIs(item, type)) return item
        var children = item.children || []
        for (var i = 0; i < children.length; i++) {
            var found = shell.find(children[i], type)
            if (found) return found
        }
        return null
    }
    function findText(item, text) {
        if (shell.typeIs(item, "Text") && item.text === text) return item
        var children = item.children || []
        for (var i = 0; i < children.length; i++) {
            var found = shell.findText(children[i], text)
            if (found) return found
        }
        return null
    }
    function kids(item, type) {
        return (item.children || []).filter(function (child) { return shell.typeIs(child, type) })
    }
    function fontPane() { return shell.find(look, "FontPane") }
    function page(pane) { return shell.kids(pane, "Column")[0] }
    function bar(pane) { return shell.kids(pane, "Item")[0] }
    function images(pane) { return shell.kids(shell.page(pane), "Image") }
    function factsText(pane) { return shell.kids(shell.page(pane), "Text")[0] }
    // "file:///x/r1-2.png" is round r1.
    function tag(source) {
        var m = /([a-z0-9]+)-\d\.png$/.exec(String(source))
        return m ? m[1] : ""
    }
    function hexOf(color) { return String(color) }
    function sizesNow() {
        return [22, 15, 12].map(function (px) { return Math.round(Math.round(px * Flea.Theme.sizeRatio) * probe.ratio) })
    }

    // What the pane shows at this instant, read from the items themselves.
    function snap() {
        var pane = shell.fontPane()
        if (!pane) return { pane: false }
        var shown = shell.images(pane)
        return {
            pane: true,
            drawn: pane.drawn,
            barVisible: shell.bar(pane).visible,
            status: pane.status,
            previewStatus: look.status,
            count: shown.length,
            ready: shown.every(function (image) { return image.status === Image.Ready }),
            tags: shown.map(function (image) { return shell.tag(image.source) }),
            facts: shell.factsText(pane).text,
            name: shell.find(shell.bar(pane), "Text").text
        }
    }
    function one(s) { return s.tags.every(function (t) { return t === s.tags[0] }) }

    // The page is whole or absent at every frame: three ready images of one round, a facts line and a bar name, or none of them.
    function frameCheck() {
        shell.frames++
        var s = shell.snap()
        if (!s.pane) return
        var bad = ""
        if (s.drawn && !(s.count === 3 && s.ready && shell.one(s) && s.facts !== "" && s.name !== ""))
            bad = "drawn page is partial: images=" + s.count + " ready=" + s.ready + " tags=" + s.tags + " facts=" + s.facts
        else if (!s.drawn && (s.count !== 0 || s.facts !== ""))
            bad = "page parts show before the answer: images=" + s.count + " facts=" + s.facts
        else if (s.barVisible !== s.drawn)
            bad = "the bar and the page do not show together: bar=" + s.barVisible + " drawn=" + s.drawn
        else if (s.previewStatus === "loading" && look.lookReady)
            bad = "Quick Look is ready while the font is still loading"
        if (bad !== "" && shell.frameBad.length < 3) shell.frameBad.push(bad)
    }

    function planFor(n) {
        var base = { delay: 40, mode: "ok", prefix: "r0", family: "Inter", style: "Bold", glyphs: 2548 }
        var own = shell.script[n] || {}
        for (var key in own) base[key] = own[key]
        return base
    }

    // The same turn: the page just before the answer and just after it, so a half-drawn page cannot hide between two frames.
    function answer(n, request) {
        var plan = shell.planFor(n)
        var message = plan.mode === "fail"
            ? { t: "fontlooked", id: request.id, err: "ImageMagick is not installed" }
            : { t: "fontlooked", id: request.id, family: plan.family, style: plan.style, glyphs: plan.glyphs,
                files: [0, 1, 2].map(function (i) { return shell.dir + "/" + plan.prefix + "-" + i + ".png" }) }
        var before = shell.snap()
        stub.fontLooked(message)
        shell.landed.push({ n: n, id: request.id, before: before, after: shell.snap() })
    }

    QtObject {
        id: stub
        signal fontLooked(var message)
        // Quick Look listens for this one on every pane, so the stub declares it with Backend.qml's own signature.
        signal meta(int row, int w, int h, int orient, real durationMs, int sampleRate, int entries, real unpacked, bool archiveFailed, var names, real lines, bool partial, bool linesFailed, string target, bool targetDir, string owner)
        function send(request) {
            shell.asks.push(request)
            var n = shell.asks.length
            answerTimer.createObject(shell, { n: n, request: request, interval: shell.planFor(n).delay })
        }
    }

    Component {
        id: answerTimer
        Timer {
            id: timer
            property int n: 0
            property var request: null
            running: true
            repeat: false
            onTriggered: { shell.answer(timer.n, timer.request); timer.destroy() }
        }
    }

    Component {
        id: paneStub
        QtObject {
            property string path: "/probe/fonts"
            property var rows: []
            property int cursorIndex: -1
            property bool listInFlight: false
            property bool storageKnown: true
            property string storageClass: "local"
            property var thumbState: ({ file: {}, order: [] })
            property var listArea: QtObject { function forceActiveFocus() {} }
            property var backend: null
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) { return null }
        }
    }
    property var stubPane: paneStub.createObject(shell, { backend: stub })

    FloatingWindow {
        implicitWidth: 900
        implicitHeight: 640
        color: Flea.Theme.color.background

        Item {
            id: probe
            readonly property real ratio: Screen.devicePixelRatio
        }
        Flea.Preview {
            id: look
            anchors.fill: parent
            pane: shell.stubPane
        }
        Connections {
            target: look.Window.window
            function onAfterAnimating() { shell.frameCheck() }
        }
    }

    function checkAsk(request, path, label) {
        var want = shell.sizesNow()
        return shell.check(request.c === "fontlook" && request.path === path
            && request.fg === shell.hexOf(Flea.Theme.color.foreground) && request.bg === shell.hexOf(Flea.Theme.color.surface)
            && request.sizes.join(",") === want.join(",") && request.text === "The quick brown fox jumps over the lazy dog",
            label + " ask is " + JSON.stringify(request) + ", want path " + path + " fg " + Flea.Theme.color.foreground
            + " bg " + Flea.Theme.color.surface + " sizes " + want)
    }

    // The recipe: 40 px at the sides, the three samples 18 px apart over the facts line, the block centred between the bar and the foot.
    function checkGeometry(label) {
        var pane = shell.fontPane()
        var column = shell.page(pane)
        var shown = shell.images(pane)
        var facts = shell.factsText(pane)
        var r = Flea.Theme.sizeRatio
        var gap = Math.round(18 * r)
        var barItem = shell.bar(pane)
        var top = barItem.height + Math.max(Math.round(24 * r), Math.round((pane.height - barItem.height - column.height) / 2))
        shell.check(column.x === Math.round(40 * r) && column.width === pane.width - 2 * column.x,
            label + " column sits at x=" + column.x + " width=" + column.width + " in a pane of " + pane.width + ", want " + Math.round(40 * r) + " at each side")
        shell.check(column.y === top, label + " column sits at y=" + column.y + ", want " + top)
        shell.check(barItem.height === Flea.Theme.chromeHeight, label + " bar is " + barItem.height + " tall, want " + Flea.Theme.chromeHeight)
        shell.check(shown[1].y - (shown[0].y + shown[0].height) === gap && shown[2].y - (shown[1].y + shown[1].height) === gap
            && facts.y - (shown[2].y + shown[2].height) === gap, label + " samples and facts are not " + gap + " px apart")
        for (var i = 0; i < 3; i++)
            shell.check(shown[i].x === 0 && shown[i].width === shown[i].implicitWidth / probe.ratio && shown[i].height === shown[i].implicitHeight / probe.ratio
                && shown[i].implicitWidth > 0, label + " sample " + i + " is drawn " + shown[i].width + "x" + shown[i].height + " from " + shown[i].implicitWidth + "x" + shown[i].implicitHeight + " pixels")
    }

    function advance() {
        if (shell.done) return
        shell.stageTicks++
        if (shell.stageTicks > 600) { shell.fail("stage " + shell.stage + " timed out"); return }
        var s
        switch (shell.stage) {
        case 0:
            shell.script[1] = { delay: 120 }
            look.open(shell.fontA, "font-x-generic", 312000, "TrueType font", "")
            shell.next(); break
        case 1:
            if (shell.asks.length < 1) return
            s = shell.snap()
            shell.check(s.pane, "no font pane loaded for a .ttf")
            shell.checkAsk(shell.asks[0], shell.fontA, "the first")
            shell.check(shell.asks[0].id === 1, "the first ask has id " + shell.asks[0].id)
            shell.check(!s.barVisible, "the bar shows before the answer: " + JSON.stringify(s))
            shell.check(!s.drawn && s.count === 0 && s.facts === "" && s.status === "loading" && s.previewStatus === "loading" && !look.lookReady,
                "before the answer the page shows parts or Quick Look is ready: " + JSON.stringify(s) + " ready=" + look.lookReady)
            shell.step("the first ask carries the path, both colours, three sizes and the sentence, and the page waits whole")
            shell.next(); break
        case 2:
            if (shell.landed.length < 1) return
            var one = shell.landed[0]
            shell.check(!one.before.drawn && one.before.count === 0 && one.before.facts === "", "the page was partly up before the answer: " + JSON.stringify(one.before))
            shell.check(one.after.drawn && one.after.count === 3 && one.after.ready && shell.one(one.after) && one.after.tags[0] === "r0",
                "the answer left a partial page in the same turn: " + JSON.stringify(one.after))
            shell.check(one.after.facts === shell.facts, "the facts line is '" + one.after.facts + "', want '" + shell.facts + "'")
            shell.check(one.after.name === "Inter-Bold.ttf" && one.after.status === "font" && look.status === "font" && look.lookReady,
                "bar name or status wrong: " + JSON.stringify(one.after) + " ready=" + look.lookReady)
            shell.check(shell.images(shell.fontPane()).every(function (image) { return String(image.source).indexOf("file://" + shell.dir + "/r0-") === 0 }),
                "the samples are not the answer's three files")
            // The Column lays its parts out on a later polish, several ticks on: its height is their sum and gaps once it has run.
            var col = shell.page(shell.fontPane()), parts = shell.images(shell.fontPane()).concat([shell.factsText(shell.fontPane())])
            if (col.height !== parts.reduce(function (a, p) { return a + p.height }, 0) + col.spacing * (parts.length - 1)) return
            shell.checkGeometry("the first page")
            shell.step("the bar, three ready samples and the facts line land in the answer's own turn, laid out to the recipe")
            shell.next(); break
        case 3:
            // The theme switch Omarchy makes: a new colors.toml, then theme.name rewritten in place.
            shell.oldForeground = String(Flea.Theme.color.foreground)
            shell.script[2] = { delay: 200, prefix: "r1" }
            Quickshell.execDetached(["bash", "-c", 'cp -- "$1" "$2" && date +%s%N > "$3"', "_",
                Quickshell.env("FONTPANE_ALT"), Quickshell.env("FONTPANE_COLORS"), Quickshell.env("FONTPANE_NAME")])
            shell.next(); break
        case 4:
            if (String(Flea.Theme.color.foreground) === shell.oldForeground || shell.asks.length < 2) return
            s = shell.snap()
            shell.check(s.drawn && s.count === 3 && s.ready && s.tags[0] === "r0", "the old page did not stay up while the new colours were drawn: " + JSON.stringify(s))
            shell.checkAsk(shell.asks[1], shell.fontA, "the theme change")
            shell.check(shell.asks[1].fg !== shell.asks[0].fg && shell.asks[1].bg !== shell.asks[0].bg,
                "the theme change asked with colours of the old palette: " + shell.asks[1].fg + " on " + shell.asks[1].bg)
            shell.next(); break
        case 5:
            // Past the old answer's due time and the new one's: a mixed-palette ask would have arrived by now.
            if (shell.stageTicks < 30 || shell.landed.length < 2) return
            shell.check(shell.asks.length === 2, "the theme change sent " + (shell.asks.length - 1) + " asks, want one with both colours new")
            var two = shell.landed[1]
            shell.check(two.before.drawn && two.before.count === 3 && two.before.tags[0] === "r0",
                "the old samples were gone before the new answer: " + JSON.stringify(two.before))
            shell.check(two.after.drawn && two.after.count === 3 && two.after.ready && shell.one(two.after) && two.after.tags[0] === "r1",
                "the answer did not swap all three samples at once: " + JSON.stringify(two.after))
            shell.check(two.after.facts === shell.facts, "the facts line changed to '" + two.after.facts + "'")
            shell.step("a theme change asks once with both colours new, the old page stays up, and all three samples swap in one turn")
            shell.next(); break
        case 6:
            // B is slow and C is quick: B's answer lands after C's and must be dropped.
            shell.script[3] = { delay: 400, prefix: "r0", family: "Slow", style: "Light", glyphs: 100 }
            shell.script[4] = { delay: 40, prefix: "hack", family: "Hack", style: "Regular", glyphs: 1500 }
            look.open(shell.fontB, "font-x-generic", 2000, "TrueType font", "")
            shell.next(); break
        case 7:
            if (shell.asks.length < 3) return
            s = shell.snap()
            shell.check(!s.drawn && s.count === 0 && s.facts === "" && s.previewStatus === "loading",
                "a font whose answer is pending shows the last font's page: " + JSON.stringify(s))
            look.open(shell.fontC, "font-x-generic", 3000, "OpenType font", "")
            shell.next(); break
        case 8:
            if (shell.landed.length < 4) return
            s = shell.snap()
            var stale = shell.landed[3]
            shell.check(stale.id === 3 && stale.n === 3, "the slow answer is not the one that landed last: " + JSON.stringify(shell.landed.map(function (e) { return e.n })))
            shell.check(s.drawn && s.tags.join(",") === "hack,hack,hack" && s.facts === "Hack" + shell.dot + "Regular" + shell.dot + Format.size(3000) + shell.dot + "1,500 glyphs",
                "a stale answer replaced the page of the font on screen: " + JSON.stringify(s))
            shell.step("an answer to a superseded ask is dropped")
            shell.next(); break
        case 9:
            shell.script[5] = { delay: 40, mode: "fail" }
            look.open(shell.fontBroken, "font-x-generic", 100, "TrueType font", "")
            shell.next(); break
        case 10:
            if (shell.landed.length < 5) return
            s = shell.snap()
            var refused = shell.findText(look, shell.sentence)
            shell.check(look.fontFailed && look.status === shell.sentence && s.count === 0 && !shell.fontPane().visible,
                "a refused font does not show the unsupported state: " + JSON.stringify(s) + " failed=" + look.fontFailed)
            shell.check(refused !== null && refused.visible, "the unsupported sentence is not on screen for a refused font")
            shell.check(shell.landed[4].before.count === 0 && !shell.landed[4].before.drawn, "a refused font showed a page before its answer")
            shell.step("a refused font draws today's unsupported state and no page")
            shell.next(); break
        case 11:
            // A text file never asks, and the font pane goes with the font.
            look.open(shell.dir + "/notes.txt", "text-plain", 16, "Text", "")
            shell.next(); break
        case 12:
            if (shell.stageTicks < 12) return
            shell.check(shell.asks.length === 5, "a text file sent a fontlook ask, " + shell.asks.length + " asks in all")
            shell.check(shell.fontPane() === null, "the font pane is still loaded for a text file")
            look.open(shell.fontA, "font-x-generic", 312000, "TrueType font", "")
            shell.next(); break
        case 13:
            if (shell.asks.length < 6 || shell.landed.length < 6) return
            shell.check(shell.landed[5].after.drawn && shell.landed[5].after.facts === shell.facts, "a reopened font did not draw whole")
            shell.next(); break
        case 14:
            // A is slow and its pane goes with it; C builds a new pane whose ask is still out when A's answer lands.
            if (shell.stageTicks === 1) shell.script = { 7: { delay: 300, prefix: "r1", family: "Slow", style: "Light", glyphs: 100 }, 8: { delay: 450, prefix: "hack", family: "Hack", style: "Regular", glyphs: 1500 } }
            var hop = { 1: shell.dir + "/notes.txt", 3: shell.fontB, 8: shell.dir + "/notes.txt", 10: shell.fontC }[shell.stageTicks]
            if (hop) look.open(hop, hop.indexOf("notes") > 0 ? "text-plain" : "font-x-generic", 2000, "TrueType font", "")
            if (shell.stageTicks === 10) shell.next()
            break
        case 15:
            if (shell.landed.length < 8) return
            var late = shell.landed[6].after
            s = shell.snap()
            shell.check(shell.landed[6].n === 7 && !late.drawn && late.count === 0 && !late.barVisible, "an earlier pane's late answer was drawn by the next pane: " + JSON.stringify(late))
            shell.check(s.drawn && s.tags.join(",") === "hack,hack,hack" && s.name === "Hack-Regular.otf", "the pane's own answer did not draw: " + JSON.stringify(s))
            shell.step("an answer to an earlier pane's ask is never drawn by the next pane")
            // The theme returns to the dark palette: the drawn font asks again and the backend refuses.
            shell.oldForeground = String(Flea.Theme.color.foreground)
            shell.script[9] = { delay: 40, mode: "fail" }
            Quickshell.execDetached(["bash", "-c", 'cp -- "$1" "$2" && date +%s%N > "$3"', "_",
                Quickshell.env("FONTPANE_DARK"), Quickshell.env("FONTPANE_COLORS"), Quickshell.env("FONTPANE_NAME")])
            shell.next(); break
        case 16:
            if (String(Flea.Theme.color.foreground) === shell.oldForeground || shell.landed.length < 9) return
            s = shell.snap()
            var again = shell.findText(look, shell.sentence)
            shell.check(shell.landed[8].before.count === 3 && !s.drawn && s.count === 0 && s.facts === "" && !s.barVisible && look.fontFailed && again !== null && again.visible,
                "a refusal after a drawn page left the page up with the unsupported state: " + JSON.stringify(s))
            shell.step("a refusal after a drawn page leaves only the unsupported state")
            look.close()
            shell.next(); break
        case 17:
            if (shell.stageTicks < 3) return
            shell.check(shell.fontPane() === null && !look.active, "closing Quick Look left the font pane up")
            shell.step("a text file asks nothing, the pane goes with the font, and a reopen starts clean")
            shell.check(shell.frames > 0, "no frame was observed")
            shell.check(shell.frameBad.length === 0, "a frame held a partial page: " + shell.frameBad.join(" | "))
            if (!shell.done) {
                shell.log("DONE steps=" + shell.steps + " asks=" + shell.asks.length + " frames=" + shell.frames)
                shell.done = true
                shell.quit()
            }
            break
        }
    }

    Timer {
        interval: 16
        repeat: true
        running: true
        onTriggered: shell.advance()
    }
}
