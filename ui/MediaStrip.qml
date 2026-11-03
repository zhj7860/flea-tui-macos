import QtQuick
import qs.Commons
import "." as Flea
import "js/Format.js" as Format

// The transport the canvas draws under a media frame: a play/pause mark, a hairline seek with a square handle, a tabular clock and, under Quick Look, Media040's volume track. No filled chrome anywhere.
Item {
    id: root

    property bool playing: false
    property real position: 0
    property real duration: 0
    // MediaMute rules 2 and 3: the state reads by glyph, off the one session flag both strips share.
    readonly property bool muted: Flea.MediaSound.muted

    // A tile borders four sides, which is the PreviewColumn artboard. Flush against the bottom of
    // the Quick Look overlay that same border reads as a box, so there it is one top hairline.
    property bool framed: true

    signal toggled()
    signal seeked(real ms)
    // Any contact at all, so a host that hides this over a video can re-arm its own timer.
    signal touched()

    readonly property real fraction: root.duration > 0
        ? Math.max(0, Math.min(1, root.position / root.duration)) : 0
    // One second a click, the step ui/Preview.qml set on the qs.Ui slider this replaced.
    readonly property int wheelStepMs: 1000

    // A drag in flight draws from the pointer, not from the player, whose own advance would fight it.
    property bool scrubbing: false
    property real scrubFraction: 0
    readonly property real shown: root.scrubbing ? root.scrubFraction : root.fraction

    implicitHeight: Theme.chromeHeight

    Rectangle {
        anchors.fill: parent
        color: Theme.color.surface
        border.width: root.framed ? Theme.spacing.hairline : 0
        border.color: Theme.color.mutedFrame
    }

    // The unframed form's own divider, the same hairline ChromeBar draws under itself.
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        visible: !root.framed
        height: Theme.spacing.hairline
        color: Theme.color.foreground
        opacity: 0.12
    }

    // A test clicks each part itself rather than guess an offset; ui/shell.qml's previewSliderCentre reads seekItem, and volumeItem is null in the framed strip.
    readonly property var playItem: playSlot
    readonly property var seekItem: track
    readonly property var muteItem: muteSlot
    readonly property var volumeItem: volumeSlot.item

    Item {
        id: playSlot
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacing.gap
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(Theme.hitMin, Theme.font.bodySmall)
        height: Math.max(Theme.hitMin, Theme.font.bodySmall)

        Accessible.role: Accessible.Button
        Accessible.name: root.playing ? "Pause" : "Play"
        Accessible.onPressAction: { root.touched(); root.toggled() }

        Flea.Glyph {
            anchors.centerIn: parent
            width: Theme.font.bodySmall
            height: Theme.font.bodySmall
            name: root.playing ? "pause" : "play"
            color: Theme.color.foreground
        }

        TapHandler {
            acceptedButtons: Qt.LeftButton
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: {
                root.touched()
                root.toggled()
            }
        }
    }

    Flea.MediaTrack {
        id: track
        anchors.left: playSlot.right
        anchors.leftMargin: Theme.spacing.gap
        anchors.right: clock.left
        anchors.rightMargin: Theme.spacing.gap
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        fraction: root.shown

        // Seeks once, on release: seeking on every dragged frame would fight the player's own
        // advance. A press and release without moving is a click, so this covers both.
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: function (mouse) {
                root.scrubbing = true
                root.scrubFraction = track.fractionAt(mouse.x)
                root.touched()
            }
            onPositionChanged: function (mouse) {
                if (root.scrubbing)
                    root.scrubFraction = track.fractionAt(mouse.x)
                root.touched()
            }
            onReleased: {
                root.scrubbing = false
                root.touched()
                if (root.duration > 0)
                    root.seeked(root.duration * root.scrubFraction)
            }
            // A wheel is not a position change, so this is the one interaction that has to re-arm a
            // host's hide timer itself; the host clamps the absolute position this produces.
            onWheel: function (wheel) {
                root.touched()
                if (root.duration > 0)
                    root.seeked(root.position + (wheel.angleDelta.y > 0 ? root.wheelStepMs : -root.wheelStepMs))
            }
        }
    }

    // MediaMute rule 1: one mark after the clock in the chrome ink, drawn by the play mark's Glyph; the track gives up its width, and under Quick Look the mark sits one gap left of the volume track.
    Item {
        id: muteSlot
        anchors.right: root.framed ? parent.right : volumeSlot.left
        anchors.rightMargin: Theme.spacing.gap
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(Theme.hitMin, Theme.font.bodySmall)
        height: Math.max(Theme.hitMin, Theme.font.bodySmall)

        Accessible.role: Accessible.Button
        Accessible.name: root.muted ? "Unmute" : "Mute"
        Accessible.onPressAction: { root.touched(); Flea.MediaSound.toggle() }

        Flea.Glyph {
            anchors.centerIn: parent
            width: Theme.font.bodySmall
            height: Theme.font.bodySmall
            // Rule 2: both states are foreground, because a muted player is a mode and not a
            // control that cannot be pressed.
            name: root.muted ? "volume-x" : "volume"
            color: Theme.color.foreground
        }

        TapHandler {
            acceptedButtons: Qt.LeftButton
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: {
                root.touched()
                Flea.MediaSound.toggle()
            }
        }
    }

    // Media040's level, built with the strip so its first frame already draws the stored one.
    Loader {
        id: volumeSlot
        active: !root.framed
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacing.gap
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        // Media040 draws a 60 px track at bodySmall 13, in resolved pixels, so space() would scale it twice.
        width: Math.round(60 * Theme.font.bodySmall / 13)
        sourceComponent: Flea.MediaVolume {}
        onLoaded: item.touched.connect(root.touched)
    }

    Text {
        id: clock
        anchors.right: muteSlot.left
        anchors.rightMargin: Theme.spacing.gap
        anchors.verticalCenter: parent.verticalCenter
        text: Format.duration(root.position) + " / " + Format.duration(root.duration)
        color: Theme.color.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
        textFormat: Text.PlainText
    }
}
