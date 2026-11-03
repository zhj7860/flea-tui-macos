.import "../../ui/js/Menu.js" as Menu
.import "../../ui/js/MarkdownPrepared.js" as Prepared
.import "../../ui/js/Lists.js" as Lists
.import "sourcefixture.js" as Source

// The backend delivers parsed replies through a var signal and readers retain them in var properties.
function received(text) {
    var parent = Qt.createComponent("QtQuick", "Item").createObject(null)
    var relay = Qt.createQmlObject("import QtQuick\nQtObject {\n"
        + "signal delivered(var message)\nproperty var received\n"
        + "onDelivered: function(message) { received = message }\n}", parent)
    relay.delivered(JSON.parse(text))
    return { parent: parent, message: relay.received }
}

// Execute the shipped QML body with only its process and singleton dependencies replaced.
function body(file, marker, args) {
    return new Function(args, Source.block(Source.source(file), marker, file))
}

// An indexed object with a generic Array method pins the sequence fallback on every Qt version.
function sequenceLike(values) {
    var sequence = { length: values.length, every: Array.prototype.every }
    for (var i = 0; i < values.length; i++)
        sequence[i] = values[i]
    return sequence
}

function run(plain) {
    function check(label, actual, expected) { plain(label, JSON.stringify(actual), JSON.stringify(expected)) }
    var fixture = received('{"kinds":[32768,32768],"paths":["/a","/b"],'
        + '"blocks":[{"type":"list","parts":[[{"type":"figure","kind":"math","source":"x"},{"type":"table"}]]}]}')
    var message = fixture.message
    console.log("sequence signal: Array.isArray=" + Array.isArray(message.kinds)
        + ", every=" + typeof message.kinds.every + ", concat=" + JSON.stringify([].concat(message.kinds)))
    // Sample input: '--qt-version=6.12.0', appended by tests/js.sh from qml6 --version.
    var qtVersion = ""
    var argv = Qt.application.arguments
    for (var a = 0; a < argv.length; a++)
        if (argv[a].indexOf("--qt-version=") === 0) qtVersion = argv[a].substring("--qt-version=".length)
    var version = /^(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$/.exec(qtVersion)
    check("sequence signal: harness supplies running Qt version", version !== null, true)
    if (version && (Number(version[1]) > 6 || (Number(version[1]) === 6 && Number(version[2]) >= 12))) {
        check("Qt >= 6.12: var signal kinds are not an Array", Array.isArray(message.kinds), false)
        check("Qt >= 6.12: var signal paths are not an Array", Array.isArray(message.paths), false)
        console.log("sequence signal: Qt " + qtVersion + " non-Array assertions ran")
    } else if (version) {
        console.log("sequence signal: SKIP non-Array assertion on Qt " + qtVersion + " (< 6.12)")
    }
    check("var signal: two regular files offer Compare", Menu.canCompare(message.kinds), true)
    check("var signal: nested Markdown formulas remain visible", Prepared.formulasIn(message.blocks, 8), [{source: "x", display: true}])

    var kinds = sequenceLike([32768, 32768])
    var parts = sequenceLike([{type: "figure", kind: "math", source: "x"}, {type: "table"}])
    var blocks = [{type: "list", parts: [parts]}]
    check("sequence fallback: fixtures are not Arrays", [Array.isArray(kinds), Array.isArray(parts)], [false, false])
    check("sequence fallback: indexed non-Array stays a list", Lists.isList(kinds), true)
    check("sequence fallback: two regular files offer Compare", Menu.canCompare(kinds), true)
    check("sequence fallback: nested Markdown formulas remain visible", Prepared.formulasIn(blocks, 8), [{source: "x", display: true}])

    var lists = Lists
    var root = {}
    var holds = body("ui/QuickLookPrepare.qml", "function holdsTable(", "root,Lists,list")
    root.holdsTable = function (list) { return holds(root, lists, list) }
    check("var signal: nested Markdown tables remain visible", root.holdsTable(message.blocks), true)
    check("sequence fallback: nested Markdown tables remain visible", root.holdsTable(blocks), true)
    var kind = body("ui/IpcPreviewState.qml", "function kindOf(", "root,block")
    root.kindOf = function (block) { return kind(root, block) }
    check("var signal: Markdown diagnostics flatten list items", root.kindOf(message.blocks[0]), "list[figure,table]")

    var shelver = {}
    body("ui/PaneMenuActions.qml", "function startAdd(", "shelver,Quickshell,paths")
        (shelver, {env: function () { return "flea" }}, message.paths)
    check("var signal: shelf command has separate path arguments", shelver.command, ["flea","shelf","add","/a","/b"])
    shelver.command.push("/c")
    check("concat: shelf command construction does not mutate received paths", message.paths, ["/a", "/b"])
    var runner = {}
    root = {entries: [{id: "test", path: "/scripts/test"}], said: function () {}}
    body("ui/Scripts.qml", "function run(", "root,runner,id,paths")(root, runner, "test", message.paths)
    check("var signal: script command has separate path arguments", runner.command, ["/scripts/test","/a","/b"])
    root = {pending: {request: 7, range: null}, picker: {markRequest: -1, marks: []}}
    root.picker.check = function (request) { root.sent = request; return 8 }
    body("ui/PickerSelection.qml", "function onPathsResolved(", "root,Picker,paths,request")
        (root, {paths: function () { return ["/old"] }}, message.paths, 7)
    check("var signal: picker selection remains a flat path list", root.sent.paths, ["/old","/a","/b"])
    var receivedEmpty = received('{"items":[],"mixed":[32768,16384],"links":[32768,40960]}')
    check("list test: var signal sequences are lists", Lists.isList(message.kinds), true)
    check("list test: native Arrays stay lists", Lists.isList([1, 2]), true)
    check("list test: empty signal sequence stays a list", Lists.isList(receivedEmpty.message.items), true)
    check("list test: strings, null and invalid objects stay refused",
        [Lists.isList("ab"), Lists.isList(new String("ab")), Lists.isList(null), Lists.isList(undefined),
         Lists.isList({}), Lists.isList({length: "2"}), Lists.isList({length: 2}),
         Lists.isList({length: -1, every: function () {}}), Lists.isList({length: Infinity, every: function () {}}),
         Lists.isList({length: 1.5, every: function () {}})],
        [false, false, false, false, false, false, false, false, false, false])
    check("var signal: a folder still refuses Compare", Menu.canCompare(receivedEmpty.message.mixed), false)
    check("var signal: a symlink still refuses Compare", Menu.canCompare(receivedEmpty.message.links), false)
    check("var signal: an empty list still refuses Compare", Menu.canCompare(receivedEmpty.message.items), false)
    check("var signal: strings and object-shaped kinds refuse Compare",
        [Menu.canCompare("ab"), Menu.canCompare({0: 32768, 1: 32768, length: 2}), Menu.canCompare(null)], [false, false, false])
    receivedEmpty.parent.destroy()
    fixture.parent.destroy()
}
