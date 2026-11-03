.import "../../ui/js/Anchor.js" as Anchor
.import "../../ui/js/Selection.js" as Selection

// The stub pane both tab suites drive, kept here so neither owns it: tests/js/tabs.js covers the
// tab list itself and tests/js/tabs-switch.js what a switch restores.
function pane(path) {
    var p = {
        path: path || "/home/gm/Work",
        home: "/home/gm",
        history: ["/home/gm"],
        cursorIndex: 4,
        viewMode: "list",
        showHidden: false,
        // ViewState.state.hidden as ui/Pane.qml reads it: the standing preference, not this tab's.
        preferenceHidden: false,
        searchMode: "",
        searchFrom: "",
        searchQuery: "",
        searchRunning: false,
        searchCancelled: false,
        searchScanned: 0,
        recentMode: "",
        recentFrom: "",
        recentPaths: [],
        filterQuery: "",
        filterTyping: false,
        listInFlight: false,
        listingState: "ready",
        stateMessage: "",
        tabs: null,
        total: 20,
        windowSize: 40,
        said: [],
        listed: [],
        sorted: [],
        windows: [],
        preview: { active: false, closed: 0, close: function () { this.active = false; this.closed += 1 } },
        selection: Selection.create(),
        selectionVersion: 0
    }
    p.selectedIndices = function () { return p.selection.indices() }
    p.clearSelection = function () { p.selection.clear(); p.selectionVersion++ }
    p.setCursor = function (i) { p.cursorIndex = i }
    // The standing count notice serial, mirroring ui/StatusBar.qml: say bumps it, withdraw names it, errors stand apart.
    p.statusBar = {
        notice: "",
        noticeSerial: 0,
        errors: [],
        say: function (text, isError) {
            if (!text) {
                if (this.errors.length > 0) this.errors = this.errors.slice(1)
                else this.notice = ""
                return
            }
            if (isError) {
                this.errors.push({ text: text })
                return
            }
            this.notice = text
            this.noticeSerial += 1
        },
        withdraw: function (serial) {
            if (serial === this.noticeSerial) this.notice = ""
        }
    }
    p.message = function (text, isError) { p.said.push(text); p.statusBar.say(text, isError) }
    // A new listing forgets the selection; without ui/Pane.qml's keepHidden it takes the dotfile answer the tab being left chose.
    p.openWithoutHistory = function (next, options) {
        Anchor.clearWaiting(p)
        if (!options || options.keepHidden !== true)
            p.showHidden = p.preferenceHidden === true
        p.clearedAtOnce = !!options && options.clearAtOnce === true
        p.superseded = !!options && options.supersede === true
        p.listed.push(next)
        p.listingPath = next
        p.path = next
        p.cursorIndex = 0
        p.selection.clear()
        p.selectionVersion++
        p.backend.listRequests += 1
    }
    p.backend = {
        sortBy: "name",
        sortDesc: false,
        // Every list bumps this, the watch's own re-read included: see ui/Backend.qml.
        listRequests: 0,
        sort: function (by, desc) { p.sorted.push(by + ":" + desc); this.sortBy = by; this.sortDesc = desc },
        window: function (start, count) { p.windows.push(start + ":" + count) },
        searchClose: function () {}
    }
    return p
}
