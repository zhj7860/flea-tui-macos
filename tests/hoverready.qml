import QtQuick
import "js/sourcefixture.js" as Source

// Shared grid hover wiring: one HoverHandler on the view, one index every tile reads; the behaviour runs in griddroplive on the real view.
Item {
    id: root
    property int checked: 0
    property int failed: 0
    function check(label, actual, expected) {
        root.checked++
        if (actual !== expected) {
            root.failed++
            console.log("FAIL " + label + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
        }
    }
    // Code only: comments name the removed handlers and must not count as builds.
    function countOf(text, marker) {
        var code = text.split("\n").map(function (line) { return line.split("//")[0] }).join("\n")
        return code.split(marker).length - 1
    }

    Component.onCompleted: {
        var tile = Source.source("ui/GridTile.qml")
        var area = Source.source("ui/GridArea.qml")
        root.check("tile builds no handler", root.countOf(tile, "HoverHandler"), 0)
        root.check("tip reads the shared hover", tile.indexOf("root.hovered && root.captionElided()") >= 0, true)
        root.check("tip reads no local handler", tile.indexOf("hover.hovered") >= 0, false)
        root.check("tile carries the band guard", tile.indexOf("property bool hoverShown") >= 0, true)
        root.check("wash honors the guard", tile.indexOf("(root.hovered && root.hoverShown) ? Style.hoverFill") >= 0, true)
        root.check("lift honors the guard", tile.indexOf("(root.hovered && root.hoverShown) || root.selected") >= 0, true)
        root.check("view holds one shared handler", root.countOf(area, "HoverHandler"), 1)
        root.check("view names the shared probe", area.indexOf("id: hoverProbe") >= 0, true)
        root.check("view holds one hover index", area.indexOf("property int hoveredIndex") >= 0, true)
        root.check("probe resolves by position", area.indexOf("root.tileAt(x + root.contentX, y + root.contentY)") >= 0, true)
        root.check("probe clears on leave", area.indexOf("if (!hovered) root.hoveredIndex = -1") >= 0, true)
        root.check("tile reads the shared index", area.indexOf("hovered: cell.live && root.hoveredIndex === cell.index") >= 0, true)
        root.check("a point change feeds the index", area.indexOf("onPointChanged: if (hovered) root.hoverScene(point.scenePosition)") >= 0, true)
        root.check("a scroll under a resting pointer feeds the index", area.indexOf("if (hoverProbe.hovered) root.hoverScene(hoverProbe.point.scenePosition)") >= 0, true)
        root.check("the probe maps its scene point into the view", area.indexOf("var p = root.mapFromItem(null, scene.x, scene.y)") >= 0, true)
        root.check("tile guards on the band", area.indexOf("hoverShown: root.pane.selectionBand === null") >= 0, true)
        console.log("hoverready: " + root.checked + " checks, " + root.failed + " failed")
        Qt.quit()
    }
}
