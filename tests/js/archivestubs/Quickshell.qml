pragma Singleton
import QtQuick

// Quickshell's env lookup, answering nothing, so ui/Backend.qml names the default binary it never starts here.
QtObject {
    function env(name) { return "" }
}
