//@ pragma AppId com.thisisgm.flea
//@ pragma ShellId flea

import QtQuick
import Quickshell
import Quickshell.Io
import "flea" as Flea

// Native captures drive the real document's refusal after its texture has been drawn.
ShellRoot {
    id: root
    property string refusal: ""
    readonly property string folder: Quickshell.env("HTML_ROOT")
    function clipActive() {
        for (var i = 0; i < document.children.length; i++) {
            var child = document.children[i]
            if (String(child.source).endsWith("HtmlClip.qml")) return child.active && !!child.item
        }
        return false
    }
    function reply(state) {
        responder.htmlResult({ slot: document.slot, token: document.token, state: state,
            file: root.folder + "/page.png", width: document.deviceWidth, total: 1 })
    }
    QtObject {
        id: responder
        property int serial: 0
        signal htmlResult(var message)
        function askHtml(slot, path, width, cancel, height) { return ++serial }
    }
    IpcHandler {
        target: "flea"
        function htmlState(column: bool): string {
            return JSON.stringify({ visible: window.visible, ready: document.firstScreen, view: document.shownView,
                state: document.status, file: document.imageFile, drawn: document.hasDrawn, clip: root.clipActive(),
                failed: document.failed, large: document.tooLarge, pending: document.pending,
                accelerated: document.GraphicsInfo.api !== GraphicsInfo.Software && document.GraphicsInfo.api !== GraphicsInfo.Unknown,
                frame: "40 40 " + card.width + " " + card.height,
                window: { width: window.width, height: window.height }, pageColor: "#2345bc" })
        }
        function htmlClipRefuse(state: string): bool {
            if (!document.contentReady || !document.hasDrawn || !root.clipActive() || root.refusal.length > 0) return false
            if (state !== "failed" && state !== "large") return false
            root.refusal = state
            if (state === "failed") { document.ask(); root.reply("failed") }
            else document.size = document.maxBytes + 1
            return true
        }
    }
    FloatingWindow {
        id: window
        title: "Flea"
        implicitWidth: 380
        implicitHeight: 280
        color: "#101315"
        Rectangle {
            id: card
            x: 40
            y: 40
            width: 300
            height: 200
            color: "#101315"
            radius: 12
            Flea.PreviewHtml {
                id: document
                anchors.fill: parent
                active: true
                compact: true
                cornerRadius: card.radius
                path: root.folder + "/page.html"
                backend: responder
            }
        }
    }
    Timer {
        interval: 50
        running: root.refusal.length === 0
        repeat: true
        onTriggered: if (document.pending) root.reply("ready")
    }
}
