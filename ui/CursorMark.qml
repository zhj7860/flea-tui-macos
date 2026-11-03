import QtQuick

// Each delegate files itself here by listing row, so a cursor move relights only the delegate it leaves and the one it reaches.
QtObject {
    id: root

    // The listing row the cursor is on; -1 lights none.
    property int row: -1
    // Listing row to the delegate filed under it, changed in place and read only here.
    readonly property var cells: new Map()
    // The delegate drawn as the cursor, null while no delegate holds the cursor row.
    property Item lit: null

    onRowChanged: {
        var cell = root.row >= 0 ? root.cells.get(root.row) : undefined
        // A delegate destroyed without parking first reads no markRow back, so its stale entry goes here.
        if (cell !== undefined && cell.markRow !== root.row) { root.cells.delete(root.row); cell = undefined }
        root.light(cell === undefined ? null : cell)
    }

    // A delegate calls this when built and whenever its listing row changes; a parked one reads -1 and files nowhere.
    function place(cell) {
        var from = cell.markRow
        var to = cell.listingIndex
        if (from >= 0 && root.cells.get(from) === cell) root.cells.delete(from)
        cell.markRow = to
        if (to >= 0) root.cells.set(to, cell)
        if (to >= 0 && to === root.row) {
            root.light(cell)
        } else {
            cell.cursor = false
            if (root.lit === cell) root.lit = null
        }
    }

    function light(cell) {
        if (root.lit !== null && root.lit !== cell) root.lit.cursor = false
        root.lit = cell
        if (cell !== null) cell.cursor = true
    }
}
