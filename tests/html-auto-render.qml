import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/PreviewKeys.js" as PreviewKeys

// Native r, follow and close paths pin transient Quick Look state and column independence for both kinds.
ShellRoot {
    id: root
    property int phase: -2
    property int kindIndex: 0
    property int checks: 0
    property int failures: 0
    property var keys: null
    property double started: Date.now()
    property double calmAt: 0
    property bool finished: false
    property bool ticking: false
    property bool capturing: false
    readonly property var files: [["index.html", "long.html"], ["notes.md", "other.md"]]
    function pane() { return body.item ? body.item.currentPane : null }
    function look() { return root.pane() ? root.pane().preview : null }
    function check(name, got, want) {
        root.checks++
        var pass = JSON.stringify(got) === JSON.stringify(want)
        if (!pass) root.failures++
        console.warn("HTML_PREVIEW " + (pass ? "PASS " : "FAIL ") + name + " got=" + JSON.stringify(got) + " want=" + JSON.stringify(want))
    }
    function calm(ok) {
        if (!ok) { root.calmAt = 0; return false }
        if (!root.calmAt) root.calmAt = Date.now()
        return Date.now() - root.calmAt > 300
    }
    function next() { root.phase++; root.started = Date.now(); root.calmAt = 0 }
    function select(name) {
        var p = root.pane()
        for (var i = 0; i < p.total; i++) {
            if (p.rowFor(i).n === name) { p.setCursor(i); return }
        }
        root.check("fixture " + name + " exists", false, true)
        root.finish()
    }
    function key(text) { root.keys.keyClickChar(text, Qt.NoModifier, -1) }
    function open(name) {
        root.select(name)
        root.pane().listArea.forceActiveFocus()
        root.keys.keyClick(Qt.Key_Space, Qt.NoModifier, -1)
    }
    function finish() {
        root.finished = true
        console.warn("HTML_PREVIEW DONE " + root.checks + " checks, " + root.failures + " failed")
        quit.start()
    }
    function tick() {
        var p = root.pane(), l = root.look()
        var m = l ? l.markdownShown : null
        var c = p ? p.previewColumnItem : null
        var ready = m && m.firstScreen && l.openState().landed
        var columnReady = c && c.visible && c.markdown && c.markdown.firstScreen && !c.textLoading
        var kind = root.kindIndex === 0 ? "HTML" : "Markdown"
        if (Date.now() - root.started > 25000) {
            root.check(kind + " phase " + root.phase + " completes", "timeout", "done")
            root.finish()
            return
        }
        switch (root.phase) {
        case -2:
            if (!p || p.listInFlight || !p.storageKnown || p.total < 4) return
            root.keys = Qt.createQmlObject("import QtTest; TestEvent {}", p.listArea)
            root.open("board.html")
            root.next()
            break
        case -1:
            if (!root.calm(ready)) return
            root.keys.keyClick(Qt.Key_Escape, Qt.NoModifier, -1)
            root.keys.keyClick(Qt.Key_2, Qt.ControlModifier, -1)
            root.next()
            break
        case 0:
            if (!p || p.listInFlight || !p.storageKnown || p.total < 4) return
            if (!root.calm(columnReady)) return
            root.check("Escape and Ctrl+2 land on the HTML column at 1100x700", [p.viewMode, p.rowFor(p.cursorIndex).n, c.isHtmlRow, window.width, window.height], ["columns", "board.html", true, 1100, 700])
            var state = JSON.parse(observer.htmlState(true))
            root.check("the column HTML observer reads the active pane", [state.visible, state.ready, state.view, state.lines, state.facts], [true, true, "rendered", 61, "HTML document · 1.6 kB · 61 lines"])
            root.check("the HTML corner observer names the real frame", [state.window.width, state.window.height, state.column, state.hairline > 0], [1100, 700, true, true])
            root.check("fresh UI state has no stored document views", [Flea.ViewState.preview.markdownView, Flea.ViewState.preview.htmlView], [undefined, undefined])
            root.capturing = true
            var output = Quickshell.env("FLEA_CI_SUITE_LOGS") || Quickshell.env("HTML_ROOT")
            body.item.grabToImage(function (grab) {
                root.check("the 1100x700 column capture saves", grab.saveToFile(output + "/html-column-1100x700.png"), true)
                root.open(root.files[root.kindIndex][0])
                root.next()
                root.capturing = false
            })
            break
        case 1:
            if (!root.calm(ready && columnReady)) return
            root.check(kind + " opens rendered", m.shownView, "rendered")
            if (root.kindIndex === 0) {
                var lookState = JSON.parse(observer.htmlState(false))
                root.check("Quick Look capture observes its actual close mark", [lookState.column, typeof lookState.close.centre, lookState.close.pressed], [false, "string", false])
            }
            var g = m.barGeometry()
            root.check(kind + " bar has no segment or view controls", [!!g.segment, !!g.rendered, !!g.source], [false, false, false])
            root.capturing = true
            var destination = Quickshell.env("FLEA_CI_SUITE_LOGS") || Quickshell.env("HTML_ROOT")
            m.grabToImage(function (grab) {
                root.check(kind + " rendered Quick Look capture saves", grab.saveToFile(destination + "/auto-" + kind.toLowerCase() + "-quicklook.png"), true)
                root.key("r")
                root.next()
                root.capturing = false
            })
            break
        case 2:
            if (!root.calm(ready && columnReady)) return
            root.check(kind + " native r flips Quick Look to source", m.shownView, "source")
            root.check(kind + " column stays rendered after r", c.markdown.shownView, "rendered")
            root.check(kind + " r stores no document view", [Flea.ViewState.preview.markdownView, Flea.ViewState.preview.htmlView], [undefined, undefined])
            root.select(root.files[root.kindIndex][1])
            PreviewKeys.follow(p)
            root.next()
            break
        case 3:
            if (!root.calm(ready && columnReady && l.path.endsWith("/" + root.files[root.kindIndex][1]))) return
            root.check(kind + " source flip survives follow to another file", m.shownView, "source")
            root.check(kind + " next file column stays rendered", c.markdown.shownView, "rendered")
            root.key("r")
            root.next()
            break
        case 4:
            if (!root.calm(ready)) return
            root.check(kind + " second r returns Quick Look to rendered", m.shownView, "rendered")
            root.key("r")
            root.next()
            break
        case 5:
            if (!root.calm(ready)) return
            root.check(kind + " third r returns Quick Look to source", m.shownView, "source")
            root.keys.keyClick(Qt.Key_Space, Qt.NoModifier, -1)
            root.open(root.files[root.kindIndex][1])
            root.next()
            break
        case 6:
            if (!root.calm(ready && columnReady)) return
            root.check(kind + " close forgets source before reopening", m.shownView, "rendered")
            root.check(kind + " reopened column is rendered", c.markdown.shownView, "rendered")
            root.keys.keyClick(Qt.Key_Space, Qt.NoModifier, -1)
            if (++root.kindIndex < root.files.length) {
                root.open(root.files[root.kindIndex][0])
                root.phase = 0
                root.next()
            } else root.finish()
        }
    }
    FloatingWindow {
        id: window
        implicitWidth: 1100
        implicitHeight: 700
        Loader {
            id: body
            anchors.fill: parent
            source: "file://" + Quickshell.env("HTML_UI") + "/WindowBody.qml"
            onLoaded: item.host = window
        }
    }
    QtObject {
        id: observedWindow
        readonly property real width: window.width
        readonly property real height: window.height
        function centreOf(item) {
            var point = item.mapToItem(null, item.width / 2, item.height / 2)
            return Math.round(point.x) + " " + Math.round(point.y)
        }
        function rectOf(item) {
            var point = item.mapToItem(null, 0, 0)
            return [Math.round(point.x), Math.round(point.y), Math.round(item.width), Math.round(item.height)].join(" ")
        }
    }
    Flea.IpcPreviewState { id: observer; pane: root.pane(); fleaWindow: observedWindow }
    Timer { id: quit; interval: 100; onTriggered: Qt.exit(root.failures > 0 ? 1 : 0) }
    Timer {
        interval: 20
        running: !root.finished
        repeat: true
        onTriggered: {
            if (root.ticking || root.capturing) return
            root.ticking = true
            try { root.tick() } finally { root.ticking = false }
        }
    }
}
