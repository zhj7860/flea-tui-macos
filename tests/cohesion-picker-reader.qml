//@ pragma ShellId flea-cohesion-picker-reader-test
import QtQuick
import Quickshell

// the picker's twin of the montage reader names each control with a box inside the picker, offscreen.
ShellRoot {
    id: root
    property var win: null
    property int ticks: 0
    property bool focused: false
    property bool menuOpened: false
    property int checks: 0
    property var failures: []

    function check(cond, label) {
        root.checks++
        if (!cond) { root.failures.push(label); console.log("COHPICKER FAIL " + label) }
    }
    function handler() {
        for (var i = 0; i < win.data.length; i++)
            if (win.data[i].target === "fleapicker") return win.data[i]
        throw new Error("the picker window has no fleapicker IPC handler")
    }
    function find(item, kind) {
        if (String(item).indexOf(kind) === 0) return item
        for (var i = 0; i < item.children.length; i++) {
            var found = root.find(item.children[i], kind)
            if (found) return found
        }
        return null
    }
    function report() {
        stepper.running = false
        console.log("COHPICKER DONE checks=" + root.checks + " failed=" + root.failures.length)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    Component.onCompleted: {
        var comp = Qt.createComponent("flea/PickerWindow.qml")
        if (comp.status !== Component.Ready) { console.log("COHPICKER FAIL compile " + comp.errorString()); root.report(); return }
        win = comp.createObject(root).pickerWin
        win.width = 1040
        win.height = 760
    }

    Timer {
        id: stepper
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            root.ticks++
            if (root.ticks > 300) { root.check(false, "the picker listing never settled"); root.report(); return }
            if (!win || win.listingState !== "ready" || win.contentItem.width !== 1040) return
            var st = JSON.parse(root.handler().cohesionControls())
            if (root.focused) {
                if (!root.menuOpened)
                    root.check(!!st.focus && st.focus.via === "owner" && st.focus.kind === "DialogButton", "the focus names the answer by the owner walk: " + JSON.stringify(st.focus))
                if (Quickshell.env("FLEA_COH_CAPTURE") === "true") {
                    if (!root.menuOpened) {
                        root.find(win.contentItem, "PickerFilter").open()
                        root.menuOpened = true
                        return
                    }
                    var choices = st.controls.filter(function(c) { return c.kind === "MenuRow" && c.exposed })
                    if (choices.length === 0) return
                    root.check(choices.length === 2 && choices[0].name === "Text" && choices[1].name === "All files", "capture reader observes the actual dropdown choices")
                    root.check(choices[0].focused && choices.every(function(c) { return c.surface === "ContextMenu" && c.hoverLive }), "dropdown targets keep their real cursor, surface and hover handlers")
                }
                root.report()
                return
            }
            var kinds = {}
            for (var i = 0; i < st.controls.length; i++) {
                var c = st.controls[i]
                kinds[c.kind] = (kinds[c.kind] || 0) + 1
                root.check(c.w > 0 && c.h > 0 && c.x >= 0 && c.y >= 0 && c.x + c.w <= 1040 && c.y + c.h <= 760,
                    c.kind + " '" + c.name + "' box inside the picker: " + [c.x, c.y, c.w, c.h])
            }
            console.log("COHPICKER controls=" + st.controls.length + " kinds=" + JSON.stringify(kinds) + " focus=" + JSON.stringify(st.focus))
            root.check((kinds.DialogButton || 0) >= 2, "the picker shows Cancel and Open")
            root.check((kinds.SidebarRow || 0) >= 1, "the picker shows its places")
            root.check(kinds.PickerFilter === 1, "the current filter dropdown type is read")
            root.check(st.controls.some(function(c) { return c.kind === "PickerFilter" && c.name === "Filter" }), "the filter keeps its control name")
            root.check(st.controls.some(function(c) { return c.kind === "PickerFilter" && c.hoverable && c.pressable }), "the filter reports its real pointer handlers")
            root.check(!!st.focus && st.focus.via === "item", "the focus at rest sits on the list, which names no control: " + JSON.stringify(st.focus))
            // The answer is the control the keyboard lands on, so the next tick pins the owner walk on it.
            var answer = root.find(win.contentItem, "Answer")
            root.check(answer !== null, "the picker draws an answer")
            if (answer) answer.forceActiveFocus()
            root.focused = true
        }
    }
}
