//@ pragma ShellId flea-quicklook-firstkind-test

import QtQuick
import QtTest
import Quickshell
import Quickshell.Io

// One fresh window per leg: the cursor rests on the first file of a kind after a real key, then Space opens Quick Look, and the kind's compiled unit and Quick Look's own must be held by then.
// Sample output: "QLFK REST pdf step=1 d-doc.pdf unit=PdfViewer.qml held=PdfViewer.qml base=true libs=libQt6Pdf.so pss=61234 objects=700" is a rest that held exactly that kind's unit.
ShellRoot {
    id: root

    readonly property string uiDir: Quickshell.env("QLFK_UI")
    readonly property string leg: Quickshell.env("QLFK_LEG")
    // Steps "name|unit,..." in order: each is Down keys from the row before to that file, a rest, and a check that exactly the units rested on so far are held. A unit of "" is a file Quick Look holds nothing for.
    readonly property var steps: Quickshell.env("QLFK_STEPS").split(",").filter(function (s) { return s.length > 0 }).map(function (s) { var p = s.split("|"); return { name: p[0], unit: p[1] } })
    readonly property bool opens: Quickshell.env("QLFK_OPEN") === "1"
    readonly property int total: Number(Quickshell.env("QLFK_TOTAL"))
    // The row the window launches with its cursor on, and whether it is a folder.
    readonly property string firstRow: Quickshell.env("QLFK_FIRST")
    // No unit is held, and no warm is built, for a launch the user has not touched; the wait must outlast the 1000 ms unit timer.
    readonly property int idleMs: 3000
    readonly property int pollMs: 20
    readonly property int quietPolls: 12
    readonly property int watchdogMs: 25000
    // A step that holds nothing still waits this long after its rest, which outlasts the unit timer.
    readonly property int nothingMs: 3000

    property int stage: 0
    property int step: -1
    property int quiet: 0
    property int failures: 0
    property double stageAt: Date.now()
    property var keys: null
    property var seen: []
    property var unitsAtKey: null
    property double keyAt: 0
    // First-open cost census: what Space maps and builds on a first open and a reopen, plus the opens judged so far on this leg and the first open's cap stamp (the second open finds the kind built).
    property int opened: 0
    property int firstCapSeq: -1
    property bool cardExpected: false
    property int firstObjects: 0
    property var filesAtKey: []
    property int objectsAtKey: 0

    function log(line) { console.log("QLFK " + line) }
    function fail(why) { root.failures++; root.log("FAIL " + root.leg + ": " + why) }
    function pane() { return body.item ? body.item.currentPane : null }
    function pv() { return root.pane() ? root.pane().preview : null }
    function finish() {
        root.log("DONE leg=" + root.leg + " steps=" + Math.max(0, root.step + 1) + " failures=" + root.failures)
        Qt.exit(root.failures ? 1 : 0)
    }
    function find(item, type) {
        if (!item) return null
        if (String(item).indexOf(type) === 0) return item
        var kids = item.children || []
        for (var i = 0; i < kids.length; i++) {
            var found = root.find(kids[i], type)
            if (found) return found
        }
        return null
    }
    function warm() { return body.item ? root.find(body.item, "QuickLookWarm") : null }
    // A fresh blocking FileView per read: reload() on one view answers the previous read.
    function proc(path) {
        var f = Qt.createQmlObject('import Quickshell.Io\nFileView { blockLoading: true }', root, "read.qml")
        f.path = path
        var text = f.text()
        f.destroy()
        return text
    }
    // Sample input: "Pss:                 28438 kB" in /proc/self/smaps_rollup answers 28438.
    function pssKb() {
        var m = /Pss:\s+(\d+) kB/.exec(root.proc("/proc/self/smaps_rollup"))
        return m ? Number(m[1]) : -1
    }
    // The Qt and media libraries mapped now, for the memory numbers only: an image decode maps libQt6Pdf through its image plugin, so a mapped library does not say which unit was compiled.
    function libs() {
        var found = root.proc("/proc/self/maps").match(/lib(?:Qt6(?:Pdf|Multimedia)[A-Za-z]*|avcodec|avformat)\.so/g) || []
        return found.filter(function (n, i) { return found.indexOf(n) === i }).sort().join("+")
    }
    // Every distinct file path mapped now, as a sorted array, for the first-open cost census.
    // Sample input: the /proc/self/maps line "7f3a1c000000-7f3a1c2a4000 r--p 00000000 08:01 1234567    /usr/lib/libQt6Pdf.so.6.12.0" answers "/usr/lib/libQt6Pdf.so.6.12.0", the path after the first " /" with a trailing " (deleted)" cut.
    function mappedFiles() {
        var found = root.proc("/proc/self/maps").match(/ \/[^\n]*/g) || []
        var seenFiles = {}
        found.forEach(function (f) { seenFiles[f.trim().replace(/ \(deleted\)$/, "")] = true })
        return Object.keys(seenFiles).sort()
    }
    // Sample input: before ["/a", "/b"] and after ["/a", "/b", "/c"] answer ["/c"].
    function addedFiles(before, after) { return after.filter(function (f) { return before.indexOf(f) < 0 }) }
    // Every object under the window, the census the startup-objects suite takes.
    function objects() {
        var seenObjects = []
        function walk(o) {
            if (!o || seenObjects.indexOf(o) >= 0) return
            seenObjects.push(o)
            var groups = [o.children, o.data, o.resources]
            for (var g = 0; g < groups.length; g++) {
                var group = groups[g]
                if (!group) continue
                for (var i = 0; i < group.length; i++) walk(group[i])
            }
            if (o.contentItem) walk(o.contentItem)
            if (o.item) walk(o.item)
        }
        walk(window)
        return seenObjects.length
    }
    function indexOf(name) {
        var p = root.pane()
        for (var i = 0; i < p.total; i++) {
            var row = p.rowFor(i)
            if (row && row.n === name) return i
        }
        return -1
    }
    function press(key, count) {
        root.pane().listArea.forceActiveFocus()
        for (var i = 0; i < count; i++) root.keys.keyClick(key, Qt.NoModifier, -1)
    }
    // The units the steps up to and including n rest on, by file name, without the empty one.
    function expectedUnits(n) {
        var units = []
        for (var i = 0; i <= n; i++)
            if (root.steps[i].unit.length > 0 && units.indexOf(root.steps[i].unit) < 0) units.push(root.steps[i].unit)
        return units.sort()
    }
    function heldUnits() {
        var w = root.warm()
        return w ? Object.keys(w.kindUnits).sort() : []
    }
    function ready(unit) {
        return unit !== null && unit !== undefined && unit.status === Component.Ready
    }
    // Quick Look's own unit, the swap wrapper, and the kind's.
    function unitsReady(unit) {
        var w = root.warm()
        if (!w) return false
        return root.ready(w.previewUnit) && root.ready(w.swapUnit) && (unit.length === 0 || root.ready(w.kindUnits[unit]))
    }
    // A window that never rested on a PDF maps no QtQuick.Pdf, and one that never rested on a clip maps no QtMultimedia. libQt6Pdf alone is excluded: an image decode maps it through its image plugin.
    function judgeLibs(where, units, mapped) {
        if (units.indexOf("PdfViewer.qml") < 0 && mapped.indexOf("libQt6PdfQuick.so") >= 0)
            root.fail(where + " mapped libQt6PdfQuick.so without a PDF unit held: " + mapped)
        if (units.indexOf("PreviewMedia.qml") < 0 && mapped.indexOf("libQt6Multimedia") >= 0)
            root.fail(where + " mapped libQt6Multimedia without a clip unit held: " + mapped)
    }
    function judgeRest() {
        var s = root.steps[root.step]
        var held = root.heldUnits()
        var want = root.expectedUnits(root.step)
        var w = root.warm()
        var mapped = root.libs()
        root.log("REST " + root.leg + " step=" + (root.step + 1) + " " + s.name + " unit=" + s.unit + " held=" + held.join("+") + " base=" + (s.unit.length > 0 && root.unitsReady(s.unit))
            + " libs=" + mapped + " pss=" + root.pssKb() + " objects=" + root.objects())
        root.judgeLibs("step " + (root.step + 1), want, mapped)
        if (held.join("+") !== want.join("+"))
            root.fail("step " + (root.step + 1) + " held [" + held.join(" ") + "], want [" + want.join(" ") + "]")
        if (s.unit.length === 0 && (w.previewUnit !== null || w.swapUnit !== null))
            root.fail("step " + (root.step + 1) + " held Quick Look's own unit for " + s.name + ", which Quick Look opens from no unit")
        // A rest on a file with a unit builds the card closed, swap wrapper included, so the first Space only opens it; a file with no unit builds none until a unit file has been rested on, as the loader keeps a built card.
        root.cardExpected = root.cardExpected || s.unit.length > 0
        var look = root.pv()
        if (root.cardExpected && (look === null || look.active || !look.swapBuilt))
            root.fail("step " + (root.step + 1) + " rested on " + s.name + " without a closed card and swap wrapper built: card=" + (look !== null) + " swap=" + (look !== null && look.swapBuilt))
        if (!root.cardExpected && look !== null)
            root.fail("step " + (root.step + 1) + " built a Quick Look card at a rest on " + s.name + ", which has no unit")
        // Qt incubates cached rows asynchronously; compare visible delegates and every wrapper consistently on both opens.
        if (s.unit === "PreviewText.qml") {
            var code = root.find(look, "CodeLines")
            var view = root.find(code, "QQuickListView")
            if (!view) root.fail("the text pane has no scrolling view for the object census")
            else view.cacheBuffer = 0
        }
    }
    // Presses Space with the census taken first.
    function startOpen() {
        root.filesAtKey = root.mappedFiles()
        root.objectsAtKey = root.objects()
        root.stage = 4
        root.stageAt = Date.now()
        root.keyAt = Date.now()
        root.press(Qt.Key_Space, 1)
    }
    // Space on the rested file: every unit it needs is Ready before the key, and the key compiles nothing (the suite reads the compile trace between KEY and OPENED).
    function openIt() {
        var s = root.steps[root.step]
        var w = root.warm()
        root.unitsAtKey = { preview: root.ready(w.previewUnit), swap: root.ready(w.swapUnit), kind: root.ready(w.kindUnits[s.unit]) }
        root.log("KEY " + root.leg + " " + s.name + " preview=" + root.unitsAtKey.preview + " swap=" + root.unitsAtKey.swap + " kind=" + root.unitsAtKey.kind)
        if (!root.unitsAtKey.preview || !root.unitsAtKey.swap || !root.unitsAtKey.kind)
            root.fail("a unit was not Component.Ready before the Space: preview=" + root.unitsAtKey.preview + " swap=" + root.unitsAtKey.swap + " kind=" + root.unitsAtKey.kind)
        root.startOpen()
        root.log("KEYRETURNED " + root.leg + " active=" + (root.pv() !== null && root.pv().active) + " keyMs=" + (Date.now() - root.keyAt))
        if (root.pv() === null || !root.pv().active) root.fail("Space returned without Quick Look open")
    }

    // The cap counts from the key for a kind already built (armed before show() returns its build) and from after the kind's first build (armed after it, so the compile is outside the cap); openSeq orders the two with no clock.
    // Sample output: "CAP pdf open=1 cold seq=2 shownSeq=1 caps=0 early=false" is a first open whose cap armed after show() returned.
    function judgeCap(state) {
        var cap = state.revealCapStart
        var cold = root.opened === 1
        root.log("CAP " + root.leg + " open=" + root.opened + (cold ? " cold" : " warm") + " seq=" + (cap ? cap.seq : "none") + " shownSeq=" + state.shownSeq + " caps=" + state.revealCaps + " early=" + state.revealedEarly)
        if (!cap) { root.fail("open " + root.opened + " never started the reveal cap"); return }
        if (cold && cap.seq < state.shownSeq) root.fail("a kind's first build was inside the reveal cap: it armed at " + cap.seq + ", before show() returned at " + state.shownSeq)
        if (!cold && cap.seq > state.shownSeq) root.fail("a warm open's reveal cap armed at " + cap.seq + ", after show() returned at " + state.shownSeq + ", not from the key")
        if (!cold && cap.seq <= root.firstCapSeq) root.fail("the second open read the first open's cap stamp " + cap.seq)
        if (cold) root.firstCapSeq = cap.seq
        if (state.revealedEarly || state.revealCaps !== 0) root.fail("a fast source drew the loading frame: caps=" + state.revealCaps + " early=" + state.revealedEarly)
    }

    FloatingWindow {
        id: window
        implicitWidth: 1000
        implicitHeight: 700
        Loader {
            id: body
            anchors.fill: parent
            source: "file://" + root.uiDir + "/WindowBody.qml"
            onLoaded: item.host = window
            onStatusChanged: if (status === Loader.Error) { root.fail("WindowBody failed to load"); root.finish() }
        }
    }

    // A key can spin the event loop, which fires the poll inside its own handler; the nested turn waits for the outer one.
    property bool busy: false
    function pollStep() {
        var pane = root.pane()
        if (Date.now() - root.stageAt > root.watchdogMs) {
            var w = root.warm()
            root.fail("stage " + root.stage + " stalled in step " + (root.step + 1) + " warm=" + (w !== null) + " preview=" + (w ? w.previewUnit !== null : "") + " swap=" + (w ? w.swapUnit !== null : "")
                + " held=" + root.heldUnits().join("+") + " rested=" + (w ? w.prepare.rested : "") + " kindUnit=" + (w ? w.kindUnit : "") + " cursor=" + (pane ? pane.cursorIndex : -1))
            root.finish()
            return
        }
        if (root.stage === 0) {
            if (!pane || pane.listInFlight || pane.listingState !== "ready" || pane.total !== root.total) return
            var first = pane.rowFor(0)
            if (!first || first.n !== root.firstRow) { root.fail("the window launched on " + (first ? first.n : "no row") + ", want " + root.firstRow); root.finish(); return }
            root.keys = Qt.createQmlObject("import QtTest; TestEvent {}", pane.listArea)
            root.log("LAUNCH " + root.leg + " cursor=" + first.n + " pss=" + root.pssKb() + " objects=" + root.objects() + " libs=" + root.libs())
            root.stage = 1
            root.stageAt = Date.now()
            return
        }
        // The launch is untouched: no key has moved the cursor, so no warm is built and no unit compiled, however long the window stays settled.
        if (root.stage === 1) {
            if (Date.now() - root.stageAt < root.idleMs) return
            if (root.warm() !== null) root.fail("a launch with no key built a QuickLookWarm")
            else root.log("IDLE " + root.leg + " no warm after " + root.idleMs + " ms")
            root.judgeLibs("the idle launch", [], root.libs())
            if (root.steps.length === 0) { root.finish(); return }
            root.step = 0
            root.stage = 2
            return
        }
        if (root.stage === 2) {
            var s = root.steps[root.step]
            var at = root.indexOf(s.name)
            if (at < 0) { root.fail("no row named " + s.name); root.finish(); return }
            root.press(Qt.Key_Down, at - pane.cursorIndex)
            if (pane.cursorIndex !== at) { root.fail("Down keys left the cursor on " + pane.cursorIndex + ", want " + at); root.finish(); return }
            root.log("MOVE " + root.leg + " step=" + (root.step + 1) + " cursor=" + s.name + " icon=" + pane.cursorRow.i + " inputAt=" + (pane.inputAt > 0))
            root.stage = 3
            root.quiet = 0
            root.stageAt = Date.now()
            return
        }
        if (root.stage === 3) {
            var cur = root.steps[root.step]
            var held = root.warm()
            // A step that holds nothing waits out the unit timer instead of a unit.
            if (cur.unit.length === 0) {
                if (held === null || Date.now() - root.stageAt < root.nothingMs) return
            } else if (!root.unitsReady(cur.unit) || !held.prepare.rested) {
                root.quiet = 0
                return
            } else if (++root.quiet < root.quietPolls) {
                return
            }
            root.judgeRest()
            if (root.step + 1 < root.steps.length) {
                root.step++
                root.stage = 2
                return
            }
            if (root.opens) { root.openIt(); return }
            root.finish()
            return
        }
        if (root.stage === 4) {
            var look = root.pv()
            if (look === null || !look.revealed) return
            var state = look.openState()
            root.log("OPENED " + root.leg + " revealed=" + look.revealed + " landed=" + state.landed + " early=" + state.revealedEarly + " lookEmptyFrames=" + state.lookEmptyFrames + " ms=" + (Date.now() - root.keyAt) + " libs=" + root.libs() + " pss=" + root.pssKb())
            var added = root.addedFiles(root.filesAtKey, root.mappedFiles())
            var built = root.objects() - root.objectsAtKey
            root.log("COST " + root.leg + " open=" + (root.opened + 1) + " objects=+" + built + " mapped=" + added.length + " " + added.join(" "))
            var unit = root.steps[root.step].unit
            if (unit === "PreviewText.qml" && root.find(look, "CsvTable") !== null)
                root.fail("a text Quick Look built a CsvTable")
            if (root.opened === 0) {
                root.firstObjects = built
                // The media backend is a library the clip itself loads; every other kind maps nothing new in its first Space.
                if (added.length > 0 && unit !== "PreviewMedia.qml")
                    root.fail("the first Space on " + root.steps[root.step].name + " mapped " + added.length + " new file(s): " + added.join(" "))
            } else if (root.firstObjects > built) {
                root.fail("the first Space on " + root.steps[root.step].name + " built " + root.firstObjects + " objects, the reopen " + built + ": the first open builds what a rest should")
            }
            root.opened++
            root.judgeCap(state)
            root.stage = 5
            root.stageAt = Date.now()
            root.press(Qt.Key_Space, 1)
            return
        }
        if (root.stage === 5) {
            if (root.pv().visible) return
            if (root.pv().openState().revealCapStart !== null) root.fail("close left the reveal cap stamp of open " + root.opened)
            // The reopen is the second Space on the same file, after the first card is gone.
            if (root.opened < 2) { root.openIt(); return }
            root.finish()
            return
        }
    }

    Timer {
        id: poll
        interval: root.pollMs
        repeat: true
        running: true
        onTriggered: {
            if (root.busy) return
            root.busy = true
            try { root.pollStep() } finally { root.busy = false }
        }
    }
}
