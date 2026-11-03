import QtQuick

// Quickshell.Io's SplitParser: read is one line of the child's stdout.
QtObject {
    property string splitMarker: "\n"

    signal read(string data)
}
