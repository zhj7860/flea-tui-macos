import QtQuick
import "js/sourcefixture.js" as Ship

// A sort's listed answer through the shipped ui/PaneSwap.qml applyListed: with Remember each folder's sort on it writes no sort leaf, so the folder keeps the order it was sorted to; with it off the leaf is written as before.
Item {
    id: root
    property int checks: 0
    property int failures: 0
    property string shipSrc: ""
    property var calls: []
    property var state: ({ rememberSort: true, sort: { key: "name", reverse: false }, folderSorts: {} })
    property var viewState: ({
        state: root.state,
        changeLeaf: function (leaf, value) { root.calls.push(leaf) }
    })
    property var thumbsStub: ({ empty: function () { return {} } })
    property var dirSizesStub: ({ empty: function () { return {} } })
    property var searchStub: ({ TYPING: "typing", RESULTS: "results", listingState: function () { return "ready" } })

    function check(label, actual, expected) {
        root.checks++
        if (JSON.stringify(actual) === JSON.stringify(expected)) {
            console.log("ok   " + label)
            return
        }
        root.failures++
        console.log("FAIL " + label + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }
    function makePane() {
        return {
            dualMode: false, listInFlight: false, searchMode: "", listingState: "ready", stateMessage: "",
            total: 0, path: "/fixture/a", listedSeen: false, reloadChanged: -1,
            listingPreferences: "fresh", appliedListingPreferences: "",
            backend: { sortBy: "size", sortDesc: false },
            thumbState: {}, dirSizeState: {},
            opened: function (path) {}
        }
    }
    // The shipped applyListed body, run over this replay's own pane and view state.
    function applyListed(remember) {
        var body = Ship.block(root.shipSrc, "function applyListed(", "ui/PaneSwap.qml")
        var f = new Function("root", "ViewState", "Thumbs", "DirSizes", "Search", "total", "readMs", "sortMs", "path", "changed", body)
        root.calls = []
        if (remember === undefined)
            delete root.state.rememberSort
        else
            root.state.rememberSort = remember
        f({ pane: makePane() }, root.viewState, root.thumbsStub, root.dirSizesStub, root.searchStub, 0, 0, 0, "/fixture/a", -1)
    }
    function runChecks() {
        root.state.folderSorts = { "/fixture/a": { key: "size", reverse: false } }
        applyListed(true)
        check("remember on writes no sort leaf", root.calls, [])
        check("remember on leaves the view sort unchanged", root.state.sort, { key: "name", reverse: false })
        check("remember on keeps the folder's own sort", root.state.folderSorts["/fixture/a"], { key: "size", reverse: false })
        applyListed(false)
        check("remember off writes the sort leaf", root.calls, ["sort"])
        check("remember off keeps the folder's own sort", root.state.folderSorts["/fixture/a"], { key: "size", reverse: false })
        // An absent key is the shipped default on, as every other rememberSort reader takes it.
        applyListed(undefined)
        check("remember absent writes no sort leaf", root.calls, [])
    }

    Timer {
        interval: 10
        repeat: false
        running: true
        onTriggered: {
            root.shipSrc = Ship.source("ui/PaneSwap.qml")
            root.runChecks()
            console.log("FOLDERSORTKEEP DONE checks=" + root.checks + " failed=" + root.failures)
            Qt.exit(root.failures === 0 ? 0 : 1)
        }
    }
}
