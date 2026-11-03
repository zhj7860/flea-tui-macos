//@ pragma ShellId flea-preview-decode-test

import Quickshell
import QtQuick
import Quickshell.Io

// tests/preview-decode.sh's harness: the real SelectionPreview swept and rested over a stub pane, then the real PreviewImage.
ShellRoot {
    id: shell

    readonly property string uiDir: Quickshell.env("PREVIEW_UI")
    readonly property string photoDir: Quickshell.env("PREVIEW_PHOTOS")
    readonly property int sweepCount: 50
    readonly property int restRow: 51

    property int movesLeft: 0
    // The interim phase's expected original size, read by the meta stub when Quick Look asks.
    property var metaWH: [640, 480]
    property string interimPhase: ""
    property string interimOrig: ""
    property string interimCache: ""
    property string pendingInterim: ""
    // The interim phase's cursor row, naming the shown file the way production always does.
    property int interimRowOverride: -1
    // e81f-r3 guard overrides: guardMap names drifted rows, guardAskLog every ask, guardHold parks replies.
    property var guardMap: ({})
    property var guardAskLog: []
    property bool guardHold: false
    // The Columns phase's row: a model file the backend offers no thumbnail for.
    property int modelRow: -1
    // The Columns phase's second row: a model file whose thumbnail is on offer and has not landed.
    property int pendingRow: -1

    function log(line) { console.log("PREVIEW " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    // Sentinel handshake: touch runs as a Process so CREATE lands before the next open.
    Process {
        id: markProc
        property string touchName: ""
        command: ["touch", shell.photoDir + "/sentinel-" + touchName]
        onExited: function(exitCode) {
            if (exitCode !== 0) { shell.log("FAIL marker " + touchName); shell.quit(); return }
            shell.onMarkDone(touchName)
        }
    }
    function onMarkDone(name) {
        if (name === "sweep") { shell.log("SWEEP START"); shell.movesLeft = shell.sweepCount; moveTimer.restart() }
        else if (name === "rest") {
            stub.cursorIndex = shell.restRow
            shell.log("REST START")
            restPoll.restart()
        }
        else if (name === "done") {
            shell.log("DONE")
            quickLook.active = true
            shell.lookAt("portrait", shell.photoDir + "/portrait.jpg")
        }
        else if (name === "istart-held" || name === "istart-heldbad") { heldKick.restart() }
        else if (name.indexOf("istart-") === 0) { shell.openAfterMark() }
        else if (name === "iend-small") { shell.beginInterim("large", "seed0.jpg", "thumb.png", 640, 480) }
        else if (name === "iend-large") { shell.beginHeld("held", "big.png", "smallcache.png", 6016, 3900) }
        else if (name === "iend-held") { shell.beginHeld("heldbad", "big2.png", "missing-cache.png", 6016, 3900) }
        else if (name === "iend-heldbad") { shell.runGuards() }
    }
    function openAfterMark() {
        quickPreview.item.open(shell.photoDir + "/" + shell.interimOrig, "image-x-generic", 1000, "", shell.photoDir + "/" + shell.interimCache)
        interimPoll.waited = 0
        interimPoll.restart()
    }

    // Backend row shape: text start row, fifty sweep photos, big PNG rest row, interim override names shown file.
    function rowFor(i) {
        if (shell.guardMap.hasOwnProperty(i))
            return { n: shell.guardMap[i], d: false, t: true, s: 1000, m: 1000, p: 33188, i: "image-x-generic" }
        if (i === shell.modelRow)
            return { n: "mount.stl", d: false, t: false, s: 1000, m: 1000, p: 33188, i: "image-x-generic" }
        if (i === shell.pendingRow)
            return { n: "pending.stl", d: false, t: true, s: 1000, m: 1000, p: 33188, i: "image-x-generic" }
        if (i === shell.interimRowOverride && shell.interimOrig !== "")
            return { n: shell.interimOrig, d: false, t: shell.interimRowT, s: 1000, m: 1000, p: 33188, i: "image-x-generic" }
        if (i < 0 || i > shell.restRow) return null
        if (i === 0) return { n: "note.txt", d: false, t: false, s: 64, m: 1000, p: 33188, i: "text-x-generic" }
        if (i === shell.restRow) return { n: "big.png", d: false, t: true, s: 2000000, m: 1051, p: 33188, i: "image-x-generic" }
        return { n: "s" + (i - 1) + ".jpg", d: false, t: true, s: 100000 + i, m: 1000 + i, p: 33188, i: "image-x-generic" }
    }

    // The stub backend answers meta for every row and asks for no thumbnail, since every row already has one.
    Item {
        id: stubBackend
        signal metaResult(var message)
        signal meta(int row, int w, int h, int orient)
        property int nextToken: 0
        property var pending: []
        property var thumbCalls: []
        function askMeta(index, text, media, archive) {
            shell.guardAskLog.push(index)
            nextToken += 1
            pending.push({ token: nextToken, index: index })
            metaTimer.restart()
            return nextToken
        }
        function thumb(rows, cacheOnly) { thumbCalls.push({ rows: rows, cacheOnly: cacheOnly === true }) }
    }

    // Local disk answers in milliseconds, so a settled selection is never left waiting on a reply.
    Timer {
        id: metaTimer
        interval: 5
        onTriggered: {
            if (shell.guardHold) return
            for (var i = 0; i < stubBackend.pending.length; i++) {
                var req = stubBackend.pending[i]
                var big = req.index === shell.restRow
                stubBackend.metaResult({ token: req.token, w: big ? 6016 : shell.metaWH[0], h: big ? 3900 : shell.metaWH[1] })
                stubBackend.meta(req.index, big ? 6016 : shell.metaWH[0], big ? 3900 : shell.metaWH[1], 1)
            }
            stubBackend.pending = []
        }
    }

    // The stub pane says local btrfs, so a rule that read originals on a local disk would fire here.
    Item {
        id: stub
        property int cursorIndex: -1
        property string path: ""
        property int settleMs: 120
        property var thumbState: ({ file: {} })
        property string fsPath: ""
        property string fsName: "btrfs"
        // The fsinfo line has named the class, and "" is local, which ui/Pane.qml holds unknown until it lands.
        property string storageClass: ""
        property bool storageKnown: true
        property bool listInFlight: false
        property var kindNames: []
        property var preview: ({ active: false })
        // ui/Pane.qml's own bound, so the miss and remember rules cap the map the same way.
        property int thumbCap: 240
        property var backend: stubBackend
        property var listArea: ({ forceActiveFocus: function () {} })
        signal rowsChanged()
        signal selectionVersionChanged()
        function rowFor(i) { return shell.rowFor(i) }
        function join(base, name) { return base + "/" + name }
        function selectionCount() { return 1 }
        function selectedIndices() { return [stub.cursorIndex] }
    }

    FloatingWindow {
        implicitWidth: 800
        implicitHeight: 600
        color: "#303030"

        Rectangle {
            id: host
            color: "#101315"
            x: 20
            y: 20
            width: 760
            height: 560

            Loader {
                id: loader
                anchors.fill: parent
                source: "file://" + shell.uiDir + "/SelectionPreview.qml"
                onLoaded: {
                    item.pane = stub
                    // ui/Pane.qml records what the column asks, so Quick Look sees that row as asked.
                    item.thumbsApplied.connect(function (work) {
                        if (!shell.thumbGate) shell.wireThumbGate()
                        stub.thumbState = shell.thumbGate.applyTo(stub.thumbState, work)
                    })
                    shell.begin()
                }
                onStatusChanged: if (status === Loader.Error) { shell.log("FAIL the preview did not load"); shell.quit() }
            }
        }

        // Quick Look's box on this test, the Columns frame's own 754x471, loaded only after the column's windows close.
        Loader {
            id: quickLook
            x: 20
            y: 20
            width: 754
            height: 471
            active: false
            source: "file://" + shell.uiDir + "/PreviewImage.qml"
            onStatusChanged: if (status === Loader.Error) { shell.log("FAIL Quick Look's image pane did not load"); shell.quit() }
        }

        // The production overlay, for the interim phase: the cached thumbnail under the full decode.
        Loader {
            id: quickPreview
            x: 20
            y: 20
            width: 754
            height: 471
            active: false
            source: "file://" + shell.uiDir + "/Preview.qml"
            onLoaded: {
                item.pane = stub
                if (shell.pendingInterim !== "") shell.openInterim()
            }
            onStatusChanged: if (status === Loader.Error) { shell.log("FAIL Quick Look did not load"); shell.quit() }
        }
    }

    // Every row pre-thumbnailed, so a load during the sweep opens its cache file and the sweep window counts it.
    function begin() {
        stub.path = shell.photoDir
        stub.fsPath = shell.photoDir
        var files = {}
        for (var i = 1; i < shell.restRow; i++) files[i] = shell.photoDir + "/t" + (i - 1) + ".png"
        files[shell.restRow] = shell.photoDir + "/t50.png"
        stub.thumbState = ({ file: files })
        stub.cursorIndex = 0
        shell.log("READY pid=" + Quickshell.processId)
        settleTimer.restart()
    }

    Timer {
        id: settleTimer
        interval: 400
        // Text row loaded, so sweep window opens on sweep alone; touch handshake orders CREATE first.
        onTriggered: { markProc.touchName = "sweep"; markProc.running = true }
    }

    // Fifty cursor moves at key-repeat rate: the first loads at once after idle, the rest trail one settle.
    Timer {
        id: moveTimer
        interval: 30
        repeat: true
        onTriggered: {
            stub.cursorIndex = shell.sweepCount + 1 - shell.movesLeft
            shell.movesLeft -= 1
            if (shell.movesLeft <= 0) {
                stop()
                shell.log("SWEEP END")
                markProc.touchName = "rest"
                markProc.running = true
            }
        }
    }

    // The rest has loaded once the column holds a path; whatever it opens is what the done window counts.
    Timer {
        id: restPoll
        interval: 10
        repeat: true
        property int waited: 0
        onTriggered: {
            waited += interval
            if (loader.item.path !== "") {
                stop()
                shell.log("RESTED")
                doneTimer.restart()
            } else if (waited > 1000) {
                stop()
                shell.log("FAIL the rest never loaded")
                shell.quit()
            }
        }
    }

    // Two seconds, longer than the 0.3.5 candidate's 580 ms sharp decode, then Quick Look's half.
    Timer {
        id: doneTimer
        interval: 2000
        onTriggered: {
            markProc.touchName = "done"
            markProc.running = true
        }
    }

    // Final picture finder: only it sets autoTransform true, interim leaves false.
    function picture() {
        var kids = quickLook.item ? quickLook.item.children : []
        for (var i = 0; i < kids.length; i++)
            if (kids[i].autoTransform === true) return kids[i]
        return null
    }

    property string looking: ""
    property string lookingName: ""
    function lookAt(label, path) {
        shell.looking = label
        shell.lookingName = path.substring(path.lastIndexOf("/") + 1)
        quickLook.item.path = path
        lookPoll.waited = 0
        lookPoll.restart()
    }

    // Sample log line: "PREVIEW QL portrait decoded=400x600 drawn=314x471", the turned photo decoded whole and upright, drawn at the exact fit.
    Timer {
        id: lookPoll
        interval: 10
        repeat: true
        property int waited: 0
        onTriggered: {
            waited += interval
            var img = shell.picture()
            // The source check keeps the portrait's Ready from answering for the small PNG.
            if (quickLook.item && quickLook.item.status === "image" && img && String(img.source).endsWith("/" + shell.lookingName)) {
                stop()
                shell.log("QL " + shell.looking + " decoded=" + img.implicitWidth + "x" + img.implicitHeight
                          + " drawn=" + Math.round(img.width) + "x" + Math.round(img.height))
                if (shell.looking === "portrait") shell.lookAt("banner", shell.photoDir + "/banner.png")
                else if (shell.looking === "banner") shell.lookAt("small", shell.photoDir + "/small.png")
                else shell.beginInterim("small", "small.png", "smallcache.png", 120, 68)
            } else if (waited > 5000) {
                stop()
                shell.log("FAIL Quick Look never drew " + shell.looking + " (status " + (quickLook.item ? quickLook.item.status : "none") + ")")
                shell.quit()
            }
        }
    }

    // Interim opens the production overlay the way Space does: cache under full decode, each once.
    function beginInterim(label, orig, cache, w, h) {
        shell.interimPhase = label
        shell.interimOrig = orig
        shell.interimCache = cache
        shell.metaWH = [w, h]
        shell.interimRowOverride = 7
        stub.cursorIndex = 7
        shell.pendingInterim = label
        if (quickPreview.status === Loader.Ready) shell.openInterim()
        else quickPreview.active = true
    }

    function openInterim() {
        shell.pendingInterim = ""
        // Touch handshake queues CREATE before the open, so the count window holds every open.
        markProc.touchName = "istart-" + shell.interimPhase
        markProc.running = true
    }

    function findAll(item, out) {
        var kids = item ? item.children : []
        for (var i = 0; i < kids.length; i++) {
            out.push(kids[i])
            shell.findAll(kids[i], out)
        }
        return out
    }

    // Interim/final finder: interim keeps autoTransform false, final sets true, sources differ.
    function interimPair() {
        var all = shell.findAll(quickPreview.item, [])
        var inter = null, finalImage = null
        for (var i = 0; i < all.length; i++) {
            var src = String(all[i].source || "")
            if (all[i].autoTransform !== undefined && src.endsWith("/" + shell.interimOrig)) finalImage = all[i]
            else if (src.endsWith("/" + shell.interimCache)) inter = all[i]
        }
        return [inter, finalImage]
    }

    function geom(item) {
        return Math.round(item.x) + "," + Math.round(item.y) + "," + Math.round(item.width) + "," + Math.round(item.height)
    }

    // The interim sits above the ground and below the final picture as siblings.
    function stackOk() {
        var pair = shell.interimPair()
        if (!pair[0] || !pair[1] || pair[0].parent !== pair[1].parent) return false
        var kids = pair[0].parent.children
        var gi = -1, ii = -1, fi = -1
        for (var i = 0; i < kids.length; i++) {
            if (kids[i] === pair[0]) ii = i
            else if (kids[i] === pair[1]) fi = i
            else if (gi < 0 && kids[i].source === undefined && kids[i].color !== undefined) gi = i
        }
        return gi >= 0 && gi < ii && ii < fi && kids[gi].z === pair[0].z && pair[0].z === pair[1].z
    }

    // Sample log line: "PREVIEW INTERIM small irect=317,201,120,68 frect=317,201,120,68".
    Timer {
        id: interimPoll
        interval: 10
        repeat: true
        property int waited: 0
        onTriggered: {
            waited += interval
            var pair = shell.interimPair()
            var done = quickPreview.item && quickPreview.item.status === "image" && quickPreview.item.imageW > 0
                && pair[0] && pair[0].status === Image.Ready && pair[1]
            if (done) {
                stop()
                shell.log("INTERIM " + shell.interimPhase + " irect=" + shell.geom(pair[0]) + " frect=" + shell.geom(pair[1]))
                shell.log("INTERIMSTACK " + shell.interimPhase + " " + (shell.stackOk() ? "ok" : "bad"))
                markProc.touchName = "iend-" + shell.interimPhase
                markProc.running = true
            } else if (waited > 8000) {
                stop()
                shell.log("FAIL the interim never settled for " + shell.interimPhase)
                shell.quit()
            }
        }
    }

    // A slow original lets the interim settle while the final decodes; held opens the production overlay fresh and heldbad the built one, the two orders Preview.qml binds the path and thumbnail in.
    function beginHeld(label, orig, cache, w, h) {
        shell.interimPhase = label
        shell.interimOrig = orig
        shell.interimCache = cache
        shell.metaWH = [w, h]
        shell.interimRowOverride = 7
        stub.cursorIndex = 7
        if (quickPreview.status !== Loader.Ready) {
            shell.log("FAIL Quick Look left before the held phase")
            shell.quit()
            return
        }
        markProc.touchName = "istart-" + label
        markProc.running = true
    }
    // After the touch handshake, so the CREATE lands first and the open meets a settled loader.
    Timer {
        id: heldKick
        interval: 100
        repeat: false
        onTriggered: {
            // Every held open starts from a fresh item, the way Space closes before it opens.
            quickPreview.item.close()
            quickPreview.item.open(shell.photoDir + "/" + shell.interimOrig, "image-x-generic",
                1000, "", shell.photoDir + "/" + shell.interimCache)
            // The interim decodes at once, so the open lands settled: Ready with a cache file, Error without one.
            var interim = shell.interimPair()[0]
            var wantReady = shell.interimPhase !== "heldbad"
            var settled = interim && interim.status !== Image.Loading
            if (!settled || (wantReady && interim.status !== Image.Ready) || quickPreview.item.surfaceItem().pictureItem.status !== Image.Null) {
                shell.log("FAIL the " + shell.interimPhase + " phase interim was not " + (wantReady ? "Ready" : "settled") + " beside the Null final at open")
                shell.quit()
                return
            }
            heldPoll.waited = 0
            heldPoll.restart()
        }
    }

    // Sample log line: "PREVIEW HELD held shown=true ready=true status=loading", sampled while the final still decodes.
    Timer {
        id: heldPoll
        interval: 10
        repeat: true
        property int waited: 0
        onTriggered: {
            waited += interval
            var qp = quickPreview.item
            var pair = shell.interimPair()
            var settled = pair[0] && (pair[0].status === Image.Ready || pair[0].status === Image.Error)
            if (qp && pair[0] && pair[1] && qp.imageW > 0 && qp.status === "loading" && settled) {
                stop()
                shell.log("HELD " + shell.interimPhase + " shown=" + qp.interimShown + " ready=" + qp.lookReady + " status=" + qp.status)
                if (shell.interimPhase === "held") shell.reopenCheck()
                else {
                    markProc.touchName = "iend-" + shell.interimPhase
                    markProc.running = true
                }
            } else if (waited > 8000) {
                stop()
                shell.log("FAIL the held phase never settled for " + shell.interimPhase)
                shell.quit()
            }
        }
    }

    // The reopen while the big final still decodes: close, open with the same arguments, and the interim is Ready in that same turn.
    property int reopenCaps: 0
    property double reopenT0: 0
    function reopenCheck() {
        var qp = quickPreview.item
        shell.reopenCaps = qp.revealCaps
        shell.reopenT0 = Date.now()
        qp.close()
        qp.open(shell.photoDir + "/" + shell.interimOrig, "image-x-generic",
            1000, "", shell.photoDir + "/" + shell.interimCache)
        var interim = shell.interimPair()[0]
        if (!interim || interim.status !== Image.Ready) {
            shell.log("FAIL the reopen interim was not Ready in its own turn")
            shell.quit()
            return
        }
        shell.reopenLater()
    }
    // The reopen lands on the interim, never through the cap: chained callLater ticks until landed, with a time bound so a missed landing still fails.
    function reopenLater() {
        Qt.callLater(function() {
            var qp = quickPreview.item
            if (qp && qp.landed && qp.revealCaps === shell.reopenCaps) {
                shell.log("REOPEN held")
                markProc.touchName = "iend-held"
                markProc.running = true
            } else if (!qp || qp.revealCaps !== shell.reopenCaps || Date.now() - shell.reopenT0 > 2000) {
                shell.log("FAIL the reopen did not land without the cap landed=" + (qp && qp.landed) + " caps=" + (qp && qp.revealCaps))
                shell.quit()
            } else {
                shell.reopenLater()
            }
        })
    }

    // e81f-r3: guards 1 to 4 pin the drifted reply, the cursor re-ask, the quiet no-match and capture-first.
    function guardShow(shown, row) {
        stubBackend.pending = []
        shell.guardAskLog = []
        quickPreview.item.show(shell.photoDir + "/" + shown, "image-x-generic",
            1000, "", shell.photoDir + "/smallcache.png", row)
    }
    function guardEnd() {
        stubBackend.pending = []
        metaTimer.stop()
    }
    function runGuards() {
        shell.guardHold = true
        // Guard 1: reply-time drift. Row 7 names guard1.jpg at the ask; an insert
        // above it moves s6.jpg there before the held reply lands with other sizes.
        shell.guardMap = ({ 7: "guard1.jpg" })
        stub.cursorIndex = 7
        shell.guardShow("guard1.jpg", 7)
        var g1asked = shell.guardAskLog.length === 1 && shell.guardAskLog[0] === 7
        shell.guardMap = ({ 7: "s6.jpg" })
        stubBackend.meta(7, 999, 888, 1)
        var g1kept = quickPreview.item.imageW === 0 && quickPreview.item.imageH === 0
        shell.log("GUARD1 " + (g1asked && g1kept ? "PASS" : "FAIL")
            + " asked7=" + g1asked + " kept=" + g1kept
            + " w=" + quickPreview.item.imageW + " h=" + quickPreview.item.imageH)
        shell.guardEnd()
        // Guard 2 asks at cursor row 3 while shown row 7 names s6.jpg, taking row 3 reply.
        shell.guardMap = ({ 7: "s6.jpg", 3: "guard2.jpg" })
        stub.cursorIndex = 3
        shell.guardShow("guard2.jpg", 7)
        var g2asked = shell.guardAskLog.length === 1 && shell.guardAskLog[0] === 3
        stubBackend.meta(3, 321, 222, 1)
        var g2took = quickPreview.item.imageW === 321 && quickPreview.item.imageH === 222
        shell.log("GUARD2 " + (g2asked && g2took ? "PASS" : "FAIL")
            + " asked3=" + g2asked + " took=" + g2took
            + " w=" + quickPreview.item.imageW + " h=" + quickPreview.item.imageH)
        shell.guardEnd()
        // Guard 3 asks nothing when neither shown row 7 nor cursor row 5 names ghost.jpg.
        shell.guardMap = ({ 7: "s6.jpg", 5: "s4.jpg" })
        stub.cursorIndex = 5
        shell.guardShow("ghost.jpg", 7)
        var g3quiet = shell.guardAskLog.length === 0
        var g3dropped = quickPreview.item.imageRow === -1
        var g3bare = quickPreview.item.imageW === 0 && quickPreview.item.imageH === 0
        shell.log("GUARD3 " + (g3quiet && g3dropped && g3bare ? "PASS" : "FAIL")
            + " quiet=" + g3quiet + " dropped=" + g3dropped + " bare=" + g3bare)
        shell.guardEnd()
        // Guard 4: capture-first. Row 7 names the shown file while cursor 3 names another.
        shell.guardMap = ({ 7: "guard4.jpg", 3: "other4.jpg" })
        stub.cursorIndex = 3
        shell.guardShow("guard4.jpg", 7)
        var g4asked = shell.guardAskLog.length === 1 && shell.guardAskLog[0] === 7
        stubBackend.meta(7, 444, 333, 1)
        var g4took = quickPreview.item.imageW === 444 && quickPreview.item.imageH === 333
        shell.log("GUARD4 " + (g4asked && g4took ? "PASS" : "FAIL")
            + " asked7=" + g4asked + " took=" + g4took
            + " w=" + quickPreview.item.imageW + " h=" + quickPreview.item.imageH)
        shell.guardEnd()
        shell.guardHold = false
        shell.guardMap = ({})
        stub.cursorIndex = shell.restRow
        shell.beginStlFb()
    }

    // An undecodable STL keeps its cache thumbnail as the picture; the control with no thumbnail keeps the sentence.
    property bool stlSawFailure: false
    // Every status change is recorded, so a sentence shown for less than one poll tick is still caught.
    Connections {
        target: quickPreview.item
        function onStatusChanged() {
            if (quickPreview.item && quickPreview.item.status === shell.sentence) {
                if (shell.interimPhase === "stlfb") shell.stlSawFailure = true
                if (shell.lateLeg !== "") shell.lateSaw = true
            }
        }
    }
    function beginStlFb() {
        shell.interimPhase = "stlfb"
        shell.interimOrig = "model.stl"
        shell.interimCache = "stl-cache.png"
        // An STL yields no pixels, so the interim stays unsized the way production leaves it.
        shell.metaWH = [0, 0]
        shell.interimRowOverride = 7
        stub.cursorIndex = 7
        shell.stlSawFailure = false
        quickPreview.item.close()
        quickPreview.item.open(shell.photoDir + "/model.stl", "image-x-generic",
            1000, "", shell.photoDir + "/stl-cache.png")
        stlPoll.waited = 0
        stlPoll.restart()
    }
    // The fallback is the interim element kept as the picture: one decode, found by its cache source.
    function fallbackItem() {
        return shell.interimPair()[0]
    }
    // True when an Image anywhere under Quick Look holds the model file itself as its source.
    function stlHanded() {
        var all = shell.findAll(quickPreview.item, [])
        for (var i = 0; i < all.length; i++) {
            if (String(all[i].source || "").endsWith("/model.stl")) return true
        }
        return false
    }
    // Sample log lines: "PREVIEW STLFALLBACK status=image sawfailure=false frect=52,0,516,388 thumb=256x192 box=620x388 handed=false" and "PREVIEW STLNOTHUMB status=This file cannot be previewed. kind=unsupported handed=false".
    Timer {
        id: stlPoll
        interval: 10
        repeat: true
        property int waited: 0
        onTriggered: {
            waited += interval
            var qp = quickPreview.item
            if (!qp) { stop(); shell.log("FAIL the stl phase lost Quick Look"); shell.quit(); return }
            var held = shell.interimPair()[1], settled = (qp.status === "image" || qp.status === "This image could not be read.") && (!held || held.status !== Image.Loading)
            if (settled) {
                stop()
                var fb = shell.fallbackItem()
                var tw = fb ? fb.implicitWidth : 0, th = fb ? fb.implicitHeight : 0
                var pane = quickPreview.item.surfaceItem()
                var bw = pane ? Math.round(pane.width) : 0, bh = pane ? Math.round(pane.height) : 0
                shell.log("STLFALLBACK status=" + qp.status + " sawfailure=" + shell.stlSawFailure
                    + " frect=" + (fb && fb.visible ? shell.geom(fb) : "none") + " thumb=" + tw + "x" + th
                    + " box=" + bw + "x" + bh + " handed=" + shell.stlHanded())
                shell.beginStlNoThumb()
            } else if (waited > 8000) {
                stop()
                shell.log("FAIL the stl fallback never settled (status " + qp.status + ", model decode " + (held ? held.status : "not asked") + ")")
                shell.quit()
            }
        }
    }
    // The same model no thumbnailer serves: the generic file pane stands, and no Image takes the model file.
    property bool interimRowT: true
    function beginStlNoThumb() {
        shell.interimRowT = false
        shell.interimPhase = "stlnothumb"
        shell.interimOrig = "model.stl"
        shell.interimCache = ""
        shell.metaWH = [0, 0]
        shell.interimRowOverride = 7
        stub.cursorIndex = 7
        stub.thumbState = ({ file: { 7: "" }, order: [7] })
        quickPreview.item.close()
        quickPreview.item.open(shell.photoDir + "/model.stl", "image-x-generic", 1000, "", "")
        stlNoThumbPoll.waited = 0
        stlNoThumbPoll.restart()
    }
    Timer {
        id: stlNoThumbPoll
        interval: 10
        repeat: true
        property int waited: 0
        onTriggered: {
            waited += interval
            var qp = quickPreview.item
            if (!qp) { stop(); shell.log("FAIL the stlnothumb phase lost Quick Look"); shell.quit(); return }
            if (qp.status !== "loading" || waited > 8000) {
                stop()
                shell.log("STLNOTHUMB status=" + qp.status + " kind=" + qp.kind + " handed=" + shell.stlHanded())
                shell.beginStlControl()
            }
        }
    }
    function beginStlControl() {
        shell.interimRowT = true
        shell.interimPhase = "stlcontrol"
        shell.interimOrig = "bad.png"
        shell.interimCache = ""
        shell.metaWH = [0, 0]
        shell.interimRowOverride = 7
        stub.cursorIndex = 7
        // The backend answered this row with no thumbnail, which is what an open with none held means.
        stub.thumbState = ({ file: { 7: "" }, order: [7] })
        quickPreview.item.close()
        quickPreview.item.open(shell.photoDir + "/bad.png", "image-x-generic", 1000, "", "")
        stlControlPoll.waited = 0
        stlControlPoll.restart()
    }
    Timer {
        id: stlControlPoll
        interval: 10
        repeat: true
        property int waited: 0
        onTriggered: {
            waited += interval
            var qp = quickPreview.item
            if (!qp) { stop(); shell.log("FAIL the control phase lost Quick Look"); shell.quit(); return }
            if (qp.status === "This image could not be read.") {
                stop()
                shell.log("STLCONTROL status=" + qp.status)
                shell.beginColumnsModel()
            } else if (waited > 8000) {
                stop()
                shell.log("FAIL the control never kept the sentence (status " + qp.status + ")")
                shell.quit()
            }
        }
    }

    // The Columns preview over a model with no thumbnail: its frame must not hand the file to the decoder.
    property bool modelSeen: false
    Connections {
        target: loader.item ? loader.item.pictureItem : null
        function onSourceChanged() {
            if (String(loader.item.pictureItem.source).indexOf("/mount.stl") >= 0) shell.modelSeen = true
        }
    }
    function beginColumnsModel() {
        quickPreview.item.close()
        stub.thumbState = ({ file: {} })
        shell.metaWH = [0, 0]
        shell.modelRow = 9
        stub.cursorIndex = 9
        colModelPoll.waited = 0
        colModelPoll.restart()
    }
    Timer {
        id: colModelPoll
        interval: 10
        repeat: true
        property int waited: 0
        onTriggered: {
            waited += interval
            var col = loader.item
            if (col.path.endsWith("/mount.stl") && col.previewState === "image" && col.noThumbComing) {
                stop()
                colModelDwell.restart()
            } else if (waited > 8000) {
                stop()
                shell.log("FAIL the Columns preview never reached the model (state " + col.previewState + ")")
                shell.quit()
            }
        }
    }
    // Long enough for an asynchronous decode of the model to fail, were one started.
    // Sample log line: "PREVIEW COLMODEL source= seen=false status=3 note=no preview could be made ready=true".
    Timer {
        id: colModelDwell
        interval: 300
        onTriggered: {
            var col = loader.item
            shell.log("COLMODEL source=" + String(col.pictureItem.source) + " seen=" + shell.modelSeen + " status=" + col.frameStatus
                + " note=" + col.frameNote() + " ready=" + col.ready)
            shell.beginColumnsPending()
        }
    }

    // The same frame over a model whose thumbnail is still to come: it reads Null and shows no sentence until the thumbnail lands, then draws it.
    property bool pendingSawError: false
    property bool pendingSawSentence: false
    function beginColumnsPending() {
        stub.thumbState = ({ file: {} })
        shell.pendingRow = 10
        stub.cursorIndex = 10
        colPendingPoll.stage = "wait"
        colPendingPoll.waited = 0
        colPendingPoll.restart()
    }
    // Sample log lines: "PREVIEW COLPENDING status=0 note= ready=false sawerror=false sawsentence=false" and "PREVIEW COLLAND status=1 source=stl-cache.png note= ready=true sawerror=false sawsentence=false".
    Timer {
        id: colPendingPoll
        interval: 10
        repeat: true
        property string stage: "wait"
        property int waited: 0
        onTriggered: {
            waited += interval
            var col = loader.item
            // Only the pending model's frames count; mount.stl's refused frame before the switch is by design.
            if (col.path.endsWith("/pending.stl") && col.frameStatus === Image.Error) shell.pendingSawError = true
            if (col.path.endsWith("/pending.stl") && col.frameNote() === "no preview could be made") shell.pendingSawSentence = true
            if (stage === "wait") {
                if (col.path.endsWith("/pending.stl") && col.previewState === "image" && col.loadedIndex === 10 && !col.noThumbComing) {
                    stage = "dwell"
                    waited = 0
                } else if (waited > 8000) {
                    stop()
                    shell.log("FAIL the Columns preview never reached the pending model (state " + col.previewState + ")")
                    shell.quit()
                }
            } else if (stage === "dwell") {
                if (waited >= 300) {
                    shell.log("COLPENDING status=" + col.frameStatus + " note=" + col.frameNote() + " ready=" + col.ready
                        + " sawerror=" + shell.pendingSawError + " sawsentence=" + shell.pendingSawSentence)
                    stub.thumbState = ({ file: { 10: shell.photoDir + "/stl-cache.png" } })
                    stage = "land"
                    waited = 0
                }
            } else if (col.frameStatus === Image.Ready && col.ready) {
                stop()
                shell.log("COLLAND status=" + col.frameStatus + " source=" + String(col.pictureItem.source).split("/").pop()
                    + " note=" + col.frameNote() + " ready=" + col.ready
                    + " sawerror=" + shell.pendingSawError + " sawsentence=" + shell.pendingSawSentence)
                shell.lateNext()
            } else if (waited > 8000) {
                stop()
                shell.log("FAIL the pending model's thumbnail never drew (status " + col.frameStatus + ")")
                shell.quit()
            }
        }
    }

    // #263: Quick Look opened on an image whose thumbnail the grid is still making, one step per poll tick.
    readonly property string sentence: "This image could not be read."
    property var lateLegs: ["model", "landed", "refused", "asked", "forgot", "relist", "vanish", "off", "hold", "move", "drift", "decodable"]
    property string lateLeg: ""
    property var lateSteps: []
    property int lateAt: 0
    property double lateStepStart: 0
    property bool lateSaw: false
    property int lateFrames: 0
    property var lateFacts: ({})
    property var viewGate: null

    function qp() { return quickPreview.item }
    function undecodable() { var pane = shell.qp().surfaceItem(); return !!pane && pane.pictureFailed === true }
    function settled() { var status = shell.qp().status; return status === "image" || status === shell.sentence }
    function pausedFor(ms) { return Date.now() - shell.lateStepStart >= ms }
    function fullAsks() { return stubBackend.thumbCalls.filter(function (call) { return !call.cacheOnly }) }
    function askedRows() { return shell.fullAsks().map(function (call) { return call.rows.join("+") }).join(",") }
    // The backend's thumbed line the way ui/PaneWire.qml records it: a cache-only miss returns to unasked.
    function reply(row, file) {
        if (!shell.thumbGate) shell.wireThumbGate()
        stub.thumbState = shell.thumbGate.replyTo(stub.thumbState, row, file,
            stub.thumbCap, stub.storageKnown, stub.storageClass)
    }
    // The planner's own cancel, the way ui/js/Thumbs.js forgets it when the backend drops the job.
    function forgetRow(row) {
        if (!shell.thumbGate) shell.wireThumbGate()
        stub.thumbState = shell.thumbGate.dropRow(stub.thumbState, row)
    }
    property var thumbGate: null
    // The real miss and remember rules, so a reply lands the way production records one.
    function wireThumbGate() {
        shell.thumbGate = Qt.createQmlObject('import QtQuick\nimport "file://' + shell.uiDir
            + '/js/Thumbs.js" as Thumbs\nimport "file://' + shell.uiDir
            + '/js/ExtThumbs.js" as Ext\nimport "file://' + shell.uiDir
            + '" as Flea\nQtObject {\nfunction replyTo(state, row, file, cap, known, storageClass) { return Ext.thumbReply(state, row, file, cap, known, storageClass, Flea.ViewState.preview).state }\nfunction applyTo(state, work) { return Thumbs.applied(state, work) }\nfunction dropRow(state, row) { Thumbs.forget(state, row); return { file: state.file, order: state.order } }\n}', shell, "thumbGate")
    }
    // ViewState is the singleton Preview.qml reads; the harness imports the ui directory to reach that same instance.
    function thumbnails(mode, storageClass) {
        if (!shell.viewGate)
            shell.viewGate = Qt.createQmlObject('import QtQuick\nimport "file://' + shell.uiDir + '" as Flea\nQtObject { function set(v) { Flea.ViewState.state = v } }', shell, "viewGate")
        shell.viewGate.set(mode === "" ? ({}) : ({ preview: { thumbnails: mode } }))
        stub.storageClass = storageClass
    }
    Connections {
        target: host.Window.window
        function onAfterAnimating() {
            if (shell.lateLeg !== "" && quickPreview.item && quickPreview.item.status === shell.sentence) shell.lateFrames += 1
        }
    }

    // Opens a fresh Quick Look on names[7] with the thumbnail map in state and none held at open.
    function lateOpen(names, state) {
        shell.interimPhase = "late-" + shell.lateLeg
        shell.metaWH = [0, 0]
        shell.guardMap = names
        shell.interimRowOverride = -1
        stub.cursorIndex = 7
        stub.thumbState = ({ file: state, order: Object.keys(state).map(Number) })
        stubBackend.thumbCalls = []
        shell.lateFacts = ({})
        // Counted from after the close, whose teardown reads the old item's status once with nothing drawn.
        shell.qp().close()
        shell.lateSaw = false
        shell.lateFrames = 0
        shell.qp().open(shell.photoDir + "/" + names[7], "image-x-generic", 1000, "", "")
    }
    // What stood on screen while the reply was still owed, and how many full asks had gone out by then.
    function pendNow() {
        shell.lateFacts.pend = shell.qp().status === shell.sentence ? "sentence" : shell.qp().status
        shell.lateFacts.asks = shell.fullAsks().length
        shell.lateFacts.pendsaw = shell.lateSaw
        shell.lateFacts.pendframes = shell.lateFrames
    }
    // Sample log line: "PREVIEW LATE landed pend=loading asks=1 pendsaw=false pendframes=0 total=1 rows=7 end=image saw=false frames=0 fallback=true".
    function lateLog() {
        var facts = shell.lateFacts
        var pane = shell.qp().surfaceItem()
        shell.log("LATE " + shell.lateLeg + " pend=" + facts.pend + " asks=" + facts.asks + " pendsaw=" + facts.pendsaw
            + " pendframes=" + facts.pendframes + " total=" + shell.fullAsks().length + " rows=" + shell.askedRows()
            + " end=" + (shell.qp().status === shell.sentence ? "sentence" : shell.qp().status)
            + " saw=" + shell.lateSaw + " frames=" + shell.lateFrames + " fallback=" + (!!pane && pane.fallbackShown === true)
            + (facts.extra || ""))
    }
    function lateNext() {
        if (shell.lateLegs.length === 0) { quitTimer.restart(); return }
        shell.lateLeg = shell.lateLegs.shift()
        var failed = function () { return shell.undecodable() && shell.pausedFor(150) }
        var done = function () { shell.lateLog(); shell.lateNext() }
        var steps
        if (shell.lateLeg === "landed" || shell.lateLeg === "refused" || shell.lateLeg === "model") {
            var landed = shell.lateLeg !== "refused"
            // The model leg is a 3D model whose thumbnailer is still working: Quick Look opens on the image pane and waits on the reply.
            shell.lateOpen({ 7: shell.lateLeg === "model" ? "model.stl" : "late.png" }, { 7: "cache-asked" })
            steps = [
                { wait: failed, run: function () { shell.pendNow(); shell.reply(7, "") } },
                { wait: function () { return shell.fullAsks().length >= 1 }, run: function () { shell.reply(7, landed ? shell.photoDir + "/stl-cache.png" : "") } },
                { wait: shell.settled, run: done }
            ]
        } else if (shell.lateLeg === "asked") {
            shell.lateOpen({ 7: "late.png" }, { 7: null })
            steps = [
                { wait: failed, run: function () { shell.pendNow(); shell.reply(7, shell.photoDir + "/stl-cache.png") } },
                { wait: shell.settled, run: done }
            ]
        } else if (shell.lateLeg === "forgot") {
            shell.lateOpen({ 7: "late.png" }, { 7: "cache-asked" })
            steps = [
                { wait: failed, run: function () { shell.pendNow(); shell.reply(7, "") } },
                { wait: function () { return shell.fullAsks().length >= 1 }, run: function () { shell.forgetRow(7) } },
                { wait: shell.settled, run: done }
            ]
        } else if (shell.lateLeg === "relist" || shell.lateLeg === "vanish") {
            var vanish = shell.lateLeg === "vanish"
            shell.lateOpen({ 7: "late.png" }, { 7: "cache-asked" })
            steps = [
                { wait: failed, run: function () { shell.pendNow(); shell.reply(7, "") } },
                // A re-list while the ask is out: the map resets, then the rows land with the file moved down one, or gone.
                { wait: function () { return shell.fullAsks().length >= 1 }, run: function () {
                    stub.listInFlight = true
                    stub.thumbState = ({ file: {}, order: [] })
                    shell.guardMap = vanish ? ({ 7: "new.png" }) : ({ 7: "new.png", 8: "late.png" })
                    stub.cursorIndex = vanish ? 0 : 8
                    stub.rowsChanged()
                    shell.lateFacts.extra = " held=" + shell.qp().status
                    stub.listInFlight = false
                } },
                { wait: function () { return vanish || shell.fullAsks().length >= 2 }, run: function () { if (!vanish) shell.reply(8, shell.photoDir + "/stl-cache.png") } },
                { wait: shell.settled, run: done }
            ]
        } else if (shell.lateLeg === "off" || shell.lateLeg === "hold") {
            shell.thumbnails(shell.lateLeg === "off" ? "off" : "", shell.lateLeg === "hold" ? "network" : "")
            shell.lateOpen({ 7: "late.png" }, { 7: "cache-asked" })
            steps = [
                { wait: failed, run: function () { shell.pendNow(); shell.thumbnails("", "") } },
                { wait: shell.settled, run: done }
            ]
        } else if (shell.lateLeg === "move") {
            shell.lateOpen({ 7: "late.png", 8: "bad.png" }, { 7: "cache-asked", 8: "cache-asked" })
            steps = [
                { wait: failed, run: function () {
                    shell.pendNow()
                    stub.cursorIndex = 8
                    shell.qp().open(shell.photoDir + "/bad.png", "image-x-generic", 1000, "", "")
                } },
                { wait: failed, run: function () {
                    shell.lateFacts.extra = " second=" + shell.askedRows()
                    shell.reply(7, shell.photoDir + "/stl-cache.png")
                } },
                { wait: function () { return shell.pausedFor(100) }, run: function () {
                    shell.lateFacts.extra += " stale=" + (shell.qp().interimThumb === "" ? "none" : "bound") + " held=" + shell.qp().status
                    shell.reply(8, "")
                } },
                { wait: function () { return shell.fullAsks().length >= 1 }, run: function () { shell.reply(8, "") } },
                { wait: shell.settled, run: done }
            ]
        } else if (shell.lateLeg === "drift") {
            shell.lateOpen({ 7: "late.png" }, { 7: "cache-asked" })
            steps = [
                { wait: failed, run: function () {
                    shell.pendNow()
                    // A listing change put another file on row 7 before the reply, so the reply is no longer this file's.
                    shell.guardMap = ({ 7: "bad.png", 8: "late.png" })
                    shell.reply(7, shell.photoDir + "/smallcache.png")
                } },
                { wait: shell.settled, run: function () {
                    shell.lateFacts.extra = " bound=" + (shell.qp().interimThumb === "" ? "none" : "wrong")
                    done()
                } }
            ]
        } else {
            shell.lateOpen({ 7: "small.png" }, { 7: "cache-asked" })
            steps = [
                { wait: function () { return shell.qp().status === "image" && shell.pausedFor(150) }, run: function () { shell.pendNow(); done() } }
            ]
        }
        shell.lateSteps = steps
        shell.lateAt = 0
        shell.lateStepStart = Date.now()
        lateTick.restart()
    }
    Timer {
        id: lateTick
        interval: 10
        repeat: true
        onTriggered: {
            var steps = shell.lateSteps
            if (Date.now() - shell.lateStepStart > 8000) {
                stop()
                shell.log("LATE " + shell.lateLeg + " stuck at step " + shell.lateAt + " status=" + shell.qp().status)
                shell.lateNext()
                return
            }
            if (!steps[shell.lateAt].wait()) return
            var step = steps[shell.lateAt]
            shell.lateAt += 1
            shell.lateStepStart = Date.now()
            step.run()
            if (steps === shell.lateSteps && shell.lateAt >= steps.length) stop()
        }
    }

    Timer {
        id: quitTimer
        interval: 500
        onTriggered: shell.quit()
    }
}
