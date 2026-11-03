import QtQuick
import "." as Flea

// Shows a bare smb://host/'s own shares as ordinary pane rows, the same instantiated-from-shell
// overlay pattern as ui/EmptyState.qml; see ui/NetworkMounts.qml "listShares" for the source data.
Item {
    id: root

    property bool active: false
    property string baseUri: ""
    property string baseLabel: ""
    property var shares: []
    property int cursorIndex: 0

    signal closed()
    // The resolved share uri and name, the same shape openShare() already takes for a bookmarked share; ui/WindowBody.qml routes this through the window-long host's openChildShare.
    signal activated(string uri, string label)

    // active flips instantly (open()/close() below), so shareBrowserOpen()'s IPC read never races
    // the close fade; visible only stays true a little longer, until content's opacity finishes it.
    visible: root.active || content.opacity > 0

    // The fade and the rise are the shared reveal of ui/Reveal.qml, built by the first open so a window that never browses shares holds none.
    property var fade: null
    onActiveChanged: {
        if (root.active && root.fade === null)
            root.fade = Qt.createComponent("Reveal.qml").createObject(root, { target: content, shown: Qt.binding(function () { return root.active }), lift: content })
    }

    function open(uri, label, names) {
        root.baseUri = uri
        root.baseLabel = label
        root.shares = names
        root.cursorIndex = 0
        root.active = true
    }

    // Idempotent, so wiring this to every Pane navigation (including one this overlay itself just requested) costs nothing once already shut.
    function close() {
        if (!root.active)
            return
        root.active = false
        root.closed()
    }

    function moveCursor(delta) {
        if (root.shares.length === 0)
            return
        root.cursorIndex = Math.max(0, Math.min(root.shares.length - 1, root.cursorIndex + delta))
    }

    function activateCursor() {
        var name = root.shares[root.cursorIndex]
        if (name === undefined)
            return
        var base = root.baseUri.charAt(root.baseUri.length - 1) === "/" ? root.baseUri : root.baseUri + "/"
        root.activated(base + name + "/", name)
    }

    // Everything visible sits under this one Item so open/close can animate it as a unit; root
    // itself stays plain (no x/y/opacity) so anchors.fill callers of ShareBrowser are unaffected.
    Item {
        id: content
        x: 0
        width: root.width
        height: root.height
        // Closed means no input, even while the fade-out is still drawn; ui/Reveal.qml owns the fade and the rise.
        enabled: root.active
        opacity: 0

        // Opaque so the real listing behind it, still rendering, never shows or flickers through.
        Rectangle {
            anchors.fill: parent
            color: Theme.color.background
        }

        // Swallows clicks in the gap below the rows so they cannot reach the hidden list beneath.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            onClicked: {}
            onWheel: function (wheel) { wheel.accepted = true }
        }

        Column {
            anchors.fill: parent

            Repeater {
                model: root.shares

                // Network.dc.html draws the sidebar's own server mark and the share name, and no
                // columns: nothing is known about a share until it is mounted, so a "-" size and a
                // "--" date were columns of nothing. ui/MenuRow.qml is the mark-and-label row.
                delegate: Flea.MenuRow {
                    id: shareRow
                    required property int index
                    required property string modelData
                    width: root.width
                    entry: ({ label: shareRow.modelData, action: "", glyph: "server" })
                    // The keyboard cursor is the pick and takes the accent; the pointer only lifts
                    // the row it is over, which is what ui/Row.qml did here before.
                    picked: shareRow.index === root.cursorIndex
                    current: shareRow.hovered
                    onActivated: {
                        root.cursorIndex = shareRow.index
                        root.activateCursor()
                    }
                }
            }
        }
    }
}
