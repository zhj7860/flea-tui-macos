import QtQuick
import qs.Commons
import "." as Flea
import "js/CodeRuns.js" as CodeRuns
import "js/Compare.js" as Compare
import "js/Icons.js" as Icons
import "js/Kinds.js" as Kinds

// Quick Look's Compare kind: the unified diff of two files, coloured by ink alone, or the sentence that says why there is none.
Item {
    id: root

    // The backend asks and answers the diff; the opener holds the text copy route Copy as Path uses.
    property var backend: null
    property var opener: null
    property bool active: false
    property string pathA: ""
    property string pathB: ""
    property string iconName: ""

    // "" until the backend has answered, then diff, identical, binary, over or failed.
    property string answer: ""
    property string patch: ""
    // The token of the ask in flight, 0 when none: an answer for any other token is dropped.
    property int token: 0
    // Asks made, so a suite can tell one run of diff per open.
    property int asks: 0
    readonly property bool hasPatch: root.answer === "diff"
    readonly property var rows: root.hasPatch ? Compare.rows(root.patch) : []
    readonly property string titleText: Compare.title(Compare.leaf(root.pathA), Compare.leaf(root.pathB),
        root.hasPatch ? Compare.changed(root.rows) : null)
    // Quick Look reads this to hold the card back until the diff or the sentence can draw whole.
    readonly property string status: root.answer === "" ? "loading" : "compare"
    // Indexed by the code reply's role: the foreground, then red, green, yellow, blue, magenta and cyan.
    readonly property var inks: CodeRuns.inks(Theme.palette, Theme.fallbackColor, String(Theme.color.foreground))
    readonly property bool engine: root.backend !== null && typeof root.backend.askCompare === "function"

    // Compare.html resolves its pixels at body 14, and each one follows the body from there.
    readonly property int boardBodyPx: 14
    readonly property int numberBoardWidth: 34
    readonly property int columnBoardGap: 10
    readonly property int signBoardWidth: 9
    readonly property int copyPaddingBoardPx: 8
    readonly property int contentMarginBoardPx: 12
    readonly property int contentPaddingBoardPx: 16
    readonly property real rowLineHeightFactor: 1.45
    function boardPx(px) {
        return Math.round(px * Theme.font.body / root.boardBodyPx)
    }
    readonly property int numberWidth: root.boardPx(root.numberBoardWidth)
    readonly property int columnGap: root.boardPx(root.columnBoardGap)
    readonly property int signWidth: root.boardPx(root.signBoardWidth)
    readonly property int textX: 2 * root.numberWidth + root.signWidth + 3 * root.columnGap
    readonly property int rowHeight: Math.round(Theme.font.body * root.rowLineHeightFactor) + 2 * Theme.spacing.hairline

    signal closeRequested

    function copyPatch() {
        if (root.hasPatch && root.opener)
            root.opener.copyText(root.patch)
    }

    // The pane consumes preview Tab, so Compare enters and cycles its own real controls.
    function stepFocus(back) {
        if (!root.active) return
        var controls = root.hasPatch ? [copyButton, barClose] : [barClose]
        var at = controls.indexOf(copyButton.activeFocus ? copyButton : barClose.activeFocus ? barClose : null)
        var next = at < 0 ? (back ? controls.length - 1 : 0)
            : (at + (back ? -1 : 1) + controls.length) % controls.length
        controls[next].forceActiveFocus(back ? Qt.BacktabFocusReason : Qt.TabFocusReason)
    }

    // A new pair starts a new ask; the first waits for the end of the turn so one change of several properties asks once.
    function fresh() {
        root.answer = ""
        root.patch = ""
        root.token = 0
        if (root.active && root.engine)
            Qt.callLater(root.ask)
    }

    function ask() {
        if (!root.active || !root.engine || root.token !== 0 || root.answer !== "" || root.pathA.length === 0 || root.pathB.length === 0)
            return
        root.asks += 1
        root.token = root.backend.askCompare(root.pathA, root.pathB)
    }

    function answered(message) {
        if (root.token === 0 || message.token !== root.token)
            return
        root.token = 0
        root.patch = message.patch || ""
        root.answer = message.state
    }

    function inkOf(kind) {
        if (kind === "removed")
            return root.inks[1]
        if (kind === "added")
            return root.inks[2]
        if (kind === "hunk")
            return root.inks[6]
        return kind === "note" ? Theme.color.muted : Theme.color.foreground
    }

    // The render suite reads the bar's order and size off these, the way MarkdownPane hands its bar over.
    function barGeometry() {
        return { bar: bar, mark: barMark, markName: barMark.name, title: barTitle, copy: copyButton, close: barClose, ready: root.answer !== "" }
    }

    onPathAChanged: root.fresh()
    onPathBChanged: root.fresh()
    onActiveChanged: root.fresh()
    onEngineChanged: root.fresh()

    Connections {
        target: root.engine ? root.backend : null
        function onCompareResult(message) { root.answered(message) }
    }

    // No fill of its own: Quick Look's surface is already the chrome colour and rounds the corners this bar sits under.
    Item {
        id: bar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.chromeHeight

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: Theme.spacing.hairline
            color: Theme.color.foreground
            opacity: 0.12
        }

        // File a's kind mark, in foreground and centred above the rule like the Markdown bar's.
        Flea.Glyph {
            id: barMark
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacing.rowPaddingX
            y: Math.round((parent.height - Theme.spacing.hairline - height) / 2)
            width: Theme.chromeMarkSize
            height: Theme.chromeMarkSize
            name: Kinds.isMarkdown(root.pathA) ? "markdown" : Icons.glyphFor(root.iconName)
            color: Theme.color.foreground
        }

        // corner: a filename is arbitrary text, so PlainText, the same rule every name on this surface follows.
        Text {
            id: barTitle
            anchors.left: barMark.right
            anchors.leftMargin: Theme.spacing.gap
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Math.max(0, (root.hasPatch ? copyButton.x : barClose.x) - x - Theme.spacing.gap))
            text: root.titleText
            color: Theme.color.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
        }

        // The strip's shared button, so its rest, hover, focus, press and disabled looks are the recipe every strip button draws.
        Flea.DialogButton {
            id: copyButton
            visible: root.hasPatch
            anchors.right: barClose.left
            anchors.rightMargin: Theme.spacing.gap
            anchors.verticalCenter: parent.verticalCenter
            label: "Copy patch"
            inStrip: true
            tabHandle: true
            // Compare.html pads the label 8 either side of its 1 px frame; the recipe's own padding is the gap.
            horizontalPadding: root.boardPx(root.copyPaddingBoardPx)
            onActivated: root.copyPatch()
            onTabbed: function(from, back) { root.stepFocus(back) }
        }

        Flea.ChromeButton {
            id: barClose
            gesturePolicy: TapHandler.ReleaseWithinBounds
            ruleRows: Theme.spacing.hairline
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacing.rowPaddingX
            anchors.verticalCenter: parent.verticalCenter
            glyph: "x"
            accessName: "Close"
            activeFocusOnTab: true
            keyboardFocused: barClose.activeFocus
            Keys.onTabPressed: function(event) { root.stepFocus((event.modifiers & Qt.ShiftModifier) !== 0) }
            Keys.onBacktabPressed: root.stepFocus(true)
            onActivated: root.closeRequested()
        }
    }

    // A pair with no patch says why, in the board's one muted sentence.
    Text {
        visible: root.answer !== "" && !root.hasPatch
        anchors.top: bar.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.spacing.rowPaddingX
        anchors.rightMargin: Theme.spacing.rowPaddingX
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: Compare.sentence(root.answer)
        color: Theme.color.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }

    TextMetrics {
        id: widest
        font.family: Theme.font.family
        font.pixelSize: Theme.font.body
        text: root.hasPatch ? root.widestLine() : ""
    }

    function widestLine() {
        var best = ""
        for (var i = 0; i < root.rows.length; i++)
            if (root.rows[i].text.length > best.length)
                best = root.rows[i].text
        return best
    }

    ListView {
        id: view
        visible: root.hasPatch
        anchors.top: bar.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
        topMargin: root.boardPx(root.contentMarginBoardPx)
        bottomMargin: root.boardPx(root.contentMarginBoardPx)
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.AutoFlickDirection
        contentWidth: root.textX + widest.advanceWidth + root.boardPx(root.contentPaddingBoardPx)
        model: root.rows

        delegate: Item {
            id: line
            required property var modelData
            // The delegate's one read of the overlay and of the list, so every other read below is qualified.
            readonly property var host: root
            readonly property var strip: view
            readonly property color ink: line.host.inkOf(line.modelData.kind)
            readonly property bool numbered: line.modelData.kind === "context" || line.modelData.kind === "removed" || line.modelData.kind === "added"
            width: Math.max(line.strip.width, line.strip.contentWidth)
            height: line.host.rowHeight

            Text {
                visible: line.numbered && line.modelData.oldNo > 0
                x: 0
                width: line.host.numberWidth
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: String(line.modelData.oldNo)
                color: Theme.color.muted
                font.family: Theme.font.family
                font.pixelSize: Theme.font.body
                textFormat: Text.PlainText
            }

            Text {
                visible: line.numbered && line.modelData.newNo > 0
                x: line.host.numberWidth + line.host.columnGap
                width: line.host.numberWidth
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: String(line.modelData.newNo)
                color: Theme.color.muted
                font.family: Theme.font.family
                font.pixelSize: Theme.font.body
                textFormat: Text.PlainText
            }

            Text {
                x: 2 * (line.host.numberWidth + line.host.columnGap)
                width: line.host.signWidth
                anchors.verticalCenter: parent.verticalCenter
                text: line.modelData.kind === "removed" ? "-" : line.modelData.kind === "added" ? "+" : ""
                color: line.ink
                font.family: Theme.font.family
                font.pixelSize: Theme.font.body
                textFormat: Text.PlainText
            }

            // corner: file contents are arbitrary text, so PlainText, and the whitespace is kept as the diff has it.
            Text {
                x: line.host.textX
                anchors.verticalCenter: parent.verticalCenter
                text: line.modelData.text
                color: line.ink
                font.family: Theme.font.family
                font.pixelSize: Theme.font.body
                textFormat: Text.PlainText
                wrapMode: Text.NoWrap
            }
        }

        // The wheel and momentum are the text preview's own, so the diff takes the same notch as the code it sits beside.
        Flea.FastScrollHandler {
            parent: view
            flickable: view
        }

        Flea.ViewportScrollBars {
            parent: view
            flickable: view
        }
    }
}
