// The pointer legs of tests/columns-pwid.qml that never store a lasting width: clicks and jitter on the preview column edge, a grab lost mid-drag, the edge hidden mid-drag, and a double click that jitters. Each leg runs one tick after the last.
function legs(shell, driver, area) {
    return [
        // A click or a jitter on the edge is not a drag: it writes nothing and keeps the default third.
        function () { shell.edgeHome.base = shell.saves().length; shell.pointer(800, 300) },
        function () {
            driver.mousePress(area, 800, 300, Qt.LeftButton, Qt.NoModifier, 0)
            shell.dragTo(801, 300)
            driver.mouseRelease(area, 801, 300, Qt.LeftButton, Qt.NoModifier, 0)
        },
        function () {
            shell.check("jitter: a 1 px move between press and release writes nothing", shell.savedAfter(shell.edgeHome.base), [])
            shell.check("jitter: the default third stays", shell.widths(), [400, 400, 400])
            driver.mousePress(area, 800, 300, Qt.LeftButton, Qt.NoModifier, 0)
            shell.dragTo(801, 300)
            shell.dragTo(800, 300)
            driver.mouseRelease(area, 800, 300, Qt.LeftButton, Qt.NoModifier, 0)
        },
        function () {
            shell.check("jitter: out and back writes nothing", shell.savedAfter(shell.edgeHome.base), [])
            shell.check("jitter: out and back keeps the default third", shell.widths(), [400, 400, 400])
            driver.mouseClick(area, 800, 300, Qt.LeftButton, Qt.NoModifier, 0)
        },
        function () {
            shell.check("click: a plain click writes nothing", shell.savedAfter(shell.edgeHome.base), [])
            shell.check("click: a plain click keeps the default third", shell.widths(), [400, 400, 400])
        },
        // A grab lost mid-drag ends the drag like a release: the zone's own canceled signal, which Qt raises when a popup or the compositor takes the pointer.
        function () {
            driver.mousePress(area, 800, 300, Qt.LeftButton, Qt.NoModifier, 0)
            shell.dragTo(700, 300)
            shell.check("cancel: the drag is live before the grab goes", shell.widths(), [350, 350, 500])
            shell.edgeHome.zone = shell.zoneItem()
            shell.edgeHome.zone.canceled()
        },
        function () {
            shell.check("cancel: the edge is no longer dragging", shell.edgeItem().dragging, false)
            shell.check("cancel: the live width is let go", area.dragLast, -1)
            shell.dragTo(500, 300)
        },
        function () {
            shell.check("cancel: later moves with no grab leave the width alone", shell.widths(), [348, 348, 504])
            shell.check("cancel: the width the user saw is the one saved", shell.savedAfter(shell.edgeHome.base), [42])
            driver.mouseRelease(area, 500, 300, Qt.LeftButton, Qt.NoModifier, 0)
            shell.pointer(shell.edgeX(), 300)
        },
        function () { driver.mouseDoubleClickSequence(area, shell.edgeX(), 300, Qt.LeftButton, Qt.NoModifier, 0) },
        function () {
            shell.check("cancel: a double click restores the default third", shell.widths(), [400, 400, 400])
            shell.check("cancel: the restore wrote 0", shell.savedAfter(shell.edgeHome.base), [42, 0])
            shell.pointer(800, 300)
        },
        // The edge hidden mid-drag (the preview column going away under a held button) ends the drag the same way.
        function () {
            driver.mousePress(area, 800, 300, Qt.LeftButton, Qt.NoModifier, 0)
            shell.dragTo(700, 300)
            shell.check("hide: the drag is live before the edge goes", shell.widths(), [350, 350, 500])
            shell.edgeHome.edge = shell.edgeItem()
            shell.edgeHome.edge.visible = false
        },
        function () {
            shell.check("hide: the edge is no longer dragging", shell.edgeHome.edge.dragging, false)
            shell.check("hide: the live width is let go", area.dragLast, -1)
            shell.dragTo(500, 300)
        },
        function () {
            shell.check("hide: later moves leave the width alone", shell.widths(), [348, 348, 504])
            shell.check("hide: the width the user saw is the one saved", shell.savedAfter(shell.edgeHome.base), [42, 0, 42])
            shell.edgeHome.edge.visible = Qt.binding(function () { return area.thirdShown })
            driver.mouseRelease(area, 500, 300, Qt.LeftButton, Qt.NoModifier, 0)
            shell.pointer(shell.edgeX(), 300)
        },
        // A double click restores the default third, then its second press can jitter before the release: Qt Quick delivers that press to the zone (pressed) and then doubleClicked, so the press is real, the restore is the zone's own signal while the button is held, and the 1 px move and the release follow.
        function () {
            driver.mousePress(area, 800, 300, Qt.LeftButton, Qt.NoModifier, 0)
            shell.edgeItem().restored()
            shell.dragTo(801, 300)
            driver.mouseRelease(area, 801, 300, Qt.LeftButton, Qt.NoModifier, 0)
        },
        function () {
            shell.check("double click with jitter: the default third is back and stays", shell.widths(), [400, 400, 400])
            shell.check("double click with jitter: only the restore wrote", shell.savedAfter(shell.edgeHome.base), [42, 0, 42, 0])
            shell.edgeHome.base = shell.saves().length
            shell.pointer(100, 300)
        }
    ]
}
