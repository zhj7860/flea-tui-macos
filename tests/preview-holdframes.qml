//@ pragma ShellId flea-preview-holdframes-test

import Quickshell
import QtQuick

// Real PreviewSwap moved as the column view does; prints 'HOLDFRAMES KEY 5 capture=1 held=3 free=1 whole=1' per key.
ShellRoot {
    id: shell

    readonly property string uiDir: Quickshell.env("PREVIEW_HOLDFRAMES_UI")
    readonly property string outDir: Quickshell.env("PREVIEW_HOLDFRAMES_OUT")
    // The basic loop syncs and renders in one call, so a change between them leaves the grab drawing dead items.
    readonly property bool basicLoop: Quickshell.env("QSG_RENDER_LOOP") === "basic"
    property bool inFrame: false
    property int inFrameChanges: 0
    readonly property int keys: 14
    readonly property int keyMs: 400
    readonly property int landMs: 60
    readonly property int rowCount: 60

    property int step: 0
    property bool simReady: true
    property int kind: 0
    property int cursor: 0
    // Per key: frames while held, frames after the release, and whether the first free frame drew the new preview whole.
    property int heldNow: 0
    property int captureNow: 0
    property int freeNow: 0
    property int wholeNow: -1
    property int heldSum: 0
    property int captureSum: 0
    property int freeSum: 0
    property int brokenKeys: 0
    property int swapped: 0
    // The hold's layer, kept to its release, which must null its source: offscreen the deferred delete lands before the next frame, so no picture shows the trap.
    property var heldLayer: null
    property int letGo: 0
    property int keptSource: 0

    function log(line) { console.log("HOLDFRAMES " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function rowText(k, i) { return "preview " + k + " row " + i + " of a file under the cursor" }

    FloatingWindow {
        implicitWidth: 1280
        implicitHeight: 900
        color: "#303030"

        Item {
            id: stage
            anchors.fill: parent

        // The list column: its cursor row moves on every key, outside the picture.
        Rectangle {
            x: 0
            y: 40 + shell.cursor * 24
            width: 300
            height: 24
            color: "#4a6a8a"
        }

        Loader {
            id: swapLoader
            x: 320
            y: 20
            width: 940
            height: 860
            source: "file://" + shell.uiDir + "/PreviewSwap.qml"
            onLoaded: {
                item.burstEnds = true
                item.ground = "#101315"
                item.ready = Qt.binding(function () { return shell.simReady })
            }
            onStatusChanged: if (status === Loader.Error) { shell.log("FAIL the swap did not load"); shell.quit() }
        }
        }

        // The QQuickWindow under the Quickshell window, which is where afterAnimating and frameSwapped come from.
        Connections {
            target: swapLoader.Window.window
            function onAfterAnimating() { shell.frame() }
            function onFrameSwapped() { shell.swapped += 1 }
            function onBeforeSynchronizing() { if (shell.basicLoop) shell.inFrame = true }
            function onBeforeRendering() { if (shell.basicLoop) shell.inFrame = false }
        }
    }

    property var swap: swapLoader.item

    Connections {
        target: shell.swap
        function onCapturingChanged() { shell.released() }
        function onHoldingChanged() { shell.released() }
    }

    // The preview: a ground and many text rows, each a node the picture has to stand in for while it changes.
    Rectangle {
        id: previewBody
        visible: false
        width: 940
        height: 860
        color: shell.kind % 2 === 0 ? "#2a3a4a" : "#3a2a4a"
        Column {
            x: 12
            y: 12
            Repeater {
                id: rowsRepeater
                model: shell.rowCount
                Text {
                    required property int index
                    text: shell.rowText(shell.kind, index)
                    color: "white"
                    font.pixelSize: 12
                }
            }
        }
    }

    function frame() {
        if (shell.step < 1 || !shell.swap)
            return
        if (shell.swap.capturing || shell.swap.holding) {
            if (shell.heldLayer === null)
                shell.heldLayer = shell.layerItem()
            shell.heldNow += 1
            if (shell.swap.capturing)
                shell.captureNow += 1
            return
        }
        shell.freeNow += 1
        if (shell.wholeNow !== -1)
            return
        // The release frame: the rows are already the new preview, and ready.
        var whole = shell.simReady && rowsRepeater.count === shell.rowCount
        for (var i = 0; i < shell.rowCount && whole; i++) {
            if (rowsRepeater.itemAt(i).text !== shell.rowText(shell.kind, i))
                whole = false
        }
        shell.wholeNow = whole ? 1 : 0
    }

    function layerItem() {
        var kids = shell.swap.children
        for (var i = 0; i < kids.length; i++) {
            if (kids[i].item && kids[i].item.hideSource !== undefined)
                return kids[i].item
        }
        return null
    }

    function released() {
        if (shell.swap.capturing || shell.swap.holding || shell.heldLayer === null)
            return
        if (shell.heldLayer.sourceItem === null)
            shell.letGo += 1
        else
            shell.keptSource += 1
        shell.heldLayer = null
    }

    function closeKey() {
        if (shell.step < 1)
            return
        shell.log("KEY " + shell.step + " capture=" + shell.captureNow + " held=" + shell.heldNow + " free=" + shell.freeNow
            + " whole=" + shell.wholeNow)
        // The first two keys warm the caches and the layer; every later key is judged.
        if (shell.step > 2) {
            shell.heldSum += shell.heldNow
            shell.captureSum += shell.captureNow
            shell.freeSum += shell.freeNow
            if (shell.wholeNow !== 1)
                shell.brokenKeys += 1
        }
    }

    function move() {
        shell.closeKey()
        if (shell.step >= shell.keys) {
            shell.finish()
            return
        }
        shell.step += 1
        shell.heldNow = 0
        shell.captureNow = 0
        shell.freeNow = 0
        shell.wholeNow = -1
        shell.cursor = shell.step
        var next = shell.step
        var key = "/nav\n" + next
        // The column view's move: hold the clear, then the new preview's own start under the same key.
        shell.swap.hold(function () {
            if (shell.inFrame)
                shell.inFrameChanges += 1
            shell.kind = next
            shell.simReady = false
        }, key)
        shell.swap.hold(function () { shell.swap.start(false) }, key, true)
        landTimer.restart()
        keyTimer.restart()
    }

    function finish() {
        var s = shell.swap.describe()
        var judged = shell.keys - 2
        shell.log("DONE keys=" + judged + " capture=" + shell.captureSum + " held=" + shell.heldSum + " free=" + shell.freeSum
            + " broken=" + shell.brokenKeys + " holds=" + s.holds + " fallbacks=" + s.fallbacks
            + " mid=" + s.midFrames + " loading=" + s.loadingFrames + " swapped=" + shell.swapped + " inframe=" + shell.inFrameChanges
            + " letgo=" + shell.letGo + " kept=" + shell.keptSource)
        // The settled window, read back by the runner: the rows' own ground must show where the preview is.
        stage.grabToImage(function (result) {
            result.saveToFile(shell.outDir + "/settled.ppm")
            shell.log("GRAB")
            shell.quit()
        })
    }

    Timer {
        id: landTimer
        interval: shell.landMs
        repeat: false
        onTriggered: shell.simReady = true
    }

    Timer {
        id: keyTimer
        interval: shell.keyMs
        repeat: false
        onTriggered: shell.move()
    }

    Timer {
        id: kickoff
        interval: 600
        running: true
        repeat: false
        onTriggered: {
            if (!shell.swap) {
                shell.log("FAIL no swap item to drive")
                shell.quit()
                return
            }
            previewBody.visible = true
            previewBody.parent = shell.swap.contentItem()
            shell.move()
        }
    }
}
