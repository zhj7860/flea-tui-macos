// Language-mark reference sheet; tests/langmarks3.sh builds it offscreen through the original symlink harness.
import Quickshell
import QtQuick
import "." as Flea
import "js/LangMarks.js" as LangMarks
import "js/Density.js" as Density

ShellRoot {
    id: root
    FloatingWindow {
        id: win
        implicitWidth: 640
        implicitHeight: 560
        visible: true
        title: "langmarks-spec"
        color: Flea.Theme.color.background

        // The same three inks ui/Row.qml binds its mark to: dim at rest, foreground lifted.
        readonly property color restInk: Flea.Theme.color.metadataFrame
        readonly property var files: ["main.rs", "app.py", "index.js", "README.md", "Dockerfile"]

        Column {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 10

            // A folder row keeps its kind glyph; every other row below replaces it with a logo.
            Row {
                spacing: 12
                Text { width: 140; text: "folder"; color: Flea.Theme.color.muted; font.pixelSize: Flea.Theme.font.caption; textFormat: Text.PlainText }
                Flea.Glyph { width: Flea.Theme.markSize; height: Flea.Theme.markSize; name: "folder"; color: win.restInk }
                Flea.Glyph { width: Flea.Theme.markSize; height: Flea.Theme.markSize; name: "folder"; color: Flea.Theme.color.foreground }
                Flea.Glyph { width: Flea.Theme.markSize; height: Flea.Theme.markSize; name: "folder"; color: Flea.Theme.color.foreground }
            }

            // An unmapped file keeps its kind glyph too.
            Row {
                spacing: 12
                Text { width: 140; text: "notes.txt"; color: Flea.Theme.color.muted; font.pixelSize: Flea.Theme.font.caption; textFormat: Text.PlainText }
                Flea.Glyph { width: Flea.Theme.markSize; height: Flea.Theme.markSize; name: "file-text"; color: win.restInk }
                Flea.Glyph { width: Flea.Theme.markSize; height: Flea.Theme.markSize; name: "file-text"; color: Flea.Theme.color.foreground }
                Flea.Glyph { width: Flea.Theme.markSize; height: Flea.Theme.markSize; name: "file-text"; color: Flea.Theme.color.foreground }
            }

            Repeater {
                model: win.files
                Row {
                    required property string modelData
                    spacing: 12
                    Text { width: 140; text: parent.modelData; color: Flea.Theme.color.muted; font.pixelSize: Flea.Theme.font.caption; textFormat: Text.PlainText }
                    Flea.LangMark {
                        width: Flea.Theme.markSize; height: Flea.Theme.markSize
                        maxSize: Flea.Theme.markSize; slug: LangMarks.slugForFile(parent.modelData)
                        color: win.restInk; strokeWidth: Flea.Theme.strokeWidth
                    }
                    Flea.LangMark {
                        width: Flea.Theme.markSize; height: Flea.Theme.markSize
                        maxSize: Flea.Theme.markSize; slug: LangMarks.slugForFile(parent.modelData)
                        color: Flea.Theme.color.foreground; strokeWidth: Flea.Theme.strokeWidth
                    }
                    Flea.LangMark {
                        width: Flea.Theme.markSize; height: Flea.Theme.markSize
                        maxSize: Flea.Theme.markSize; slug: LangMarks.slugForFile(parent.modelData)
                        color: Flea.Theme.color.foreground; strokeWidth: Flea.Theme.strokeWidth
                    }
                }
            }

            // One grid cell at the Medium tile's grid mark size, muted as the tile's glyph.
            Row {
                spacing: 12
                Text { width: 140; text: "grid main.rs"; color: Flea.Theme.color.muted; font.pixelSize: Flea.Theme.font.caption; textFormat: Text.PlainText }
                Flea.LangMark {
                    width: 64; height: 64
                    maxSize: Density.glyphCap(64); slug: "rust"
                    color: Flea.Theme.color.mutedFrame; strokeWidth: Flea.Theme.strokeWidth
                }
            }
        }
    }
    Timer {
        interval: 800
        running: Quickshell.env("LANGMARK_SPEC_TEST") === "1"
        onTriggered: {
            var count = 0, stack = [win.contentItem]
            while (stack.length > 0) {
                var item = stack.pop()
                if (String(item).indexOf("LangMark_") === 0) count += 1
                var children = item.children || []
                for (var i = 0; i < children.length; i++) stack.push(children[i])
            }
            console.log("LANGMARK_SPEC " + (count === 16 ? "PASS" : "FAIL") + " marks=" + count)
            Quickshell.execDetached(["kill", String(Quickshell.processId)])
        }
    }

}
