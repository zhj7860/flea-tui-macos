import QtQuick
import "." as Flea
import "js/CodeRuns.js" as CodeRuns

// The Source view: the file's lines coloured by the backend's code engine and numbered, asked a screen at a time through CodeLines.
Item {
    id: root

    // The whole text, empty while Rendered shows; a save changes it, so the lines are asked again.
    property string text: ""
    property string path: ""
    // True on network and phone storage, where the backend is never given the path.
    property bool truncate: false
    property var backend: null
    // The backend's name for this pane's Source ask, so a sibling pane's ask never ends it.
    property string slot: "look"
    property bool active: false
    // The document's read or listing-size refusal also applies when no code request can be made.
    property bool tooLarge: false
    property bool readFailed: false
    // The wrap the code view uses: a long line ends in an ellipsis until w wraps it.
    property bool wrap: false
    property int insetX: 0
    property int insetY: 0
    // The notice drawn above the first line, empty for none, and the gap between it and the text.
    property string notice: ""
    property int blockGap: 0
    property int bodyPx: Theme.font.body
    // The lines are built on the first Source view and kept after it, so a Rendered file builds no CodeLines.
    property bool built: false
    Component.onCompleted: root.built = root.active
    onActiveChanged: if (root.active) root.built = true
    readonly property bool engine: root.backend !== null && typeof root.backend.askCode === "function"
    // The CodeLines once built, null before.
    readonly property var lines: frame.item !== null ? frame.item.lines : null
    // CodeLines' scrolling view, which the scroll bar and the wheel read.
    readonly property var list: frame.item !== null ? frame.item.list : null
    readonly property bool binary: root.lines !== null && root.lines.answer === "binary"
    readonly property bool large: root.tooLarge || (root.lines !== null && root.lines.answer === "large")
    readonly property bool failed: root.readFailed || (root.lines !== null && root.lines.answer === "failed")
    readonly property bool refused: root.binary || root.large || root.failed
    readonly property string status: root.large ? "This file is too large to preview." : root.failed ? "This file could not be read." : root.firstScreen ? "ready" : "loading"
    // Characters of the rows the list lays out, re-read as it scrolls or an answer lands.
    readonly property int laidChars: root.list === null ? 0 : root.laidOf(root.list.contentY, root.lines.stamp)
    // Lines in view are answered; a file the backend refused (binary, large, failed) has no lines, so it is no screen to wait for.
    readonly property bool firstScreen: root.refused || (root.lines !== null && root.lines.firstScreen)
    readonly property Item noticeItem: root.list !== null && root.list.headerItem !== null ? root.list.headerItem.notice : null

    function laidOf(top, stamp) {
        var n = 0
        var rows = root.list.contentItem.children
        for (var i = 0; i < rows.length; i++)
            if (rows[i].index !== undefined && rows[i].children.length === 2) {
                var runs = root.lines.rowAt(rows[i].index + 1)
                if (runs) n += CodeRuns.plain(runs).length
            }
        return n
    }
    function keepTop(top) {
        root.list.forceLayout()
        root.list.positionViewAtIndex(top, ListView.Beginning)
    }
    // The line at the top of the view stays at the top while the rows change width.
    onWrapChanged: if (root.list !== null) Qt.callLater(root.keepTop, Math.max(0, root.list.indexAt(0, root.list.contentY + 1)))

    // The notice sits above the first line and scrolls with the rows, so the list never moves under a change to it.
    Component {
        id: noticeHeader

        Item {
            id: noticeRow
            // The notice's Text, which the pane and the suites read for its place.
            readonly property Item notice: deepNotice
            width: ListView.view.width
            height: root.notice !== "" ? deepNotice.height + root.blockGap : 0
            visible: root.notice !== ""
            onHeightChanged: if (root.list !== null && root.notice !== "") Qt.callLater(root.list.positionViewAtBeginning)

            Text {
                id: deepNotice
                width: noticeRow.width
                visible: root.notice !== ""
                text: root.notice
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.color.muted
                font.family: Theme.font.family
                font.pixelSize: Theme.font.caption
            }
        }
    }

    // Without an engine the backend cannot colour a line, so the text the caller holds is drawn plain.
    Loader {
        id: frame
        anchors.fill: parent
        active: root.built

        sourceComponent: Item {
            id: frameItem
            anchors.fill: parent
            property alias lines: codeLines
            Component.onCompleted: Qt.callLater(frameItem.list.positionViewAtBeginning)
            // CodeLines' scrolling view, its one Flickable child.
            readonly property var list: {
                var kids = codeLines.children
                for (var i = 0; i < kids.length; i++)
                    if (kids[i].contentY !== undefined) return kids[i]
                return null
            }

            Flea.CodeLines {
                id: codeLines
                anchors.fill: parent
                anchors.leftMargin: root.insetX
                anchors.rightMargin: root.insetX
                anchors.topMargin: root.insetY
                anchors.bottomMargin: root.insetY
                visible: !root.refused
                backend: root.backend
                slot: root.slot
                path: root.path
                fromText: root.truncate || !root.engine
                text: root.text
                active: root.active && !root.tooLarge
                numbered: true
                wrap: root.wrap
                scrolls: true
                pixelSize: root.bodyPx
                header: noticeHeader
            }

            // The wheel and the bar belong to the frame, as in Rendered: the bar sits on the frame edge beside the list's top.
            Flea.FastScrollHandler {
                flickable: frameItem.list
                visible: !root.refused
            }

            Flea.ViewportScrollBar {
                anchors { top: parent.top; topMargin: root.insetY; right: parent.right }
                flickable: frameItem.list
                visible: !root.refused
            }
        }
    }

    Flea.CodeRefusal {
        anchors.fill: parent
        visible: root.refused
        binary: root.binary
        tooLarge: root.large
        failed: root.failed
        markName: "markdown"
    }
}
