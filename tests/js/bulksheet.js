.import "../../ui/js/SheetQuery.js" as SheetQuery
.import "sourcefixture.js" as Source

// A pane that owns a sheetAction stops every key-sheet row at "close", so none may exist.
function run(check) {
    var paneSource = Source.source("ui/Pane.qml")
    check("the pane defines no sheetAction entry point", paneSource.indexOf("function sheetAction(") < 0, true)
    var calls = []
    var holder = {
        listInFlight: false,
        message: function (text, shown) { calls.push("message") },
        act: function (action) { calls.push("act:" + action) }
    }
    function close() { calls.push("close") }
    SheetQuery.runAction(holder, "newFolder", close)
    check("a non-rename sheet action on a pane reaches the shared dispatch", calls.join(","), "close,act:newFolder")
}
