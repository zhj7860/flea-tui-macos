.pragma library

.import "Kinds.js" as Kinds

// Which compilation unit Quick Look opens a row's content from, for ui/QuickLookWarm.qml to hold compiled before the first Space.
var MARKDOWN = "MarkdownPane.qml"
var PDF = "PdfViewer.qml"
var MEDIA = "PreviewMedia.qml"
var IMAGE = "PreviewImage.qml"
var TEXT = "PreviewText.qml"

// Sample input: { n: "a.pdf", i: "x-office-document" } answers "PdfViewer.qml", { n: "a.mp4", i: "video-x-generic" } "PreviewMedia.qml", { n: "a.png", i: "image-x-generic" } "PreviewImage.qml", { n: "a.md", i: "text-x-generic" } "MarkdownPane.qml".
// A folder, an archive, an unsupported file and null answer "" because no unit of their own is compiled for them.
function unitOf(row) {
    if (row === null || row === undefined || row.d === true)
        return ""
    if (Kinds.isMarkdown(row.n))
        return MARKDOWN
    switch (Kinds.quickLookKind(row.i, row.n, row.t === true)) {
    case Kinds.PDF: return PDF
    case Kinds.VIDEO:
    case Kinds.AUDIO: return MEDIA
    case Kinds.IMAGE: return IMAGE
    case Kinds.TEXT: return TEXT
    }
    return ""
}
