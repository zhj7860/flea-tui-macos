import QtQuick
import qs.Commons
import "." as Flea
import "js/Crumbs.js" as Crumbs
import "js/PathBar.js" as PathBar

// The window's top chrome, per the canvas: where you are on the left, how you are looking at it on
// the right. The path lives here rather than in the status bar, which the design gives to counts.
Item {
    id: root

    property string path: ""
    // True only when the drawn path's listing failed, so retyping it retries and all else is a no-op.
    property bool pathFailed: false
    property string home: ""
    property var pathAlias: null
    property bool canGoBack: false
    property bool canGoUp: false
    // "list", "columns" or "grid"; the button naming the current one takes the accent.
    property string viewMode: "list"
    property bool showPath: true
    // Read by the path bar alone, so a Tab on a dotted leaf peeks the way the listing is set to look.
    property bool showHidden: false
    property bool canFilter: false
    property bool canSort: false
    // False while Quick Look is open: Qt 6 still hands a press beneath an accepted shield, so only handlers stop, never Item.enabled.
    property bool inputLive: true
    // Tab's chrome stop: the keyboard is on the control named by glyph, which draws its own frame; ui/js/ChromeKeys.js moves it.
    property bool stopFocused: false
    property string focusedGlyph: ""
    // Drops callout 4: the pane whose collide sends a drop on a crumb.
    property var dropPane: null

    signal backRequested()
    signal upRequested()
    signal searchRequested()
    signal filterRequested()
    signal sortRequested()
    signal viewChosen(string mode)
    // The path bar's four. ui/shell.qml navigates, hands the keyboard back, runs the peek behind Tab
    // and carries what the bar says to the status line, because this file draws the chrome and knows
    // nothing about the backend, the pane or the bar below it.
    signal pathEntered(string path)
    signal editClosed()
    signal completeRequested(string dir, bool hidden)
    signal said(string text)
    // The folder jump's one read per open, carried to the pane's backend like Tab's peek; see ui/PathJump.qml.
    signal jumpRequested(int id, int ranking, var favourites, var recent)
    // Built by the first edit and kept for the window's life, so a bar never opened compiles none of it.
    property bool entryBuilt: false
    readonly property var jump: entryLoader.item !== null ? entryLoader.item.jump : null
    readonly property bool jumpShown: entryLoader.item !== null && entryLoader.item.jumpShown
    // Its dropdown hangs below the strip, so the strip rises over the tab bar and the listing while it shows.
    z: root.jumpShown ? 1 : 0
    // The settings panel's pointer door, beside the comma key; see ui/shell.qml for the third.
    signal settingsRequested()

    // The path bar, typed instead of drawn; the typed half is ui/PathEntry.qml, shared with the picker, and this bar answers its commit and jump.
    readonly property bool editing: entryLoader.item !== null && entryLoader.item.editing
    // What the seam reads: the line as it stands, and the box a test double-clicks to open the bar.
    readonly property string editText: entryLoader.item !== null ? entryLoader.item.editText : ""
    readonly property alias pathArea: pathArea
    // The open field and its frame, null until the bar is first opened, so a test measures where they lie in the strip once it is.
    readonly property var pathFrame: entryLoader.item !== null ? entryLoader.item.pathFrame : null
    readonly property var pathField: entryLoader.item !== null ? entryLoader.item.pathField : null
    // The collapsed middle's own crumb, so a test can press the one segment that names no directory. Its index moves with the room, because the crumbs nearest the root are put back before it.
    readonly property int elisionIndex: {
        for (var i = 0; i < crumbs.model.length; i++)
            if (crumbs.model[i].elided)
                return i
        return -1
    }
    // itemAt is a call and not a property, so the model is named here too: without it a width that keeps the same index hands back the item the model before it built, which is by then destroyed.
    readonly property var elisionMarker: root.elisionIndex >= 0 && crumbs.model ? crumbs.itemAt(root.elisionIndex) : null
    // Issue 45's segments as items, so tests/ui.sh can press one the way it presses a tab.
    readonly property alias crumbItems: crumbs
    function startEdit() { root.entryBuilt = true; entryLoader.item.startEdit() }

    function closeEdit() { if (entryLoader.item !== null) entryLoader.item.closeEdit() }

    function commitEdit() {
        var typed = root.editText
        var target = PathBar.resolve(typed, root.path, root.home)
        root.closeEdit()
        // An empty line closes the bar, and a settled path stays a no-op to keep the selection, while a failed or locked one retries.
        if (PathBar.shouldNavigate(target, root.path, root.pathFailed)) {
            root.pathEntered(target)
            return
        }
        // A line that named something and still resolved to nothing is a file:// URI on another
        // host. Silence there would read as a broken Enter, so it gets the sentence the rest of
        // this application gives a key that cannot do what was asked.
        if (PathBar.refused(typed)) {
            root.said(PathBar.REFUSED_SENTENCE)
        }
    }

    // Tab. The rows come from the backend's peek, which is the read the columns view already makes of
    // a directory that is not the pane's, so completing costs no new request type.
    function completeEdit() { if (entryLoader.item !== null) entryLoader.item.completeEdit() }

    // A peek came back. The columns view peeks the pane's ancestors on the same wire, and a Tab that
    // gained a dot asks the same directory again with the other hidden flag, so the reply is matched
    // on the pair the backend echoes rather than on the path alone: a line completing ".conf" was
    // otherwise free to answer off rows that carried no dotfiles at all. Only directories are kept:
    // this bar goes to a directory, and a name that cannot be opened is not a completion.
    function completeWith(dir, hidden, rows) { if (entryLoader.item !== null) entryLoader.item.completeWith(dir, hidden, rows) }

    function applyCompletion(dir, names) { if (entryLoader.item !== null) entryLoader.item.applyCompletion(dir, names) }

    // A chrome strip, not a data row; see Theme.qml's chromeHeight comment.
    implicitHeight: Theme.chromeHeight

    Rectangle {
        anchors.fill: parent
        color: Glass.surface
    }

    // A test drives these by coordinate, because a glyph button carries no text to find on screen.
    function buttonFor(glyph) {
        var groups = [nav, views, modes]
        for (var g = 0; g < groups.length; g++) {
            var kids = groups[g].children
            for (var i = 0; i < kids.length; i++) {
                if (kids[i].glyph === glyph)
                    return kids[i]
            }
        }
        return null
    }

    Row {
        id: nav
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacing.rowPaddingX
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacing.gap

        Flea.ChromeButton {
            inputLive: root.inputLive
            ruleRows: Theme.spacing.hairline
            glyph: "arrow-left"
            keyboardFocused: root.stopFocused && root.focusedGlyph === glyph
            enabled: root.canGoBack
            onActivated: root.backRequested()
        }

        Flea.ChromeButton {
            inputLive: root.inputLive
            ruleRows: Theme.spacing.hairline
            glyph: "arrow-up"
            keyboardFocused: root.stopFocused && root.focusedGlyph === glyph
            enabled: root.canGoUp
            onActivated: root.upRequested()
        }
    }

    // Where the path is drawn is where it is typed. A double click opens the bar, which is the
    // pointer's half of ":" and Ctrl+L. Issue 45 made the segments above the leaf a control as well
    // as a label: one tap on any of them opens that directory, and the leaf is where the pane
    // already is, so it stays a label and only the bar answers a click on it.
    Item {
        id: pathArea
        anchors.left: nav.right
        anchors.leftMargin: Theme.spacing.gap
        anchors.right: views.left
        anchors.rightMargin: Theme.spacing.gap
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        // The strip draws its own rule along that bottom edge, so the content stops above it: without
        // this the rename editor's frame sat two pixels clear of the strip's top and one of its rule,
        // which is the same unequal margin the Trash chrome's control had.
        anchors.bottomMargin: Theme.spacing.hairline

        // The tail identifies the directory, so a path too long for the bar loses its head: the row
        // slides left inside a clipped slot, which is the left elision the single Text drew, made of
        // pieces a click can land on.
        Text {
            anchors.fill: parent
            visible: !root.editing && root.showPath && ViewState.addressBar === "path"
            text: root.home && (root.path === root.home || root.path.indexOf(root.home + "/") === 0)
                  ? "~" + root.path.substring(root.home.length) : root.path
            color: Theme.color.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideLeft
            textFormat: Text.PlainText
            TapHandler { enabled: root.inputLive; onDoubleTapped: root.startEdit() }
        }

        // One glyph's advance is every glyph's advance in this face, so the crumbs are fitted by
        // character count rather than by a layout pass that would feed its own width back in.
        TextMetrics {
            id: crumbMetrics
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
            text: "0"
        }

        Item {
            id: crumbSlot
            visible: !root.editing && root.showPath && ViewState.addressBar === "breadcrumb"
            anchors.fill: parent
            clip: true

            Row {
                id: crumbRow
                anchors.verticalCenter: parent.verticalCenter

                Repeater {
                    id: crumbs
                    model: Crumbs.fitCrumbs(Crumbs.crumbs(root.path, root.home, root.pathAlias),
                                         Math.floor(crumbSlot.width / crumbMetrics.advanceWidth))

                    delegate: Flea.Crumb {
                        inputLive: root.inputLive
                        dropPane: root.dropPane
                        // The strip's height with the glyphs centred, because the crumb's handlers are the path area's
                        // whole gesture and a text-tall box left 11 of the strip's 27 px dead, measured at the window.
                        height: crumbSlot.height
                        onChosen: function (path) { root.pathEntered(path) }
                        onEditRequested: root.startEdit()
                    }
                }
            }

            // The rest of the line, which names no directory and so keeps the plain caret and the
            // one gesture the whole strip used to carry. It is empty once the path fills the bar.
            Item {
                id: typeArea
                anchors.left: crumbRow.right
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom

                HoverHandler {
                    enabled: root.inputLive
                    cursorShape: Qt.IBeamCursor
                }

                TapHandler {
                    enabled: root.inputLive
                    acceptedButtons: Qt.LeftButton
                    onDoubleTapped: root.startEdit()
                }
            }

        }

        // The typed half, shared with the file picker; the bar answers its commit and its jump choice, which differ by host.
        Loader {
            id: entryLoader
            anchors.fill: parent
            active: root.entryBuilt
            asynchronous: false
            source: "PathEntry.qml"
            onLoaded: {
                item.path = Qt.binding(function () { return root.path })
                item.home = Qt.binding(function () { return root.home })
                item.showHidden = Qt.binding(function () { return root.showHidden })
            }
        }
        Connections {
            target: entryLoader.item
            function onCommitLine() { root.commitEdit() }
            function onJumpChosen(path) { root.closeEdit(); if (PathBar.shouldNavigate(path, root.path, root.pathFailed)) root.pathEntered(path) }
            function onEditClosed() { root.editClosed() }
            function onCompleteRequested(dir, hidden) { root.completeRequested(dir, hidden) }
            function onSaid(text) { root.said(text) }
            function onJumpRequested(id, ranking, favourites, recent) { root.jumpRequested(id, ranking, favourites, recent) }
        }
    }

    Row {
        id: views
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacing.rowPaddingX
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacing.gap

        Flea.ChromeButton {
            inputLive: root.inputLive
            ruleRows: Theme.spacing.hairline
            visible: root.viewMode !== "grid"
            glyph: "search"
            keyboardFocused: root.stopFocused && root.focusedGlyph === glyph
            onActivated: root.searchRequested()
        }

        Flea.ChromeButton {
            inputLive: root.inputLive
            ruleRows: Theme.spacing.hairline
            visible: root.viewMode === "grid"
            enabled: root.canFilter
            glyph: "filter"
            keyboardFocused: root.stopFocused && root.focusedGlyph === glyph
            accessName: "Filter"
            onActivated: root.filterRequested()
        }

        Flea.ChromeButton {
            inputLive: root.inputLive
            ruleRows: Theme.spacing.hairline
            visible: root.viewMode === "grid"
            enabled: root.canSort
            glyph: "sort"
            keyboardFocused: root.stopFocused && root.focusedGlyph === glyph
            accessName: "Sort"
            onActivated: root.sortRequested()
        }

        Flea.ChromeModes {
            id: modes
            inputLive: root.inputLive
            viewMode: root.viewMode
            focusedGlyph: root.stopFocused ? root.focusedGlyph : ""
            onChosen: function (mode) { root.viewChosen(mode) }
        }

        // Row owns horizontal placement; the short Settings divider stays vertically centered.
        Rectangle {
            width: Theme.spacing.hairline
            height: Theme.chromeMarkSize - Theme.spacing.hairline
            y: (parent.height - height) / 2
            color: Theme.color.foreground
            opacity: 0.12
        }

        Flea.ChromeButton {
            inputLive: root.inputLive
            ruleRows: Theme.spacing.hairline
            glyph: "sliders"
            keyboardFocused: root.stopFocused && root.focusedGlyph === glyph
            onActivated: root.settingsRequested()
        }
    }

    // The strip's own bottom edge, declared last so it draws over the path area: the elided head's
    // opaque fill reaches the same row and used to leave a seven pixel gap in it.
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.spacing.hairline
        color: Theme.color.foreground
        opacity: 0.12
    }

    // The pointer's title bar over the whole strip; the controls under it keep their own taps.
    Flea.WindowDrag { anchors.fill: parent; editing: root.editing; inputLive: root.inputLive }
}
