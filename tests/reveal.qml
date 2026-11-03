//@ pragma ShellId flea-reveal-test
import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Motion.js" as Motion
import "qml-probe.js" as QmlProbe

// tests/reveal.sh's harness: the real dialog, share browser and context menu fade in and out on the one shared curve, snap under reduced motion, and never move their card while they fade out.
ShellRoot {
    id: shell

    property int checks: 0
    property var failures: []
    property bool done: false
    property int step: 0
    property double stepStart: 0
    property double watchStart: 0
    property bool acted: false
    property var samples: []
    property var script: []
    property var carry: ({})
    // A step's samples run this long past its action, enough for a fade of either length to finish and a frame or two over.
    readonly property int watchMs: 360
    // OutCubic is at 7/8 of its way by half its time; a sample near half a duration must be past this share, or inside its complement for a fade-out.
    readonly property real halfwayShare: 0.75
    // A fade reads as settled at this distance from its end opacity.
    readonly property real settledGap: 0.002
    // Timing windows on the driver clock, as shares of the shared duration; a fade reads as settled near seven eighths of its time, and offscreen frames are not vsync.
    readonly property real earliestShare: 0.8
    readonly property real latestShare: 1.1
    // One pixel of rounding between two reads of the same card rectangle.
    readonly property int roundingSlack: 1
    // Reveal's own times, read where it reads them.
    readonly property int openMs: Motion.durMs.open
    readonly property int closeMs: Motion.durMs.close
    // A reopen lands this far into a close fade, as a share of the close time.
    readonly property real midCloseShare: 0.4
    readonly property int midCloseMs: Math.round(shell.closeMs * shell.midCloseShare)
    // A close is waited out for its own time and a frame or two over.
    readonly property int frameSlackMs: 20
    // A protocol pick is read for a short run of frames, enough for any relayout it causes.
    readonly property int pickMs: 100
    readonly property var protocols: ["SFTP", "FTPS", "WebDAV", "NFS", "SMB"]
    readonly property int afterCloseMs: shell.closeMs + shell.frameSlackMs
    // A reopen mid close may start a frame behind where the close stood.
    readonly property real reopenOpacitySlack: 0.15
    // Two reads of one opacity differ by float noise only.
    readonly property real opacityNoise: 1e-6
    // The rise is cut by a close at half its time, and a reopen follows a short way into the close fade.
    readonly property int riseCutMs: Math.round(shell.openMs / 2)
    readonly property int reopenGapMs: Math.round(shell.closeMs * shell.midCloseShare / 2)

    function log(line) { QmlProbe.log("REVEAL", line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(name, actual, expected) { QmlProbe.checkQuiet(shell, name, actual, expected) }

    function report() {
        QmlProbe.reportCard(shell, ticker)
        shell.quit()
    }

    FloatingWindow {
        implicitWidth: 900
        implicitHeight: 600
        color: "#303030"
        Item {
            id: host
            anchors.fill: parent
            Item {
                id: bare
                x: 20; y: 20; width: 100; height: 60
                opacity: 0
                Item { id: bareCard; width: 100; height: 60 }
                Flea.Reveal { id: bareReveal; target: bare; shown: false; lift: bareCard }
            }
            Flea.TrashConfirm { id: trash }
            Flea.ShareBrowser { id: shares }
            Flea.ContextMenu { id: menu }
            Flea.NetworkDialog { id: net }
        }
    }

    function rectOf(item) {
        var p = item.mapToItem(null, 0, 0)
        return [Math.round(p.x), Math.round(p.y), Math.round(item.width), Math.round(item.height)]
    }

    // One surface: how it opens and closes, the item whose opacity fades, the item whose visibility and input the fade holds, and the card that must keep still.
    function surfaces() {
        return [
            { name: "bare reveal", open: function () { bareReveal.shown = true }, close: function () { bareReveal.shown = false },
              fader: bare, host: null, gate: null, card: bareCard },
            { name: "dialog", open: function () { trash.open({ token: 1, all: true, count: 3, bytes: 4096 }) }, close: function () { trash.close() },
              fader: trash, host: trash, gate: trash, card: trash.cardItem },
            { name: "share browser", open: function () { shares.open("smb://host/", "host", ["alpha", "beta"]) }, close: function () { shares.close() },
              fader: shares.children[0], host: shares, gate: shares.children[0], card: shares.children[0] },
            { name: "context menu", open: function () { menu.openAt(Qt.point(100, 40)) }, close: function () { menu.close() },
              fader: menu.frameItem, host: menu, gate: menu, card: menu.frameItem }
        ]
    }

    function snap(s, t) {
        return { t: t, op: s.fader.opacity, vis: s.host === null ? true : s.host.visible, en: s.gate === null ? false : s.gate.enabled, rect: shell.rectOf(s.card) }
    }

    // The first sample at or past a time, or the last one.
    function nearest(samples, ms) {
        for (var i = 0; i < samples.length; i++) if (samples[i].t >= ms) return samples[i]
        return samples[samples.length - 1]
    }
    // The first sample whose opacity is past a bound in a direction, as its time, else -1.
    function settledAt(samples, target) {
        for (var i = 0; i < samples.length; i++) if (Math.abs(samples[i].op - target) <= shell.settledGap) return samples[i].t
        return -1
    }
    function monotonic(samples, up) {
        for (var i = 1; i < samples.length; i++) {
            if (up && samples[i].op < samples[i - 1].op - shell.opacityNoise) return false
            if (!up && samples[i].op > samples[i - 1].op + shell.opacityNoise) return false
        }
        return true
    }
    function sameRect(a, b) {
        for (var i = 0; i < 4; i++) if (Math.abs(a[i] - b[i]) > shell.roundingSlack) return false
        return true
    }
    function stillCard(samples, resting) {
        return samples.every(function (p) { return shell.sameRect(p.rect, resting) })
    }

    function buildScript() {
        var out = []
        shell.surfaces().forEach(function (s, index) {
            var tag = s.name
            function surface() { return shell.surfaces()[index] }
            out.push({ name: tag + ": open", act: function () { Flea.Theme.reducedMotion = false; surface().open() }, record: function (samples) {
                var want = Motion.durMs.open
                var settled = shell.settledAt(samples, 1)
                shell.check(tag + ": opening reaches full opacity", settled >= 0, true)
                shell.check(tag + ": opening takes the shared open time on the driver clock", settled >= want * shell.earliestShare && settled <= want * shell.latestShare, true)
                shell.check(tag + ": opening only ever gains opacity", shell.monotonic(samples, true), true)
                shell.check(tag + ": opening is OutCubic, mostly there by half its time", shell.nearest(samples, want / 2).op >= shell.halfwayShare, true)
                shell.check(tag + ": the surface is drawn the whole open", samples.every(function (p) { return p.vis || p.op === 0 }), true)
                var last = samples[samples.length - 1]
                shell.carry[tag] = last.rect
                if (s.host !== null) shell.check(tag + ": the open surface takes input", last.en, true)
                shell.check(tag + ": the card rests where it is laid", shell.sameRect(last.rect, shell.rectOf(surface().card)), true)
            } })
            out.push({ name: tag + ": close", act: function () { surface().close() }, record: function (samples) {
                var want = Motion.durMs.close
                var settled = shell.settledAt(samples, 0)
                shell.check(tag + ": closing reaches no opacity", settled >= 0, true)
                shell.check(tag + ": closing takes the shared close time on the driver clock", settled >= want * shell.earliestShare && settled <= want * shell.latestShare, true)
                shell.check(tag + ": closing only ever loses opacity", shell.monotonic(samples, false), true)
                shell.check(tag + ": closing is OutCubic, mostly gone by half its time", shell.nearest(samples, want / 2).op <= 1 - shell.halfwayShare, true)
                shell.check(tag + ": the card never moves while it fades out", shell.stillCard(samples, shell.carry[tag]), true)
                var last = samples[samples.length - 1]
                if (s.host !== null) {
                    shell.check(tag + ": a closed surface is hidden", last.vis, false)
                    shell.check(tag + ": the fading surface takes no input", samples.every(function (p) { return !p.en }), true)
                    shell.check(tag + ": it stays drawn until its fade ends", samples.every(function (p) { return p.vis || p.op < shell.settledGap }), true)
                }
            } })
            out.push({ name: tag + ": reopen", watch: 0, act: function () { surface().open() }, record: function () {} })
            out.push({ name: tag + ": settle", act: function () {}, record: function () {} })
            out.push({ name: tag + ": reopen mid close", watch: shell.midCloseMs, act: function () { surface().close() }, record: function (samples) {
                shell.carry.mid = samples[samples.length - 1].op
                surface().open()
            } })
            out.push({ name: tag + ": reopened", act: function () {}, record: function (samples) {
                shell.check(tag + ": a reopen fades up from where the close stood", samples[0].op >= shell.carry.mid - shell.reopenOpacitySlack, true)
                shell.check(tag + ": a reopen in a close does not replay the rise", shell.stillCard(samples, shell.carry[tag]), true)
                shell.check(tag + ": the reopened surface is full", samples[samples.length - 1].op, 1)
            } })
            out.push({ name: tag + ": reduced", watch: 0, act: function () {
                Flea.Theme.reducedMotion = true
                surface().close()
                var closed = shell.snap(surface(), 0)
                shell.check(tag + ": under reduced motion a close is instant", closed.op, 0)
                if (s.host !== null) shell.check(tag + ": and the surface is gone at once", closed.vis, false)
                surface().open()
                var opened = shell.snap(surface(), 0)
                shell.check(tag + ": under reduced motion an open is instant", opened.op, 1)
                shell.check(tag + ": and the card sits at rest at once", shell.sameRect(opened.rect, shell.carry[tag]), true)
                surface().close()
                Flea.Theme.reducedMotion = false
            }, record: function () {} })
            out.push({ name: tag + ": closed", watch: shell.afterCloseMs, act: function () {}, record: function (samples) {
                shell.check(tag + ": the reduced-motion close left it closed", samples[samples.length - 1].op, 0)
            } })
        })
        shell.riseSteps(out)
        shell.flyoutSteps(out)
        shell.networkSteps(out)
        shell.script = out
    }

    // A close cut inside the rise leaves no offset: a reopen in the fade rises on to rest, and a close waited out rests the card.
    function riseSteps(out) {
        function lone(t) { return { t: t, op: bare.opacity, rise: bareReveal.rise.y } }
        out.push({ name: "rise: open", sample: lone, act: function () { Flea.Theme.reducedMotion = false; bareReveal.shown = true }, watch: shell.riseCutMs, record: function (samples) {
            var cut = samples[samples.length - 1].rise
            shell.check("rise: a close at half the rise lands mid rise", cut > 0 && cut < Motion.translateUpPx, true)
            shell.carry.riseCut = cut
            bareReveal.shown = false
        } })
        out.push({ name: "rise: reopen", sample: lone, act: function () {}, watch: shell.reopenGapMs, record: function (samples) {
            var last = samples[samples.length - 1]
            shell.check("rise: the reopen lands while the card still fades out", last.op > 0 && last.op < 1, true)
            bareReveal.shown = true
        } })
        out.push({ name: "rise: reopened", sample: lone, act: function () {}, record: function (samples) {
            var last = samples[samples.length - 1]
            shell.check("rise: a reopen in the fade of a cut rise rises on from the cut, never back from the full offset", samples.every(function (p) { return p.rise <= shell.carry.riseCut }), true)
            shell.check("rise: a reopen in the fade of a cut rise ends at rest and full", [last.rise, last.op], [0, 1])
        } })
        out.push({ name: "rise: close", sample: lone, act: function () { bareReveal.shown = false }, record: function (samples) {
            var last = samples[samples.length - 1]
            shell.check("rise: a close after a full rise ends at rest and gone", [last.rise, last.op], [0, 0])
        } })
        out.push({ name: "rise: open again", sample: lone, act: function () { bareReveal.shown = true }, watch: shell.riseCutMs, record: function () { bareReveal.shown = false } })
        out.push({ name: "rise: waited out", sample: lone, act: function () {}, record: function (samples) {
            var last = samples[samples.length - 1]
            shell.check("rise: a close cut inside the rise and waited out ends at rest and gone", [last.rise, last.op], [0, 0])
        } })
    }

    // The Network card rises as it opens; once risen, picking a protocol leaves the chip row where it stood.
    function networkSteps(out) {
        function chipRow(t) { var chip = net.formChip("SMB"); return { t: t, y: Math.round(chip.mapToItem(null, chip.width / 2, chip.height / 2).y), op: net.opacity } }
        out.push({ name: "network: open", sample: chipRow, act: function () { Flea.Theme.reducedMotion = false; net.open() }, record: function (samples) {
            shell.carry.chipRest = samples[samples.length - 1].y
            shell.check("network: the card is full once risen", samples[samples.length - 1].op, 1)
        } })
        shell.protocols.forEach(function (protocol) {
            out.push({ name: "network: " + protocol, sample: chipRow, watch: shell.pickMs, act: function () { net.formChip(protocol).activated() }, record: function (samples) {
                shell.check("network: picking " + protocol + " leaves the protocol chip row where it stood", samples.every(function (p) { return p.y === shell.carry.chipRest }), true)
            } })
        })
        out.push({ name: "network: closed", sample: chipRow, act: function () { net.close() }, record: function () {} })
    }

    // A flyout fades on its own frame and keeps its rows while it fades out (ui/FlyoutFade.qml).
    function flyoutSteps(out) {
        function flyoutOf(t) { return { t: t, op: menu.submenuFrameItem.opacity, vis: menu.submenuFrameItem.visible, held: menu.heldRows.length, now: menu.submenuEntries.length, offset: menu.heldOffset, action: menu.heldAction } }
        function rowIndex(action) {
            for (var i = 0; i < menu.entries.length; i++) if (menu.entries[i].action === action) return i
            return -1
        }
        out.push({ name: "flyout: open", sample: flyoutOf, act: function () {
            Flea.Theme.reducedMotion = false
            menu.rowMode = 0o100644
            menu.selectionCount = 1
            menu.rowIsFile = true
            menu.openWithLoaded = true
            menu.openWithApps = [{ id: "a", label: "App A", default: true }, { id: "b", label: "App B" }]
            menu.openAt(Qt.point(100, 40))
            var index = rowIndex("openWith")
            shell.carry.flyoutRow = index
            if (index >= 0) { menu.cursor = index; menu.openSubmenu(index) }
        }, record: function (samples) {
            var last = samples[samples.length - 1]
            shell.check("flyout: the row that opens Open with exists", shell.carry.flyoutRow >= 0, true)
            shell.check("flyout: it fades up to full opacity", shell.settledAt(samples, 1) >= 0 && last.op === 1, true)
            shell.check("flyout: it only ever gains opacity", shell.monotonic(samples, true), true)
            shell.check("flyout: it holds the rows it draws", last.held > 0 && last.held === last.now, true)
            shell.carry.flyoutRows = last.held
            shell.carry.flyoutPlace = [last.offset, last.action]
        } })
        out.push({ name: "flyout: close", sample: flyoutOf, act: function () { menu.openSubmenuRow = -1 }, record: function (samples) {
            var last = samples[samples.length - 1]
            shell.check("flyout: it fades out to no opacity", shell.settledAt(samples, 0) >= 0, true)
            shell.check("flyout: it only ever loses opacity", shell.monotonic(samples, false), true)
            shell.check("flyout: it draws the same rows through the fade, and the menu names none", samples.every(function (p) { return p.held === shell.carry.flyoutRows && p.now === 0 }), true)
            shell.check("flyout: it keeps its place and its action through the fade", samples.every(function (p) { return p.offset === shell.carry.flyoutPlace[0] && p.action === shell.carry.flyoutPlace[1] }), true)
            shell.check("flyout: it stays drawn until its fade ends", samples.every(function (p) { return p.vis || p.op < shell.settledGap }), true)
            shell.check("flyout: a closed flyout is hidden", last.vis, false)
        } })
        out.push({ name: "flyout: empty", sample: flyoutOf, act: function () { menu.loneFlyoutAction = "noFlyout" }, record: function (samples) {
            var last = samples[samples.length - 1]
            shell.check("flyout: a flyout opened with no entries draws no rows, not the last flyout's", [last.now, last.held], [0, 0])
            menu.close()
        } })
    }

    Timer {
        id: starter
        interval: 400
        running: true
        onTriggered: { shell.buildScript(); shell.stepStart = Date.now(); ticker.running = true }
    }

    // One frame at a time: a step acts, then samples every frame for its watch time, then records.
    FrameAnimation {
        id: ticker
        running: false
        onTriggered: {
            if (shell.done) return
            if (shell.step >= shell.script.length) { shell.report(); return }
            var current = shell.script[shell.step]
            var s = shell.surfaces()[Math.floor(shell.step / 8)]
            var watch = current.watch !== undefined ? current.watch : shell.watchMs
            var sampler = current.sample !== undefined ? current.sample : function (t) { return shell.snap(s, t) }
            if (!shell.acted) {
                shell.acted = true
                shell.samples = []
                shell.watchStart = Date.now()
                current.act()
            }
            var elapsed = Date.now() - shell.watchStart
            if (watch > 0) shell.samples.push(sampler(elapsed))
            if (elapsed >= watch) {
                if (watch === 0) shell.samples.push(sampler(0))
                current.record(shell.samples)
                shell.acted = false
                shell.step += 1
            }
        }
    }
}
