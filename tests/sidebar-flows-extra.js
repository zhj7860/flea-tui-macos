.import "flea/js/Devices.js" as Devices
.import "flea/js/TextSize.js" as TextSize
.import "flea/js/Tap.js" as Tap
.import "sidebar-flows-rail.js" as RailPress

// One rail row per trailing shape, each with the board's rule for where its label ends (see railBoardEdges).
var RAIL_BOARD = [
    { name: "a share's square", want: "slot", label: "Archive", path: "", group: "network", kind: "share", uri: "smb://example.com/data", mounted: false, glyph: "server" },
    { name: "an eject mark", want: "slot", label: "NAS", path: "", group: "network", kind: "share", uri: "smb://example.com/data", mounted: true, glyph: "server" },
    { name: "a phone's square", want: "slot", label: "SAMSUNG Android", path: "", group: "device", kind: "phone", uri: "mtp://x", size: null, mounted: false, glyph: "smartphone" },
    { name: "a mounted phone's mark", want: "slot", label: "SAMSUNG Android", path: "", group: "device", kind: "phone", uri: "mtp://x", size: null, mounted: true, glyph: "smartphone" },
    { name: "a volume with no size", want: "slot", label: "QEMU HARDDISK", path: "", group: "device", kind: "volume", device: "/dev/sdb1", mounted: false, removable: false, size: null, glyph: "drive" },
    { name: "a drive size and a square", want: "number", label: "QEMU HARDDISK", path: "", group: "device", kind: "volume", device: "/dev/sdb1", mounted: false, removable: false, size: 1000398934016, glyph: "drive" },
    { name: "a drive size and an eject mark", want: "number", label: "128GB", path: "/run/media/gm/128GB", group: "device", kind: "volume", device: "/dev/sda1", mounted: true, removable: true, size: 116100000000, glyph: "drive" },
    { name: "the system disk's size", want: "number", label: "minipc", path: "/", group: "device", kind: "disk", device: "/dev/nvme0n1", mounted: true, removable: false, size: 239000000000, glyph: "drive" },
    { name: "the Trash count", want: "count", label: "Trash", path: "trash:///", group: "trash", kind: "trash", glyph: "trash", count: 3 },
    { name: "a system disk with no size", want: "none", label: "minipc", path: "/", group: "device", kind: "disk", device: "/dev/nvme0n1", mounted: true, removable: false, size: null, glyph: "drive" },
    { name: "a Dropbox row", want: "none", label: "Dropbox", path: "/home/gm/Dropbox", group: "network", kind: "dropbox", glyph: "cloud" },
    { name: "a favourite", want: "none", label: "Home", path: "/home", group: "favorite", kind: "favorite", glyph: "house" }
]

// RailEject.html and RailDetails.html: the label ends one gap before its number, else its slot; the Trash count has no slot.
function railBoardEdges(row, want, pad, gap, slot, mark) {
    var edge = row.width - pad
    if (want === "slot") edge -= slot + gap
    else if (want === "number") edge -= slot + gap + row.detailItem.width + gap
    else if (want === "count") edge -= row.detailItem.width + gap
    return { left: pad + mark + gap, right: edge }
}

// The first board row that draws a drive size, the one an incomplete board waits on.
var FIRST_SIZE_INDEX = RAIL_BOARD.findIndex(function (kind) { return kind.want === "number" })
var FIRST_SIZE_ROW = RAIL_BOARD[FIRST_SIZE_INDEX].name

// The first drive size row's detail read straight off the row, "no row" when the board lacks it.
function firstSizeDetail(rows) {
    var row = rows.itemAt(FIRST_SIZE_INDEX)
    return row ? row.detail : "no row"
}

// Why the board is not whole yet: a wrong row count, else the first row missing, short of its width or of its detail; "" when whole.
function railBoardWaiting(rows, width) {
    if (rows.count !== RAIL_BOARD.length) return "the rail board has " + rows.count + " rows, want " + RAIL_BOARD.length
    for (var i = 0; i < RAIL_BOARD.length; i++) {
        var row = rows.itemAt(i), want = RAIL_BOARD[i].want
        if (!row || row.width !== width || ((want === "number" || want === "count") && row.detail.length === 0)) return RAIL_BOARD[i].name
    }
    return ""
}

// Each board row draws the detail its kind wants and ends its label on the board's edge; run once railBoardWaiting answers "".
function railBoardChecks(root, rows, pad, gap, slot, mark) {
    for (var i = 0; i < RAIL_BOARD.length; i++) {
        var row = rows.itemAt(i), kind = RAIL_BOARD[i], wantsDetail = kind.want === "number" || kind.want === "count"
        root.check("rail-board: " + kind.name + " draws " + (wantsDetail ? "a detail" : "no detail") + " (drew " + JSON.stringify(row.detail) + ")", row.detail.length > 0, wantsDetail)
        var edges = railBoardEdges(row, kind.want, pad, gap, slot, mark)
        root.check("rail-board: " + kind.name + " starts its label after the mark", row.labelItem.x, edges.left)
        root.check("rail-board: " + kind.name + " ends its label on the board's edge", row.labelItem.x + row.labelItem.width, edges.right)
    }
}

