import QtQuick
import Quickshell
import Quickshell.Io
import "flea" as Flea
import "flea/js/Format.js" as Format

ShellRoot {
    id: root
    property int phase: 0
    property int failures: 0
    property bool capturing: false
    property string fileSource: ""
    readonly property string folder: Quickshell.env("HTML_ROOT")
    readonly property string picturePath: root.folder + "/reload.png"
    readonly property string output: Quickshell.env("FLEA_CI_SUITE_LOGS") || root.folder
    function check(name, good) {
        if (!good) root.failures++
        console.warn("HTML_PREVIEW " + (good ? "PASS " : "FAIL ") + name)
    }
    function reply() {
        responder.htmlResult({slot: document.slot, token: document.token, state: "ready", file: root.picturePath,
            width: document.deviceWidth, total: 1, title: "Reload"})
    }
    function shot(name, after) {
        root.capturing = true
        document.grabToImage(function (image) {
            root.check(name + " capture saved", image.saveToFile(root.output + "/" + name + ".png"))
            root.capturing = false
            after()
        })
    }
    QtObject {
        id: responder
        property int serial: 0
        signal htmlResult(var message)
        function askHtml(slot, path, width, cancel, height) { return ++serial }
    }
    Process {
        id: writer
        command: ["python3", "-u", root.folder + "/reload-writer.py", root.folder]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: function (line) {
                if (line.indexOf("armed ") === 0) {
                    document.ask()
                    root.check("re-ask keeps the drawn image without a loading mark", !document.loading)
                    root.reply()
                    var picture = document.bodyItem.contentItem.children[0]
                    root.fileSource = picture.source.toString()
                    root.check("reply selects the real same-path URL with its new token", root.fileSource === Format.fileUri(root.picturePath) + "#t" + document.token)
                    // Sample input: armed 43127, the controlled image transport's bound port.
                    var port = parseInt(line.substring(6))
                    // Hold the native Image in Loading without blocking Qt's local-file decoder.
                    picture.source = "http://127.0.0.1:" + port + "/reload.png#t" + document.imageToken
                } else if (line === "reader") {
                    var picture = document.bodyItem.contentItem.children[0]
                    root.check("reply changes the image token before pending capture", document.imageToken === document.token && !document.pending)
                    root.check("new image is Loading after reply", picture.status === Image.Loading)
                    root.shot("html-reload-pending", function () {
                        root.check("new image stays Loading throughout pending capture", picture.status === Image.Loading)
                        writer.write("publish\n")
                    })
                } else console.warn(line)
            }
        }
        onExited: function (code) {
            root.check("replacement bytes published to the same path (exit " + code + ")", code === 0)
            if (code !== 0) {
                console.warn("HTML_PREVIEW DONE reload, " + root.failures + " failed")
                Qt.exit(1)
                return
            }
            var picture = document.bodyItem.contentItem.children[0]
            picture.source = Qt.binding(function () { return Format.fileUri(document.imageFile) + "#t" + document.imageToken })
            root.phase = 3
        }
    }
    FloatingWindow {
        implicitWidth: 300
        implicitHeight: 200
        visible: true
        color: "transparent"
        Flea.PreviewHtml {
            id: document
            anchors.fill: parent
            active: true
            path: root.folder + "/reload.html"
            backend: responder
        }
    }
    Timer {
        interval: 20
        running: true
        repeat: true
        onTriggered: {
            if (root.capturing) return
            if (root.phase === 0 && document.token > 0) { root.reply(); root.phase = 1 }
            else if (root.phase === 1 && document.contentReady) {
                root.phase = 2
                root.shot("html-reload-before", function () { writer.running = true })
            } else if (root.phase === 3 && document.contentReady) {
                root.phase = 4
                root.check("same-path reply is loaded", document.imageFile === root.picturePath)
                root.shot("html-reload-after", function () {
                    console.warn("HTML_PREVIEW DONE reload, " + root.failures + " failed")
                    Qt.exit(root.failures ? 1 : 0)
                })
            }
        }
    }
    Timer {
        interval: 15000
        running: true
        onTriggered: { root.check("same-path reload completes", false); Qt.exit(1) }
    }
}
