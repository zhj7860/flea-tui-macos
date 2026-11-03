import QtQuick

// Quickshell.Io's Process as ui/Backend.qml drives it: started is the child coming up, written is every line sent to it.
QtObject {
    property var command: []
    property bool running: false
    property bool stdinEnabled: false
    property QtObject stdout: null
    property var written: []

    signal started()
    signal exited(int exitCode, int exitStatus)

    function write(data) { written = written.concat([data]) }
}
