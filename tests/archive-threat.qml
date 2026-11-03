//@ pragma ShellId flea-archive-threat-test

import QtQuick
import Quickshell
import "flea" as Flea

// The offscreen walk of tests/archive-threat.sh: a canary held in each password card is in no property of the cards or their host after submit, close or failure.
ShellRoot {
    id: shell

    readonly property string canary: "S3cr3t-canary-1006"
    readonly property string busySentence: "Another archive is waiting for its password. Enter it, then try again."

    property int checks: 0
    property var failures: []
    property int step: 0
    property int waited: 0
    property var script: []
    property var sent: []
    property var said: []
    property var refused: []
    property var accepted: []
    property var holder: ({ path: "/s", listArea: stubArea,
        join: function (a, b) { return a + "/" + b },
        sticky: function () {},
        message: function (text, isError) { shell.said.push(text) },
        backend: {
            // The backend reports zip first; the card still offers 7z first, as the board draws it.
            archiveFormats: ["zip", "tar", "7z"],
            compressPassword: function (paths, dest, format, password, encrypt, id) {
                shell.sent.push([paths.length, dest, format, password === shell.canary, encrypt, id].join("|")) },
            extractPassword: function (path, dest, password, id) {
                shell.sent.push(["extract", path, dest, password === shell.canary, id].join("|")) }
        } })

    Item {
        id: stubArea
        width: 64
        height: 64
    }

    Item {
        id: stage
        width: 800
        height: 600

        Flea.ArchiveCards {
            id: cards
        }
    }

    function log(line) { console.log("ARCHIVETHREAT " + line) }
    function check(name, actual, expected) {
        shell.checks += 1
        if (JSON.stringify(actual) === JSON.stringify(expected)) {
            shell.log("ok " + name)
            return
        }
        shell.failures.push(name)
        shell.log("FAIL " + name + ": got " + JSON.stringify(actual) + ", expected " + JSON.stringify(expected))
    }

    // Whether a value holds the canary: a string, or a plain object or array that does, to a bounded depth.
    function holds(value, depth) {
        if (typeof value === "string")
            return value.indexOf(shell.canary) >= 0
        if (value === null || typeof value !== "object" || depth > 4 || value.objectName !== undefined)
            return false
        for (var key in value) {
            if (shell.holds(value[key], depth + 1))
                return true
        }
        return false
    }

    // Every property, of every object under root, that holds the canary: a held secret can sit in any of them.
    function held(root) {
        var out = []
        var seen = []
        var stack = [root]
        while (stack.length > 0) {
            var o = stack.pop()
            if (!o || seen.indexOf(o) >= 0)
                continue
            seen.push(o)
            for (var key in o) {
                var value
                try { value = o[key] } catch (e) { continue }
                if (typeof value !== "function" && shell.holds(value, 0))
                    out.push(key)
            }
            for (var i = 0; o.data !== undefined && i < o.data.length; i++) stack.push(o.data[i])
            if (o.item) stack.push(o.item)
        }
        return out
    }

    function finish() {
        shell.log("DONE checks=" + shell.checks + " failed=" + shell.failures.length)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }

    // A step that throws is a failure, so a broken card cannot end the walk looking clean.
    Timer {
        id: stepper
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            if (shell.step >= shell.script.length) {
                stepper.stop()
                shell.finish()
                return
            }
            var entry = shell.script[shell.step]
            // A step with an `until` waits for its state to settle, and runs after 100 polls so a state that never settles fails its own check.
            if (entry.until !== undefined && !entry.until() && (shell.waited += 1) < 100) return
            shell.waited = 0
            shell.step += 1
            try {
                entry.run()
            } catch (e) {
                shell.checks += 1
                shell.failures.push(entry.id)
                shell.log("FAIL " + entry.id + " threw: " + e)
            }
        }
    }

    Component.onCompleted: {
        shell.script = [
            // Nothing is built until a card is asked for, and the held scan can see a typed secret.
            { id: "AB10 held scan", run: function () {
                shell.check("no card is built before the first ask", [cards.compressItem, cards.extractItem], [null, null])
                cards.askCompressPassword(shell.holder, ["/s/a", "/s/b"], 7)
                shell.check("the card offers 7z then zip, whatever the backend's order", cards.compressItem.formats.join("|"), "7z|zip")
                cards.compressItem.takeSecretForTest(shell.canary)
                shell.check("compress holds the typed secret", cards.compressItem.password, shell.canary)
                shell.check("AT5: the scan sees the held field", shell.held(cards).length > 0 && shell.held(cards).indexOf("text") >= 0, true)
            } },
            // The menu id rides the real dialog path to the wire; submit clears every property.
            { id: "AB1 submit", run: function () {
                cards.compressItem.commit()
                shell.check("AB1: the dialog's submit reaches the wire with the secret and the menu id",
                    shell.sent, ["2|/s/s.7z|7z|true|true|7"])
                shell.check("AB10: submit clears the pair", cards.compressItem.password, "")
                shell.check("AB10: no property of the cards or the host holds it after submit", shell.held(cards), [])
            } },
            // Close clears a held secret without submitting.
            { id: "AB10 close", run: function () {
                shell.sent = []
                cards.askCompressPassword(shell.holder, ["/s/a"], 0)
                cards.compressItem.takeSecretForTest(shell.canary)
                shell.check("AT5: a typed secret is held before close", shell.held(cards).length > 0, true)
                cards.compressItem.close()
                shell.check("AB10: close sends nothing and holds nothing", [shell.sent, shell.held(cards)], [[], []])
                var part = cards.compressItem.focusPart
                cards.compressItem.commit()
                shell.check("AB10: a commit on the closed card sends nothing and leaves its sentence and focus",
                    [shell.sent, cards.compressItem.errorText, cards.compressItem.focusPart], [[], "", part])
            } },
            // An empty pair, or a mismatched one, never reaches the wire.
            { id: "AB2 pair", run: function () {
                cards.askCompressPassword(shell.holder, ["/s/a"], 0)
                shell.check("AB2: an empty pair cannot compress", cards.compressItem.canCompress, false)
                cards.compressItem.commit()
                shell.check("AB2: and an empty commit sends nothing", shell.sent, [])
                cards.compressItem.takeSecretForTest(shell.canary, "other")
                shell.check("AB2: a mismatched pair cannot compress", cards.compressItem.canCompress, false)
                cards.compressItem.commit()
                shell.check("AB2: and says so in a sentence", cards.compressItem.errorText, "Passwords do not match.")
                cards.compressItem.takeSecretForTest(shell.canary)
                shell.check("AB2: a matching pair can", cards.compressItem.canCompress, true)
                var stops = cards.compressItem.tabStops()
                var nameStop = stops[1]
                var kept = nameStop.text
                cards.compressItem.takeSecretForTest(shell.canary, "other")
                cards.compressItem.commit()
                cards.compressItem.takeSecretForTest(shell.canary)
                nameStop.text = ""
                // Offscreen the window is never active, so focus is read as the field's own focus, moved off the name first.
                stops[2].forceActiveFocus()
                shell.check("AB2: the mismatch sentence stands before the empty-name submit", cards.compressItem.errorText, "Passwords do not match.")
                cards.compressItem.submitItem.activated()
                shell.check("AB2: Compress over an empty name sends nothing, drops the old sentence and focuses the name",
                    [shell.sent.length, cards.compressItem.errorText, cards.compressItem.focusPart, nameStop.focus, stops[2].focus, cards.compressItem.opened],
                    [0, "", 0, true, false, true])
                nameStop.text = kept
            } },
            // Tab never lands on a disabled stop.
            { id: "AB7 tab", run: function () {
                var stops = cards.compressItem.tabStops()
                shell.check("AB7: a card with a pair offers only enabled tab stops",
                    stops.every(function (s) { return s.enabled }) && stops.indexOf(cards.compressItem.submitItem) >= 0, true)
                cards.compressItem.takeSecretForTest("")
                stops = cards.compressItem.tabStops()
                shell.check("AB7: an empty pair keeps the live Compress in the tab order, as the board draws it",
                    stops.every(function (s) { return s.enabled }) && stops.indexOf(cards.compressItem.submitItem) >= 0, true)
                cards.compressItem.close()
            } },
            // One extract card at a time, and a second request is answered with a whole sentence.
            { id: "AB4 AB8 open", run: function () {
                shell.sent = []
                shell.said = []
                cards.openExtractPassword({ path: "/s/one.7z", dest: "/s/one" }, shell.holder, "")
                shell.check("AB4: the extract card names its archive", cards.extractItem.leaf, "one.7z")
                var stops = cards.extractItem.tabStops()
                shell.check("AB7: an empty password keeps the live Extract in the tab order, as the board draws it",
                    stops.every(function (s) { return s.enabled }) && stops.indexOf(cards.extractItem.submitItem) >= 0, true)
                cards.extractItem.submitItem.activated()
                shell.check("AB7: Extract with no password sends nothing and asks for one",
                    [shell.sent.length, cards.extractItem.errorText, cards.extractItem.opened].join("|"),
                    "0|Type a password first.|true")
                cards.openExtractPassword({ path: "/s/two.7z", dest: "/s/two" }, shell.holder, "encrypted")
                shell.check("AB8: a second extract request keeps the first card", cards.extractItem.leaf, "one.7z")
                shell.check("AB8: and is answered with a whole sentence",
                    shell.said, [shell.busySentence])
                cards.askCompressPassword(shell.holder, ["/s/x"], 0)
                shell.check("AB8: a compress request over an open card is answered too",
                    [shell.said[1], cards.compressItem === null || !cards.compressItem.opened],
                    [shell.busySentence, true])
                cards.extractItem.takeSecretForTest(shell.canary)
                shell.check("AT5: the extract card holds the typed secret", shell.held(cards).length > 0, true)
            } },
            // The retry's submit goes to the archive the card named, and nothing holds the secret after it.
            { id: "AB4 retry", run: function () {
                cards.extractItem.commit()
                shell.check("AB4: the retry goes to the archive the card named", shell.sent, ["extract|/s/one.7z|/s/one|true|0"])
                shell.check("AT6: the card closes on submit and nothing holds the secret after it",
                    [cards.extractItem.opened, shell.held(cards)], [false, []])
            } },
            // The backend answers wrong-password, and the card that reopens draws as many bullets as were typed, holding none.
            { id: "AT5 wrong-password", run: function () {
                cards.openExtractPassword({ path: "/s/one.7z", dest: "/s/one" }, shell.holder, "wrong-password")
                shell.check("AT5: a wrong answer reopens with its sentence",
                    cards.extractItem.errorText, "That password did not open one.7z.")
                shell.check("AT6: the reopened card holds no secret, only the count of what was typed",
                    [shell.held(cards), cards.extractItem.password, cards.extractItem.heldMarks], [[], "", shell.canary.length])
                var state = cards.extractItem.captureState()
                shell.check("AT6: its bullets sit in the error frame, and the capture state names no character",
                    [state.fieldError, state.filled, shell.holds(state, 0)], [true, true, false])
                cards.extractItem.commit()
                shell.check("AT6: Extract over the bullets alone sends nothing and asks for the password",
                    [shell.sent.length, cards.extractItem.errorText, cards.extractItem.opened], [1, "Type a password first.", true])
                // Typing is a textEdited from the field input, which replaces the bullets and drops the sentence and the frame.
                cards.extractItem.tabStops()[0].textEdited()
                shell.check("AT6: typing again replaces the bullets and clears the error state",
                    [cards.extractItem.heldMarks, cards.extractItem.errorText, cards.extractItem.captureState().fieldError], [0, "", false])
                cards.extractItem.close()
            } },
            // The card clears its leaf when its close fade ends, so this step waits for the card to leave the tree.
            { id: "AB4 cancelled", until: function () { return !cards.extractItem.visible }, run: function () {
                shell.check("AB4: Cancel on the re-ask leaves no source and no secret behind",
                    [cards.extractItem.leaf, shell.held(cards)], ["", []])
            } },
            // Bullets are drawn only for the wrong-password answer to the card's own last submit.
            { id: "AT6 bullets", run: function () {
                var submit = function () {
                    shell.sent = []
                    cards.openExtractPassword({ path: "/s/one.7z", dest: "/s/one" }, shell.holder, "encrypted")
                    cards.extractItem.takeSecretForTest(shell.canary)
                    cards.extractItem.commit()
                    return [cards.extractItem.opened, shell.held(cards)]
                }
                shell.check("AT6: a submit closes the card and leaves nothing held", submit(), [false, []])
                cards.openExtractPassword({ path: "/s/other.7z", dest: "/s/other" }, shell.holder, "wrong-password")
                shell.check("AT6: another archive's wrong password draws no bullets", cards.extractItem.heldMarks, 0)
                cards.extractItem.close()
                submit()
                cards.openExtractPassword({ path: "/s/one.7z", dest: "/s/one" }, shell.holder, "encrypted")
                shell.check("AT6: a first ask of the same archive draws no bullets", cards.extractItem.heldMarks, 0)
                cards.extractItem.close()
                submit()
                cards.openExtractPassword({ path: "/s/one.7z", dest: "/s/one" }, shell.holder, "wrong-password")
                shell.check("AT6: the re-ask after it draws the count", cards.extractItem.heldMarks, shell.canary.length)
                cards.extractItem.close()
                cards.openExtractPassword({ path: "/s/one.7z", dest: "/s/one" }, shell.holder, "wrong-password")
                shell.check("AT6: and a closed re-ask spent the count, so a later one draws none", cards.extractItem.heldMarks, 0)
                cards.extractItem.close()
            } },
            // A request carrying a password is never parked in a QML property while the backend starts.
            { id: "AB3 queue", run: function () {
                var made = Qt.createComponent("flea/Backend.qml").createObject(shell)
                var failed = []
                made.failed.connect(function (where, input, message, mode) { failed.push(message) })
                made.askFsInfo()
                made.compressPassword(["/s/a"], "/s/a.7z", "7z", shell.canary, true, 0)
                made.extractPassword("/s/a.7z", "/s/a", shell.canary, 0)
                shell.check("AB3: a plain request waits for the child", made.pending.length, 1)
                shell.check("AB3: a password request is refused at once, naming the backend",
                    failed, ["the backend is not running", "the backend is not running"])
                shell.check("AB3: and no queued line holds the secret", made.pending.join("").indexOf(shell.canary) < 0, true)
                made.quit()
            } }
        ]
    }
}
