//@ pragma ShellId flea-picker-save-wrap-test
import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Picker.js" as PickerLib

// The real PickerSave's collision line wraps at name joints or spaces at large text sizes, inside its column.
ShellRoot {
    id: root
    readonly property var sizes: [14, 18]
    // Dots and one underscore, no spaces or hyphens: only the joints under test can break the name.
    readonly property string longName: "quarterly.report.june_2026.final.export.reviewed.pdf"
    readonly property string shortName: "export.txt"
    readonly property string tail: " already exists here · review before continuing"
    readonly property string zwsp: String.fromCharCode(8203)
    readonly property real epsilon: 1
    // FontMetrics and the laid-out row round glyph advances apart, so a row end matches its width within two pixels.
    readonly property real advanceSlack: 2
    readonly property string refusedName: "../a%2b.txt"
    property var stages: []
    property int stageIndex: -1
    property int ticks: 0
    property int checks: 0
    property var failures: []
    property real shortImplicit: 0
    property var realLines: []
    property int realLinesStamp: -2
    property string wrapText: ""
    property int wrapRows: 0
    property var wrapWidths: []

    Flea.PickerSave {
        id: saveCard
        picker: fakePicker
        width: 280
        maximumHeight: 2000
    }

    QtObject {
        id: fakePicker
        property bool saving: true
        property bool submitting: false
        property string path: "/tmp"
        property string saveName: "export.txt"
        property string saveError: ""
        property bool collisionReview: true
        property var req: ({ name: "export.txt" })
        function stepFocus() {}
        function control() { return null }
        function cancel() {}
        function accept() {}
    }

    // Advances under the status line's own font, to match each row end to its natural width.
    FontMetrics {
        id: probeMetrics
        font.family: saveCard.statusItem.font.family
        font.pixelSize: saveCard.statusItem.font.pixelSize
    }

    function check(cond, label) {
        root.checks++
        if (!cond) {
            root.failures.push(label)
            console.log("PICKERSAVEWRAP FAIL " + label)
        }
    }

    // The natural width of every laid out line of the real status Text, reread per stage.
    Connections {
        target: saveCard.statusItem
        function onLineLaidOut(line) {
            if (root.realLinesStamp !== root.stageIndex)
                root.realLines = []
            root.realLinesStamp = root.stageIndex
            root.realLines[line.number] = line.implicitWidth
        }
    }

    // Row ends matched to the real natural widths, so every break check reads the status line.
    function checkJoints() {
        var T = root.wrapText
        var bad = ""
        if (root.wrapWidths.length !== root.wrapRows)
            bad += "stale geometry; "
        var start = 0
        for (var b = 0; bad === "" && b + 1 < root.wrapRows; b++) {
            // A break space is consumed, so a row after one starts past it.
            if (T.charAt(start) === " ")
                start++
            var end = rowEnd(T, start, root.wrapWidths[b])
            if (end < 0) {
                bad += "row" + b + " width " + root.wrapWidths[b] + " matches no end; "
                break
            }
            var last = T[end - 1]
            var next = end < T.length ? T[end] : ""
            if (last !== " " && last !== root.zwsp && last !== "-" && next !== " " && next !== root.zwsp && next !== "")
                bad += "row" + b + " ends " + JSON.stringify(last) + " before " + JSON.stringify(next) + "; "
            start = end
        }
        check(bad === "", "the long name wraps at word joints" + (bad === "" ? "" : ": " + bad))
    }

    // The first offset past start whose advance meets the row width, trailing space either way.
    function rowEnd(T, start, w) {
        for (var e = start + 1; e <= T.length; e++) {
            var piece = T.substring(start, e)
            if (Math.abs(probeMetrics.advanceWidth(piece) - w) <= root.advanceSlack)
                return e
            if (piece.charAt(piece.length - 1) === " " && Math.abs(probeMetrics.advanceWidth(piece.substring(0, piece.length - 1)) - w) <= root.advanceSlack)
                return e
        }
        return -1
    }

    function checkWrap() {
        var line = saveCard.statusItem
        check(line.lineCount >= 2, "the long name wraps at this width")
        var fresh = root.realLinesStamp === root.stageIndex && root.realLines.length === line.lineCount
        var inside = fresh
        for (var k = 0; inside && k < line.lineCount; k++)
            inside = root.realLines[k] !== undefined && root.realLines[k] <= line.width + root.epsilon
        check(inside, "paint stays inside the column")
        check(line.height + 0.5 >= line.implicitHeight && line.implicitHeight > root.shortImplicit, "the row follows the grown text, unclipped")
        root.wrapText = line.text
        root.wrapRows = line.lineCount
        root.wrapWidths = []
        if (fresh)
            for (var w = 0; w < line.lineCount; w++)
                root.wrapWidths.push(root.realLines[w] === undefined ? -1 : root.realLines[w])
        checkJoints()
    }

    function checkRefused() {
        var line = saveCard.statusItem
        check(line.text === root.refusedName + " cannot be used: " + PickerLib.NAME_REFUSED, "the refused branch keeps the asked name literal")
        check(line.height + 0.5 >= line.implicitHeight, "the refused row follows the text, unclipped")
    }

    function applyStage() {
        var stage = root.stages[root.stageIndex]
        root.realLines = []
        root.realLinesStamp = -2
        saveCard.width = stage.width
        Flea.ViewState.setTextSize({ mode: stage.size })
        fakePicker.saveName = stage.name
    }

    function runStage() {
        var stage = root.stages[root.stageIndex]
        var line = saveCard.statusItem
        if (stage.kind === "record") {
            root.shortImplicit = line.implicitHeight
            return
        }
        if (stage.kind === "wrap") {
            checkWrap()
            return
        }
        if (stage.kind === "refused") {
            checkRefused()
            return
        }
        check(line.lineCount === 1, "the short name fits one line wide")
        check(Math.abs(line.contentWidth - probeMetrics.advanceWidth(line.text)) < 0.5, "one-line draw keeps its natural width")
    }

    Component.onCompleted: {
        var out = []
        for (var s = 0; s < root.sizes.length; s++) {
            out.push({ kind: "record", size: root.sizes[s], width: 280, name: root.shortName })
            out.push({ kind: "wrap", size: root.sizes[s], width: 280, name: root.longName })
            out.push({ kind: "wide", size: root.sizes[s], width: 840, name: root.shortName })
            out.push({ kind: "refused", size: root.sizes[s], width: 280, name: root.refusedName })
        }
        root.stages = out
    }

    Timer {
        interval: 50
        running: true
        repeat: true
        onTriggered: {
            if (root.stages.length === 0)
                return
            if (root.stageIndex === -1) {
                root.stageIndex = 0
                root.applyStage()
                root.ticks = 0
                return
            }
            root.ticks++
            if (root.ticks < 4)
                return
            root.runStage()
            root.ticks = 0
            root.stageIndex++
            if (root.stageIndex >= root.stages.length) {
                if (root.failures.length === 0)
                    console.log("PICKERSAVEWRAP PASS " + root.checks + " checks")
                console.log("PICKERSAVEWRAP DONE checks=" + root.checks + " failed=" + root.failures.length)
                Quickshell.execDetached(["kill", String(Quickshell.processId)])
            } else {
                root.applyStage()
            }
        }
    }
}