// Additional real-UI proofs share the hunt's fixture, driver and tally.
function steps(root, pane, state, theme) {
    var expectedSize = 0
    var tests = [
        function () {
            state.changeKey("openMode", "double")
            pane.chooseView("list")
            pane.open(root.fixture)
            return true
        },
        function () {
            if (!root.ready(root.fixture)) return false
            expectedSize = TextSize.stepped(state.textSize, state.omarchyBase, 1).mode
            var sheet = root.openSheet()
            sheet.query = "larger"
            sheet.resultCursor = sheet.queryResults.findIndex(function (row) { return row.action === "textSizeUp" })
            root.check("control: sheet offers Larger", sheet.resultCursor >= 0, true)
            sheet.activateResult()
            return true
        },
        function () {
            root.check("sheet-window-action: Larger steps the real text size", theme.baseSize, expectedSize)
            state.followTextSize()
            state.changeLeaf("places", { rail: "hidden" })
            return true
        },
        function () {
            if (pane.sidebar) return false
            var sheet = root.openSheet()
            sheet.query = "home"
            sheet.resultCursor = sheet.queryResults.findIndex(function (row) { return row.section === 2 && row.name === "Home" })
            root.check("control: hidden rail Home can be chosen", sheet.resultCursor >= 0, true)
            sheet.activateResult()
            return true
        },
        function () {
            if (pane.listInFlight) return false
            root.check("sheet-hidden-rail: Home runs its real navigation", pane.path, pane.home)
            state.changeLeaf("places", { rail: "shown" })
            pane.open(root.fixture)
            return true
        },
        function () {
            if (!root.ready(root.fixture)) return false
            pane.trash.open()
            return true
        },
        function () {
            var trash = pane.trash.item
            if (!trash || trash.busy) return false
            root.check("control: Trash has its seeded item", trash.total, 1)
            trash.choose(0, false)
            pane.trash.sheetAction("keymapSheet")
            var sheet = root.sheet()
            sheet.query = "restore"
            root.check("trash-sheet: query offers Restore", sheet.queryResults.some(function (row) { return row.menuAction === "restoreTrashSelection" }), true)
            sheet.query = "empty trash"
            root.check("trash-sheet: query offers Empty Trash", sheet.queryResults.some(function (row) { return row.menuAction === "emptyTrash" && row.danger }), true)
            sheet.query = "delete permanently"
            sheet.resultCursor = sheet.queryResults.findIndex(function (row) { return row.menuAction === "deletePermanently" && row.danger })
            root.check("trash-sheet: permanent delete keeps its danger", sheet.resultCursor >= 0, true)
            sheet.activateResult()
            return true
        },
        function () {
            var trash = pane.trash.item
            if (trash.busy) return false
            root.check("trash-sheet: destructive query opens confirmation", trash.confirming, true)
            trash.close()
            return true
        },
        function () {
            // MountFail: the rail's own DeviceMounts reports a refused mount through the real chain to the real bar.
            var devices = null
            for (var i = 0; i < pane.sidebar.data.length; i++)
                if (typeof pane.sidebar.data[i].reportFailure === "function") devices = pane.sidebar.data[i]
            root.check("mount-fail: the rail holds its DeviceMounts", devices !== null, true)
            if (devices === null) return true
            var bar = pane.statusBar
            var prior = bar.errors
            var stderr = "gio: Error mounting /dev/sdb1 at /run/media/user/DATA #2: wrong fs type, bad option, bad superblock on /dev/sdb1, missing codepage or helper program, or other error"
            var headline = Devices.mountError("mount", 1, stderr, "DATA #2")
            var reason = "wrong fs type, bad option, bad superblock on /dev/sdb1, missing codepage or helper program, or other error"
            bar.errors = []
            devices.reportFailure(headline, stderr)
            root.check("mount-fail: the first failed click shows its headline", bar.errors.map(function (e) { return e.text }), [headline])
            root.check("mount-fail: the first failed click carries gio's reason", bar.errorDetail, reason)
            devices.reportFailure(headline, stderr)
            root.check("mount-fail: a repeated click shows the error again", bar.errors.length, 2)
            bar.errors = prior
            return true
        },
        mountExits(root, pane)
    ]
    return tests.concat(clicks(root, pane, "list"), clicks(root, pane, "grid"), clicks(root, pane, "columns"), RailPress.steps(root, pane, state))
}

