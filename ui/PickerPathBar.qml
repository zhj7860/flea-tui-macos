import QtQuick
import "js/Format.js" as Format
import "js/PathBar.js" as PathBar
import "js/Picker.js" as Picker

// A committed picker line, named by the backend's peek first: a folder opens, a file answers through its row's accept, nothing else.
Item {
    id: root

    required property var picker
    required property var listing
    required property var backend
    required property var entry

    // Recent is a location and not a path, so a relative line resolves against home there, never onto the location token.
    readonly property string basePath: root.picker.recent ? root.picker.home : root.picker.path

    // The path peeked and waiting for its answer.
    property string asked: ""
    // A typed file's path, waiting for its parent's listing to name its row, and that row once named.
    property string leaf: ""
    property string leafParent: ""
    property int leafIndex: -1
    // A listing that fails answers a waiting typed file with the footer's own error, so the leaf waits on nothing.
    readonly property bool listingFailed: root.picker.listingFailed
    onListingFailedChanged: if (root.listingFailed) root.leaf = ""

    function commitTyped(text) {
        var target = PathBar.resolve(text, root.basePath, root.picker.home)
        if (target === "") {
            // A URI on another host says its sentence; an empty line only closes, as the chrome's commit does.
            if (PathBar.refused(text)) {
                root.picker.say(PathBar.REFUSED_SENTENCE, false)
                return
            }
            root.entry.closeEdit()
            return
        }
        root.ask(target)
    }

    // A peek of count zero is the stat and nothing else; Tab's own peek asks for rows, so the two replies never mix.
    function ask(target) {
        root.asked = target
        root.leaf = ""
        root.listing.peek(target, 0, root.picker.showHidden)
    }

    function answered(path, readFailed, mode) {
        if (path !== root.asked) return
        root.asked = ""
        var kind = PathBar.kindOfPeek(readFailed, mode)
        if (kind === "missing") {
            root.picker.say(Format.fill(PathBar.MISSING_SENTENCE, path), true)
        } else if (kind === "folder") {
            root.picker.open(path)
            root.entry.closeEdit()
        } else {
            root.openFile(path)
        }
    }

    function openFile(path) {
        // A file where a folder answers is the backend's own refusal: the mark names the folder type and fails it, and a mark in flight keeps its accept.
        if (root.picker.saving || root.picker.folderMode) {
            root.picker.pathProbe = root.picker.check({op: "mark", path: path, directory: true, multiple: false})
            return
        }
        root.leaf = path
        root.leafParent = Picker.parentOf(path)
        root.leafIndex = -1
        if (root.leafParent !== root.picker.path) root.picker.open(root.leafParent)
        else if (root.picker.listingFailed) root.leaf = ""
        else if (root.picker.pendingListings === 0) root.listing.locate(path)
    }

    // Sample input: {"t":"located","directory":"/d","path":"/d/a.txt","index":42}; -1 is a name the filter or the hidden files setting left out.
    function located(message) {
        // A reply against another listing is stale; the leaf's own listing locates it again when it lands.
        if (root.leaf === "" || message.path !== root.leaf || message.directory !== root.leafParent) return
        if (message.index < 0) {
            root.picker.say(Format.fill(PathBar.FILTERED_SENTENCE, root.leaf.substring(root.leaf.lastIndexOf("/") + 1)), true)
            root.leaf = ""
            return
        }
        root.leafIndex = message.index
        root.picker.cursorIndex = message.index
        root.picker.viewItem().reshow(message.index)
        root.take()
    }

    // The row's own accept runs once its window is held; the reshow above asks for that window when it is not.
    function take() {
        if (root.leaf === "" || root.leafIndex < 0 || !root.picker.rowFor(root.leafIndex)) return
        var index = root.leafIndex
        root.leaf = ""
        root.leafIndex = -1
        root.picker.activate(index)
    }

    // The field closing, or the picker moving on, drops whatever was still being looked for.
    function editClosed() {
        root.asked = ""
        root.leaf = ""
        root.picker.focusDefault()
    }

    // Every listing of the leaf's folder, its first or a re-read, renumbers the rows, so the leaf is located afresh against it.
    Connections {
        target: root.backend
        function onListed() {
            if (root.leaf === "") return
            if (root.picker.path !== root.leafParent) { root.leaf = ""; return }
            root.leafIndex = -1
            root.listing.locate(root.leaf)
        }
        function onLocated(message) { root.located(message) }
        function onRows() { root.take() }
        function onJumped(id, favourites, zoxide, recent, frecency) {
            if (root.entry.jump !== null) root.entry.jump.take(id, favourites, zoxide, recent, frecency)
        }
        function onPeeked(path, hidden, total, rows, readFailed, mode, hiddenLast, first) {
            if (first === 0) root.answered(path, readFailed, mode)
            else root.entry.completeWith(path, hidden, rows)
        }
    }
}
