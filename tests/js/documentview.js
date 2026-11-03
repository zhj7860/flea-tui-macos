// Retired document views never enter stored state; close resets the open view.
function run(check, quickSrc, stateSrc, block) {
    // Only the read-only IPC observer may name a retired view key in these state-owning files.
    function storedViewWrite(text) {
        return /\b(markdownView|htmlView|setDocumentView)\b/.test(text.replace('function markdownView()', 'function transientView()'))
    }
    check("Quick Look owns a transient source flip and close forgets it",
        quickSrc.indexOf('property bool markdownSource: false') >= 0
            && block(quickSrc, "function close()", "ui/Preview.qml").indexOf("root.markdownSource = false") >= 0
            && !storedViewWrite(quickSrc)
            && !storedViewWrite(stateSrc), true)
    for (var write of ['{ htmlView: v }', '{ "markdownView": v }', 'preview.htmlView = v', 'preview["markdownView"] = v',
            'ViewState.changeLeaf("preview", {htmlView: v})', 'ViewState.setDocumentView(v)'])
        check("stored document view guard rejects " + write, storedViewWrite(write), true)
    var closeBody = block(quickSrc, "function close()", "ui/Preview.qml")
    var closeFn = new Function("root", "followSettle", "stripHideTimer", "mediaLoader", "pdfLoader", "imageLoader", closeBody)
    var closing = { swap: null, pane: null, markdownSource: true }
    closeFn(closing, { stop: function () {} }, { stop: function () {} }, {}, {}, {})
    check("driving close forgets the flip", closing.markdownSource, false)
}
