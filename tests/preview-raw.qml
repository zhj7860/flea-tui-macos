//@ pragma ShellId flea-preview-raw-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Messages.js" as Messages
import "flea/js/Thumbs.js" as Thumbs

// A camera RAW in Quick Look and in the column, on the real Preview and SelectionPreview over a stub pane whose backend answers with the meta line the backend writes.
ShellRoot {
    id: shell

    readonly property string dir: Quickshell.env("PVRAW_DIR")
    readonly property real tol: 1
    property int checks: 0
    property int failures: 0
    property bool finished: false
    // Every row of the stub listing: the name, and the picture the meta reply names for it (empty for the null reply of a RAW with no preview).
    readonly property var files: [
        { n: "a.cr2", copy: "preview.jpg", w: 1620, h: 1080, orient: 1 },
        { n: "b.nef", copy: "preview.jpg", w: 1620, h: 1080, orient: 6 },
        { n: "c.jpg", copy: "", w: 800, h: 600, orient: 1 },
        { n: "d.dng", copy: "", w: 0, h: 0, orient: 1 }
    ]
    property int rawAsks: 0
    property int refusedThumbs: 0

    function log(line) { console.log("PVRAW " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(cond, what) {
        shell.checks++
        if (!cond) { shell.failures++; shell.log("FAIL " + what) }
        return cond
    }
    function near(a, b) { return Math.abs(a - b) <= shell.tol }
    function item() { return look.surfaceItem() }
    function drawn() { var it = shell.item(); return it !== null && it.status === "image" }
    function bandText(it) { return it.band.children[0].text }
    function same(a, b) { return Qt.colorEqual(a, b) }

    // The line Rust's meta_line writes for this row: a RAW carries its copy as an object, anything else null, and w and h stay the file's own.
    function metaLine(row, token) {
        var f = shell.files[row]
        var raw = f.copy.length > 0 ? '{"file":"' + shell.dir + '/' + f.copy + '","w":' + f.w + ',"h":' + f.h + ',"orient":' + f.orient + '}' : 'null'
        var own = /\.(cr2|nef|dng)$/i.test(f.n) ? 0 : f.w
        return '{"t":"meta","row":' + row + ',"w":' + own + ',"h":' + (own === 0 ? 0 : f.h) + ',"orient":1,"ms":0,"rate":0,"entries":0,"unpacked":0,"afailed":false,"names":[],"lines":0,"partial":false,"lfailed":false,"target":"","targetdir":false,"raw":' + raw + ',"owner":"gm","token":' + token + '}'
    }

    Item {
        id: stubBackend
        signal metaResult(var message)
        signal meta(int row, int w, int h, int orient, real durationMs, int sampleRate, int entries, real unpacked, bool archiveFailed, var names, real lines, bool partial, bool linesFailed, string target, bool targetDir, string owner)
        property int nextToken: 0
        property var pending: []
        property var pendingThumbs: []
        function askMeta(index) {
            nextToken += 1
            pending.push({ token: nextToken, index: index })
            metaTimer.restart()
            return nextToken
        }
        function thumb(rows, cacheOnly) {
            for (var i = 0; i < rows.length; i++) pendingThumbs.push({ row: rows[i], cacheOnly: cacheOnly === true })
            thumbTimer.restart()
        }
    }
    Timer {
        id: metaTimer
        interval: 5
        onTriggered: {
            var asks = stubBackend.pending
            stubBackend.pending = []
            for (var i = 0; i < asks.length; i++) {
                if (asks[i].index === 0 || asks[i].index === 1) shell.rawAsks++
                Messages.route(stubBackend, JSON.parse(shell.metaLine(asks[i].index, asks[i].token)))
            }
        }
    }

    Timer {
        id: thumbTimer
        interval: 5
        onTriggered: {
            var asks = stubBackend.pendingThumbs
            stubBackend.pendingThumbs = []
            for (var i = 0; i < asks.length; i++) {
                if (asks[i].row === 3 && !asks[i].cacheOnly) {
                    var it = shell.item()
                    shell.check(look.rawAnswered && look.rawCopy === null && it !== null && it.thumbPending && !it.failed && it.status === "loading", "a RAW with no preview did not wait for its thumbnail reply")
                    shell.refusedThumbs++
                }
                stub.thumbState = Thumbs.remember(stub.thumbState, asks[i].row, "", shell.files.length)
            }
        }
    }

    Item {
        id: stub
        property int cursorIndex: 0
        property string path: shell.dir
        property int settleMs: 120
        property var thumbState: ({ file: {}, order: [] })
        property string fsPath: shell.dir
        property string fsName: "btrfs"
        property string storageClass: ""
        property bool storageKnown: true
        property bool listInFlight: false
        property var kindNames: []
        property var preview: ({ active: false })
        property var backend: stubBackend
        property var listArea: ({ forceActiveFocus: function () {} })
        signal rowsChanged()
        signal selectionVersionChanged()
        function rowFor(i) {
            if (i < 0 || i >= shell.files.length) return null
            return { n: shell.files[i].n, d: false, t: true, s: 1000, m: 1000, p: 33188, i: "image-x-generic" }
        }
        function join(base, name) { return base + "/" + name }
        function selectionCount() { return 1 }
        function selectedIndices() { return [stub.cursorIndex] }
    }

    FloatingWindow {
        implicitWidth: 1000
        implicitHeight: 800
        color: Flea.Theme.color.background
        Flea.Preview { id: look; anchors.fill: parent; pane: stub }
        Flea.SelectionPreview { id: column; x: 0; y: 0; width: 300; height: 500; visible: false; pane: stub }
    }

    // Every frame: the band is drawn only over a RAW at fit, only once its picture is, and never over a JPEG.
    Connections {
        target: look.Window.window
        function onAfterAnimating() {
            var it = shell.item()
            if (it === null || !look.active || !it.band.visible || it.zoomed) return
            shell.check(it.raw, "a frame drew the caption band over " + it.path)
            shell.check(it.pictureItem === it.fullPicture || it.pictureItem.status === Image.Ready, "a frame drew the band before its picture")
        }
    }

    property var waitReady: null
    property var waitThen: null
    property string waitWhat: ""
    property int waited: 0
    function until(ready, then, what) {
        shell.waitReady = ready
        shell.waitThen = then
        shell.waitWhat = what
        shell.waited = 0
        ticker.start()
    }
    Timer {
        id: ticker
        interval: 10
        repeat: true
        onTriggered: {
            if (shell.waitReady()) {
                ticker.stop()
                shell.waitThen()
            } else if (++shell.waited > 1500) {
                ticker.stop()
                shell.check(false, "timed out waiting for " + shell.waitWhat)
                shell.finish()
            }
        }
    }

    function openRow(row, then) {
        stub.cursorIndex = row
        look.open(shell.dir + "/" + shell.files[row].n, "image-x-generic", 1, "image", "")
        shell.until(function () { var it = shell.item(); return it !== null && it.path === shell.dir + "/" + shell.files[row].n && it.status !== "loading" },
            function () { then(shell.item()) }, shell.files[row].n + " settled")
    }

    function landscape(it) {
        shell.check(shell.drawn(), "the RAW did not draw")
        shell.check(String(it.pictureItem.source).indexOf("/preview.jpg") > 0, "the RAW drew " + it.pictureItem.source + ", want its embedded copy")
        shell.check(it.band.visible, "no caption band under the RAW")
        shell.check(shell.bandText(it) === "Embedded preview · 1620 × 1080", "caption read " + shell.bandText(it))
        shell.check(shell.near(it.band.height, Flea.Theme.chromeHeight) && shell.near(it.band.y + it.band.height, it.height), "the band is not a chromeHeight strip at the bottom")
        shell.check(shell.same(it.band.color, Flea.Theme.color.background) && shell.same(it.band.children[0].color, Flea.Theme.color.muted), "the band is not the frame ground with muted text")
        shell.check(it.band.children[0].font.pixelSize === Flea.Theme.font.caption, "the caption is not caption size")
        var p = it.pictureItem
        shell.check(p.y >= -shell.tol && p.y + p.height <= it.band.y + shell.tol, "the picture runs into the band: " + p.y + "+" + p.height + " vs " + it.band.y)
        shell.check(shell.near(p.width / p.height, 1620 / 1080), "the picture is not drawn at the embedded aspect")
    }

    function run() {
        shell.openRow(0, function (a) {
            shell.landscape(a)
            // The zoomed band is the zoom's own, with the surface colour and the zoom label.
            look.zoomBy(1)
            shell.check(a.zoomed && a.band.visible && shell.bandText(a) === a.zoomLabel && shell.same(a.band.color, Flea.Theme.color.surface), "a zoomed RAW did not keep the zoom band")
            look.zoomFit()
            shell.check(shell.bandText(a) === "Embedded preview · 1620 × 1080", "fit did not bring the caption back")
            shell.openRow(1, function (b) {
                shell.check(shell.bandText(b) === "Embedded preview · 1080 × 1620", "a turned preview read " + shell.bandText(b))
                shell.openRow(2, function (c) {
                    shell.check(shell.drawn() && !c.band.visible && !c.raw, "the band stayed over a JPEG")
                    shell.check(shell.near(c.pictureItem.y + c.pictureItem.height / 2, c.height / 2), "a JPEG is not centred on the whole surface")
                    shell.openRow(3, function (d) {
                        shell.check(d.failed && d.status === "This image could not be read." && !d.band.visible, "a RAW with no preview did not draw the unreadable state, status " + d.status)
                        shell.check(shell.refusedThumbs === 1 && look.thumbRow === -1, "a RAW with no preview did not settle after one thumbnail refusal")
                        look.close()
                        shell.checkColumn()
                    })
                })
            })
        })
    }

    // The column card: a RAW row draws no caption, and the frame holds nothing named Embedded preview.
    function checkColumn() {
        stub.cursorIndex = 0
        column.visible = true
        shell.until(function () { return column.meta !== null }, function () {
            var texts = []
            var stack = [column]
            while (stack.length > 0) {
                var n = stack.pop()
                if (n.visible && typeof n.text === "string" && n.text.length > 0) texts.push(n.text)
                for (var i = 0; i < (n.children || []).length; i++) stack.push(n.children[i])
            }
            shell.check(texts.length > 0, "the column drew no text at all")
            shell.check(texts.every(function (t) { return t.indexOf("Embedded preview") < 0 }), "the column card drew a caption: " + texts.join("|"))
            shell.check(column.meta.w === 0 && column.meta.h === 0, "the column took the preview's pixels for the RAW's own")
            shell.finish()
        }, "the column's meta")
    }

    function finish() {
        if (shell.finished) return
        shell.finished = true
        shell.log("DONE checks=" + shell.checks + " failures=" + shell.failures)
        shell.log(shell.failures === 0 ? "PASS" : "FAIL " + shell.failures)
        shell.quit()
    }

    Component.onCompleted: Qt.callLater(shell.run)
}
