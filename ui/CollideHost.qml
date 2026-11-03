import QtQuick
import "js/Clipboard.js" as Clipboard
import "js/Collide.js" as Collide

// A pane's question before a transfer lands on names that exist: the transfer waits here, so Cancel sends nothing.
Loader {
    id: root
    required property var pane
    anchors.fill: parent
    z: 2
    // Built by the first question that collides, see AGENTS.md rule 6: a hidden card is not a free one.
    active: false
    source: "CollideConfirm.qml"
    readonly property bool opened: item !== null && item.opened
    // The transfer waiting on the answer, or null, and whether sending it spends a cut clipboard.
    property var pending: null
    property bool spendsCut: false
    property var cutClipboard: null
    property int askId: 0
    // A merge holds its transfer across two cards: the walk's answer lands on the second.
    property bool merging: false
    property var outerNames: []
    property var probe: null
    // Built by the first FAT answer, with no placeholder: a Loader here would stand at startup for a card most windows never open.
    property var fatCard: null

    // A cut is spent when its transfer goes out, so a Cancel leaves it on the clipboard to paste elsewhere.
    function ask(request, probe, cut) {
        var refused = Collide.refusal(root.opened, root.pending)
        if (refused.length > 0) {
            root.pane.message(refused, false)
            return false
        }
        root.askId += 1
        // Its rows keep the numbering they were read in, so a listing landing before the answer gets the transfer refused, not resolved anew.
        root.pending = Collide.waiting(request, root.pane.backend.heldListing)
        root.spendsCut = cut === true
        root.cutClipboard = cut === true ? root.pane.clipboard : null
        root.merging = false
        root.outerNames = []
        root.probe = probe || null
        root.pane.backend.send(Collide.question(root.pending, probe, root.askId))
        return true
    }

    // A merge's terminal line; only a merge this card asked carries into, so every other line is the pane's own.
    function doneLine(transfer, result) {
        return Collide.doneLine(transfer, result)
    }

    // Nothing collided: the transfer goes out as it would have, carrying the refusal for any late name.
    function answered(id, total, names, mergeable) {
        if (id !== root.askId || root.pending === null)
            return
        if (total === 0) {
            root.decide(Collide.NONE)
            return
        }
        root.outerNames = names
        root.active = true
        // Paste as links never merges: the Merge card is the transfer's own second card.
        root.item.open(Collide.title(names, total, root.pending.dest), names, Collide.more(total, names.length),
                       mergeable === true && root.pending.c !== "link")
    }

    // The destination cannot hold some names: Rename and copy or Skip them rides the question again, before any collision is asked.
    function answeredFat(id, renames, fstype, volume) {
        if (id !== root.askId || root.pending === null)
            return
        if (root.fatCard === null) {
            root.fatCard = Qt.createComponent("FatNamesConfirm.qml").createObject(root.parent, { z: root.z })
            root.fatCard.chosen.connect(root.decideFat)
        }
        root.fatCard.open(Collide.cardTitle(renames.length, volume, fstype), renames, Collide.cardNote(fstype))
    }

    function decideFat(choice) {
        if (choice === "cancel" || root.pending === null) {
            root.decide("cancel")
        } else {
            root.pending.fat = choice
            root.pane.backend.send(Collide.question(root.pending, root.probe, root.askId))
        }
        root.pane.listArea.forceActiveFocus()
    }

    // The second card: what files inside the merging folders already exist, asked by one walk before anything is written.
    function answeredMerge(id, total, names) {
        if (id !== root.askId || root.pending === null || !root.merging)
            return
        if (total === 0) {
            root.decideMerge("refuse")
            return
        }
        var into = Collide.mergeDest(root.pending, root.outerNames)
        root.item.open(Collide.title(names, total, into), names, Collide.more(total, names.length), false)
    }

    // Merge leaves the first card for the walk: the transfer waits on the second answer, not this one.
    function decide(choice) {
        if (choice === "merge") {
            root.merging = true
            root.pane.backend.send(Collide.mergeQuestion(root.pending, root.probe, root.askId))
            return
        }
        var request = root.pending
        if (request && choice !== "cancel") {
            // MenuAdditions040: Paste as links asks through this same card.
            root.pane.backend.send(request.c === "link" ? Collide.link(request, choice, root.askId)
                                                        : Collide.transfer(request, choice, root.askId))
            Clipboard.spent(root.pane, root.cutClipboard, root.spendsCut)
        }
        root.pending = null
        root.cutClipboard = null
        root.merging = false
        root.outerNames = []
        root.probe = null
    }

    // The second card's answer rides the merge transfer; Cancel sends nothing and keeps the cut.
    function decideMerge(choice) {
        var request = root.pending
        if (request && choice !== "cancel") {
            root.pane.backend.send(Collide.mergeTransfer(request, choice, root.askId))
            Clipboard.spent(root.pane, root.cutClipboard, root.spendsCut)
        }
        root.pending = null
        root.cutClipboard = null
        root.merging = false
        root.outerNames = []
        root.probe = null
    }

    Connections {
        target: root.pane.backend
        function onCollisions(id, total, names, mergeable) { root.answered(id, total, names, mergeable) }
        function onMergeCollisions(id, total, names) { root.answeredMerge(id, total, names) }
        function onFatnames(id, renames, fstype, volume) { root.answeredFat(id, renames, fstype, volume) }
        // A dead backend or a refused question ends the wait here and closes the card.
        function onFailed(where, input) {
            if (where === "backend" || Collide.droppedPending(where, input)) {
                root.pending = null
                root.cutClipboard = null
                root.merging = false
                root.outerNames = []
                root.probe = null
                if (root.item)
                    root.item.opened = false
                if (root.fatCard !== null)
                    root.fatCard.opened = false
            }
        }
    }
    Connections {
        target: root.item
        function onChosen(choice) {
            if (root.merging)
                root.decideMerge(choice)
            else
                root.decide(choice)
            root.pane.listArea.forceActiveFocus()
        }
    }
}
