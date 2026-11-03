import QtQuick
import Quickshell.Io
import "js/Unlock.js" as Unlock

// U039: the udisksctl lock after releasing an unlocked crypt; a refusal names the drive.
Item {
    id: root
    // The DeviceMounts that posts the refusal and re-polls once the lock has settled.
    property var host: null
    property string _label: ""
    // Locks waiting while one runs, each keeping its own backing container and label.
    property var _queue: []

    // Answers whether a lock started: only a crypt leaf has a backing container, so no caller checks the kind first.
    function lockCryptAfter(listing, cryptDevice, label) {
        var backing = Unlock.backingFor(String(listing || ""), String(cryptDevice || ""))
        if (backing.length === 0)
            return false
        if (lockProcess.running) {
            root._queue = root._queue.concat([{ backing: backing, label: label }])
            return true
        }
        root._label = label
        lockProcess.command = ["udisksctl", "lock", "--block-device", backing]
        lockProcess.running = true
        return true
    }

    Process {
        id: lockProcess
        onExited: function (exitCode) {
            var label = root._label
            root._label = ""
            if (exitCode !== 0)
                root.host.message(Unlock.lockNote(label), true)
            if (root._queue.length > 0) {
                var next = root._queue[0]
                root._queue = root._queue.slice(1)
                root._label = next.label
                lockProcess.command = ["udisksctl", "lock", "--block-device", next.backing]
                lockProcess.running = true
                return
            }
            root.host.poll()
        }
    }
}
