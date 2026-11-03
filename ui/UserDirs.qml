pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "js/FolderSorts.js" as FolderSorts

QtObject {
    id: root
    readonly property string home: Quickshell.env("HOME")
    property string body: ""
    readonly property var newestFolders: FolderSorts.newestPaths(root.body, root.home)

    // First-list defaults must use the file before onLoaded arrives, as ViewState's initial read does.
    Component.onCompleted: root.body = file.text()
    property FileView reader: FileView {
        id: file
        path: (Quickshell.env("XDG_CONFIG_HOME") || root.home + "/.config") + "/user-dirs.dirs"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.body = text()
        onLoadFailed: root.body = ""
    }
}
