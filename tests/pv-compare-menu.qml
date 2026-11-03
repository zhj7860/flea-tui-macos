//@ pragma ShellId flea-pv-compare-menu-test
import QtQuick
import Quickshell
import "flea" as Flea
import "flea/js/Ops.js" as Ops

// The real pane, menu snapshot and Compare activation over marks farther apart than one held window.
ShellRoot {
    id: root
    readonly property int rowCount: 5002
    readonly property int farIndex: 4800
    readonly property int pollMs: 20
    readonly property int stablePolls: 5
    readonly property int stepBudgetMs: 20000
    readonly property int typeMask: 0o170000
    readonly property int regularKind: 0o100000
    readonly property int linkKind: 0o120000
    readonly property string fixture: Quickshell.env("PVCMP_DIR") + "/marks"
    property int step: -2
    property int checks: 0
    property int failures: 0
    property double started: Date.now()
    property bool finished: false
    property string stableIdentity: ""
    property int identityPolls: 0
    property string snapshotAskedIdentity: ""

    function pane() { return body.item ? body.item.currentPane : null }
    function check(label, actual, expected) {
        checks++
        var ok = JSON.stringify(actual) === JSON.stringify(expected)
        if (!ok) failures++
        console.log("PVCMP " + (ok ? "PASS " : "FAIL ") + label + " got=" + JSON.stringify(actual) + " expected=" + JSON.stringify(expected))
    }
    function advance() { step++; started = Date.now() }
    function finish() {
        if (finished) return
        finished = true
        console.log("PVCMP DONE " + checks + " checks, " + failures + " failed")
        if (body.item) body.item.quitBackends()
        quitter.start()
    }
    function row() {
        return pane().contextMenu().entries.filter(function (entry) { return entry.action === "compare" })[0] || null
    }
    function openMenu() { pane().contextMenu().openAt(Qt.point(400, 200)) }
    function lateKinds(p, menu) {
        var heldRows = p.rows
        p.menuActions.ready = false
        p.rows = heldRows.map(function (entry) { var copy = Object.assign({}, entry); copy.p = 0; return copy })
        check("rows before stat expose unknown Compare kinds", menu.compareKinds, [0, 0])
        check("unknown modes do not retain stale Compare", row(), null)
        p.menuActions.identity = "retired selection"
        p.menuActions.selectedKinds = [root.regularKind, root.regularKind]
        p.menuActions.ready = true
        check("a ready snapshot for another identity cannot supply unread kinds", [menu.compareKinds, row()], [[0, 0], null])
        p.backend.menuResult({op: "snapshot", id: p.menuActions.requestId - 1, ok: true, count: 2,
            kinds: [root.regularKind, root.regularKind]})
        check("a snapshot reply for an old request cannot add Compare", [menu.compareKinds, row()], [[0, 0], null])
        p.menuActions.ready = false
        menu.refreshProviderRows()
        check("a menu built before stat has no Compare", row(), null)
        p.rows = heldRows
        check("the late stat exposes both regular Compare kinds", menu.compareKinds.map(function (kind) { return kind & root.typeMask }), [root.regularKind, root.regularKind])
        check("late stat adds Compare before the delayed snapshot", row() ? row().label : null, "Compare")
        p.menuActions.identity = p.menuSelectionIdentity()
        p.backend.menuResult({op: "snapshot", id: p.menuActions.requestId, ok: true, count: 2,
            kinds: [root.regularKind, root.regularKind]})
        check("a matching snapshot after menu build keeps Compare", [p.menuActions.ready, row() ? row().label : null], [true, "Compare"])
        menu.setEntries([])
        menu.setEntries(menu.buildEntries())
        check("a matching snapshot before menu build offers Compare", row() ? row().label : null, "Compare")
        var state = JSON.parse(menuReader.state())
        check("menu IPC reports both kinds, both identities and each marked row's own mode",
            [state.compareKinds, state.snapshotKinds, state.snapshotIdentity === state.menuSelectionIdentity,
                state.markedRows.map(function (entry) { return [entry.index, entry.p] })],
            [[root.regularKind, root.regularKind], [root.regularKind, root.regularKind], true,
                [[0, heldRows[0].p], [1, heldRows[1].p]]])
    }
    function tick() {
        if (finished) return
        if (Date.now() - started > stepBudgetMs) {
            if (body.item) {
                var p = pane(), look = body.item.quickLook
                console.log("PVCMP wait ready=" + p.menuActions.ready + " pending=" + p.menuActions.pendingAction + " activation=" + p.menuActions.pendingActivation
                    + " identity=" + (p.menuActions.identity === p.menuSelectionIdentity()) + " look=" + !!look
                    + (look ? " active=" + look.active + " kind=" + look.kind + " status=" + look.status : ""))
            }
            check("menu path finishes step " + step, false, true)
            finish()
            return
        }
        if (!body.item) return
        var p = pane(), menu = p.contextMenu(), look = body.item.quickLook
        switch (step) {
        case -2:
            if (p.listInFlight || p.listingState !== "ready" || p.total !== rowCount || !p.rowFor(0) || !p.rowFor(1)) {
                identityPolls = 0
                return
            }
            var currentIdentity = p.menuSelectionIdentity()
            identityPolls = currentIdentity === stableIdentity ? identityPolls + 1 : 1
            stableIdentity = currentIdentity
            if (identityPolls < stablePolls) return
            p.selectOnly(0)
            p.toggleSelectAt(1)
            openMenu()
            snapshotAskedIdentity = p.menuActions.identity
            advance()
            return
        case -1:
            currentIdentity = p.menuSelectionIdentity()
            // A refill may retire an in-flight snapshot; retry each changed identity once, only after its reply.
            if (!p.menuActions.ready || p.menuActions.identity !== currentIdentity) {
                if ((p.menuActions.ready || p.menuActions.identity === "") && snapshotAskedIdentity !== currentIdentity) {
                    snapshotAskedIdentity = currentIdentity
                    p.menuActions.snapshot()
                }
                return
            }
            check("both held rows retain regular modes", [p.rowFor(0).p & root.typeMask, p.rowFor(1).p & root.typeMask], [root.regularKind, root.regularKind])
            lateKinds(p, menu)
            p.menuActions.selectedKinds = [root.linkKind, root.linkKind]
            check("the ready matching snapshot inspects two links", [p.menuActions.ready, p.menuActions.identity === p.menuSelectionIdentity(), p.menuActions.selectedKinds], [true, true, [root.linkKind, root.linkKind]])
            check("inspected links hide Compare over held regular rows", row(), null)
            check("Quick Look is unbuilt before the refused choice", body.item.quickLook === null, true)
            Ops.open(p, [fixture + "/f0000.txt", fixture + "/f0001.txt"])
            check("inspected links block Ops.open over held regular rows", [body.item.quickLook !== null, !!(body.item.quickLook && body.item.quickLook.active)], [false, false])
            menu.close()
            advance()
            return
        case 0:
            if (p.listInFlight || p.listingState !== "ready" || p.total !== rowCount || !p.rowFor(0)) return
            p.selectOnly(0)
            p.setCursor(farIndex)
            advance()
            return
        case 1:
            if (!p.rowFor(farIndex) || p.rowFor(0)) return
            p.toggleSelect()
            check("two regular files are marked more than one window apart", p.selectedIndices().slice().sort(function (a, b) { return a - b }), [0, farIndex])
            check("the first marked file is outside the held rows", p.rowFor(0), null)
            openMenu()
            advance()
            return
        case 2:
            if (!p.menuActions.ready || row() === null) return
            check("the live snapshot resolves both own regular kinds", p.menuActions.selectedKinds, [0o100000, 0o100000])
            check("the drawn menu offers Compare for the unheld mark", row().label, "Compare")
            menu.choose("compare")
            advance()
            return
        case 3:
            if (!look || !look.active || !look.isCompare || !look.surfaceItem() || look.surfaceItem().status !== "compare") return
            check("activation opens the resolved files in listing order", [look.path, look.comparePath], [fixture + "/f0000.txt", fixture + "/f4800.txt"])
            check("the backend compares the unheld pair", look.surfaceItem().patch.indexOf("-row 0\n+row 4800\n") >= 0, true)
            look.close()
            p.selectOnly(rowCount - 2)
            p.toggleSelectAt(rowCount - 1)
            advance()
            return
        case 4:
            if (!p.rowFor(rowCount - 2) || !p.rowFor(rowCount - 1)) return
            openMenu()
            advance()
            return
        case 5:
            if (!p.menuActions.ready) return
            check("symlinks to regular files retain their own kinds", p.menuActions.selectedKinds, [0o120000, 0o120000])
            check("a real symlink pair hides Compare", row(), null)
            menu.close()
            finish()
        }
    }

    Flea.IpcMenuState {
        id: menuReader
        pane: root.pane()
        fleaWindow: QtObject { function rectOf(item) { return "" } }
    }

    FloatingWindow {
        id: window
        implicitWidth: 1300
        implicitHeight: 600
        Loader {
            id: body
            anchors.fill: parent
            source: "file://" + Quickshell.env("PVCMP_UI") + "/WindowBody.qml"
            onLoaded: item.host = window
            onStatusChanged: if (status === Loader.Error) { root.check("WindowBody loads", false, true); root.finish() }
        }
    }
    Timer { interval: root.pollMs; running: true; repeat: true; onTriggered: root.tick() }
    Timer { id: quitter; interval: 200; onTriggered: Qt.exit(root.failures > 0 ? 1 : 0) }
}
