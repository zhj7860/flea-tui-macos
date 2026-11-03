import QtQuick
import "." as Flea
import "js/Picker.js" as Picker
import "js/Sort.js" as Sort

// Owns no sort state; the picker's sortable gates both this click and the s and S keys so they cannot differ.
Flea.Header {
    id: root
    required property var picker
    required property var backend

    hiddenCols: Picker.HIDDEN_COLS
    compactDate: true
    enabled: root.picker.sortable
    // Recent is the desktop's own order, so no mark; the mark moves on the click, not the reply.
    sortBy: root.picker.recent ? "" : root.backend.sortBy
    sortDesc: root.backend.sortDesc
    onSortRequested: function (key) {
        root.picker.requestSort(Sort.columnOrder(Picker.SORT_ORDERS, root.backend.sortBy, root.backend.sortDesc, key))
    }

    // What tests/picker-native.py clicks, in the shape every other chooser control reports.
    function controls() {
        return [["Sort by Name", "name"], ["Sort by Size", "size"], ["Sort by Modified", "date"]].map(function (entry) {
            return root.picker.control(entry[0], root.cell(entry[1]), root.enabled)
        })
    }
}
