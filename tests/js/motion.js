.import "../../ui/js/Motion.js" as Motion
.import "sourcefixture.js" as Source

// mo1: the structural transitions use OutCubic, 180 ms to reveal and 140 ms to hide.

function run(check) {
    check("a reveal reads 180", Motion.durMs.open, 180)
    check("a hide reads 140", Motion.durMs.close, 140)
    check("reveal slower than hide", Motion.durMs.open > Motion.durMs.close, true)
    check("no bezier curve to drift back to", Motion.bezierCurve, undefined)
    check("the rise stays 10 px", Motion.translateUpPx, 10)
    runStructural(check)
}

// The source with its comments gone, so a word in a comment never stands for code.
function withoutComments(text) {
    return text.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "")
}

// The transitions a fullscreen take or a dialog open runs through, so a curve change here is a product change.
function runStructural(check) {
    var files = ["ui/Preview.qml", "ui/Reveal.qml", "ui/EmptyState.qml", "ui/FleaMark.qml"]
    for (var i = 0; i < files.length; i++) {
        var src = Source.source(files[i])
        check(files[i] + " carries OutCubic", src.indexOf("Easing.OutCubic") >= 0, true)
        check(files[i] + " carries no BezierSpline", src.indexOf("BezierSpline") < 0, true)
    }
    var shared = ["ui/ShareBrowser.qml", "ui/NetworkDialog.qml"]
    for (var j = 0; j < shared.length; j++) {
        var own = Source.source(shared[j])
        check(shared[j] + " fades through Reveal", /Reveal(\.qml"\)|\s*\{)/.test(withoutComments(own)), true)
        check(shared[j] + " carries no easing of its own", own.indexOf("easing.type") < 0, true)
    }
    runCurve(check)
}

// Every Flea transition runs on OutCubic, so a press scale or a caption fade on another curve is a product change.
function runCurve(check) {
    var press = ["ui/ChromeButton.qml", "ui/DialogButton.qml"]
    var fades = [{ file: "ui/EmptyState.qml", durations: ["close", "open"] }, { file: "ui/FleaMark.qml", durations: ["close"] }]
    var files = ["ui/PickerChrome.qml"].concat(press, fades.map(function(fade) { return fade.file }))
    for (var i = 0; i < files.length; i++) {
        var src = Source.source(files[i])
        check(files[i] + " carries no OutQuad", src.indexOf("Easing.OutQuad") < 0, true)
        check(files[i] + " carries no InQuad", src.indexOf("Easing.InQuad") < 0, true)
    }
    // The press scale keeps its named token, 150 ms and under the reveal ceiling.
    for (var p = 0; p < press.length; p++)
        check(press[p] + " eases the press on OutCubic over PRESS_MS",
              Source.source(press[p]).indexOf("duration: Buttons.PRESS_MS; easing.type: Easing.OutCubic") >= 0, true)
    for (var f = 0; f < fades.length; f++) {
        var src = Source.source(fades[f].file)
        var lines = src.split("\n").filter(function(line) { return line.indexOf('property: "opacity"') >= 0 && line.indexOf("duration:") >= 0 })
        check(fades[f].file + " names its opacity fades", lines.length, fades[f].durations.length)
        for (var n = 0; n < lines.length; n++) {
            check(fades[f].file + " fade " + n + " reads Motion.durMs." + fades[f].durations[n],
                  lines[n].indexOf("duration: Motion.durMs." + fades[f].durations[n] + ";") >= 0, true)
            check(fades[f].file + " fade " + n + " is OutCubic", lines[n].indexOf("Easing.OutCubic") >= 0, true)
        }
        check(fades[f].file + " imports Motion", src.indexOf('import "js/Motion.js" as Motion') >= 0, true)
    }
}
