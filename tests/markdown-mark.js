.import "flea/js/LangMarkPaths.js" as LangMarkPaths

// The mark a Quick Look bar draws, read off its Shape for the Markdown render suite.

// The path the bar's mark cell strokes, read off its drawn Shape and not off the name property that chose it.
function drawnPath(mark) {
    for (var i = 0; i < mark.children.length; i++) {
        var shape = mark.children[i];
        for (var j = 0; shape.data && j < shape.data.length; j++) {
            var elements = shape.data[j].pathElements;
            if (elements && elements.length > 0 && elements[0].path !== undefined)
                return String(elements[0].path);
        }
    }
    return "";
}

// The mark the bar draws is the board's Markdown mark, whatever markName was set to.
function markGeometryError(g, tokens) {
    if (!g.language || g.language.slug !== "markdown" || g.mark.visible)
        return "the bar draws no Markdown language mark in place of its kind glyph";
    if (g.language.markSize !== g.mark.markSize || String(g.language.color) !== String(g.mark.color))
        return "the Markdown language mark changes the bar glyph's size or ink";
    var shape = g.language.children[0], paths = [];
    for (var i = 0; shape && shape.data && i < shape.data.length; i++) {
        var elements = shape.data[i].pathElements;
        if (elements && elements.length > 0) paths.push(String(elements[0].path));
    }
    if (paths.length !== 2 || paths[0] !== "M4 7V2h10l6 6v14H17 M14 2v6h6" || paths[1] !== LangMarkPaths.pathFor("markdown"))
        return "the bar does not draw the approved file page and original Markdown logo";
    return "";
}

function markError(g, tokens) {
    // Hidden MarkdownPane fixtures still check geometry; a shown bar must draw its language mark.
    if (!g.language || !g.bar || typeof g.bar.visible !== "boolean" || g.language.visible !== g.bar.visible
        || g.mark.visible !== false)
        return "the bar draws no Markdown language mark in place of its kind glyph";
    return markGeometryError(g, tokens);
}

// Exercise the full bar reader with a real blank slot, then restore and recheck it.
function visibilityControlError(g, tokens, reader) {
    var positive = reader(g, tokens);
    if (positive) return positive;
    if (g.bar.visible !== true || g.language.visible !== true)
        return "the Markdown visibility control is not shown";
    g.language.visible = false;
    var original = markGeometryError(g, tokens), corrected = reader(g, tokens);
    g.language.visible = true;
    if (original || corrected !== "the bar draws no Markdown language mark in place of its kind glyph")
        return "the Markdown reader accepts a blank slot or the control changes its geometry";
    console.log("MARKDOWN_RENDER CONTROL invisible-language originalError=" + original.length
        + " correctedError=" + corrected.length + " restored=" + g.language.visible);
    return reader(g, tokens);
}
