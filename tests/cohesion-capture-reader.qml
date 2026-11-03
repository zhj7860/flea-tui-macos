//@ pragma ShellId flea-cohesion-capture-reader-test
import QtQuick
import Quickshell
import QtTest
import "flea" as Flea
import "flea/js/Buttons.js" as Buttons
import "flea/js/Scroll.js" as Scroll
import "button-probe.js" as Probe

// Real controls exercise the capture-only reader, including geometry while pressed and an item outside its clipping parent.
ShellRoot {
    id: root
    property int stage: 0
    property int ticks: 0
    property int checks: 0
    property var failures: []
    property var rest: null
    property var restLabel: null
    property double pressSince: 0
    property var reader: null
    property var restFrame: null
    property var restWash: null
    property double pressedAt: 0
    property double wakeAt: 0
    readonly property int wakeWaitMs: 3000
    property double hoverAt: 0

    function check(cond, label) {
        root.checks++
        if (!cond) { root.failures.push(label); console.log("COHCAPTURE FAIL " + label) }
    }
    function read() {
        return JSON.parse(root.reader.read(window, window.contentItem, /^(DialogButton|SettingsRow)_QML/, {}))
    }
    function control(state, name) { return state.controls.find(function(c) { return c.name === name }) }
    function named(item, name) {
        if (item.objectName === name) return item
        for (var i = 0; i < item.children.length; i++) {
            var found = root.named(item.children[i], name)
            if (found) return found
        }
        return null
    }
    function rect(item, target) {
        var box = item.mapToItem(target, 0, 0, item.width, item.height)
        return [box.x, box.y, box.width, box.height]
    }
    function pdfBar(item) {
        if (!item || !item.visible) return null
        if (String(item).indexOf("ViewportScrollBar_QML") === 0 && item.vertical) return item
        for (var i = 0; i < item.children.length; i++) {
            var found = root.pdfBar(item.children[i])
            if (found) return found
        }
        return null
    }
    function box(item) {
        var a = item.mapToItem(window.contentItem, 0, 0)
        var b = item.mapToItem(window.contentItem, item.width, item.height)
        return [a.x, a.y, b.x - a.x, b.y - a.y]
    }
    function insetBox(before, x, y) { return [before[0] + x, before[1] + y, before[2] - 2 * x, before[3] - 2 * y] }
    function report() {
        timer.running = false
        console.log("COHCAPTURE DONE checks=" + root.checks + " failed=" + root.failures.length)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
    Component.onCompleted: {
        Flea.Theme.reducedMotion = false
        root.reader = Qt.createComponent("flea/IpcControls.qml").createObject(root)
    }

    FloatingWindow {
        id: window
        implicitWidth: 500
        implicitHeight: 400
        Item {
            id: stage
            anchors.fill: parent
            visible: root.stage < 3
            Flea.DialogButton { id: button; x: 100; y: 100; width: 100; height: 30; label: "Press" }
            Item {
                x: 100; y: 160; width: 40; height: 30; clip: true
                Flea.DialogButton { x: 50; width: 80; height: 30; label: "Clipped" }
            }
            Flea.MediaStrip { id: media; x: 10; y: 220; width: 480 }
            Flea.MenuRow { x: 100; y: 280; width: 100; entry: ({label: "Images", action: "1"}); current: true }
            Flea.SettingsRow { x: 100; y: 330; width: 200; row: ({kind: "hint", label: "Information"}) }
        }
        Flea.SelectionPreview {
            id: pdf
            anchors.fill: parent
            visible: root.stage === 3 || root.stage === 4 || root.stage === 6 || root.stage === 7
            row: ({n: "manual.pdf", d: false, s: 1000, p: 33188})
            meta: ({})
            path: Quickshell.env("HOME") + "/fixture/manual.pdf"
        }
        Flea.KeymapSheet {
            anchors.fill: parent
            opened: root.stage === 5
        }
        TestEvent { id: driver }
    }
    Timer {
        id: timer
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            root.ticks++
            if (root.ticks > 100) { root.check(false, "the capture reader did not finish"); root.report(); return }
            if (!root.reader || window.width !== 500) return
            if (root.stage === 0) {
                var state = root.read()
                root.rest = root.control(state, "Press")
                root.restLabel = root.rect(root.named(button, "buttonLabel"), stage)
                root.check(!!root.rest && root.rest.exposed && root.rest.pressLive, "the button exposes a real press target")
                root.check(root.control(state, "Clipped").exposed === false, "a centre outside its clipping parent is not a pointer target")
                var play = root.control(state, "Play")
                root.check(!!play && play.exposed && !play.hoverable && play.pressLive, "media play reports its real TapHandler and absence of a hover effect")
                var choice = root.control(state, "Images")
                root.check(!!choice && choice.value === "1" && choice.focused, "the filter menu row reports its caption, action and cursor")
                var hint = state.controls.find(function(c) { return c.kind === "SettingsRow" })
                root.check(!!hint && !hint.hoverLive && !hint.pressLive, "an informational settings row has no live hover or press target")
                var frame = Probe.find(button, "buttonFrame"), wash = Probe.find(button, "buttonWash")
                root.check(!!frame && !!wash, "the button exposes its actual frame and wash")
                if (!frame || !wash) { root.report(); return }
                root.restFrame = root.box(frame)
                root.restWash = root.box(wash)
                root.pressedAt = Date.now()
                driver.mousePress(stage, root.rest.targetX, root.rest.targetY, Qt.LeftButton, Qt.NoModifier, 0)
                root.pressSince = Date.now()
                root.stage = 1
                return
            }
            if (root.stage === 1) {
                // Both press clocks must settle, including the unit's extra timer interval.
                if (Date.now() - root.pressSince < Buttons.PRESS_MS
                    || Date.now() - root.pressedAt < Buttons.PRESS_MS + timer.interval) return
                var held = root.control(root.read(), "Press")
                root.check(held.pressed, "a held press is read from the actual button")
                root.check([held.x, held.y, held.w, held.h, held.targetX, held.targetY].join() ===
                    [root.rest.x, root.rest.y, root.rest.w, root.rest.h, root.rest.targetX, root.rest.targetY].join(), "a press keeps the hit box and coordinate signature fixed")
                root.check(button.scale === 1 && held.x === root.rest.x && held.y === root.rest.y
                    && held.w === root.rest.w && held.h === root.rest.h, "press keeps the root unscaled and coordinate signature stable")
                var insetX = Flea.Theme.reducedMotion ? 0 : Math.round(button.width * (1 - Buttons.PRESS_SCALE) / 2)
                var insetY = Flea.Theme.reducedMotion ? 0 : Math.round(button.frameHeight * (1 - Buttons.PRESS_SCALE) / 2)
                root.check(root.rect(root.named(button, "buttonFrame"), button).join() ===
                    [insetX, button.frameY + insetY, Math.round(button.width) - 2 * insetX, Math.round(button.frameHeight) - 2 * insetY].join(), "only the frame takes the exact whole-pixel press inset")
                root.check(root.rect(root.named(button, "buttonLabel"), stage).join() === root.restLabel.join(), "a press keeps the caption geometry fixed")
                var frame = Probe.find(button, "buttonFrame"), wash = Probe.find(button, "buttonWash")
                root.check(JSON.stringify(root.box(frame)) === JSON.stringify(root.insetBox(root.restFrame, insetX, insetY)),
                    "press insets only the frame on whole pixels")
                root.check(JSON.stringify(root.box(wash)) === JSON.stringify(root.insetBox(root.restWash, insetX, insetY)),
                    "press insets only the wash on whole pixels")
                root.check(Math.abs(wash.color.a - Buttons.WASH_PRESS) < 0.002, "the inset wash draws the actual press ink")
                root.check(held.x <= root.rest.targetX && root.rest.targetX < held.x + held.w
                    && held.y <= root.rest.targetY && root.rest.targetY < held.y + held.h, "the original hit point still identifies the held control")
                button.x += 1
                var moved = root.control(root.read(), "Press")
                root.check(moved.x === held.x + 1 && moved.targetX === held.targetX + 1, "a real move invalidates the old coordinate signature")
                button.x -= 1
                driver.mouseRelease(stage, root.rest.targetX, root.rest.targetY, Qt.LeftButton, Qt.NoModifier, 0)
                var point = media.playItem.mapToItem(stage, media.playItem.width / 2, media.playItem.height / 2)
                driver.mousePress(stage, point.x, point.y, Qt.LeftButton, Qt.NoModifier, 0)
                root.stage = 2
                return
            }
            if (root.stage === 2) {
                var playing = root.control(root.read(), "Play")
                root.check(playing.pressed, "media play reads a real held press")
                driver.mouseRelease(stage, playing.targetX, playing.targetY, Qt.LeftButton, Qt.NoModifier, 0)
                driver.mouseMove(window.contentItem, 0, 0, 0, Qt.NoButton, Qt.NoModifier)
                root.stage = 3
                return
            }
            if (root.stage === 3) {
                if (!pdf.pdfDrawn || pdf.pdfPages !== 2) return
                var actual = root.pdfBar(pdf)
                if (!actual || actual.shown || actual.knobItem.parent.opacity > 0) return
                var bar = root.control(root.read(), "Vertical scroll bar")
                root.check(actual.visible && actual.overflow, "the derived native PDF has a real overflowing scrollbar")
                root.check(!!bar && bar.surface === "PreviewColumn" && !bar.exposed,
                    "SelectionPreview's bar starts asleep and is not an exposed capture target")
                if (!bar) { root.report(); return }
                console.log("COH_SLEEP headless cols-pdf bar=false type=" + String(pdf).split("(")[0])
                root.wakeAt = Date.now()
                var frame = pdf.frameItem, centre = frame.mapToItem(pdf, frame.width / 2, frame.height / 2)
                if (Quickshell.env("FLEA_COH_SKIP_WHEEL") !== "true")
                    driver.mouseWheel(pdf, centre.x, centre.y, Qt.NoButton, Qt.NoModifier, 0, -120, 1)
                root.stage = 6
                return
            }
            if (root.stage === 6) {
                var awakened = root.control(root.read(), "Vertical scroll bar")
                if (!awakened || !awakened.exposed) {
                    if (Date.now() - root.wakeAt < root.wakeWaitMs) return
                    root.check(false, "an asleep PDF bar cannot expose without a wheel")
                    root.report()
                    return
                }
                root.check(pdf.pdfScrollY > 0, "one actual wheel step scrolls the PDF before target discovery")
                console.log("COH_WAKE headless cols-pdf bar=true after=" + (Date.now() - root.wakeAt))
                driver.mouseMove(window.contentItem, awakened.targetX, awakened.targetY, 0, Qt.NoButton, Qt.NoModifier)
                root.hoverAt = Date.now()
                root.stage = 7
                return
            }
            if (root.stage === 7) {
                var bar = root.control(root.read(), "Vertical scroll bar")
                if (Date.now() - root.hoverAt <= Scroll.HOLD_MS + Scroll.FADE_MS) return
                root.check(!!bar && bar.exposed && bar.hovered && bar.hoverLive && bar.pressLive,
                    "a pointer in the native lane keeps its real bar exposed past the idle hold and fade")
                if (!bar) { root.report(); return }
                root.rest = bar
                driver.mousePress(window.contentItem, bar.targetX, bar.targetY, Qt.LeftButton, Qt.NoModifier, 0)
                root.stage = 4
                return
            }
            if (root.stage === 4) {
                var heldBar = root.control(root.read(), "Vertical scroll bar")
                root.check(!!heldBar && heldBar.pressed, "the scrollbar reads its held MouseArea after the grab reparents")
                driver.mouseRelease(window.contentItem, root.rest.targetX, root.rest.targetY, Qt.LeftButton, Qt.NoModifier, 0)
                root.stage = 5
                return
            }
            var sheet = root.control(root.read(), "Keys body")
            if (!sheet || !sheet.exposed) return
            root.check(sheet.kind === "CardScroll" && sheet.surface === "KeymapSheet" && !sheet.hoverLive && !sheet.pressLive,
                "the buttonless Keys sheet exposes its real scrolling body without inventing pointer state")
            root.report()
        }
    }
}
