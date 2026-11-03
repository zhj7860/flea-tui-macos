pragma ComponentBehavior: Bound
import QtQuick
import "." as Flea
import "js/Kinds.js" as Kinds
import "js/Ops.js" as Ops

// The font page: Quick Look's bar, the sample at three sizes and the facts line, all drawn in the frame the backend's answer lands in.
Item {
    id: root

    property bool active: false
    property string path: ""
    property int size: 0
    property var backend: null

    signal closeRequested

    // "loading" until the answer, "font" once the page draws, and the unsupported sentence for a font the backend refused.
    readonly property string status: root.failed ? "This file cannot be previewed." : (root.drawn ? "font" : "loading")
    readonly property bool drawn: root.look !== null && root.look.path === root.path
    readonly property bool failed: root.failedPath === root.path
    property string failedPath: ""
    // The last good answer. A theme change asks again and the old images stay up until the new three replace them at once.
    property var look: null
    property int pending: 0
    // The path the pending ask carried, so an answer is read against its own request and not the path at answer time.
    property string pendingPath: ""
    property string askedKey: ""

    // The board's sizes before the text-size ratio, then the pixels the image is drawn with at this window's pixel ratio.
    readonly property real ratio: Screen.devicePixelRatio
    readonly property var physical: Kinds.SAMPLE_SIZES.map(function (px) { return Math.round(Math.round(px * Theme.sizeRatio) * root.ratio) })
    readonly property string fg: root.hex(Theme.color.foreground)
    // The card's own colour, so the images carry no box of another one.
    readonly property string bg: root.hex(Theme.color.surface)
    readonly property string askKey: root.active && root.path !== "" && root.backend !== null
        ? [root.path, root.fg, root.bg, root.physical.join(",")].join("\n") : ""
    readonly property string factsLine: root.drawn
        ? Kinds.fontLine(root.look.message.family || "", root.look.message.style || "", root.size, root.look.message.glyphs || 0, Ops.pluralWord) : ""

    function hex(c) {
        return "#" + [c.r, c.g, c.b].map(function (v) { return ("0" + Math.round(v * 255).toString(16)).slice(-2) }).join("")
    }
    // A theme load moves the surface before the foreground, so the ask goes out once from a zero timer, never with a mixed palette.
    onAskKeyChanged: askTimer.restart()

    Timer {
        id: askTimer
        interval: 0
        onTriggered: root.ask()
    }

    // The id comes from one count shared by every font pane, so an older answer is dropped even across a Loader rebuild.
    function ask() {
        if (root.askKey === "" || root.askKey === root.askedKey) return
        root.askedKey = root.askKey
        root.pending = Kinds.nextLookId()
        root.pendingPath = root.path
        root.backend.send({ c: "fontlook", id: root.pending, path: root.path, fg: root.fg, bg: root.bg, sizes: root.physical, text: Kinds.SAMPLE_TEXT })
    }

    Connections {
        target: root.backend
        function onFontLooked(message) {
            if (message.id !== root.pending) return
            if (message.err) {
                root.failedPath = root.pendingPath
                // The old page goes with a refusal, so it never draws beside the unsupported state.
                root.look = null
            } else {
                root.failedPath = ""
                root.look = { path: root.pendingPath, message: message }
            }
        }
    }

    // Until the answer Quick Look draws its loading state, so the bar, the images and the facts never appear apart.
    visible: root.drawn

    // No fill of its own: Quick Look's surface is already the chrome colour and rounds the corners this bar sits under.
    Item {
        id: bar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.chromeHeight

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: Theme.spacing.hairline
            color: Theme.color.foreground
            opacity: 0.12
        }

        Flea.Glyph {
            id: barMark
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacing.rowPaddingX
            y: Math.round((parent.height - Theme.spacing.hairline - height) / 2)
            width: Theme.chromeMarkSize
            height: Theme.chromeMarkSize
            name: "type"
            color: Theme.color.foreground
        }

        // corner: a filename is arbitrary text, so PlainText, the same rule every name on this surface follows.
        Text {
            id: barName
            anchors.left: barMark.right
            anchors.leftMargin: Theme.spacing.gap
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Math.max(0, barClose.x - x - 2 * Theme.spacing.gap))
            text: root.path.substring(root.path.lastIndexOf("/") + 1)
            color: Theme.color.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
        }

        Flea.ChromeButton {
            id: barClose
            gesturePolicy: TapHandler.ReleaseWithinBounds
            ruleRows: Theme.spacing.hairline
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacing.rowPaddingX
            anchors.verticalCenter: parent.verticalCenter
            glyph: "x"
            accessName: "Close"
            onActivated: root.closeRequested()
        }
    }

    // One left-aligned column, centred between the bar and the foot, 24 px above and below and 40 px at the sides.
    Column {
        id: page
        x: Math.round(40 * Theme.sizeRatio)
        width: parent.width - 2 * x
        y: bar.height + Math.max(Math.round(24 * Theme.sizeRatio), Math.round((parent.height - bar.height - height) / 2))
        spacing: Math.round(18 * Theme.sizeRatio)

        Repeater {
            model: root.drawn ? Kinds.SAMPLE_SIZES.length : 0
            // Drawn at its logical size from its own pixels, so a fractional pixel ratio leaves it unscaled.
            Image {
                id: sample
                required property int index
                source: "file://" + root.look.message.files[sample.index]
                width: sample.implicitWidth / root.ratio
                height: sample.implicitHeight / root.ratio
                fillMode: Image.Pad
                smooth: false
                cache: false
            }
        }

        Text {
            width: parent.width
            text: root.factsLine
            color: Theme.color.muted
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
            font.features: { "tnum": 1 }
            textFormat: Text.PlainText
            elide: Text.ElideRight
        }
    }
}
