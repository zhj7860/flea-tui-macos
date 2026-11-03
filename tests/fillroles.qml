//@ pragma ShellId flea-fillroles-test

import QtQuick
import Quickshell
import "flea" as Flea
import "qml-probe.js" as QmlProbe

// tests/fillroles.sh's harness: the real transfer card, seek strip and two dialogs with a sentinel per accent or error role, so each fill and ink is read off the component.
ShellRoot {
    id: root

    // Each sentinel differs from the raw role it stands next to, so a component reading the raw role cannot pass by coincidence.
    readonly property color frameSentinel: "#ff00aa"
    readonly property color errorSentinel: "#00aaff"
    readonly property color onSurfaceSentinel: "#aaff00"
    // Frames a step waits after it runs, so layout and the dialogs' fades have settled before a read.
    readonly property int settleTicks: 6
    // The most frames a step waits for the card's 250 ms fill ease to land, which a loaded box stretches.
    readonly property int easeTicks: 200
    readonly property int tickMs: 16
    readonly property int outerTimeoutS: Number(Quickshell.env("FILLROLES_TIMEOUT_S")) || 60
    readonly property int capShare: 2
    readonly property int msPerSecond: 1000
    readonly property double startedAt: Date.now()
    readonly property int capMs: root.outerTimeoutS * root.msPerSecond / root.capShare
    readonly property int milli: 1000
    readonly property real firstShare: 0.25
    readonly property real secondShare: 0.75
    readonly property real halfway: 0.5
    readonly property real pixelSlack: 0.5
    readonly property string invalidName: "bad/name"
    readonly property string invalidReason: "contains /"
    readonly property string terminalMessage: "Bulk rename refused: the number of names changed."
    readonly property string unlockMessage: "That passphrase did not unlock the drive."

    property int checks: 0
    property var failures: []
    property int at: 0
    property int waited: 0
    // The strip's played part and handle, then the card's fill width read in the frame its fraction changed.
    property real beforeWidth: 0
    property real sameFrameWidth: 0

    function log(line) { QmlProbe.log("FILLROLES", line) }
    function check(name, actual, expected) { QmlProbe.checkLoud(root, name, actual, expected) }
    function finish() {
        QmlProbe.logDone(root)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
    function rgba(c) { return [c.r, c.g, c.b, c.a].map(function (v) { return Math.round(v * root.milli) / root.milli }).join(",") }
    // Sample input: "QQuickText(0x55d0c0a0)" gives QQuickText, "DialogButton_QML_42(0x55d0c0a0, \"ok\")" gives DialogButton.
    // The type name without the instance address or the QML suffix, so Text and TextInput are told apart.
    function typeName(o) { return String(o).split("(")[0].replace(/_QML_\d+$/, "") }
    function findAll(top, accept) {
        var out = []
        var stack = [top]
        while (stack.length > 0) {
            var o = stack.pop()
            if (accept(o)) out.push(o)
            var kids = (o && o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
        }
        return out
    }
    function rectangles(top, accept) { return root.findAll(top, function (o) { return root.typeName(o) === "QQuickRectangle" && accept(o) }) }
    function textWith(top, type, text) { return root.findAll(top, function (o) { return root.typeName(o) === type && o.text === text })[0] }
    function inkOf(item) { return item ? root.rgba(item.color) : "missing" }
    function landed(share) {
        var fill = root.bars().fill
        return Math.abs(fill.width - fill.parent.width * share) < root.pixelSlack
    }
    function transfer(share) {
        return { id: 1, moving: false, n: 2, index: 1, name: "a.txt", running: true, done: 0, bytes: 1024, total: 4096, moved: 0, writing: false, drive: "", share: share }
    }
    // The card's two bars are the rectangles one bar tall; the track is the one drawn at the track opacity.
    function bars() {
        var both = root.rectangles(card, function (o) { return o.height === card.barHeight })
        return { track: both.filter(function (o) { return o.opacity === card.trackOpacity })[0], fill: both.filter(function (o) { return o.opacity !== card.trackOpacity })[0] }
    }
    // The seek track draws, in order, the full line, the played part and the square handle.
    function seekParts() { return root.rectangles(strip.seekItem, function () { return true }).reverse() }

    readonly property var plan: [
        { wait: 0, run: function () {
            Flea.Theme.color.accentFrame = root.frameSentinel
            Flea.Theme.color.error = root.errorSentinel
            Flea.Theme.color.errorOnSurface = root.onSurfaceSentinel
            card.shown = root.transfer(root.firstShare)
            bulk.open(["/fillroles/a.txt", "/fillroles/b.txt"], parking)
            bulk.newNames = [root.invalidName, "b.txt"]
            unlock.openFor("/dev/fillroles", "Backup", 500000000000, "crypto_LUKS", "2")
            unlock.showRefusal(root.unlockMessage)
        } },
        { wait: root.settleTicks, until: function () { return root.landed(root.firstShare) }, run: function () {
            var c = Flea.Theme.color
            root.check("the sentinels differ from the raw accent and from each other's role",
                       [root.rgba(c.accentFrame) !== root.rgba(c.accent), root.rgba(c.errorOnSurface) !== root.rgba(c.error)], [true, true])
            root.check("the theme keeps the sentinels the run set", [root.rgba(c.accentFrame), root.rgba(c.error), root.rgba(c.errorOnSurface)],
                       [root.rgba(root.frameSentinel), root.rgba(root.errorSentinel), root.rgba(root.onSurfaceSentinel)])
            root.check("transfer: the card draws a track and a fill", [!!root.bars().track, !!root.bars().fill], [true, true])
            root.check("transfer: the fill takes accentFrame", root.inkOf(root.bars().fill), root.rgba(root.frameSentinel))
            var parts = root.seekParts()
            root.check("strip: the seek track draws a line, a played part and a handle", parts.length, 3)
            root.check("strip: the played part takes accentFrame", root.inkOf(parts[1]), root.rgba(root.frameSentinel))
            root.check("strip: the handle takes accentFrame", root.inkOf(parts[2]), root.rgba(root.frameSentinel))
            root.check("strip: the played part is half the line and the handle is the handle",
                       parts.length === 3 ? [Math.abs(parts[1].width - parts[0].width * root.halfway) < root.pixelSlack, parts[2].width === strip.seekItem.handle] : [], [true, true])
            root.check("unlock: the refusal note takes errorOnSurface", root.inkOf(root.textWith(unlock.cardItem, "QQuickText", root.unlockMessage)), root.rgba(root.onSurfaceSentinel))
            root.check("bulk rename: an invalid name line takes errorOnSurface", root.inkOf(root.textWith(bulk.cardItem, "QQuickTextInput", root.invalidName)), root.rgba(root.onSurfaceSentinel))
            root.check("bulk rename: its reason takes errorOnSurface", root.inkOf(root.textWith(bulk.cardItem, "QQuickText", root.invalidReason)), root.rgba(root.onSurfaceSentinel))
            bulk.terminalError = root.terminalMessage
        } },
        { wait: root.settleTicks, until: function () { return root.landed(root.firstShare) }, run: function () {
            root.check("bulk rename: the footer's terminal error takes errorOnSurface", root.inkOf(root.textWith(bulk.cardItem, "QQuickText", root.terminalMessage)), root.rgba(root.onSurfaceSentinel))
            Flea.Theme.reducedMotion = true
            root.beforeWidth = root.bars().fill.width
            card.shown = root.transfer(root.secondShare)
            root.sameFrameWidth = root.bars().fill.width
            root.check("transfer: under reduced motion a new fraction lands its full width in the same frame",
                       [root.beforeWidth !== root.sameFrameWidth, Math.abs(root.sameFrameWidth - root.bars().fill.parent.width * root.secondShare) < root.pixelSlack], [true, true])
        } },
        { wait: root.settleTicks, until: function () { return root.landed(root.secondShare) }, run: function () {
            Flea.Theme.reducedMotion = false
            root.beforeWidth = root.bars().fill.width
            card.shown = root.transfer(root.firstShare)
            root.sameFrameWidth = root.bars().fill.width
            root.check("transfer: with motion on a new fraction is not applied in the frame it arrives, the ease runs",
                       Math.abs(root.sameFrameWidth - root.bars().fill.parent.width * root.firstShare) > root.pixelSlack, true)
        } },
        { wait: 0, until: function () { return root.landed(root.firstShare) }, run: function () {
            root.check("transfer: with motion on the ease lands on the new fraction", root.landed(root.firstShare), true)
        } }
    ]

    function advance() {
        if (Date.now() - root.startedAt > root.capMs) {
            root.failures.push("the harness did not finish")
            root.log("FAIL the harness did not finish at step " + root.at)
            root.finish()
            return
        }
        if (root.at === root.plan.length) { root.at += 1; root.finish(); return }
        var step = root.plan[root.at]
        // A step settles for its frames, then waits on its condition for at most easeTicks more, so a stuck ease fails its check instead of hanging.
        var ready = root.waited >= step.wait && (!step.until || step.until() || root.waited >= step.wait + root.easeTicks)
        if (!ready) { root.waited += 1; return }
        root.waited = 0
        root.at += 1
        step.run()
    }

    Timer {
        interval: root.tickMs
        repeat: true
        running: root.at <= root.plan.length
        onTriggered: root.advance()
    }

    FloatingWindow {
        implicitWidth: 1000
        implicitHeight: 900
        color: Flea.Theme.color.background

        Item {
            anchors.fill: parent
            Flea.BulkRenameDialog { id: bulk }
            Flea.UnlockDialog { id: unlock }
        }

        Column {
            x: 400
            width: 600
            Flea.TransferCard { id: card }
            Flea.MediaStrip { id: strip; width: parent.width; duration: 60000; position: 30000 }
        }

        Item { id: parking; width: 10; height: 10; focus: true }
    }
}
