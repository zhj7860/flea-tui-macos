// The real ui/ArchiveCards.qml, both password cards and ui/Backend.qml over tests/js/archivestubs, for tests/js/archivecards.js.
.import "sourcefixture.js" as Source

// ui/<file> as one Component over the stubs; each [from, to] swap must match, so a renamed line fails loudly.
// Sample input: built("ArchiveCards.qml", parent, [['source: "ArchivePasswordDialog.qml"', "sourceComponent: passwordCard"]], "property Component passwordCard\n")
function built(file, parent, swaps, extra) {
    var text = Source.source("ui/" + file)
        .replace(/^import (Quickshell|Quickshell\.Io|qs\.Commons)\n/gm, "")
        .replace(/import "js\//g, "import \"../../../ui/js/")
    var list = swaps || []
    list.forEach(function (swap) {
        if (text.indexOf(swap[0]) < 0) throw new Error("archivefixture: ui/" + file + " has no " + swap[0])
        text = text.replace(swap[0], swap[1])
    })
    var body = text.search(/^[A-Z]\w* \{/m)
    return Qt.createQmlObject(text.substring(0, body) + "QtObject {\n" + (extra || "") + "property Component made: Component { "
                              + text.substring(body) + " } }", parent, Qt.resolvedUrl("archivestubs/" + file))
}

// The cards host as WindowBody.openArchiveCards builds it, its two Loaders given the real card documents.
function cards(parent) {
    var host = built("ArchiveCards.qml", parent,
                     [['source: "ArchiveCompressDialog.qml"', "sourceComponent: compressCard"],
                      ['source: "ArchivePasswordDialog.qml"', "sourceComponent: passwordCard"]],
                     "property Component compressCard\nproperty Component passwordCard\n")
    host.compressCard = built("ArchiveCompressDialog.qml", parent).made
    host.passwordCard = built("ArchivePasswordDialog.qml", parent).made
    return host.made.createObject(parent)
}

// ui/Backend.qml with its child not yet started, which is the queueing state a launch begins in.
function backend(parent) {
    return built("Backend.qml", parent).made.createObject(parent)
}

// The stub child under a built Backend: emit started() to bring it up, read written for every line sent.
function child(backend) {
    for (var i = 0; i < backend.data.length; i++) {
        if (backend.data[i].written !== undefined) return backend.data[i]
    }
    throw new Error("archivefixture: ui/Backend.qml built no Process")
}

// A pane as the cards and the archive ops reach it; sent and said are shared logs, each line led by the pane's name.
function pane(name, sent, said) {
    return { path: "/" + name, listArea: null,
        join: function (a, b) { return a + "/" + b },
        sticky: function () {},
        message: function (text) { said.push(name + ":" + text) },
        backend: { archiveFormats: ["7z", "zip"], queueing: false,
            compressPassword: function (paths, dest, format, password, encrypt, id) {
                sent.push([name, "compress", paths.join(","), dest, format, password, encrypt, id].join("|")) },
            extractPassword: function (path, dest, password, id) {
                sent.push([name, "extract", path, dest, password, id].join("|")) } } }
}
