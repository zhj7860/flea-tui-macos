//@ pragma ShellId flea-startup-objects-test
import QtQuick
import Quickshell

ShellRoot {
    id: root
    // The shared rail receiver adds five objects; three enabled code slots add fifteen.
    readonly property int startupObjectLimit: root.marksOff ? 592 : 607
    readonly property int sectorsWrittenField: 6
    readonly property int deadlineProbeMs: 1200
    readonly property int sectorChangeDelayMs: 600
    readonly property int deadlineSlackMs: 200
    readonly property int reloadWaitMs: 2000
    // The hang leg's backend never answers, so the pane turns "waiting" after Startup.LISTING_WAIT_MS (10 s).
    readonly property bool hang: Quickshell.env("STARTUP_OBJECTS_HANG") === "1"
    readonly property string earlyMenu: Quickshell.env("STARTUP_OBJECTS_MENU_EARLY")
    readonly property bool marksOff: Quickshell.env("STARTUP_OBJECTS_MARKS_OFF") === "1"
    property bool finished: false
    property bool answered: false
    property bool coldReadChecked: false
    property var menuWarmFocus: null
    property int stableSamples: 0
    property int lastTotal: -1
    property int phase: 0
    property var device: null
    property var reader: null
    property var chainTimer: null
    property double chainStartedAt: 0
    property double pollStartedAt: 0
    property double chainExpiredAt: 0

    function finish(ok, reason) {
        if (finished) return
        finished = true
        console.log("STARTUP_OBJECTS " + (ok ? "PASS " : "FAIL ") + reason)
        console.log("STARTUP_OBJECTS DONE")
        if (body.item) body.item.quitBackends()
        retire.start()
    }

    // The seam's Loader in the body: "none", "idle", "active" while it incubates, or "built"; the census waits for "built".
    function seamState() {
        var d = body.item ? body.item.data : []
        for (var i = 0; i < d.length; i++)
            if (d[i] && String(d[i].source).indexOf("/Ipc.qml") >= 0)
                return String(d[i].item).indexOf("Ipc_") === 0 ? "built" : d[i].active ? "active" : "idle"
        return "none"
    }

    function census(start) {
        var seen = [], counts = {}
        function walk(object) {
            if (!object || seen.indexOf(object) >= 0) return
            seen.push(object)
            // Sample input: "PowerSectorsReader_QMLTYPE_42(0x1234)" becomes "PowerSectorsReader".
            var type = String(object).split("(")[0].replace(/_QML(TYPE)?_\d+/g, "")
            counts[type] = (counts[type] || 0) + 1
            var groups = [object.children, object.data, object.resources]
            for (var g = 0; g < groups.length; g++) {
                var group = groups[g]
                if (!group) continue
                for (var i = 0; i < group.length; i++) walk(group[i])
            }
            if (object.contentItem) walk(object.contentItem)
            if (object.item) walk(object.item)
        }
        walk(start || window)
        return { total: seen.length, counts: counts, objects: seen }
    }

    function checkDemand() {
        var sample = census()
        if (phase === 1) {
            if ((sample.counts.PowerSectorsReader || 0) !== 1)
                return finish(false, "first power-off did not build exactly one reader")
            reader = sample.objects.filter(function (object) {
                return String(object).indexOf("PowerSectorsReader_") === 0
            })[0]
            if (reader.owner !== device || !reader.path.endsWith("/stat"))
                return finish(false, "reader lost its owner or disk path")
            phase = 2
        } else if (phase === 2 && device._powerSectors.length > 0) {
            // Sample input: "1 0 2 3 0 0 42 0 0 0 0 0 0 0 0", field 6 is sectors written ("42").
            if (device._powerSectors !== String(reader.text()).trim().split(/\s+/)[sectorsWrittenField])
                return finish(false, "disk write count did not reach the host")
            if (Date.now() - chainStartedAt < sectorChangeDelayMs || device._streamPending) return
            device._powerSectors = "not-a-sector-count"
            phase = 3
            pollStartedAt = Date.now()
            var listingsBefore = device._listingsStarted
            device.poll()
            if (device._listingsStarted !== listingsBefore + 1)
                return finish(false, "production poll did not start while the chain was active")
        } else if (phase === 3) {
            if (device._powerSectors !== "not-a-sector-count") phase = 4
            else if (Date.now() - pollStartedAt >= reloadWaitMs)
                return finish(false, "production poll did not reload the disk write count")
        } else if (phase === 4 && chainExpiredAt > 0) {
            if (chainExpiredAt < pollStartedAt + deadlineProbeMs - deadlineSlackMs)
                return finish(false, "a changed sector count did not rearm the running chain deadline")
            console.log("STARTUP_OBJECTS DEADLINE initial=" + deadlineProbeMs + " changeAfter="
                + (pollStartedAt - chainStartedAt) + " expiredAfter=" + (chainExpiredAt - chainStartedAt))
            if (reader.path !== "" || census().counts.PowerSectorsReader !== 1)
                return finish(false, "reader was not retained and idle after the chain")
            chainTimer.interval = device.powerOffWaitMs
            device._powerSectors = ""
            device._powerOffDisk = Quickshell.env("STARTUP_OBJECTS_DISK")
            phase = 5
        } else if (phase === 5 && device._powerSectors.length > 0) {
            var next = census().objects.filter(function (object) {
                return String(object).indexOf("PowerSectorsReader_") === 0
            })
            if (next.length !== 1 || next[0] !== reader)
                return finish(false, "a later chain rebuilt the reader")
            device._powerOffDisk = ""
            root.phase = 6
        } else if (phase === 6) {
            var host = body.item.currentPane.menuHost
            if (!host.ready) return
            var menu = host.item
            if (host.Window.window.activeFocusItem !== root.menuWarmFocus)
                return finish(false, "idle menu warming changed the focused item")
            if ((census().counts.ContextMenu || 0) !== 1)
                return finish(false, "post-frame warming did not build exactly one context menu")
            menu.openBackground(Qt.point(50, 50))
            menu.close()
            menu.openBackground(Qt.point(60, 60))
            menu.close()
            if (host.item !== menu || (census().counts.ContextMenu || 0) !== 1)
                return finish(false, "context menu reopen rebuilt the warmed root")
            console.log("STARTUP_OBJECTS MENU cold=0 warm=1 reopen=1 ready=" + host.status)
            finish(true, "total=" + lastTotal + " limit=" + startupObjectLimit + " reader=0->1 retained=1 reload=ok deadline=ok")
        }
    }

    function earlyDemand() {
        var host = body.item.currentPane.menuHost
        if (!host.Window.window) return
        if (host.item) return root.finish(false, "early menu leg already warmed")
        body.item.currentPane.listArea.forceActiveFocus()
        var focused = host.Window.window.activeFocusItem
        if (!focused) return root.finish(false, "early menu focus control did not focus the listing")
        if (root.earlyMenu === "warming") {
            host.prewarm()
            if (host.status !== Loader.Loading || host.item !== null)
                return root.finish(false, "warming menu leg did not start an in-flight Loader")
        }
        host.openBackground(Qt.point(50, 50))
        var menu = host.item
        if (!menu || menu.parent !== host.parent || menu.identitySource !== body.item.currentPane
                || menu.focusOwner !== body.item.currentPane.listArea)
            return root.finish(false, "early menu demand lost its parent or live inputs")
        var oldZipMember = body.item.currentPane.flashZipMember
        body.item.currentPane.flashZipMember = "startup-menu-binding"
        if (menu.flashZipMember !== "startup-menu-binding")
            return root.finish(false, "early menu demand lost a live input binding")
        body.item.currentPane.flashZipMember = oldZipMember
        if (menu.focusHolder !== focused)
            return root.finish(false, "early menu construction changed the focus return target")
        host.close()
        if (host.Window.window.activeFocusItem !== focused)
            return root.finish(false, "early menu close did not restore focus")
        host.openBackground(Qt.point(60, 60))
        host.close()
        if (!menu || host.item !== menu || host.status !== Loader.Ready
                || (root.census().counts.ContextMenu || 0) !== 1)
            return root.finish(false, "early menu demand did not retain one ready root")
        var originalParent = host.parent
        var secondParent = Qt.createQmlObject('import QtQuick; Item { anchors.fill: parent }', originalParent, "menu-parent-check")
        host.parent = secondParent
        var followed = menu.parent === secondParent
        host.parent = originalParent
        followed = followed && menu.parent === originalParent
        secondParent.destroy()
        if (!followed) return root.finish(false, "loaded menu parent did not follow host parent")
        if (host.item !== menu || host.status !== Loader.Ready
                || (root.census().counts.ContextMenu || 0) !== 1)
            return root.finish(false, "reparenting the host lost the ready menu root")
        console.log("STARTUP_OBJECTS PARENT follows=1")
        return root.finish(true, "early-menu=" + root.earlyMenu + " ready=1 retained=1")
    }

    Connections {
        target: root.chainTimer
        function onTriggered() { root.chainExpiredAt = Date.now() }
    }

    FloatingWindow {
        id: window
        implicitWidth: 800
        implicitHeight: 600
        Loader {
            id: body
            anchors.fill: parent
            source: "file://" + Quickshell.env("STARTUP_OBJECTS_UI") + "/WindowBody.qml"
            onLoaded: {
                item.host = window
                if (root.earlyMenu) return
                var early = {
                    none: "the body has no IPC seam Loader",
                    active: "the IPC seam Loader was active before the first listing answered",
                    built: "the IPC seam was built before the first listing answered"
                }[root.seamState()]
                if (early) root.finish(false, early)
            }
            onStatusChanged: if (status === Loader.Error) root.finish(false, "WindowBody failed to load")
        }
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (root.finished || !body.item) return
            if (root.earlyMenu) { root.earlyDemand(); return }
            if (root.phase > 0) { root.checkDemand(); return }
            var pane = body.item.currentPane
            // Until the first listing answers, every sample must find the seam unbuilt; the hang leg loads for 10 s.
            if (!root.answered && pane.listingState === "loading") {
                if (root.seamState() !== "idle") root.finish(false, "the IPC seam was started while the first listing was loading")
                return
            }
            root.answered = true
            if (root.hang) {
                if (pane.listingState === "waiting" && root.seamState() === "built") root.finish(true, "waiting=ok seam=built")
                return
            }
            if (pane.listInFlight || pane.listingState !== "ready" || pane.total !== 3 || root.seamState() !== "built") return
            if (!root.coldReadChecked) {
                var host = pane.menuHost
                if (host.item) return root.finish(false, "the context menu was built before cold menu reads")
                pane.listArea.forceActiveFocus()
                root.menuWarmFocus = pane.Window.window.activeFocusItem
                if (!root.menuWarmFocus) return root.finish(false, "menu warm focus control did not focus the listing")
                host.close()
                host.refreshProviderRows()
                host.providersSettled()
                host.listingContext("", true)
                root.coldReadChecked = true
                if (host.item) return root.finish(false, "a cold menu read or provider reply built its visual")
            }
            var sample = root.census()
            root.stableSamples = sample.total === root.lastTotal ? root.stableSamples + 1 : 0
            root.lastTotal = sample.total
            if (root.stableSamples < 3) return
            console.log("STARTUP_OBJECTS TOTAL " + sample.total)
            var names = Object.keys(sample.counts).sort()
            for (var i = 0; i < names.length; i++)
                console.log("STARTUP_OBJECTS TYPE " + names[i] + " " + sample.counts[names[i]])
            var marks = root.marksOff ? 0 : 3
            if ((sample.counts.LangMark || 0) !== marks || (sample.counts.LangMarkLoader || 0) !== marks)
                return root.finish(false, "the default or saved-OFF code slots have the wrong language object count")
            var baseline = root.marksOff ? 590 : 605
            if (sample.total !== baseline)
                return root.finish(false, "startup moved from its " + baseline + "-object baseline to " + sample.total)
            console.log("LANGCOST startup off=" + root.marksOff + " total=" + sample.total
                + " added=" + (sample.total - 590) + " language=" + marks + " baseline=" + baseline)
            if ((sample.counts.ContextMenu || 0) !== 0)
                return root.finish(false, "the context menu was built before the startup cut")
            if (sample.total > root.startupObjectLimit)
                return root.finish(false, "total=" + sample.total + " limit=" + root.startupObjectLimit)
            if ((sample.counts.RailDrop || 0) !== 1)
                return root.finish(false, "startup has no single shared rail drop receiver")
            var rows = sample.objects.filter(function (object) {
                return String(object).indexOf("Row_") === 0
            })
            if (rows.length !== pane.total)
                return root.finish(false, "row count mismatch: rows.length=" + rows.length + " pane.total=" + pane.total)
            for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
                if (typeof rows[rowIndex].dateStamp !== "function")
                    return root.finish(false, "date stamp is not deferred: rows[" + rowIndex + "]="
                        + String(rows[rowIndex]) + " dateStamp type=" + typeof rows[rowIndex].dateStamp)
            }
            // Sample input: "Preview_QMLTYPE_77(0x55d0)" is Quick Look's root; "PreviewText_..." is one of its panes.
            var looks = function () {
                return root.census().objects.filter(function (object) { return /^Preview_/.test(String(object)) })
            }
            if (looks().length !== 0 || pane.preview !== null)
                return root.finish(false, "Quick Look is built before the first Space")
            var look = pane.quickLook()
            console.log("STARTUP_OBJECTS QUICKLOOK CARD " + (root.census().total - sample.total))
            if (looks().length !== 1 || look === null || pane.preview !== look || body.item.quickLook !== look)
                return root.finish(false, "pane.quickLook() did not build exactly one Quick Look and hand it to the pane")
            if (pane.quickLook() !== look || looks().length !== 1)
                return root.finish(false, "a second pane.quickLook() built another Quick Look")
            if (look.pane !== pane || look.active !== false)
                return root.finish(false, "the built Quick Look is not wired to the current pane, closed")
            var trashRows = sample.objects.filter(function (object) { return /^RailTrashRow_/.test(String(object)) })
            if (trashRows.length !== 1)
                return root.finish(false, "startup has no single Trash row")
            var trashDrop = trashRows[0].dropDecisions()
            if (!trashDrop || trashDrop.pane !== pane || trashRows[0].dropDecisions() !== trashDrop)
                return root.finish(false, "first Trash demand lost its pane or rebuilt its handler")
            if (trashDrop.accepts("", ["file://" + pane.join(pane.path, "a.txt")], pane.path)
                    || trashDrop.drop(null, "", []))
                return root.finish(false, "the loaded Trash handler accepted a foreign offer or no pane")
            var devices = sample.objects.filter(function (object) {
                return String(object).indexOf("DeviceMounts_") === 0
            })
            if (devices.length !== 1)
                return root.finish(false, "expected one device host")
            root.device = devices[0]
            var cold = root.census(root.device).counts
            if ((cold.PowerSectorsReader || 0) !== 0 || cold.FileView !== 1)
                return root.finish(false, "disk-write FileView exists before first power-off")
            root.phase = 1
            root.device._powerOffDisk = Quickshell.env("STARTUP_OBJECTS_DISK")
            root.device._powerOffQueue = []
            root.device.powerOffNext()
            var timers = root.census(root.device).objects.filter(function (object) {
                return String(object).indexOf("QQmlTimer") === 0 && object.interval === root.device.powerOffWaitMs && object.running
            })
            if (timers.length !== 1)
                return root.finish(false, "powerOffNext did not arm exactly one chain deadline")
            root.chainTimer = timers[0]
            // Shorten the real chain's timer before sampling progress, then observe its actual expiry.
            root.chainTimer.interval = root.deadlineProbeMs
            root.chainStartedAt = Date.now()
        }
    }
    Timer { id: retire; interval: 200; onTriggered: Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    Timer {
        interval: root.hang ? 14000 : 12000
        running: true
        onTriggered: root.finish(false, root.hang ? "a listing that never answered built no IPC seam" : "listing did not settle")
    }
}
