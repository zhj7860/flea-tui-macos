import QtQuick

// ui/CardFrame.qml's surface as the cards set it; the qmldir also names it Reveal, whose target, shown and lift a card sets and a stub ignores.
Item {
    default property alias content: holder.data
    property alias title: titleHolder.data
    property alias buttons: buttonHolder.data
    property real spacing: 0
    property int bleed: 0
    property int bleedX: bleed
    property int bleedY: bleed
    property real revealClearY: 0
    property real contentY: 0
    property Item target: null
    property bool shown: false
    property Item lift: null
    readonly property real holderWidth: width - 2 * bleedX
    readonly property real wanted: titleHolder.childrenRect.height + holder.childrenRect.height + buttonHolder.childrenRect.height
    readonly property var scrollItem: holder
    function reveal(item) {}
    function holds(item) { return true }
    function resetSteps() {}
    Item { id: titleHolder }
    Item { id: holder }
    Item { id: buttonHolder }
}
