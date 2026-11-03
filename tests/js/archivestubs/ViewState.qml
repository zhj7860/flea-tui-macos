pragma Singleton
import QtQuick

// ui/ViewState.qml with no saved state, which ui/Backend.qml reads only for listing and sort requests.
QtObject {
    property var state: ({})
    function changeMapEntries() {}
}
