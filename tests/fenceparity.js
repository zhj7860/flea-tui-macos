.pragma library

// A pixel within this many levels of the block background on every channel counts as background.
var backgroundTolerance = 2
// Antialiased glyph edges blend the ink at 55% to 105% of its distance from the background.
var inkCoverageMin = 0.55
var inkCoverageMax = 1.05
// A blended pixel within this many levels of the ink at its coverage counts as that ink.
var inkTolerance = 3

function descendants(item) {
    var out = [item]
    for (var i = 0; i < out.length; i++) {
        var kids = out[i].children || []
        for (var j = 0; j < kids.length; j++) out.push(kids[j])
    }
    return out
}

function rect(item, viewport) {
    var p = item.mapToItem(viewport, 0, 0)
    return { x: p.x, y: p.y, w: item.width, h: item.height }
}

// Sample input: '<font color="#cba6f7">fn</font> x' yields magenta for fn and the foreground for x.
function spans(text, coloured, foreground) {
    if (!coloured) return [{ ink: foreground, text: text }]
    var pieces = String(text).split(/(<font color="[^"]+">|<\/font>)/)
    var ink = foreground, out = []
    for (var i = 0; i < pieces.length; i++) {
        var open = /^<font color="([^"]+)">$/.exec(pieces[i])
        if (open) ink = open[1].toLowerCase()
        else if (pieces[i] === "</font>") ink = foreground
        else if (pieces[i] !== "") out.push({ ink: ink, text: pieces[i] })
    }
    return out
}

function record(doc, fence, host, ordinal, index, theme) {
    var text = descendants(fence).filter(function (n) { return n.text !== undefined })[0]
    var foreground = String(text.color).toLowerCase()
    return {
        host: host, ordinal: ordinal, blockIndex: index, blocks: doc.blockList.length,
        info: fence.info, lines: fence.fenceLines.length, coloured: fence.coloured,
        textFormat: text.textFormat, spans: spans(text.text, fence.coloured, foreground),
        family: text.font.family, expectedFamily: theme.font.family,
        background: String(fence.color).toLowerCase(),
        expectedBackground: String(host === "list" ? theme.color.background : theme.color.surface).toLowerCase(),
        rect: rect(fence, doc.viewport), fontPixels: text.font.pixelSize,
        padX: doc.fencePadX, padY: doc.fencePadY, viewportHeight: doc.viewport.height,
        documentScroll: null
    }
}

function rgb(hex) {
    // Sample input: '#cba6f7' yields the red, green and blue channels [203, 166, 247].
    return [parseInt(hex.slice(1, 3), 16), parseInt(hex.slice(3, 5), 16), parseInt(hex.slice(5, 7), 16)]
}

// Pixel evidence comes from the rendered viewport grab; each ink must own core or strongly covered antialiased pixels.
function pixelInks(data, width, height, record) {
    var inks = []
    record.spans.forEach(function (span) { if (/\S/.test(span.text.replace(/<br>/g, "")) && inks.indexOf(span.ink) < 0) inks.push(span.ink) })
    var background = rgb(record.background)
    var colors = inks.map(rgb), counts = inks.map(function () { return 0 })
    var fill = 0, r = record.rect
    var left = Math.max(0, Math.ceil(r.x)), right = Math.min(width, Math.floor(r.x + r.w))
    var top = Math.max(0, Math.ceil(r.y)), bottom = Math.min(height, Math.floor(r.y + r.h))
    for (var y = top; y < bottom; y++) {
        for (var x = left; x < right; x++) {
            var at = (y * width + x) * 4
            var pixel = [data[at], data[at + 1], data[at + 2]]
            if (pixel.every(function (v, k) { return Math.abs(v - background[k]) <= backgroundTolerance })) { fill++; continue }
            for (var i = 0; i < colors.length; i++) {
                var norm = 0, dot = 0
                for (var k = 0; k < 3; k++) {
                    var direction = colors[i][k] - background[k]
                    norm += direction * direction
                    dot += (pixel[k] - background[k]) * direction
                }
                var alpha = dot / norm
                if (alpha < inkCoverageMin || alpha > inkCoverageMax) continue
                var close = pixel.every(function (v, k) { return Math.abs(v - (background[k] + alpha * (colors[i][k] - background[k]))) <= inkTolerance })
                if (close) counts[i]++
            }
        }
    }
    return { background: fill, inks: inks.map(function (ink, i) { return { ink: ink, pixels: counts[i] } }) }
}
