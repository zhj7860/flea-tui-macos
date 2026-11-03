.pragma library

// The existing delegate gates walk children/resources; the full census also sees paths and transforms.
function census(start, full) {
    var objects = [], types = {}
    function walk(object) {
        if (!object || objects.indexOf(object) >= 0) return
        objects.push(object)
        var type = String(object).split("(")[0].replace(/_QML(TYPE)?_\d+/g, "")
        types[type] = (types[type] || 0) + 1
        var groups = full ? [object.children, object.resources, object.data, object.transform, object.pathElements]
                          : [object.children, object.resources]
        for (var g = 0; g < groups.length; g++) {
            var group = groups[g] || []
            for (var i = 0; i < group.length; i++) walk(group[i])
        }
        if (full && object.contentItem) walk(object.contentItem)
        if (full && object.item) walk(object.item)
    }
    walk(start)
    return { total: objects.length - 1, types: types, objects: objects }
}

function languageObjects(sample) {
    return (sample.types.LangMark || 0) + (sample.types.LangMarkLoader || 0)
}

function plain(failures, item, label, baseline) {
    var sample = census(item, false)
    if (languageObjects(census(item, true)) !== 0 || item.langLoader !== null)
        failures.push(label + " builds language objects for a non-code row")
    if (baseline >= 0 && sample.total !== baseline)
        failures.push(label + " holds " + sample.total + " objects, want the unchanged " + baseline)
    console.log("LANGCOST " + label + " noncode=" + sample.total + " language=0 baseline=" + baseline)
    return sample.total
}

function effectiveAlpha(item) {
    var alpha = item.color.a
    for (var current = item; current; current = current.parent) alpha *= current.opacity
    return alpha
}

// Capture-only callers read the actual mark, glyph and label, without a product IPC property.
function state(row) {
    if (!row) return null
    var loader = row.langLoader, mark = loader ? loader.item : null
    var objects = census(row, true).objects, glyph = loader ? loader.glyph : null
    if (!glyph) {
        for (var i = 0; i < objects.length; i++) {
            if (/^Glyph_/.test(String(objects[i])) && objects[i].name !== "scissors") { glyph = objects[i]; break }
        }
    }
    var label = row.captionItem || row.nameItem(), slot = glyph ? glyph.mapToItem(row, 0, 0) : {x: 0, y: 0}
    return { name: row.row ? row.row.n : "", slug: row.langSlug, built: mark !== null,
        markVisible: mark ? mark.visible : false,
        glyphVisible: glyph ? glyph.visible : false, glyphName: glyph ? glyph.name : "", ink: mark ? String(mark.color) : glyph ? String(glyph.color) : "",
        glyphInk: glyph ? String(glyph.color) : "", alpha: mark ? effectiveAlpha(mark) : glyph ? effectiveAlpha(glyph) : 0,
        slot: [slot.x, slot.y, glyph ? glyph.width : 0, glyph ? glyph.height : 0],
        markSize: mark ? mark.markSize : glyph ? glyph.markSize : 0,
        labelX: label.mapToItem(row, 0, 0).x, page: mark ? mark.page : "",
        cursor: row.cursor, hovered: row.hovered, clip: row.clipMark, thumb: row.thumbDrawn,
        objects: census(row, false).total, fullObjects: census(row, true).total }
}

// Native captures read the StyledText that is on screen, rather than only the backend's colour reply.
function codeState(pane, column, styledText) {
    var surface = column ? pane.previewColumnItem : pane.preview
    if (!surface) return {}
    var objects = census(surface, true).objects
    var code = objects.filter(function(object) { return typeof object.rowAt === "function" && object.inks !== undefined })
        .filter(function(object) { return object.visible && object.firstScreen })[0]
    if (!code || !code.viewport) return {}
    var bodies = objects.filter(function(object) {
        if (!object.visible || object.textFormat !== styledText) return false
        var point = object.mapToItem(code.viewport, 0, 0)
        return point.y >= 0 && point.y < code.viewport.height
    })
    var colors = []
    for (var i = 0; i < bodies.length; i++) {
        // Sample input: '<font color="#abcdef">let</font>' contributes "#abcdef".
        var pattern = /<font color="([^"]+)">/g, match
        while ((match = pattern.exec(bodies[i].text)) !== null)
            if (colors.indexOf(match[1]) < 0) colors.push(match[1])
    }
    var bars = objects.filter(function(object) { return typeof object.closeState === "function" && object.langSlug !== undefined })
    var bar = bars.length > 0 ? bars[0] : null
    var mark = bar && bar.langLoader ? bar.langLoader.item : null
    return { path: code.path, answer: code.answer, firstScreen: code.firstScreen, total: code.total,
        bodies: bodies.map(function(body) { return body.text }), colors: colors, inks: code.inks,
        language: mark ? { slug: mark.slug, color: String(mark.color), slotInk: String(bar.langLoader.glyph.color),
            size: mark.markSize, slotSize: bar.langLoader.glyph.markSize, page: mark.page,
            glyphVisible: bar.langLoader.glyph.visible } : null }
}
