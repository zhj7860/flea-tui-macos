//@ pragma ShellId flea-framegap-test

import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Settings.js" as Settings
import "framegap.js" as Gap
import "button-probe.js" as Probe

// tests/framegap.sh's harness: every framed control in the real dialogs, cards, rows and panels keeps Theme.chromeControlInset from the nearest rule and from its host's edge, at three text stops, at rest and with focus on every control.
ShellRoot {
    id: root

    readonly property var stops: [12, 14, 16]
    // Frames a step waits after an act, so layout, delegates and the card fades have settled before a read.
    readonly property int settleTicks: 6
    readonly property int tickMs: 16
    readonly property int windowWidth: 1000
    readonly property int windowHeight: 900
    readonly property int sideHostWidth: 600
    // One copy in flight, as the transfer card and the Flash step read it.
    readonly property var inFlight: ({ id: 1, moving: false, n: 2, index: 1, name: "a.txt", running: true, done: 0, bytes: 1024, total: 4096, moved: 0, writing: false, drive: "" })
    // The picker's filter trigger in the answer row, at every stop the Display section offers.
    readonly property var chipStops: [9, 10, 11, 12, 14, 16, 20]
    property int chipChecks: 0
    property int chipFailed: 0
    property int chipWant: -1

    property var plan: []
    property int at: 0
    property int wait: 0
    property int checks: 0
    property int failed: 0
    // Control rows are counted apart: fixtures that must be flagged.
    property int controls: 0
    property int controlMiss: 0
    property int focusMiss: 0
    property int clipped: 0
    property var seen: ({})

    function log(line) { console.log("FRAMEGAP " + line) }
    function finish() {
        var hosts = Object.keys(root.seen).sort()
        root.log("HOSTS " + hosts.length + " " + hosts.join(","))
        if (root.chipChecks === 0) root.log("FAIL no picker chip row was read")
        if (root.failed === 0 && root.controlMiss === 0 && root.focusMiss === 0 && root.chipChecks > 0 && root.chipFailed === 0)
            root.log("PASS " + root.checks + " checks over " + hosts.length + " hosts plus " + root.controls + " controls, every frame keeps the inset and every control is flagged")
        root.log("DONE checks=" + root.checks + " failed=" + root.failed + " controls=" + root.controls + " controlMiss=" + root.controlMiss + " focusMiss=" + root.focusMiss)
        root.log("CHIPS checks=" + root.chipChecks + " failed=" + root.chipFailed)
        root.at = root.plan.length + 1
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
    function stopState(stop) { Flea.ViewState.load(JSON.stringify({ display: { textSize: { mode: stop } } })) }

    // Each host is measured on its card, its own root where it has no card.
    function hosts() {
        return [["OpenWithDialog", openWith.cardItem], ["ConvertDialog", convert.cardItem], ["ArchiveCompressDialog", compress.cardItem],
                ["ArchivePasswordDialog", password.cardItem], ["FatNamesConfirm", fat.cardItem], ["TrashConfirm", trash.cardItem],
                ["CollideConfirm", collide.cardItem], ["BulkRenameDialog", bulk.cardItem], ["MenuActionDialog", menuAction.cardItem],
                ["UnlockDialog", unlock.cardItem], ["NetworkDialog", network.cardItem], ["RunCard", runCard.cardItem],
                ["KeymapSheet", sheet.cardItem], ["TransferCard", transfer], ["FlashStepRow", flashRow], ["MediaStrip", framedStrip],
                ["MediaStrip unframed", bareStrip]]
    }

    // Fixture hosts the reader must flag, apart from the real hosts.
    function controlHosts() {
        return [["GapDialog", controlDialogHost], ["GapCheck", controlCheckHost], ["GapChrome", controlChromeHost], ["GapCrossing", controlCrossingHost]]
    }

    // A control row must be flagged; an unflagged one means the reader went blind, not that the fixtures are clear.
    function measure(name, host, state, stop, control) {
        if (!control) root.seen[name] = true
        var rows = Gap.rows(name, host, Flea.Theme.spacing.hairline, Flea.Theme.chromeControlInset, state, stop)
        for (var i = 0; i < rows.length; i++) {
            var r = rows[i]
            var line = [r.host, r.owner, r.name, r.frame, r.box, r.state, r.stop, r.side, r.rule, r.edge, r.inset].join("\t")
            if (control) {
                root.controls += 1
                if (!r.under) { root.controlMiss += 1; root.log("CONTROLMISS " + line); continue }
                root.log("CONTROLROW " + line)
                continue
            }
            if (r.clipped) { root.clipped += 1; root.log("CLIPPED " + line); continue }
            root.checks += 1
            root.log("ROW " + line)
            if (!r.under) continue
            root.failed += 1
            root.log("FAIL " + line)
        }
    }

    // The filter trigger is the one chip; it sits in the answer row under the listing.
    function pickerChips() { return pickerAnswers.filterItem.visible ? [pickerAnswers.filterItem] : [] }

    // Each picker chip frame against the path strip top and its rule, one row per side.
    function chipMeasure(state, stop) {
        var chips = root.pickerChips()
        if (chips.length !== 1) {
            root.chipChecks += 1
            root.chipFailed += 1
            root.log("FAIL PickerChips " + chips.length + " items for one filter trigger at stop " + stop)
            return
        }
        // An offscreen window is never active, so the focus a chip takes shows as focus and not activeFocus; a pass without the asked chip would re-measure another state.
        if (state === "focus" && !(chips[root.chipWant] && chips[root.chipWant].focus)) {
            root.chipChecks += 1
            root.chipFailed += 1
            root.log("FAIL PickerChips chip " + root.chipWant + " does not hold the focus at stop " + stop)
        }
        // The answer row's rule is its top hairline; its bottom edge is the far rule the trigger keeps clear of.
        var stripTop = Flea.Theme.spacing.hairline
        var ruleTop = pickerAnswers.height - Flea.Theme.spacing.hairline
        chips.forEach(function (chip) {
            var frame = Gap.chipFind(chip, "frame")
            if (!frame) {
                root.chipChecks += 1
                root.chipFailed += 1
                root.log("FAIL PickerChips no frame under " + chip.name + " at stop " + stop)
                return
            }
            var box = frame.mapToItem(pickerAnswers, 0, 0, frame.width, frame.height)
            Gap.chipRows("PickerChips", chip.name, box, stripTop, ruleTop, Flea.Theme.spacing.hairline, Flea.Theme.chromeControlInset, state, stop, chip.focus).forEach(function (r) {
                var line = [r.host, r.name, r.state, r.stop, r.side, r.rule, r.edge, r.inset, r.focused].join("\t")
                root.chipChecks += 1
                root.log("CHIPROW " + line)
                if (!r.under) return
                root.chipFailed += 1
                root.log("FAIL " + line)
            })
        })
    }
    function chipRest() { root.chipWant = -1; parking.forceActiveFocus() }
    function chipFocus(i) { root.chipWant = i; root.pickerChips()[i].forceActiveFocus() }

    // A focused DialogButton frames itself in the rule's colour, read off Theme and never off focusFrame.
    function drawsFocus(button) {
        var frame = Probe.find(button, "buttonFrame")
        if (frame === null) return false
        var want = button.setMember && Flea.Theme.color.accentHasHue ? Flea.Theme.color.accent : Flea.Theme.color.foreground
        var colour = Probe.rgba(frame.border.color)
        var width = frame.border.width
        button.focused = false
        var restColour = Probe.rgba(frame.border.color)
        var restWidth = frame.border.width
        button.focused = true
        return colour === Probe.rgba(want) && (colour !== restColour || width !== restWidth)
    }

    // Focus every control at once (set member current, check box filled, mark keyboard-lit); a control that does not draw its focus frame once set is a miss.
    function focusAll(quiet) {
        var roots = root.hosts().map(function (h) { return [h[0], h[1]] })
        roots.push(["SettingsPanel", settings.cardItem])
        root.controlHosts().forEach(function (h) { roots.push(h) })
        var totals = { DialogButton: [0, 0], CheckBox: [0, 0], ChromeButton: [0, 0] }
        roots.forEach(function (entry) {
            var counts = { DialogButton: [0, 0], CheckBox: [0, 0], ChromeButton: [0, 0] }
            var stack = [entry[1]]
            while (stack.length > 0) {
                var o = stack.pop()
                if (!o) continue
                var kids = o.children !== undefined ? o.children : []
                for (var i = 0; i < kids.length; i++) stack.push(kids[i])
                // A protocol chip is a DialogButton set member, so the accent rule reaches it.
                var type = Gap.typeOf(o) === "ProtocolChip" ? "DialogButton" : Gap.typeOf(o)
                if (counts[type] === undefined) continue
                counts[type][0] += 1
                if (type === "DialogButton") { o.focused = true; if (o.setMember) o.current = true }
                else if (type === "CheckBox") { o.value = "on"; o.focused = true }
                else if (type === "ChromeButton") o.keyboardFocused = true
                var held = type === "ChromeButton" ? o.keyboardFocused === true && (!o.visible || !o.enabled || o.ringItem.visible)
                    : type === "CheckBox" ? o.focused === true && o.value === "on" && (!o.visible || (Probe.find(o, "checkRing") || { visible: false }).visible)
                    : o.focused === true && (!o.setMember || o.current === true) && (!o.available || root.drawsFocus(o))
                if (held) counts[type][1] += 1
            }
            for (var t in counts) {
                totals[t][0] += counts[t][0]
                totals[t][1] += counts[t][1]
                if (counts[t][1] < counts[t][0]) { root.focusMiss += 1; root.log("FOCUSMISS " + entry[0] + " " + t) }
            }
            if (!quiet) root.log("FOCUS " + entry[0] + " DialogButton=" + counts.DialogButton[0] + "/" + counts.DialogButton[1]
                                 + " CheckBox=" + counts.CheckBox[0] + "/" + counts.CheckBox[1]
                                 + " ChromeButton=" + counts.ChromeButton[0] + "/" + counts.ChromeButton[1])
        })
        for (var g in totals) {
            if (totals[g][1] === 0) { root.focusMiss += 1; root.log("FOCUSMISS all " + g) }
        }
        if (!quiet) root.log("FOCUSSUM DialogButton=" + totals.DialogButton[0] + "/" + totals.DialogButton[1]
                             + " CheckBox=" + totals.CheckBox[0] + "/" + totals.CheckBox[1]
                             + " ChromeButton=" + totals.ChromeButton[0] + "/" + totals.ChromeButton[1])
    }

    function buildPlan() {
        var plan = [function () {
            Flea.Theme.applyColors(Probe.COLOURED_THEME)
            openWith.open("openWith", 1, "", parking)
            openWith.receive({ op: "applications", id: 1, ok: true, path: "/framegap/notes.txt", kind: "Plain text document", mime: "text/plain",
                               applications: [{ id: "a.desktop", label: "Alpha", icon: "a", default: true }],
                               installed: [{ id: "a.desktop", label: "Alpha", icon: "a" }, { id: "b.desktop", label: "Beta", icon: "b" }] })
            convert.open("photo.png", holder)
            compress.open({ paths: ["/framegap/notes.txt"], menuId: 0 }, "framegap", holder)
            password.open({ path: "/framegap/locked.7z", dest: "/framegap" }, holder, "")
            fat.open("Some names change on this drive", [{ old: "a:b.txt", new: "a_b.txt", d: false, i: "" }], "The drive cannot store these characters.")
            trash.open({ token: 1, all: true, count: 3, bytes: 4096 })
            collide.open("1 item already exists here", [{ n: "a.txt", d: false, i: "" }], "", true)
            bulk.open(["/framegap/a.txt", "/framegap/b.txt"], parking)
            menuAction.open("newFile", 1, "/framegap", parking)
            unlock.openFor("/dev/sdb1", "Backup", 500000000000, "crypto_LUKS", "2")
            network.open()
            runCard.open({ path: "/framegap/tool.sh", raw: '{"ask":"run","kind":"script","size":9420,"handlerId":"","handlerName":"","dev":"8","ino":"9","mtimeS":"11","mtimeNs":"12","target":"/framegap/tool.sh"}' }, null)
            sheet.open(sheetHolder)
            // A typed query shows the sheet's own field frame.
            sheet.query = "copy"
            settings.open(null)
        }]
        var states = ["rest", "focus"]
        states.forEach(function (state) {
            if (state === "focus") plan.push(root.focusAll)
            root.stops.forEach(function (stop) {
                plan.push(function () { root.stopState(stop) })
                plan.push(function () { root.hosts().forEach(function (h) { root.measure(h[0], h[1], state, stop) }) })
                plan.push(function () { root.controlHosts().forEach(function (h) { root.measure(h[0], h[1], state, stop, true) }) })
                Settings.SECTIONS.forEach(function (section) {
                    plan.push(function () { settings.showSection(section.id) })
                    plan.push(function () {
                        if (state === "focus") root.focusAll(true)
                        root.measure("SettingsPanel " + section.id, settings.cardItem, state, stop)
                    })
                })
            })
        })
        root.chipStops.forEach(function (stop) {
            plan.push(function () { root.stopState(stop) })
            plan.push(function () { root.chipRest(); root.chipMeasure("rest", stop) })
            plan.push(function () { root.chipFocus(0) })
            plan.push(function () { root.chipMeasure("focus", stop) })
        })
        root.plan = plan
    }

    Timer {
        interval: root.tickMs
        repeat: true
        running: root.at <= root.plan.length
        onTriggered: {
            if (root.wait > 0) { root.wait -= 1; return }
            if (root.plan.length === 0) { root.buildPlan(); return }
            if (root.at === root.plan.length) { root.finish(); return }
            root.plan[root.at]()
            root.at += 1
            root.wait = root.settleTicks
        }
    }

    FloatingWindow {
        implicitWidth: root.windowWidth
        implicitHeight: root.windowHeight
        color: Flea.Theme.color.background

        Item {
            anchors.fill: parent
            Flea.OpenWithDialog { id: openWith }
            Flea.ConvertDialog { id: convert }
            Flea.ArchiveCompressDialog { id: compress }
            Flea.ArchivePasswordDialog { id: password }
            Flea.FatNamesConfirm { id: fat }
            Flea.TrashConfirm { id: trash }
            Flea.CollideConfirm { id: collide }
            Flea.BulkRenameDialog { id: bulk }
            Flea.MenuActionDialog { id: menuAction }
            Flea.UnlockDialog { id: unlock }
            Flea.NetworkDialog { id: network }
            Flea.RunCard { id: runCard }
            Flea.KeymapSheet { id: sheet; anchors.fill: parent }
            Flea.SettingsPanel { id: settings; anchors.fill: parent }
        }

        // The cards and strips a window hosts outside a dialog, each at the width its host gives it.
        Column {
            x: root.windowWidth - root.sideHostWidth
            width: root.sideHostWidth
            Flea.TransferCard { id: transfer; transfer: root.inFlight }
            Flea.FlashStepRow { id: flashRow; width: parent.width; transfer: root.inFlight; words: ({ erase: "Erase Backup", action: "Flash" }); live: true; cursor: true }
            Flea.MediaStrip { id: framedStrip; width: parent.width; duration: 60000 }
            Flea.MediaStrip { id: bareStrip; width: parent.width; duration: 60000; framed: false }
            Flea.PickerChrome { id: pickerChrome; width: parent.width; picker: mockPicker }
            Flea.PickerAnswers { id: pickerAnswers; width: parent.width; picker: mockPicker }
        }

        // The holders the dialogs read: a source, a list area, a backend that answers nothing, and the sheet's pane.
        Item {
            id: holder
            property var convertSource: ({ name: "photo.png", path: "/framegap/photo.png", menuId: "framegap" })
            property Item listArea: Item {}
            property QtObject backend: QtObject {
                signal convertChecked(var message)
                signal convertStarted(int id, int requestId, var source)
                signal convertDone(int id, bool ok, string path, string err, int requestId, var source, bool collision)
                signal failed(string where, var input, string message, string mode)
                function convertImage() {}
                readonly property var archiveFormats: ["7z", "zip"]
            }
        }
        Item {
            id: sheetHolder
            property bool dualMode: false
            property string home: "/framegap"
            property var sidebar: null
            property bool listInFlight: false
            property var cursorRow: ({ n: "a.txt", d: false })
            property var context: ({})
            function sheetMenuAction(action) {}
            function checkShebang() {}
            function message(text, sticky) {}
            function contextMenu() { return { listingContext: function () { return sheetHolder.context } } }
        }
        // The picker's own face as PickerChrome and PickerAnswers read it: one filter with its chips, one chosen.
        QtObject {
            id: mockPicker
            property var req: ({ mode: "open", title: "Choose file", app: "", accept: "", multiple: false, filters: [{ label: "Images" }] })
            property color edge: "#444444"
            property var marks: []
            property bool canAccept: true
            property var history: ["/a"]
            property bool backendUnavailable: false
            property bool submitting: false
            property bool saving: false
            property bool collisionReview: false
            property bool recent: false
            property bool answered: false
            property string path: "/home/x/y"
            property string home: "/home/x"
            property bool showHidden: false
            property bool listingFailed: false
            property int filterIndex: 0
            property string viewMode: "list"
            property Item contentItem: holder
            function accept() {}
            function cancel() {}
            function replace() {}
            function stepFocus(from, back) {}
            function control(name, item, available) { return { name: name } }
        }
        Item { id: parking; width: 10; height: 10; focus: true }
    }

    // Negative controls the reader must flag: a dialog button a hairline from a rule, a check box on its host edge, a ruleless chrome button over a rule, a dialog button crossing the bottom edge of a host that does not scroll.
    FloatingWindow {
        implicitWidth: 340
        implicitHeight: 640
        color: Flea.Theme.color.background

        Item {
            anchors.fill: parent
            Item {
                id: controlDialogHost
                x: 20; y: 20; width: 300; height: 120
                Flea.DialogButton { id: controlDialog; x: 40; y: 30; width: 220; height: 48; label: "Gap control" }
                Rectangle { height: Flea.Theme.spacing.hairline; x: 40; width: 220; anchors.top: controlDialog.bottom; anchors.topMargin: 1; color: Flea.Theme.color.muted }
                Rectangle { height: Flea.Theme.spacing.hairline; x: 40; width: 220; anchors.bottom: controlDialog.top; anchors.bottomMargin: 1; color: Flea.Theme.color.muted }
                Rectangle { width: Flea.Theme.spacing.hairline; y: 30; height: 48; anchors.right: controlDialog.left; anchors.rightMargin: 1; color: Flea.Theme.color.muted }
                Rectangle { width: Flea.Theme.spacing.hairline; y: 30; height: 48; anchors.left: controlDialog.right; anchors.leftMargin: 1; color: Flea.Theme.color.muted }
            }
            Item {
                id: controlCheckHost
                x: 20; y: 160; width: 300; height: 120
                Flea.CheckBox { id: controlCheck; objectName: "GapCheck"; x: 40; y: 0 }
                Rectangle { width: Flea.Theme.spacing.hairline; anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.right: controlCheck.left; anchors.rightMargin: 1; color: Flea.Theme.color.muted }
                Rectangle { width: Flea.Theme.spacing.hairline; anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: controlCheck.right; anchors.leftMargin: 1; color: Flea.Theme.color.muted }
                Rectangle { height: Flea.Theme.spacing.hairline; anchors.left: parent.left; anchors.right: parent.right; anchors.top: controlCheck.bottom; anchors.topMargin: 1; color: Flea.Theme.color.muted }
            }
            Item {
                id: controlChromeHost
                x: 20; y: 300; width: 300; height: 140
                // The ring centres in the button, so its host box is read off the ring, not anchored to it.
                readonly property real ringX: controlChrome.x + (controlChrome.width - controlChrome.ringItem.width) / 2
                readonly property real ringY: controlChrome.y + (controlChrome.height - controlChrome.ringItem.height) / 2
                readonly property real ringW: controlChrome.ringItem.width
                readonly property real ringH: controlChrome.ringItem.height
                Flea.ChromeButton { id: controlChrome; x: 40; y: 30; width: 64; height: 40 }
                Rectangle { height: Flea.Theme.spacing.hairline; width: controlChromeHost.ringW + 8; x: controlChromeHost.ringX - 4; y: controlChromeHost.ringY - 1 - Flea.Theme.spacing.hairline; color: Flea.Theme.color.muted }
                Rectangle { height: Flea.Theme.spacing.hairline; width: controlChromeHost.ringW + 8; x: controlChromeHost.ringX - 4; y: controlChromeHost.ringY + controlChromeHost.ringH + 1; color: Flea.Theme.color.muted }
                Rectangle { width: Flea.Theme.spacing.hairline; height: controlChromeHost.ringH + 8; x: controlChromeHost.ringX - 1 - Flea.Theme.spacing.hairline; y: controlChromeHost.ringY - 4; color: Flea.Theme.color.muted }
                Rectangle { width: Flea.Theme.spacing.hairline; height: controlChromeHost.ringH + 8; x: controlChromeHost.ringX + controlChromeHost.ringW + 1; y: controlChromeHost.ringY - 4; color: Flea.Theme.color.muted }
            }
            Item {
                id: controlCrossingHost
                x: 20; y: 460; width: 300; height: 120
                Flea.DialogButton { x: 0; y: 0; width: 300; height: 140; label: "Gap crossing" }
            }
        }
    }
}
