.pragma library

// Sample input: surface({ kind: "pdf", known: true, w: 595, h: 842, orient: 1 }, 1200, 760, false, { fraction: 0.82, edge: 24, bar: 27 }) is { w: 484.06, h: 712 }.
// The want before Theme.cardSpan rounds it. A shape is the kind plus its one fact: a PDF's page 1 size or an image's pixels and EXIF orientation, known false while unasked or unanswered.
function surface(shape, winW, winH, expanded, tokens) {
    var today = { w: winW * tokens.fraction, h: winH * tokens.fraction }
    if (expanded)
        return { w: winW, h: winH }
    var tallH = winH - 2 * tokens.edge
    var seen = shape.known === true && shape.w > 0 && shape.h > 0
    if (shape.kind === "text" || shape.kind === "archive")
        return { w: today.w, h: tallH }
    if (shape.kind === "pdf" && seen)
        return { w: Math.min(today.w, (tallH - tokens.bar) * shape.w / shape.h), h: tallH }
    if (shape.kind === "image" && seen) {
        var turned = shape.orient >= 5
        var ow = turned ? shape.h : shape.w
        var oh = turned ? shape.w : shape.h
        // A portrait shorter than the tall rect keeps today's frame rather than being stretched to it.
        if (oh > ow && oh >= tallH)
            return { w: Math.min(today.w, tallH * ow / oh), h: tallH }
    }
    return today
}
