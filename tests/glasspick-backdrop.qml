//@ pragma AppId com.thisisgm.flea.glasspick.backdrop
//@ pragma ShellId flea-glasspick-backdrop
import QtQuick
import Quickshell

// An owned native window under the capture pair, so the operator's wallpaper is never changed.
ShellRoot {
    FloatingWindow {
        title: "Flea material backdrop"
        implicitWidth: 1584
        implicitHeight: 740
        color: "#000000"
        Canvas {
            anchors.fill: parent
            readonly property bool bright: Quickshell.env("GLASSPICK_BACKDROP") === "bright"
            readonly property int tile: 8
            onPaint: {
                var ctx = getContext("2d")
                ctx.fillStyle = bright ? "#ffffff" : "#000000"
                ctx.fillRect(0, 0, width, height)
                ctx.fillStyle = bright ? "#cccccc" : "#222222"
                for (var y = 0; y < height; y += tile)
                    for (var x = 0; x < width; x += tile)
                        if ((x / tile + y / tile) % 2 === 0) ctx.fillRect(x, y, tile, tile)
            }
        }
    }
}
