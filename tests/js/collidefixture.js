// The real ui/CollideHost.qml, ui/FileDrag.qml and ui/RowDrag.qml over a stub pane and backend, for tests/js/collide.js.
.import "sourcefixture.js" as Source
.import "../../ui/js/DragOut.js" as DragOut

// The shipped key record in ui/js/DragOut.js, the one every built file reads, cleared and renumbered for a fresh drag.
// Sample input: realDropKeys() answers the record at marker "" with ctrl and shift -1 and no lift stamped yet.
function realDropKeys() {
    DragOut.keys.clear()
    DragOut.keys.lifts = 0
    return DragOut.keys
}

// ui/<file> built beside ui/js (qml6 lacks Quickshell's singletons), reading the shared key record as shipped.
// Sample input: 'import QtQuick\nimport "js/Drag.js" as DragOps\n\n// Delegate input ...\nItem {\n    id: root\n'
function built(file, parent, properties) {
    var text = Source.source("ui/" + file)
    var body = text.search(/^[A-Z]\w* \{/m)
    var imports = text.substring(0, body).replace(/import "js\//g, "import \"")
    var wrapper = Qt.createQmlObject(imports + "QtObject { property Component made: Component { " + text.substring(body) + " } }",
                                     parent, Qt.resolvedUrl("../../ui/js/" + file))
    return wrapper.made.createObject(parent, properties)
}

// ui/Backend.qml as the card and the drag reach it: the two replies CollideHost hears, and send() naming rows as it does.
// The failed signal carries production's four arguments (ui/Backend.qml), because CollideHost reads
// the second: the error line's path, "collisions" for a refused question.
var BACKEND = "import QtQuick\nimport \"../../ui/js/Swap.js\" as Swap\nQtObject {\n"
    + "    signal collisions(int id, int total, var names, bool mergeable)\n    signal mergeCollisions(int id, int total, var names)\n    signal failed(string where, string input, string message, int mode)\n"
    + "    property real heldListing: 0\n    property var sent: []\n"
    + "    function send(object) { sent.push(Swap.named(object, heldListing)) }\n}\n"

// The commands written so far, in order.
function verbs(backend) {
    return backend.sent.map(function (line) { return line.c }).join(",")
}

// A pane at rest over a folder row in listing held, its card the real one, its drag session and the folder row's drop target.
function scene(held, said) {
    var parent = Qt.createComponent("QtQuick", "Item").createObject(null)
    var backend = Qt.createQmlObject(BACKEND, parent, Qt.resolvedUrl("backend.qml"))
    backend.heldListing = held
    var folder = [{ n: "a.txt", d: false }, { n: "b.txt", d: false }, { n: "omarchy", d: true }]
    var p = { path: "/d", backend: backend, statusBar: null, clipboard: { paths: ["/s/a.txt"], moving: true },
              listInFlight: false, renamePending: false, renamingIndex: -1, menuVisible: false, menuActions: { opened: false },
              filterTyping: false, searchMode: "", selectionBand: null }
    p.rowFor = function (index) { return folder[index] || null }
    p.selectedIndices = function () { return [] }
    p.selectionCount = function () { return 0 }
    p.join = function (base, name) { return base + "/" + name }
    p.message = said ? function (text) { said.push(text) } : function () {}
    p.collide = built("CollideHost.qml", parent, { pane: p })
    p.asks = function () { return p.collide }
    var keys = realDropKeys()
    var session = built("FileDrag.qml", parent, { pane: p })
    var target = built("RowDrag.qml", parent, { session: session, listingIndex: 2, row: folder[2] })
    return { parent: parent, backend: backend, pane: p, session: session, target: target, keys: keys }
}
