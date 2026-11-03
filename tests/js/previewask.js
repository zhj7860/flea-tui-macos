.import "../../ui/js/PreviewAsk.js" as PreviewAsk
.import "sourcefixture.js" as Source

// The cursor row's thumbnail ask (AGENTS.md "Thumbnail requests in the GUI"): the early ask and load()'s askThumb share one gate, so the second sends nothing twice.

function base(over) {
    var o = { canRead: true, storageKnown: true, selectionCount: 1, index: 3, rowT: true,
        asked: false, storageClass: "local", preview: {} }
    for (var k in over) o[k] = over[k]
    return o
}

function earlyBase(over) {
    var o = base(over)
    o.now = 1000
    o.lastMoveAt = 0
    o.interval = 120
    o.key = "/d\n3"
    o.lastMoveKey = "/d\n2"
    o.armed = false
    for (var k in over) o[k] = over[k]
    return o
}

function run(check) {
    var work = PreviewAsk.workFor(base({}))
    check("an idle press asks the cursor row", work && work.ask.join(","), "3")
    check("and carries no drop", work && work.drop.length, 0)
    check("local decodes in full", work && work.cacheOnly, false)
    check("a switched-on class decodes in full",
        PreviewAsk.workFor(base({ storageClass: "network", preview: { thumbNetwork: true } })).cacheOnly, false)
    check("an idle press passes the settle's own rule",
        PreviewAsk.earlyWorkFor(earlyBase({})).ask.join(","), "3")
    check("a walk step asks nothing early",
        PreviewAsk.earlyWorkFor(earlyBase({ now: 50 })), null)
    check("a pending repeat asks nothing early",
        PreviewAsk.earlyWorkFor(earlyBase({ now: 1000, key: "/d\n2", lastMoveKey: "/d\n2", armed: true })), null)
    check("unknown storage asks nothing early, a NAS image would thumbnail in full",
        PreviewAsk.earlyWorkFor(earlyBase({ storageKnown: false })), null)
    check("and load's own ask stays held too", PreviewAsk.workFor(base({ storageKnown: false })), null)
    check("a manual-hold class asks nothing early",
        PreviewAsk.earlyWorkFor(earlyBase({ storageClass: "network", preview: {} })), null)
    check("load's own ask on an off class asks cache only, the hold is not its gate",
        JSON.stringify(PreviewAsk.workFor(base({ storageClass: "network", preview: {} }))),
        JSON.stringify({ ask: [3], drop: [], cacheOnly: true }))
    check("an already asked row asks nothing again",
        PreviewAsk.earlyWorkFor(earlyBase({ asked: true })), null)
    check("a multi-selection asks nothing", PreviewAsk.earlyWorkFor(earlyBase({ selectionCount: 3 })), null)
    check("an unreadable frame asks nothing", PreviewAsk.earlyWorkFor(earlyBase({ canRead: false })), null)
    check("a row with no thumbnail asks nothing", PreviewAsk.earlyWorkFor(earlyBase({ rowT: false })), null)
    check("no row asks nothing", PreviewAsk.earlyWorkFor(earlyBase({ index: -1 })), null)
    var preview = Source.source("ui/SelectionPreview.qml")
    check("the preview imports the shared gate",
        preview.indexOf('import "js/PreviewAsk.js" as PreviewAsk') >= 0, true)
    var askArm = Source.slice(preview, "function askThumb()", "function askCursorThumb()")
    check("load's own ask spends the shared gate", askArm.indexOf("PreviewAsk.workFor(") >= 0, true)
    check("a held frame asks nothing, so only a released preview reaches the gate",
        askArm.indexOf("if (root.manualHold || !root.isShown()) return") >= 0
        && askArm.indexOf("if (root.manualHold || !root.isShown()) return") < askArm.indexOf("PreviewAsk.workFor("), true)
    check("and sends only its answer", askArm.indexOf("if (!work) return") >= 0
        && askArm.indexOf("pane.backend.thumb(work.ask, work.cacheOnly)") >= 0, true)
    var earlyArm = Source.slice(preview, "function askCursorThumb()", "function startSwap(")
    check("the early ask spends the idle half and the shared gate",
        earlyArm.indexOf("PreviewAsk.earlyWorkFor(") >= 0, true)
    check("it stays out of manual preview and a hidden column",
        earlyArm.indexOf("if (!ViewState.previewAutomatic || !ViewState.previewColumn) return") >= 0, true)
    check("it names a file row only", earlyArm.indexOf("Columns.isFileRow(current)") >= 0, true)
    check("it stamps no move clock", earlyArm.indexOf("root.lastMoveAt =") < 0 && earlyArm.indexOf("root.lastMoveKey =") < 0, true)
    var area = Source.source("ui/ColumnsArea.qml")
    var cursor = Source.slice(area, "function followCursor()", "function swapState()")
    var earlyAt = cursor.indexOf("preview.askCursorThumb()")
    var moveAt = cursor.indexOf("root.moveThird()", earlyAt)
    check("every cursor move asks before the column moves", earlyAt >= 0 && moveAt > earlyAt, true)
}
