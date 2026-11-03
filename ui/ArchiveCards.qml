import QtQuick
import "js/ArchiveCard.js" as ArchiveCard
import "js/ArchiveOps.js" as ArchiveOps

// The two password cards, built on their first open and kept like every overlay, so a launch that never opens one pays nothing.
Item {
    id: root

    property var compressOwner: null
    property var extractOwner: null
    readonly property var compressItem: compressDialog.item
    readonly property var extractItem: extractDialog.item

    function askCompressPassword(pane, paths, menuId) {
        if (paths) ArchiveOps.compressPasswordResolved(root, pane, paths, menuId)
        else ArchiveOps.openCompressPassword(pane, menuId, root)
    }

    // One card at a time: a second request is answered with a sentence and never dropped silently.
    function cardBusy(holder) {
        if (!compressDialog.opened && !extractDialog.opened)
            return false
        holder.message(ArchiveCard.CARD_BUSY, true)
        return true
    }

    function openCompressDialog(source, parentLeaf, holder) {
        if (cardBusy(holder)) return
        compressOwner = holder
        compressDialog.active = true
        compressDialog.item.open(source, parentLeaf, holder)
    }

    function openExtractPassword(source, holder, err) {
        if (cardBusy(holder)) return
        extractOwner = holder
        extractDialog.active = true
        extractDialog.item.open(source, holder, err)
    }

    anchors.fill: parent

    Loader {
        id: compressDialog
        anchors.fill: parent
        active: false
        source: "ArchiveCompressDialog.qml"
        readonly property bool opened: item !== null && item.opened
    }
    Connections {
        target: compressDialog.item
        function onAccepted(source, format, name, password, encryptNames) {
            ArchiveOps.submitCompressPassword(root.compressOwner, source, format, name, password, encryptNames)
        }
    }

    Loader {
        id: extractDialog
        anchors.fill: parent
        active: false
        source: "ArchivePasswordDialog.qml"
        readonly property bool opened: item !== null && item.opened
    }
    Connections {
        target: extractDialog.item
        function onAccepted(source, password) { ArchiveOps.submitExtractPassword(root.extractOwner, source, password) }
    }
}
