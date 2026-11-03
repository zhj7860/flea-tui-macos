import QtQuick
import Quickshell
import "flea" as Flea

// Controlled terminal replies exercise the real source renderer with stale listing metadata.
ShellRoot {
    id: root
    property int phase: 0
    property int checks: 0
    property int failures: 0
    property double started: Date.now()
    property bool finished: false
    readonly property var states: ["binary", "large", "failed"]
    function check(name, got, want) {
        root.checks++
        var pass = JSON.stringify(got) === JSON.stringify(want)
        if (!pass) root.failures++
        console.warn("HTML_PREVIEW " + (pass ? "PASS " : "FAIL ") + name + " got=" + JSON.stringify(got) + " want=" + JSON.stringify(want))
    }
    function finish() {
        root.finished = true
        console.warn("HTML_PREVIEW DONE " + root.checks + " checks, " + root.failures + " failed")
        quit.start()
    }
    QtObject {
        id: sourceBackend
        property int token: 0
        signal codeResult(var message)
        signal htmlResult(var message)
        function askCode(slot, source, first, count) {
            var id = ++sourceBackend.token
            var state = root.states[root.phase]
            Qt.callLater(function () { sourceBackend.codeResult({ token: id, slot: slot, first: first, total: 0, lines: [], state: state }) })
            return id
        }
    }
    FloatingWindow {
        implicitWidth: 984
        implicitHeight: 600
        Flea.PreviewHtml {
            id: doc
            anchors.fill: parent
            active: true
            path: "/fixture/refusal-0.html"
            size: 1
            backend: sourceBackend
            view: "source"
            slot: "refusal"
        }
    }
    Timer { id: quit; interval: 100; onTriggered: Qt.exit(root.failures > 0 ? 1 : 0) }
    Timer {
        interval: 20
        running: true
        repeat: true
        onTriggered: {
            if (root.finished) return
            if (Date.now() - root.started > 5000) {
                root.check("Source refusal completes", "timeout", "done")
                root.finish()
                return
            }
            if (!doc.sourceCode || doc.sourceCode.answer !== root.states[root.phase]) return
            var state = root.states[root.phase]
            root.check(state + " stops loading and releases first-screen readiness", [doc.loading, doc.firstScreen], [false, true])
            root.check(state + " uses the existing refusal state", [doc.binary, doc.tooLarge, doc.failed],
                [state === "binary", state === "large", state === "failed"])
            root.check(state + " keeps source reader active to retain its terminal reply", doc.sourceCode.active, true)
            root.phase++
            if (root.phase === root.states.length) { root.finish(); return }
            doc.path = "/fixture/refusal-" + root.phase + ".html"
            root.started = Date.now()
        }
    }
}
