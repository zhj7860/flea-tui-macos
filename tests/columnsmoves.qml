//@ pragma ShellId flea-columnsmoves-test
import QtQuick
import QtTest
import Quickshell
import "flea" as Flea
import "flea/js/Nav.js" as Nav
import "flea/js/Swap.js" as Swap
import "columnsframes.js" as Frames

// Every move runs through a real Pane and ColumnsArea; replies and assertions advance by rendered frames.
ShellRoot {
    id: root
    property var pane: null
    readonly property var area: pane ? pane.columnsArea : null
    property int frameNumber: 0
    property int caseIndex: 0
    property int phase: 0
    property int waited: 0
    property var queue: []
    property var samples: []
    property var before: null
    property int failures: 0
    property bool warmed: false
    property bool freezePeeks: false
    property bool freezeLists: false
    property var waitStep: null
    property bool samplingSupersede: false
    property int supersedeFrames: 0
    property bool supersedeBlank: false
    property double shownAt: 0
    readonly property int capSlackMs: 35 // Margin past the cap so the timer has fired before the read.
    readonly property int minSlackMs: 60 // Margin past cap plus minimum to prove hidden time cannot satisfy the shown minimum.
    readonly property int waitTimeoutMs: 3000 // Bound for one backend round trip before the control fails.
    readonly property string base: "/fixture/group/a"
    readonly property string railPath: Quickshell.env("HOME")
    readonly property var cases: ["parent-click", "grandparent-click", "third-click", "right", "enter", "left", "back", "chrome-up", "backspace", "rail", "arrow", "parent-file-click"]
    readonly property var dirs: root.makeDirs()

    function rows(names) {
        return names.map(function (n) { return { n: n, d: true, i: "folder", s: 4096, m: 1, p: 16877, k: 0 } })
    }
    function makeDirs() {
        var out = { "/": rows(["fixture"]), "/fixture": rows(["group", "other"]), "/fixture/group": rows(["a", "b", "file"]),
                    "/elsewhere": rows(["rail"]), "/elsewhere/rail": rows(["child", "second"]) }
        for (var path of [base, "/fixture/group/b", "/fixture/other", "/elsewhere/rail"])
            for (var suffix of ["", "/child", "/child/grand", "/child/grand/child", "/second", "/second/child"])
                out[path + suffix] = rows(suffix === "/child" ? ["grand", "second"] : ["child", "second"])
        out["/fixture/group/file"] = [{ n: "data.bin", d: false, i: "application-octet-stream", s: 36, m: 1, p: 33188, k: 1 }]
        out[railPath] = rows(["child", "second"])
        out[railPath + "/child"] = rows(["grand", "second"])
        var at = railPath
        while (at !== "/") {
            var parent = Nav.parentOf(at)
            if (!out[parent]) out[parent] = rows([Nav.leafOf(at)])
            at = parent
        }
        return out
    }

    FloatingWindow {
        id: win
        implicitWidth: 2100
        width: implicitWidth
        implicitHeight: 600
        color: Flea.Theme.color.background
        Item {
            id: host
            anchors.fill: parent
            Rectangle {
                width: 1; height: 1; y: host.height - 1; z: 100
                color: win.color
                NumberAnimation on x { from: 0; to: 1; duration: 1000; loops: Animation.Infinite }
            }
            Connections {
                target: host.Window.window
                function onAfterAnimating() { root.sample(); Qt.callLater(root.advance) }
            }
        }
        TestEvent { id: driver }
    }
    Flea.ChromeBar {
        id: chrome
        parent: host
        anchors { top: parent.top; left: parent.left; right: parent.right }
        path: root.pane ? root.pane.path : ""
        canGoBack: root.pane && root.pane.history.length > 0
        canGoUp: root.pane && root.pane.canGoUp
        viewMode: "columns"
        onBackRequested: root.pane.goBack()
        onUpRequested: root.pane.openParent()
    }
    Flea.Backend {
        id: probeBackend
        function send(one) {
            if (one.c === "list" || one.c === "peek" || one.c === "fsinfo" || one.c === "meta")
                root.queue = root.queue.concat([{ request: one, due: root.frameNumber + (one.c === "peek" ? 2 : 1) }])
        }
    }
    Component {
        id: paneComponent
        Flea.Pane { anchors.fill: parent; anchors.topMargin: chrome.height; backend: probeBackend }
    }

    function pump() {
        var blocked = function (one) { return root.freezePeeks && one.request.c === "peek" || root.freezeLists && one.request.c === "list" }
        var ready = queue.filter(function (one) { return one.due <= root.frameNumber && !blocked(one) })
        queue = queue.filter(function (one) { return one.due > root.frameNumber || blocked(one) })
        for (var item of ready) {
            var one = item.request, all = dirs[one.path] || []
            if (one.c === "list") {
                probeBackend.listed(all.length, 0, 0, one.path, -1, 0)
                probeBackend.rows(0, all, 0, ["Folder", "Data"], root.frameNumber, 0)
            } else if (one.c === "peek") {
                probeBackend.peeked(one.path, one.hidden, all.length, all.map(function (r) { return { n: r.n, d: r.d, i: r.i } }),
                               false, 0, one.hiddenLast, one.first, 2049, true, one.by || "", one.desc === true)
            } else if (one.c === "meta") probeBackend.metaResult({ token: one.token, row: one.row, w: 0, h: 0, ms: 0, rate: 0,
                entries: 0, unpacked: 0, names: [], lines: 0, partial: false, lfailed: false, afailed: false, target: "", targetdir: false, owner: "" })
            else probeBackend.fsInfo("ext4", 1000000, pane.listingPath, "local", true, false)
        }
    }
    function census() { return Frames.census(area) }
    function sample() {
        if (samplingSupersede && pane.path === "/elsewhere/rail") {
            supersedeFrames++
            var columns = census().columns
            if (!area.landing.loading(area.parentPath) && (!columns[0] || columns[0].rows === 0)) supersedeBlank = true
        }
        if (phase !== 3 || !area) return
        var state = census()
        samples.push(state)
        console.log("COLUMNMOVES FRAME " + cases[caseIndex] + " " + JSON.stringify(state))
    }
    function settled() {
        if (!pane || pane.listInFlight || queue.length || !area.thirdReady || !area.shownHasRow) return false
        if (area.cursorIsDir && area.shownChildPath !== area.childPath) return false
        if (!area.cursorIsDir && !area.previewColumn.ready) return false
        var state = census()
        return state.columns.length === area.columnCount - (area.cursorIsDir ? 0 : 1) && state.columns.every(function (col) { return col.rows > 0 })
    }
    function press(item) {
        if (!item) throw new Error("pointer target is missing")
        driver.mousePress(item, 20, item.height / 2, Qt.LeftButton, Qt.NoModifier, 0)
        driver.mouseRelease(item, 20, item.height / 2, Qt.LeftButton, Qt.NoModifier, 0)
    }
    function click(item) { if (!item || !item.row) throw new Error("pointer target has no row"); press(item) }
    function issue() {
        var name = cases[caseIndex]
        before = census(); samples = []; phase = 3; waited = 0
        Flea.ViewState.changeKey("keys", name === "right" || name === "left" ? "mac" : "default")
        pane.focusView = "list"
        area.forceActiveFocus()
        if (name === "parent-click") click(area.parentItemAt(1))
        else if (name === "parent-file-click") click(area.parentItemAt(2))
        else if (name === "grandparent-click") click(area.grandparentItemAt(1))
        else if (name === "third-click") click(area.childItemAt(0))
        else if (name === "right") driver.keyClick(Qt.Key_Right, Qt.NoModifier, 0)
        else if (name === "enter") driver.keyClick(Qt.Key_Return, Qt.NoModifier, 0)
        else if (name === "left") driver.keyClick(Qt.Key_Left, Qt.NoModifier, 0)
        else if (name === "back") press(chrome.buttonFor("arrow-left"))
        else if (name === "chrome-up") press(chrome.buttonFor("arrow-up"))
        else if (name === "backspace") driver.keyClick(Qt.Key_Backspace, Qt.NoModifier, 0)
        else if (name === "rail") press(pane.sidebar.railItemFor(0))
        else driver.keyClick(Qt.Key_Down, Qt.NoModifier, 0)
    }
    function judge() {
        var after = census(), bad = [], readingFrames = 0
        var name = cases[caseIndex], expected = ["left", "back", "chrome-up", "backspace", "arrow"].indexOf(name) >= 0 ? base
            : name === "parent-click" ? "/fixture/group/b" : name === "parent-file-click" ? "/fixture/group/file" : name === "grandparent-click" ? "/fixture/other"
            : name === "third-click" ? base + "/child/grand" : name === "rail" ? railPath : base + "/child"
        if (pane.path !== expected) bad.push("path=" + pane.path + " expected=" + expected)
        if (name === "arrow" && pane.cursorIndex !== 1) bad.push("cursor=" + pane.cursorIndex + " expected=1")
        for (var frame = 0; frame < samples.length; frame++) {
            var state = samples[frame]
            for (var i = 0; i < before.columns.length; i++) {
                // The listing's explicit capped reading state is allowed; an ancestor or third-column hole never is.
                if (i === before.columns.length - 2 && state.loading && state.listing.fellBack) { readingFrames++; continue }
                if (before.columns[i].rows > 0 && after.columns[i] && after.columns[i].rows > 0
                        && (!state.columns[i] || state.columns[i].rows === 0)) bad.push("frame=" + (frame + 1) + " column=" + i + " rows=0")
            }
            if (before.hasThird && after.hasThird && !state.hasThird) bad.push("frame=" + (frame + 1) + " third=empty")
            if (state.hasThird && state.third !== "folder" && !state.preview.row && !state.capturing && !state.holding)
                bad.push("frame=" + (frame + 1) + " preview=empty")
        }
        if (!samples.length) bad.push("no rendered frame sampled")
        if (bad.length) failures++
        console.log("COLUMNMOVES " + (bad.length ? "FAIL " : "PASS ") + cases[caseIndex] + ": every non-empty column stays non-empty; " + (bad.join("; ") || "frames=" + samples.length) + " reading=" + readingFrames)
        caseIndex++; phase = 1; waited = 0
        if (caseIndex === cases.length) {
            if (failures || !area.landing) finish()
            else phase = 4
        }
    }
    function control(ok, label) {
        if (!ok) failures++
        console.log("COLUMNMOVES CONTROL " + (ok ? "PASS " : "FAIL ") + label)
    }
    function finish() { console.log("COLUMNMOVES DONE " + cases.length + " moves, " + failures + " failed"); Qt.quit() }
    function until(label, condition, then) {
        waitStep = { label: label, condition: condition, then: then, deadline: Date.now() + waitTimeoutMs }
    }
    Timer {
        interval: 4; running: root.waitStep !== null; repeat: true
        onTriggered: {
            var step = root.waitStep
            if (step.condition()) { root.waitStep = null; step.then() }
            else if (Date.now() >= step.deadline) { root.waitStep = null; root.control(false, step.label + " timed out"); root.finish() }
        }
    }
    function findItem(item, predicate) {
        if (predicate(item)) return item
        if (item.children !== undefined)
            for (var child of item.children) { var found = findItem(child, predicate); if (found) return found }
        return null
    }
    function supersede() {
        freezePeeks = true
        pane.open("/elsewhere/rail")
        until("first landing with a pending ancestor", function () { return !pane.listInFlight && pane.path === "/elsewhere/rail" }, function () {
            var drawn = area.rowsFor(area.parentPath)
            control(area.landing.waiting(area.parentPath) && drawn.length > 0, "first landing holds its pending ancestor")
            freezeLists = true
            pane.open("/fixture/other")
            control(area.rowsFor(area.parentPath).length > 0, "superseding request keeps the on-screen ancestor")
            control(area.landing.held["/fixture"] && area.landing.held["/fixture"].rows === drawn, "new hold takes the rows the old slot draws")
            samplingSupersede = true
            until("two superseding frames", function () { return supersedeFrames >= 2 }, function () {
                control(!supersedeBlank, "every superseding frame keeps the on-screen ancestor until the swap or cap")
                samplingSupersede = false; freezeLists = false; freezePeeks = false
                until("superseding landing settles", settled, function () {
                    control(pane.path === "/fixture/other" && area.rowsFor(area.parentPath)[0].n === "group", "superseding landing draws the new ancestor")
                    timedFallback()
                })
            })
        })
    }
    function timedFallback() {
        freezePeeks = true
        var began = Date.now()
        pane.open("/elsewhere/rail")
        until("timed fallback lands", function () { return !pane.listInFlight && pane.path === "/elsewhere/rail" }, function () {
            var column = findItem(area, function (item) { return item.viewport !== undefined && item.pane === null && item.visible && item.width > 0 })
            control(column !== null && area.rowsFor(area.parentPath).length > 0, "pending ancestor starts with held rows")
            if (!column) { finish(); return }
            column.visible = false
            until("past the real cap", function () { return Date.now() - began >= Swap.CAP_MS + capSlackMs }, function () {
                control(area.landing.loading(area.parentPath) && area.rowsFor(area.parentPath).length === 0, "real cap timer replaces held rows with reading")
                var mark = findItem(column, function (item) { return item.shown !== undefined && item.heldOff !== undefined })
                if (!mark) { control(false, "cap builds the LoadingState"); finish(); return }
                mark.shownChanged.connect(function () { if (mark.shown) root.shownAt = Date.now() })
                until("minimum passes while the mark is hidden", function () { return Date.now() - began >= Swap.CAP_MS + Swap.MIN_SHOW_MS + minSlackMs }, function () {
                    column.visible = true
                    control(mark.shown && shownAt > 0, "LoadingState reports when its mark is shown")
                    freezePeeks = false; pump()
                    control(area.landing.loading(area.parentPath) && area.landing.held[area.parentPath] && area.landing.held[area.parentPath].ready,
                            "reply during the shown minimum stays covered")
                    until("real minimum timer releases the reply", function () { return !area.landing.waiting(area.parentPath) }, function () {
                        control(Date.now() - shownAt >= Swap.MIN_SHOW_MS && !column.loadingRows && area.rowsFor(area.parentPath).length > 0,
                                "real minimum timer releases only after the mark stands MIN_SHOW_MS")
                        loadingSupersede()
                    })
                })
            })
        })
    }
    function loadingSupersede() {
        pane.open("/fixture/other")
        until("reading supersede starts from a settled listing", settled, function () {
            freezePeeks = true
            pane.open("/elsewhere/rail")
            var column = findItem(area, function (item) { return item.viewport !== undefined && item.pane === null && item.visible && item.width > 0 })
            var appearedAt = 0
            column.loadingShown.connect(function (shown) { if (shown && appearedAt === 0) appearedAt = Date.now() })
            until("ancestor's real cap shows reading", function () {
                var mark = findItem(column, function (item) { return item.shown !== undefined && item.heldOff !== undefined })
                return !pane.listInFlight && column.loadingRows && mark && mark.shown
            }, function () {
                pane.open("/fixture/other")
                control(column.loadingRows, "superseding request keeps the shown reading state")
                until("reading supersede lands", function () { return !pane.listInFlight && pane.path === "/fixture/other" }, function () {
                    var mark = findItem(column, function (item) { return item.shown !== undefined && item.heldOff !== undefined })
                    control(column.loadingRows && mark && mark.shown, "superseding landing carries the shown reading state")
                    freezePeeks = false
                    until("reading supersede's reply lands", settled, function () {
                        control(Date.now() - appearedAt >= Swap.MIN_SHOW_MS && !column.loadingRows && area.rowsFor(area.parentPath).length > 0,
                                "superseding reading state keeps its shown minimum before releasing to the new rows")
                        noCarryClears()
                    })
                })
            })
        })
    }
    function noCarryClears() {
        freezePeeks = true
        pane.open("/elsewhere/rail")
        until("no-carry landing holds its drawn column", function () { return !pane.listInFlight && pane.path === "/elsewhere/rail" }, function () {
            var heldPaths = Object.keys(area.landing.held)
            control(heldPaths.length > 0, "no-carry setup holds a drawn column")
            if (!heldPaths.length) { finish(); return }
            var heldPath = heldPaths[0]
            area.visible = false
            pane.open("/fixture/other")
            until("no-carry hidden hop lands", function () { return !pane.listInFlight && pane.path === "/fixture/other" }, function () {
                pane.open("/elsewhere/rail")
                until("no-carry hidden return lands", function () { return !pane.listInFlight && pane.path === "/elsewhere/rail" }, function () {
                    area.visible = true
                    control(area.landing.previous === null, "hidden navigations keep no previous landing")
                    control(!area.landing.waiting(heldPath), "hidden navigations wait on no stale held row")
                    freezePeeks = false; pump()
                    until("no-carry landing settles", settled, noCarrySingleStep)
                })
            })
        })
    }
    function noCarrySingleStep() {
        freezePeeks = true
        pane.open("/fixture/other")
        until("single-step no-carry landing holds its drawn column", function () { return !pane.listInFlight && pane.path === "/fixture/other" }, function () {
            var heldPath = area.parentPath
            control(area.landing.target === pane.path && area.landing.waiting(heldPath), "single-step no-carry setup holds its current landing")
            area.landing.begin(null, [])
            control(area.landing.previous === null, "begin with no carry keeps no previous landing")
            control(!area.landing.waiting(heldPath), "begin with no carry waits on nothing")
            freezePeeks = false; pump()
            until("single-step no-carry landing settles", settled, finish)
        })
    }
    function advance() {
        frameNumber++; pump(); waited++
        if (phase >= 6) return
        if (waited > 300) { console.log("COLUMNMOVES FAIL stalled " + cases[caseIndex] + " phase=" + phase); Qt.quit(); return }
        if (phase === 0) {
            Flea.ViewState.state = { view: "columns", keys: "default", columnsLimit: 3 }
            pane = paneComponent.createObject(host)
            phase = 1
        }
        if (phase === 1) {
            Flea.ViewState.changeKey("columnsLimit", cases[caseIndex] === "grandparent-click" ? 4 : 3)
            pane.open(base)
            phase = 2; waited = 0
        } else if (phase === 2 && settled() && waited >= 4) {
            if (!warmed) {
                warmed = true; click(area.parentItemAt(1)); phase = 1; waited = 0
            } else if (["left", "back", "chrome-up", "backspace"].indexOf(cases[caseIndex]) >= 0 && pane.path === base) {
                pane.open(base + "/child"); waited = 0
            } else issue()
        } else if (phase === 3 && settled() && waited >= 5) judge()
        else if (phase === 4) {
            dirs[area.parentPath] = dirs[area.parentPath].concat(rows(["fresh"]))
            area.denials[area.peekKey(area.parentPath)] = 0
            probeBackend.changed(area.parentPath)
            control(queue.some(function (one) { return one.request.c === "peek" && one.request.path === area.parentPath }), "changed re-asks the kept parent")
            pane.open(base)
            phase = 5; waited = 0
        } else if (phase === 5 && settled()) {
            control(area.rowsFor(area.parentPath).some(function (row) { return row.n === "fresh" }), "watching refresh survives a lateral landing and updates in place")
            control(area.deniedMode(area.parentPath) === -1, "successful refresh removes the previous denial")
            phase = 6; supersede()
        }
    }
}
