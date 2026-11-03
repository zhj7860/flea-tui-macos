import QtQuick
import "selection" as Selection

// Controlled replies keep the production selection component's asynchronous boundaries explicit.
Item {
    id: root
    property int checks: 0
    property int failures: 0
    readonly property int regularFileMode: 33188
    readonly property int testPathsDeadlineMs: 1
    readonly property int deadlineObservationMs: 50
    property int expiredPathsRequest: 0
    property var requests: []
    property var indices: []
    function check(label, got, want) {
        checks++
        if (JSON.stringify(got) === JSON.stringify(want)) return
        failures++
        console.log("FAIL " + label + " got=" + JSON.stringify(got) + " expected=" + JSON.stringify(want))
    }
    function paths(names) { return names.map(function(name) { return "/virtual/" + name }) }
    function reply(names, removed) {
        selection.received({ok: true, marks: paths(names).map(function(path) { return {path: path, bytes: 1} }), removed: removed || 0})
    }
    function deliverPaths(values, request) {
        backend.paths(values)
        listing.pathsResolved(values, request === undefined ? listing.pathRequest : request)
    }
    function deliver(names) { deliverPaths(paths(names)) }
    function settleQueued() {
        check("queued selection reaches paths reply", picker.markRequest, -1)
        if (picker.markRequest !== -1) return []
        var before = requests.length
        deliver(indices.map(function(index) { return picker.rowFor(index).n }))
        check("queued selection paths reply starts a fresh check", requests.length, before + 1)
        if (requests.length !== before + 1) return []
        var desired = requests[before].paths
        var unique = desired.filter(function(path, index) { return desired.indexOf(path) === index })
        var outstanding = picker.markRequest
        reply(unique.map(function(path) { return path.slice("/virtual/".length) }))
        // A completed check may already have started the next queued paths request.
        check("queued selection check reply completes", picker.markRequest === outstanding, false)
        return picker.marks.map(function(mark) { return mark.path })
    }
    function selected(label, names) {
        check(label, requests[requests.length - 1].paths, paths(names))
        reply(requests[requests.length - 1].paths.map(function(path) { return path.slice("/virtual/".length) }))
        check(label + " final marks", picker.marks.map(function(mark) { return mark.path }), paths(names))
    }
    function reset() {
        selection.reset()
        picker.markRequest = 0
        picker.marks = []
        picker.marksDirty = false
        picker.acceptMarks = false
        picker.pathProbe = 0
        picker.folderMode = false
        picker.message = ""
        picker.messageError = false
        requests = []
    }
    QtObject {
        id: picker
        property bool marksAllowed: true
        property bool backendUnavailable: false
        property int pendingListings: 0
        property bool listingFailed: false
        property int markRequest: 0
        property int pathProbe: 0
        property bool submitting: false
        property var marks: []
        property bool marksDirty: false
        property bool acceptMarks: false
        property bool folderMode: false
        property bool saving: false
        property bool recent: false
        property bool showHidden: false
        property string home: "/home/virtual"
        property int cursorIndex: -1
        property var activated: []
        property string path: "/virtual"
        property int shownTotal: 5
        property string message: ""
        property bool messageError: false
        function rowFor(index) { return {n: String.fromCharCode(65 + index), mode: root.regularFileMode} }
        function check(request) { root.requests = root.requests.concat([request]); return root.requests.length }
        function say(text, error) {
            message = text
            messageError = error === true
        }
        function finish() { root.check("validation removal never accepts", true, false) }
        function open(path) { root.check("a typed file in the shown folder opens no folder", path, "") }
        function activate(index) { activated = activated.concat([index]) }
        function viewItem() { return view }
        function focusView() {}
    }
    QtObject {
        id: view
        property var reshown: []
        function reshow(index) { reshown = reshown.concat([index]) }
    }
    QtObject {
        id: entry
        property var jump: null
        function closeEdit() {}
        function completeWith() {}
    }
    QtObject {
        id: listing
        property bool running: true
        property int pathRequest: 0
        property var located: []
        signal pathsResolved(var paths, int request)
        function locate(path) { located = located.concat([path]) }
        function peek() {}
        function paths(indices, request) {
            if (!running) return false
            root.indices = indices
            pathRequest = request || 0
            return true
        }
    }
    QtObject {
        id: backend
        signal paths(var paths)
        signal listed()
        signal located(var message)
        signal rows()
        signal jumped(int id, var favourites, var zoxide, var recent, var frecency)
        signal peeked(string path, bool hidden, int total, var rows, bool readFailed, int mode, bool hiddenLast, int first)
    }
    Selection.PickerSelection { id: selection; picker: picker; listing: listing; backend: backend }
    Selection.PickerPathBar { id: pathBar; picker: picker; listing: listing; backend: backend; entry: entry }
    Component.onCompleted: {
        reset()
        selection.range(0, 1)
        deliver(["A", "B"])
        check("first range check remains outstanding", picker.markRequest > 0, true)
        selection.endRange()
        selection.range(2, 3)
        check("second range waits for first reply", requests.length, 1)
        reply(["A", "B"])
        deliver(["C", "D"])
        selected("queued range keeps earlier range", ["A", "B", "C", "D"])

        reset()
        selection.toggle(0)
        check("toggle check remains outstanding", requests[0].op, "mark")
        selection.endRange()
        selection.range(2, 3)
        reply(["A"])
        deliver(["C", "D"])
        selected("queued range keeps earlier toggle", ["A", "C", "D"])

        reset()
        reply(["A", "B"])
        selection.range(2, 3)
        deliver(["C", "D"])
        reply(["A", "B", "C", "D"])
        selection.validate(true)
        reply(["B", "C", "D"], 1)
        check("identity removal message stays", picker.message, "1 selected item moved or changed; select it again.")
        selection.range(3, 4)
        deliver(["C", "D", "E"])
        selected("extension excludes rejected identity", ["B", "C", "D", "E"])

        reset()
        selection.range(0, 3)
        deliver(["A", "B", "C", "D"])
        selection.range(3, 2)
        selection.range(2, 1)
        reply(["A", "B", "C", "D"])
        check("queued shrink dispatches first action", indices, [0, 1, 2])
        settleQueued()
        check("queued shrink dispatches second action", indices, [0, 1])
        deliver(["A", "B"])
        selected("queued shrink keeps original base", ["A", "B"])

        reset()
        reply(["A"])
        selection.range(1, 2)
        deliver(["B", "C"])
        selection.range(2, 3)
        selection.endRange()
        reply(["B", "C"], 1)
        deliver(["B", "C", "D"])
        selected("ended queued range excludes rejected A", ["B", "C", "D"])

        reset()
        selection.toggle(0)
        selection.all()
        selection.range(2, 3)
        reply(["A"])
        check("queued Select All dispatches before later range", indices, [0, 1, 2, 3, 4])
        settleQueued()
        check("later range dispatches after Select All", indices, [2, 3])
        var rangeMarks = settleQueued()
        check("Select All then range produces A to E", rangeMarks, paths(["A", "B", "C", "D", "E"]))

        reset()
        picker.message = ""
        selection.received({ok: true, marks: [{path: "/virtual/A", bytes: 1}], skipped: [
            {path: "/virtual/broken", why: "file or folder not found"},
            {path: "/virtual/locked", why: "permission denied"}
        ]})
        check("F20 partial selection names first skipped path and remaining count", picker.message,
            "Selected 1 of 3. 2 were left out: /virtual/broken (file or folder not found) and 1 more.")
        check("F20 partial selection keeps valid mark", picker.marks.map(function(mark) { return mark.path }), ["/virtual/A"])

        reset()
        picker.message = ""
        listing.running = false
        selection.all()
        check("F23 unavailable listing clears pending", selection.pending, null)
        check("F23 unavailable listing clears mark request", picker.markRequest, 0)
        check("F23 unavailable listing names failure", picker.message, "Flea stopped responding. Reopen this folder.")
        check("F23 unavailable listing sends no selection check", requests.length, 0)
        listing.running = true

        reset()
        picker.marks = [{path: "/a/held", bytes: 1}]
        picker.path = "/b"
        picker.shownTotal = 2
        selection.all()
        deliverPaths(["/b/first", "/b/second"])
        var desired = ["/a/held", "/b/first", "/b/second"]
        check("F24 Ctrl+A in b preserves marks from a", requests[0].paths, desired)
        selection.received({ok: true, marks: requests[0].paths.map(function(path) { return {path: path, bytes: 1} })})
        selection.all()
        deliverPaths(["/b/first", "/b/second"])
        check("F24 repeated Ctrl+A sends unchanged desired set", requests[1].paths, desired)
        selection.received({ok: true, marks: requests[1].paths.map(function(path) { return {path: path, bytes: 1} })})
        check("F24 repeated Ctrl+A keeps unchanged marks", picker.marks.map(function(mark) { return mark.path }), desired)

        reset()
        picker.marks = [{path: "/a/stale", bytes: 1}]
        selection.all()
        deliverPaths(["/b/first", "/b/second"])
        check("F34 refused select includes retained identity", requests[0].paths, ["/a/stale", "/b/first", "/b/second"])
        var refusal = "Selected item changed; select it again."
        selection.received({op: "select", ok: false, error: refusal})
        check("F34 refused select asks exactly one validation", requests.length, 2)
        check("F34 refused select asks validation of retained marks", requests.length > 1 ? requests[1].op : "", "validate")
        check("F34 refused select keeps standing message", picker.message, refusal)
        if (requests.length > 1) {
            selection.received({op: "validate", ok: true, marks: [], removed: 1})
            check("F34 validation removes stale identity", picker.marks, [])
            check("F34 validation preserves refusal message", picker.message, refusal)
            check("F34 validation does not ask again", requests.length, 2)
            selection.all()
            deliverPaths(["/b/first", "/b/second"])
            check("F34 retry selects without stale identity", requests[2].paths, ["/b/first", "/b/second"])
            selection.received({op: "select", ok: true, marks: [{path: "/b/first", bytes: 1}, {path: "/b/second", bytes: 1}]})
            check("F34 retry leaves requested marks", picker.marks.map(function(mark) { return mark.path }), ["/b/first", "/b/second"])
        }

        reset()
        picker.marks = [{path: "/a/stale", bytes: 1}]
        selection.all()
        deliverPaths(["/b/first"])
        selection.received({op: "select", ok: false, error: refusal})
        var validations = requests.length
        selection.received({op: "validate", ok: false, error: "The check stopped; open the file chooser again."})
        check("F34 refused validation never asks again", requests.length, validations)
        check("F34 refused validation clears guard", picker.markRequest, 0)

        // Accept's mark 7 is in flight in a folder dialog when a typed file line reaches the real openFile.
        reset()
        var notThatType = "This item is not the requested file type."
        picker.folderMode = true
        picker.markRequest = 7
        picker.acceptMarks = true
        pathBar.openFile("/virtual/typed.txt")
        var probe = requests.length ? requests[requests.length - 1] : {}
        check("a typed file in a folder dialog sends the folder mark probe", [probe.op, probe.path, probe.directory, probe.multiple],
            ["mark", "/virtual/typed.txt", true, false])
        check("the probe leaves the mark in flight and its accept", [picker.pathProbe, picker.markRequest, picker.acceptMarks], [requests.length, 7, true])
        selection.received({id: picker.pathProbe, ok: false, error: notThatType})
        check("a refused path probe says the backend's sentence", [picker.message, picker.messageError], [notThatType, true])
        check("a refused path probe ends only the probe", [picker.pathProbe, picker.markRequest, picker.acceptMarks], [0, 7, true])

        // A typed file that became a folder before its mark: the backend's mark op holds it as the one mark.
        reset()
        picker.folderMode = true
        picker.markRequest = 7
        picker.acceptMarks = true
        selection.range(2, 3)
        pathBar.openFile("/virtual/turned")
        selection.received({id: picker.pathProbe, ok: true, marks: [{path: "/virtual/turned", bytes: 1}], removed: 0})
        check("an ok path probe ends only the probe", [picker.pathProbe, picker.markRequest, picker.acceptMarks], [0, 7, true])
        check("an ok path probe leaves the queue to the mark in flight", selection.queued.length, 1)
        check("an ok path probe mirrors the backend's marks", picker.marks.map(function(mark) { return mark.path }), ["/virtual/turned"])

        // A located line answered against another listing is stale, so the leaf waits for its own listing's answer.
        reset()
        picker.path = "/virtual"
        pathBar.openFile("/virtual/kept.txt")
        check("a typed file in the shown folder is located by name", listing.located, ["/virtual/kept.txt"])
        backend.located({t: "located", directory: "/elsewhere", path: "/virtual/kept.txt", index: -1})
        check("a located reply for another listing is ignored", [picker.message, pathBar.leaf], ["", "/virtual/kept.txt"])
        backend.located({t: "located", directory: "/virtual", path: "/virtual/kept.txt", index: 2})
        check("the current listing's reply takes the row", [picker.cursorIndex, view.reshown, picker.activated], [2, [2], [2]])

        // A failed listing never locates, so a typed file there ends at once, and one waiting on a listing that then fails ends too.
        reset()
        var asked = listing.located.length
        picker.listingFailed = true
        pathBar.openFile("/virtual/lost.txt")
        check("a typed file in a failed listing is not located and waits on nothing", [listing.located.length - asked, pathBar.leaf], [0, ""])
        picker.listingFailed = false
        picker.pendingListings = 1
        pathBar.openFile("/virtual/late.txt")
        check("a typed file waits while its listing runs", pathBar.leaf, "/virtual/late.txt")
        picker.listingFailed = true
        check("and a listing that fails ends the wait", pathBar.leaf, "")
        picker.listingFailed = false
        picker.pendingListings = 0

        reset()
        var timers = selection.data.filter(function(child) { return child.objectName === "selectionPathsDeadline" })
        if (timers.length) timers[0].interval = testPathsDeadlineMs
        selection.all()
        expiredPathsRequest = listing.pathRequest
        selection.range(0, 1)
        check("F33 stalled paths queues later selection", selection.queued.length, 1)
        deadlineObservation.start()
    }
    Timer {
        id: deadlineObservation
        interval: root.deadlineObservationMs
        onTriggered: {
            root.check("F33 stalled paths resets sentinel", picker.markRequest, 0)
            root.check("F33 stalled paths clears pending", selection.pending, null)
            root.check("F33 stalled paths clears queue", selection.queued, [])
            var refusal = "Flea did not confirm the selection. Try again."
            root.check("F33 stalled paths names visible refusal", picker.message, refusal)
            root.check("F33 stalled paths keeps error visible", picker.messageError, true)
            root.deliverPaths(["/b/late"], root.expiredPathsRequest)
            root.check("F33 late reply sends no check", root.requests.length, 0)
            root.check("F33 late reply leaves marks", picker.marks, [])
            root.check("F33 late reply leaves message", picker.message, refusal)

            root.reset()
            selection.all()
            root.deliverPaths(["/b/late"], root.expiredPathsRequest)
            root.check("F33 expired reply cannot complete retry", picker.markRequest, -1)
            root.check("F33 expired reply during retry sends no check", root.requests.length, 0)
            root.deliverPaths(["/b/fresh"])
            root.check("F33 fresh reply starts one check", root.requests.length, 1)
            root.check("F33 fresh reply selects requested path", root.requests.length ? root.requests[0].paths : [], ["/b/fresh"])
            selection.received({op: "select", ok: true, marks: [{path: "/b/fresh", bytes: 1}]})
            root.check("F33 fresh reply completes retry", picker.markRequest, 0)
            console.log("picker-selection QML: " + root.checks + " checks, " + root.failures + " failed")
            Qt.exit(root.failures ? 1 : 0)
        }
    }
}