// MountFail: each exit handler of the rail's DeviceMounts runs for real on a fake gio that fails with stderr; the bar must show the handler's headline and gio's reason.
function mountExits(root, pane) {
    var damaged = "Error mounting /dev/sdb1 at /run/media/user/DATA #2: wrong fs type, bad option, bad superblock on /dev/sdb1, missing codepage or helper program, or other error"
    var busy = "Error unmounting /dev/sdb1: target is busy"
    var refused = "gio: file:///run/media/user/Stick: Error ejecting /dev/sdb: Not authorized"
    var runs = [
        { name: "a refused mount", process: "mountProcess", stderr: damaged, label: "DATA #2", detail: "wrong fs type, bad option, bad superblock on /dev/sdb1, missing codepage or helper program, or other error",
          state: { _pendingOpenDevice: "/dev/sdb1", _pendingOpenLabel: "DATA #2", _mountErr: "" }, op: "mount" },
        { name: "a refused unmount", process: "unmountProcess", stderr: busy, label: "Vault", detail: "target is busy",
          state: { _unmountLabel: "Vault", _unmountEndedLate: false, _powerOffDisk: "" }, op: "unmount" },
        { name: "a refused unmount in a power-off chain", process: "unmountProcess", stderr: busy, label: "Stick", detail: "target is busy",
          state: { _ejectLabel: "Stick", _unmountEndedLate: false, _powerOffDisk: "/dev/sdb" }, op: "unmount" },
        { name: "a refused power-off eject", process: "ejectProcess", stderr: refused, label: "Stick", detail: "Not authorized",
          state: { _ejectLabel: "Stick", _ejectEndedLate: false, _powerOffDisk: "/dev/sdb" }, op: "eject" }
    ]
    var at = 0, started = false, devices = null, prior = null
    return function () {
        if (devices === null) {
            for (var i = 0; i < pane.sidebar.data.length; i++)
                if (typeof pane.sidebar.data[i].reportFailure === "function") devices = pane.sidebar.data[i]
            root.check("mount-exit: the rail holds its DeviceMounts", devices !== null, true)
            if (devices === null) return true
            prior = pane.statusBar.errors
        }
        var bar = pane.statusBar, run = runs[at]
        if (!started) {
            var process = null
            for (var j = 0; j < devices.data.length; j++)
                if (devices.data[j].objectName === run.process) process = devices.data[j]
            root.check("mount-exit: " + run.name + " finds its process", process !== null, true)
            if (process === null) return true
            for (var key in run.state) devices[key] = run.state[key]
            bar.errors = []
            process.command = ["sh", "-c", "printf '%s' \"$0\" >&2; exit 1", run.stderr]
            process.running = true
            started = true
            return false
        }
        if (bar.errors.length === 0) return false
        root.check("mount-exit: " + run.name + " shows the handler's headline", bar.errors.map(function (e) { return e.text }), [Devices.mountError(run.op, 1, run.stderr, run.label)])
        root.check("mount-exit: " + run.name + " carries gio's reason", bar.errorDetail, run.detail)
        started = false
        at++
        if (at < runs.length) return false
        bar.errors = prior
        return true
    }
}

function clicks(root, pane, mode) {
    var at = 0
    var name = "renamed.txt"
    function row() { return pane.visibleItemFor(root.indexOf(name)) }
    function settled() { return Date.now() - at > Qt.styleHints.mouseDoubleClickInterval + 100 }
    function blank() {
        var item = row(), label = item.captionItem || item.nameItem()
        root.click(label, label.width - 2, Math.min(label.implicitHeight, label.height) / 2)
        at = Date.now()
    }
    return [
        function () {
            pane.chooseView(mode)
            pane.cancelSlowClick()
            pane.clearSelection()
            return true
        },
        function () {
            if (!row()) return false
            var item = row(), label = item.captionItem || item.nameItem()
            // Sample input: 412 237 (rowNameCentre x y, window-relative), or empty for a row with no name.
            var centre = root.ipc().rowNameCentre(root.indexOf(name)).split(" ").map(Number)
            var point = item.mapFromItem(null, centre[0], centre[1])
            root.check("rowNameCentre-" + mode + ": lands inside its own row",
                centre.length === 2 && point.x >= 0 && point.x < item.width && point.y >= 0 && point.y < item.height, true)
            root.check("rowNameCentre-" + mode + ": product accepts the drawn name",
                Tap.onName(label, null, {x: centre[0], y: centre[1]}, !!item.captionItem), true)
            root.check("rowNameCentre-" + mode + ": missing row has no target", root.ipc().rowNameCentre(-1), "")
            root.clickName(name)
            at = Date.now()
            return true
        },
        function () { if (!settled()) return false; root.clickName(name); at = Date.now(); return true },
        function () {
            if (!settled()) return false
            root.check("slow-click-" + mode + ": second name click renames", pane.renamingIndex, root.indexOf(name))
            pane.renamingIndex = -1
            pane.cancelSlowClick()
            return true
        },
        function () { blank(); return true },
        function () { if (!settled()) return false; blank(); return true },
        function () {
            if (!settled()) return false
            root.check("slow-click-name-only-" + mode + ": blank label slot only selects", pane.renamingIndex, -1)
            pane.renamingIndex = -1
            pane.cancelSlowClick()
            return true
        }
    ]
}
