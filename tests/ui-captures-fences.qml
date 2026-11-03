import QtQuick
import "../ui/js/Markdown.js" as Markdown

// Prints the tagged code fences ui/js/Markdown.js builds for each file named after --, one "FENCES <path> <fences>" line each, read as capmdfence14_tagged reads the pane's previewBlockKinds row.
Item {
    id: root
    // The theme colours paint only chips and links, so any pair builds the same blocks.
    readonly property string chrome: "#181825"
    readonly property string ink: "#c0caf5"
    // Sample input: a list whose item holds a fence with info "sh title=x" answers fence:sh, each tag cut at its first space, comma or bracket.
    function tagged(blocks, out) {
        for (var i = 0; i < blocks.length; i++) {
            var block = blocks[i]
            if (Array.isArray(block)) {
                root.tagged(block, out)
            } else if (block) {
                var tag = block.type === "fence" ? /^[^\],\[\s]+/.exec(block.info || "") : null
                if (tag !== null)
                    out.push("fence:" + tag[0])
                if (block.parts !== undefined)
                    root.tagged(block.parts, out)
            }
        }
        return out
    }
    Component.onCompleted: {
        var argv = Qt.application.arguments
        for (var a = argv.indexOf("--") + 1; a > 0 && a < argv.length; a++) {
            var request = new XMLHttpRequest()
            request.open("GET", "file://" + argv[a], false)
            request.send()
            var dir = argv[a].substring(0, argv[a].lastIndexOf("/"))
            console.log("FENCES " + argv[a] + " " + root.tagged(Markdown.blocks(String(request.responseText), dir, root.chrome, root.ink), []).join(","))
        }
        Qt.exit(0)
    }
}
