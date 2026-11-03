import QtQuick
import Quickshell
import Quickshell.Io

// One preview's MPRIS player (tools/flea-mpris): the helper starts when `active` first turns true, off the first frame.
QtObject {
    id: root

    // The PreviewMedia this speaks for, which carries out the helper's commands.
    required property var media
    property bool active: false
    property bool ready: false
    // The newest state line, written when the helper starts if it was not up yet.
    property string last: ""

    onActiveChanged: if (root.active) helper.running = true

    function send(state) {
        root.last = JSON.stringify(state)
        if (root.ready) helper.write(root.last + "\n")
    }

    // Destroying the preview destroys this Process, which kills the helper; a UI that died instead closes its stdin.
    property Process helper: Process {
        id: helper
        command: [Quickshell.env("FLEA_MPRIS") || "/usr/lib/flea/flea-mpris"]
        stdinEnabled: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function (line) { root.media.remote(line) }
        }
        onStarted: {
            root.ready = true
            if (root.last.length > 0) helper.write(root.last + "\n")
        }
        onExited: root.ready = false
    }
}
