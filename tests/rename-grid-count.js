// Runs in tests/rename-grid-bottom.js's Qt fixture: a count change during a rename, near the top (20 rows) and far down (1202 rows), keeps the open editor and its focus.
function countStep(turn) {
    var label = turn < 3 ? "near count change" : "far count change", last = turn < 3 ? 19 : 1201
    if (turn === 0 || turn === 3) {
        Theme.rowHeight = 31
        editPane.shownTotal = last + 1
        view.visible = true
        editPane.setCursor(last)
        editPane.renamingIndex = last
        return
    }
    if (turn === 1 || turn === 4) {
        var field = probe.editor()
        probe.check(field && field.ownsEdit() && field.inputItem.activeFocus, label + " starts on a focused owning editor")
        if (!field) { probe.finish(); return }
        field.inputItem.text = "count-draft.md"
        field.inputItem.select(9, 2)
        editPane.shownTotal = last + 2
        probe.countKept(last, label + " grow")
        editPane.shownTotal = last + 1
        probe.countKept(last, label + " shrink")
        return
    }
    probe.countKept(last, label + " next turn")
    editPane.renamingIndex = -1
    if (turn === 5) probe.finish()
}
function countKept(last, label) {
    var kept = probe.editor()
    probe.check(kept && kept === view.renameEditor && kept.ownsEdit() && editPane.renamingIndex === last
        && kept.inputItem.activeFocus, label + " keeps focus in the owning editor")
    probe.check(kept && kept.current === "count-draft.md" && kept.inputItem.selectionStart === 2
        && kept.inputItem.selectionEnd === 9 && kept.inputItem.cursorPosition === 2, label + " keeps the draft, selection and caret")
}

module.exports = {countStep, countKept};
