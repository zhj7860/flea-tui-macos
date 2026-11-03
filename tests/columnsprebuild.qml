//@ pragma ShellId flea-columnsprebuild-test

import QtQuick
import Quickshell
import "flea" as Flea

// columnsprebuild: quiet turns park rows for the next landing (0 built); the first landing holds, peeks never build, keys hold ticks a frame, Back pools, hide drops.
ShellRoot {
    id: root

    property var failures: []
    property bool finished: false
    property int step: 0
    property string stage: "empty"
    property var keyTimes: []
    property double firstCountAt: -1
    property int peekBase: -1
    property int createdBefore: 0
    property int ticksBefore: 0
    property double watchStart: 0
    property var tickLog: []
    property var tickTimer: null

    function pad(i) { var n = String(i); while (n.length < 4) n = "0" + n; return n }
    function fileRows(n) {
        var out = []
        for (var i = 0; i < n; i++)
            out.push({ n: "f_" + root.pad(i) + ".txt", d: false, i: "text-plain", p: 420, s: 0, m: 1758835200, t: false, k: 0, v: 0 })
        return out
    }
    function dirRows(prefix, n) {
        var out = []
        for (var i = 0; i < n; i++)
            out.push({ n: prefix + root.pad(i), d: true, i: "folder", p: 493, s: 0, m: 1758835200, t: false, k: 0, v: 0 })
        return out
    }
    property var bigRows: root.fileRows(1000)

    // Peeks answer one turn after the ask, so the neighbour columns land after the listing's turn.
    Component {
        id: backendStub
        QtObject {
            id: stub
            signal peeked(string path, bool hidden, int total, var rows, bool readFailed, int mode, bool hiddenLast, int first, int dev, bool writable, string by, bool desc)
            property int dirDev: 0
            property string sortBy: "name"
            property bool sortDesc: false
            function peek(path, size, hidden) {
                var p = String(path)
                Qt.callLater(function () { var rows = root.dirRows("s_", 6); stub.peeked(p, false, rows.length, rows, false, 0, false, 35, 0, true, "", false) })
            }
            function thumb(rows, cacheOnly) {}
            function thumbcancel(rows) {}
            function dirsize(rows) {}
            function dirsizecancel() {}
            function window(start, count) {}
            function askMeta(index, text, media, archive) { return 0 }
        }
    }

    Component {
        id: paneStub
        QtObject {
            property string path: "/probe"
            property var rows: []
            property var shown: null
            readonly property int shownTotal: shown === null ? total : shown.length
            property int total: 0
            property int held: 0
            property int cursorIndex: 0
            property int renamingIndex: -1
            property int renameRequest: 0
            property string renameError: ""
            property bool renamePending: false
            property int selectionVersion: 0
            property bool paneFocused: true
            property bool dualMode: false
            property bool showHidden: false
            property var trash: ({ opened: false })
            property var clipboard: ({ paths: [], moving: false })
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property var kindNames: []
            property string searchMode: ""
            property string searchQuery: ""
            property string recentMode: ""
            property string filterQuery: ""
            property var selectionBand: null
            property int previewIndex: -1
            property bool storageKnown: true
            property string storageClass: ""
            property bool listInFlight: false
            property string listingState: "ready"
            property string pendingSelect: ""
            property bool pendingMenu: false
            property string focusView: "columns"
            property double inputAt: 0
            property int visibleRows: 43
            property int cacheRows: 2
            property int firstSettleMs: 70
            property int settleMs: 120
            property int coalesceMs: 16
            property int refetchMargin: 25
            property int buffer: 150
            property int windowSize: 35
            property var backend: null
            property var sidebar: null
            property var listArea: null
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) { var o = index - held; return (o >= 0 && o < rows.length) ? rows[o] : null }
            function isSelected(index) { return false }
            function selectedIndices() { return [] }
            function selectionCount() { return 0 }
            function thumbFor(index) { return "" }
            function setCursor(index, mode) { cursorIndex = index }
            function slowClickWasSole(index) { return false }
            function pressSlowClick() {}
            function cancelSlowClick() {}
            function armSlowClick() {}
            function commitRename(newName) {}
            function open(path) {}
            function openFile(path) {}
            function focusRequested() {}
        }
    }
    Component { id: menuStub; QtObject { function close() {} function openBackground(point) {} } }

    property var stubPane: paneStub.createObject(root, { backend: backendStub.createObject(root) })

    FloatingWindow {
        implicitWidth: 2536
        implicitHeight: 1389
        color: "black"
        Flea.ColumnsArea {
            id: area
            width: 2536
            height: 1381
            pane: root.stubPane
            menu: menuStub.createObject(root)
        }
    }

    function active() { return area.activeColumn() }
    function isColumnPane(o) {
        return o !== null && o.drawsEmpty !== undefined && o.lockedMode !== undefined && typeof o.itemAtIndex === "function"
    }
    function panes() {
        var out = [], stack = [area]
        while (stack.length > 0) {
            var o = stack.pop()
            if (root.isColumnPane(o)) out.push(o)
            var kids = (o !== null && o.children !== undefined) ? o.children : []
            for (var i = 0; i < kids.length; i++) stack.push(kids[i])
        }
        return out
    }
    function delegatesOf(col) {
        var out = [], kids = col.viewport.contentItem.children
        for (var i = 0; i < kids.length; i++)
            if (kids[i].listingIndex !== undefined) out.push(kids[i])
        return out
    }
    // Every delegate any peek column holds, so a driver that reaches them shows here.
    function peekDelegates() {
        var n = 0, all = root.panes()
        for (var i = 0; i < all.length; i++)
            if (all[i] !== root.active()) n += root.delegatesOf(all[i]).length
        return n
    }
    function createdAll() {
        var n = 0, all = root.panes()
        for (var i = 0; i < all.length; i++) n += all[i].prebuild !== undefined ? all[i].prebuild.createdCount : root.delegatesOf(all[i]).length
        return n
    }

    function land(path, total, rows) {
        var p = root.stubPane
        p.listInFlight = true
        p.total = 0
        p.held = 0
        p.rows = []
        p.cursorIndex = 0
        p.listingState = "loading"
        p.rows = rows
        p.total = total
        p.path = path
        p.listingState = "ready"
        p.listInFlight = false
    }

    function checkViewport() {
        var v = root.active().viewport
        var rows = Math.ceil(v.height / Flea.Theme.fileRowHeight)
        for (var i = 0; i < rows; i++) {
            var it = v.itemAtIndex(i)
            var want = "f_" + root.pad(i) + ".txt"
            if (!it) { root.failures.push("landing: viewport row " + i + " has no delegate"); return }
            if (!it.live || !it.visible) { root.failures.push("landing: viewport row " + i + " is parked"); return }
            if (!it.row || it.row.n !== want) { root.failures.push("landing: viewport row " + i + " shows " + (it.row ? it.row.n : "null")); return }
        }
    }

    // A key keeps its column and that column's tick count, so a tick in the key's own millisecond counts only if it ran after the key.
    function keyStamp(at) { var col = root.active(); return { at: at, col: col, tick: col.prebuild.tickAt.length } }
    function checkKeys() {
        for (var k = 0; k < root.keyTimes.length; k++) {
            var key = root.keyTimes[k], driver = key.col.prebuild, ticks = driver.tickAt || []
            if (ticks.length >= driver.keepTicks) root.failures.push("key: the tick log reached keepTicks, so a key's tick index no longer holds")
            for (var i = key.tick; i < ticks.length; i++)
                if (ticks[i] - key.at < driver.frameMs)
                    root.failures.push("key: a tick ran " + (ticks[i] - key.at) + " ms after a key")
        }
    }

    // Every tick of the active column's Timer, built or not, so a driver that ticks with no progress shows here.
    function hookTicks() {
        var col = root.active()
        if (!col.prebuild) return
        root.tickTimer = col.prebuild.timer
        var last = { n: col.prebuild.createdCount }
        root.tickTimer.triggered.connect(function () {
            root.tickLog.push({ at: Date.now(), built: col.prebuild.createdCount > last.n })
            last.n = col.prebuild.createdCount
        })
    }
    function settled(name) {
        var now = Date.now(), ticks = 0, idle = 0
        for (var i = 0; i < root.tickLog.length; i++)
            if (now - root.tickLog[i].at <= 100) { ticks += 1; if (!root.tickLog[i].built) idle += 1 }
        // One tick may build nothing: the one that finds no work left and stops the driver.
        if (idle > 1) root.failures.push(name + ": " + idle + " of " + ticks + " ticks in the last 100 ms built nothing")
    }
    function waited(ms) { return Date.now() - root.watchStart >= ms }
    function landBuilt(name, path, total, rows) {
        var before = root.createdAll()
        root.land(path, total, rows)
        if (root.createdAll() !== before) root.failures.push(name + ": the landing built " + (root.createdAll() - before) + " delegates, want 0")
        root.watchStart = Date.now()
    }

    function finish() {
        if (root.finished) return
        root.finished = true
        var col = root.active()
        if (root.failures.length > 0) console.log("COLUMNSPREBUILD FAIL " + root.failures.slice(0, 8).join("; "))
        else console.log("COLUMNSPREBUILD PASS warmRows=" + col.viewport.model.warmRows + " ticks=" + col.prebuild.tickAt.length + " created=" + col.prebuild.createdCount)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    Timer { id: key2; interval: 8; repeat: false; onTriggered: { root.stubPane.inputAt = Date.now(); root.keyTimes.push(root.keyStamp(root.stubPane.inputAt)) } }

    Timer {
        interval: 120
        running: true
        repeat: true
        onTriggered: {
            var col = root.active()
            root.step += 1
            if (root.step > 400) { root.failures.push("timeout at stage " + root.stage); root.finish(); return }
            if (root.stage === "empty") {
                // Before any listing lands the count is 0: the driver waits for a landing without ticking.
                if (root.tickTimer === null) { root.hookTicks(); root.watchStart = Date.now() }
                if (!root.waited(500)) return
                root.settled("start: no landing yet")
                root.stage = "first"
            } else if (root.stage === "first") {
                root.land("/probe", 1, root.dirRows("big", 1))
                root.stage = col.prebuild === undefined ? "unsupported" : "hold"
            } else if (root.stage === "unsupported") {
                root.failures.push("prebuild: the active column has no parked pool")
                var before = root.createdAll()
                root.land("/probe/big", 1000, root.bigRows)
                root.failures.push("landing: built " + (root.createdAll() - before) + " delegates, want 0")
                root.finish()
            } else if (root.stage === "hold") {
                // (f) Inside the hold after the first landing: no parked rows, and the peeks have answered.
                if (root.firstCountAt < 0) root.firstCountAt = col.prebuild.countAt
                if (root.firstCountAt < 0) { root.failures.push("hold: the first landing stamped no count"); root.finish(); return }
                if (Date.now() - root.firstCountAt >= col.prebuild.holdMs) { root.failures.push("hold: the hold ended before the check ran"); root.finish(); return }
                if (col.prebuild.parkedCount !== 0 || col.prebuild.tickAt.length !== 0) root.failures.push("hold: parked=" + col.prebuild.parkedCount + " ticks=" + col.prebuild.tickAt.length + " within the hold after the first landing")
                root.peekBase = root.peekDelegates()
                root.stage = "holdwait"
            } else if (root.stage === "holdwait") {
                // Inside the hold the driver sleeps until the hold ends instead of ticking.
                if (Date.now() - root.firstCountAt < 600) return
                if (Date.now() - root.firstCountAt >= col.prebuild.holdMs) root.failures.push("hold: the hold ended before the check ran")
                root.settled("hold: inside the first landing's hold")
                root.stage = "keys"
            } else if (root.stage === "keys") {
                // (d) Keys at 0 and 8 ms into the prebuild.
                if (col.prebuild.tickAt.length >= 2) {
                    root.stubPane.inputAt = Date.now()
                    root.keyTimes.push(root.keyStamp(root.stubPane.inputAt))
                    key2.restart()
                    root.stage = "idle"
                }
            } else if (root.stage === "idle") {
                // (a) The driver idles with warmRows - 1 parked, none drawn, and no peek column built a row.
                if (col.prebuild.want !== 0 || col.prebuild.parkedCount !== col.viewport.model.warmRows - 1) return
                var all = root.delegatesOf(col), live = 0
                for (var j = 0; j < all.length; j++) {
                    if (all[j].live) { live += 1; continue }
                    if (!all[j].prebuilt || all[j].visible) root.failures.push("idle: a parked row is drawn")
                }
                if (live !== 1) root.failures.push("idle: " + live + " live rows, want 1")
                if (root.peekDelegates() !== root.peekBase) root.failures.push("idle: peek columns went from " + root.peekBase + " to " + root.peekDelegates() + " rows")
                if (Date.now() - root.firstCountAt < col.prebuild.holdMs) root.failures.push("idle: the pool filled inside the hold")
                root.checkKeys()
                // (b) The 1000-row landing adopts the pool: 0 built in any column, every viewport row live and named.
                root.createdBefore = root.createdAll()
                root.land("/probe/big", 1000, root.bigRows)
                if (root.createdAll() !== root.createdBefore) root.failures.push("landing: built " + (root.createdAll() - root.createdBefore) + " delegates, want 0")
                root.checkViewport()
                root.ticksBefore = col.prebuild.tickAt.length
                root.watchStart = Date.now()
                root.stage = "after"
            } else if (root.stage === "after") {
                // (c) Nothing builds and no tick runs in the 300 ms after the landing.
                if (Date.now() - root.watchStart < 300) return
                if (root.createdAll() !== root.createdBefore) root.failures.push("after: " + (root.createdAll() - root.createdBefore) + " delegates built in the 300 ms after the landing")
                if (col.prebuild.tickAt.length !== root.ticksBefore) root.failures.push("after: a prebuild tick ran in the 300 ms after the landing")
                // A Back pools the screenful, which the next landing takes, so the driver wants nothing.
                root.land("/probe", 1, root.dirRows("big", 1))
                if (root.createdAll() !== root.createdBefore) root.failures.push("back: built " + (root.createdAll() - root.createdBefore) + " delegates")
                if (col.prebuild.want !== 0) root.failures.push("back: the driver wants " + col.prebuild.want + " rows over a pooled screenful")
                root.watchStart = Date.now()
                root.stage = "a"
            } else if (root.stage === "a") {
                // (a) 1000 rows, then a 1-row folder; (e) Back to the 1000 rows, then the 1-row folder again.
                if (!root.waited(1000)) return
                root.settled("a: 1000 rows then a 1-row folder")
                root.landBuilt("e: Back after (a)", "/probe/big", 1000, root.bigRows)
                root.stage = "e"
            } else if (root.stage === "e") {
                if (!root.waited(1000)) return
                root.settled("e: Back after (a)")
                root.land("/probe", 1, root.dirRows("big", 1))
                root.stage = "hide"
            } else if (root.stage === "hide") {
                if (col.prebuild.tickAt.length !== root.ticksBefore) root.failures.push("back: a tick ran over a pooled screenful")
                area.visible = false
                root.stage = "refill"
            } else if (root.stage === "refill") {
                // A hidden column holds only its kept row; shown again it refills its pool with no second hold.
                if (col.prebuild.createdCount - col.prebuild.destroyedCount > 1) root.failures.push("hide: the column still holds " + (col.prebuild.createdCount - col.prebuild.destroyedCount) + " rows")
                area.visible = true
                root.watchStart = Date.now()
                root.stage = "refilled"
            } else if (root.stage === "refilled") {
                if (col.prebuild.parkedCount !== col.viewport.model.warmRows - 1) {
                    if (Date.now() - root.watchStart > 1500) { root.failures.push("refill: parked=" + col.prebuild.parkedCount + " 1500 ms after showing"); root.finish() }
                    return
                }
                root.settled("d: hidden and shown again")
                // (c) A folder shorter than warmRows adopts its rows and keeps the rest parked.
                root.landBuilt("c: a 20-row folder", "/probe/short", 20, root.fileRows(20))
                root.stage = "short"
            } else if (root.stage === "short") {
                if (!root.waited(1000)) return
                root.settled("c: a 20-row folder")
                if (col.prebuild.parkedCount !== col.viewport.model.warmRows - 20) root.failures.push("c: parked=" + col.prebuild.parkedCount + " in a 20-row folder")
                // A resize drains the pool under rows parked past a Back, and the driver refills the rows the next landing draws.
                root.land("/probe", 1, root.dirRows("big", 1))
                area.height = 1382
                area.height = 1381
                root.watchStart = Date.now()
                root.stage = "drain"
            } else if (root.stage === "drain") {
                if (!root.waited(1000)) return
                root.settled("drain: a resize after a Back")
                root.landBuilt("drain", "/probe/big", 1000, root.bigRows)
                root.land("/probe", 1, root.dirRows("big", 1))
                // A listing in flight holds the driver, and its landing starts it again.
                area.visible = false
                area.visible = true
                root.stubPane.listInFlight = true
                root.watchStart = Date.now()
                root.stage = "flight"
            } else if (root.stage === "flight") {
                if (!root.waited(500)) return
                root.settled("flight: a listing in flight")
                root.land("/probe/two", 1, root.dirRows("two", 1))
                root.watchStart = Date.now()
                root.stage = "landed"
            } else if (root.stage === "landed") {
                if (col.prebuild.parkedCount !== col.viewport.model.warmRows - 1) {
                    if (root.waited(1500)) { root.failures.push("flight: parked=" + col.prebuild.parkedCount + " 1500 ms after the landing"); root.finish() }
                    return
                }
                area.visible = false
                area.visible = true
                root.stubPane.renamingIndex = 0
                root.watchStart = Date.now()
                root.stage = "rename"
            } else if (root.stage === "rename") {
                if (!root.waited(500)) return
                root.settled("rename: a rename open")
                root.stubPane.renamingIndex = -1
                // Hiding the view drops the pool.
                area.visible = false
                root.stage = "hidden"
            } else if (root.stage === "hidden") {
                if (col.prebuild.parkedCount !== 0) root.failures.push("hide: parked=" + col.prebuild.parkedCount + ", want 0")
                if (col.prebuild.createdCount - col.prebuild.destroyedCount > 1) root.failures.push("hide: the column still holds " + (col.prebuild.createdCount - col.prebuild.destroyedCount) + " rows")
                root.finish()
            }
        }
    }

    Timer {
        interval: 50000
        running: true
        onTriggered: { root.failures.push("timeout at stage " + root.stage); root.finish() }
    }
    Component.onCompleted: Flea.ViewState.setTextSize({ mode: 14 })
}
