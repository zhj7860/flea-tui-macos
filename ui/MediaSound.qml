pragma Singleton
import QtQuick

// MediaMute rule 3: mute is one session flag both media surfaces read, never written to ui.json; the level beside it is stored as preview.volume.
QtObject {
    id: root

    property bool muted: false

    // The level under a press, 0 to 100, or -1 with none down, when the stored level shows.
    property int held: -1
    // Every Flea player plays at this, mute or not: 100 is the full-scale output a player had before the level existed.
    readonly property int volume: root.held >= 0 ? root.held : ViewState.mediaVolume
    // What the player takes: QtAudio.convertVolume(volume / 100, Logarithmic, Linear), which QML does not expose, as qtaudio.cpp computes it.
    readonly property real gain: root.volume > 99 ? 1 : -Math.log(1 - root.volume / 100) / Math.log(100)

    function toggle() { root.muted = !root.muted }

    // A press or drag sets the level live and writes nothing; the release stores it once.
    function setVolume(level) { root.held = level }

    function keepVolume() {
        ViewState.setMediaVolume(root.volume)
        root.held = -1
    }
}
