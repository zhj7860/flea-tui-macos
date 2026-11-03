.import "../../ui/js/QuickLookRect.js" as QuickLookRect

// Quick Look's surface rect: tall kinds take the window's height less the edge, the rest keep 82% by 82%.

var TOKENS = { fraction: 0.82, edge: 24, bar: 27 }

function shape(kind, w, h, orient) {
    return { kind: kind, known: w !== undefined, w: w || 0, h: h || 0, orient: orient || 1 }
}

// Theme.cardSpan's rounding, which the surface applies to the want.
function cardSpan(want, room) { return Math.max(0, Math.min(Math.ceil(want), Math.floor(room))) }

function rect(s, expanded) {
    var r = QuickLookRect.surface(s, 1200, 760, expanded === true, TOKENS)
    return cardSpan(r.w, 1200) + "x" + cardSpan(r.h, 760)
}

function run(check) {
    check("code takes 82% of the width and the height less 24 above and below", rect(shape("text")), "984x712")
    check("an archive list takes the code rect", rect(shape("archive")), "984x712")
    check("an A4 PDF takes its width from page 1 plus the 27 px top bar", rect(shape("pdf", 595, 842)), "485x712")
    check("a PDF whose page size is not yet known keeps today's rect", rect({ kind: "pdf", known: false, w: 0, h: 0, orient: 1 }), "984x624")
    check("a wide PDF page is capped at the 82% width", rect(shape("pdf", 1000, 500)), "984x712")
    check("a 1170 x 2532 portrait PNG takes the full height and its aspect width", rect(shape("image", 1170, 2532)), "330x712")
    check("a 4000 x 3000 photo keeps today's rect", rect(shape("image", 4000, 3000)), "984x624")
    check("a 4000 x 3000 photo turned by EXIF 6 counts as portrait", rect(shape("image", 4000, 3000, 6)), "534x712")
    check("a turned portrait file (EXIF 8 on 3000 x 4000) counts as landscape", rect(shape("image", 3000, 4000, 8)), "984x624")
    check("a square picture keeps today's rect", rect(shape("image", 1000, 1000)), "984x624")
    check("a 200 x 400 portrait, shorter than the tall rect, keeps today's rect", rect(shape("image", 200, 400)), "984x624")
    check("a portrait exactly as tall as the tall rect takes it", rect(shape("image", 356, 712)), "356x712")
    check("an image whose size is not yet known keeps today's rect", rect({ kind: "image", known: false, w: 0, h: 0, orient: 1 }), "984x624")
    check("an image whose reply carried no size keeps today's rect", rect({ kind: "image", known: true, w: 0, h: 0, orient: 1 }), "984x624")
    check("video keeps today's rect", rect(shape("video")), "984x624")
    check("audio keeps today's rect", rect(shape("audio")), "984x624")
    check("a file that cannot be previewed keeps today's rect", rect(shape("")), "984x624")
    check("expand fills the window", rect(shape("pdf", 595, 842), true), "1200x760")
}
