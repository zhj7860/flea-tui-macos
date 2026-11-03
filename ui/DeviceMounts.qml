import QtQuick
import Quickshell.Io
import "js/Devices.js" as Devices
import "js/Format.js" as Format
import "js/Mounts.js" as Mounts
import "js/Eject.js" as Eject

// The DEVICES group's own Service, the shape ui/NetworkMounts.qml has for NETWORK: the only thing
// here that runs a process, while ui/Sidebar.qml reads "entries" and renders it. Enumeration is
// lsblk, which any user may run; acting on a volume is gio, the tool the shares already drive.
Item {
    id: root

    property var entries: []
    // RailAdditions rule 1's switch, on by default from 0.3.3; off answers 0.2.1's rows, and the state document is read elsewhere.
    property bool showUnmounted: true

    signal opened(string path)
    signal message(string text, bool isError)
    // A failed mount, unmount or eject: the headline plus gio's own reason for the status bar's detail line.
    signal operationResult(string headline, string detail, bool isError)
    // An eject is about to release this mountpoint: readers on it stop first (#232).
    signal quiesce(string path)
    signal unlockRequested(string device, string label, double size, string fstype)
    // The verdict this surface last posted, so a newer one replaces it and nothing else.
    signal forgetMessage(string text)
    property string _lastVerdict: ""

    // lsblk costs 5 ms on this box where gio mount -l costs 513 ms, so the rail's own five second
    // rhythm carries this too rather than earning a slower clock of its own.
    readonly property int pollMs: 5000
    // A listing is bounded the same way a mount is below, and for the same reason ui/NetworkMounts.qml
    // bounds its own: an lsblk that never answers left poll() refusing forever and froze the rail.
    readonly property int listTimeoutMs: 10000
    // A mount that never grows a mountpoint has to stop waiting, or the row waits on the poll forever.
    readonly property int mountTimeoutMs: 15000
    // How long an eject waits for a listing it can judge after gio exits, before the user is told
    // that nothing was confirmed: three polls, the same bound the mount above gets.
    readonly property int ejectVerdictMs: 15000
    // How long a power-off chain may hold the eject guard: a hung unmount leg ends here instead.
    readonly property int powerOffWaitMs: 15000

    property string _listing: ""
    // A Process's own onExited can race its StdioCollector's text property, the same guard every
    // stdout-reading process in ui/NetworkMounts.qml already carries.
    property string _listOutput: ""
    // The device a mount was asked for; rebuild() opens it the moment lsblk reports its mountpoint.
    property string _pendingOpenDevice: ""
    property string _pendingOpenLabel: ""
    // The volume an unmount was asked for, so its refusal can name it.
    property string _unmountLabel: ""
    // The last written-sector count the chain saw, so a flushing leg restarts the deadline.
    property string _powerSectors: ""
    // A power-off in flight: the disk to stop and the nodes still to unmount.
    property string _powerOffDisk: ""
    property var _powerOffQueue: []
    // gio's own stderr per action, so a refusal names its cause instead of a guess.
    property string _mountErr: ""
    property string _unmountErr: ""
    property string _ejectErr: ""
    property string _unmountDevice: ""
    // The device whose eject awaits its verdict, "" when none. The listing taken after gio exits is
    // the only witness: gio's own exit code has been 0 over a volume that was still mounted.
    property string _ejectDevice: ""
    property string _ejectLabel: ""
    property bool _ejectLoop: false
    // A loop detach failed; the next listing judges whether the unmount succeeded.
    property bool _ejectDetachFailed: false
    // Listings are counted as they start. _verdictFromListing is 0 while gio runs, so nothing is
    // judged before it exits; at exit it becomes one past the count, so the listing in flight at
    // that moment, taken before the eject finished, is never the witness.
    property int _listingsStarted: 0
    property int _verdictFromListing: 0
    // poll() refuses to start a listing until the previous one's stream has finished, so the body a
    // verdict is read from and the count it is gated on always belong to the same run.
    property bool _streamPending: false
    // Cleared only when the next listing starts, which onExited's own release of _streamPending
    // guarantees cannot happen until the ended listing is fully done with.
    property bool listTimedOut: false
    // Set when the chain deadline ends that leg, so its own onExited is swallowed once.
    property bool _unmountEndedLate: false
    // The -t leg's own ended-late flag, never set by an unmount the deadline ends.
    property bool _ejectEndedLate: false
    // The rail's DEVICES gate: true once the first listing answered, timed out or not, without replacing anything.
    property bool firstAnswered: false
    // Set on the unmount's first turn, since a binding on Process.running would still say idle when PaneRail decides whether to unload this host.
    property bool _unmounting: false
    // True while a release is in flight: an eject awaiting its verdict, which a power-off chain holds too, or a user unmount.
    readonly property bool releasing: root._ejectDevice.length > 0 || root._unmounting

    // The internal disk row reads the hostname alone (decided 2026-09-08; the canvas drew "<host> · <kernel name>"), and /etc/hostname is the
    // one source for that host name that costs no process.
    FileView {
        id: hostnameFile
        path: "/etc/hostname"
        blockLoading: true
        printErrors: false
        onLoaded: root.rebuild()
        onLoadFailed: root.rebuild()
    }

    // The write counter is built by the first power-off and retained for later chains.
    Loader {
        id: powerSectorsFile
        active: false
        source: "PowerSectorsReader.qml"
        onLoaded: item.owner = root
    }
    on_PowerOffDiskChanged: if (_powerOffDisk.length > 0) powerSectorsFile.active = true

    // False parks the poll once the first listing answered; a mount or a release in flight reads the next listing, so it keeps polling.
    property bool polling: true
    Timer {
        interval: root.pollMs
        running: root.polling || !root.firstAnswered || root.releasing || root._pendingOpenDevice.length > 0 || root._powerOffDisk.length > 0
        repeat: true
        triggeredOnStart: true
        onTriggered: root.poll()
    }

    function poll() {
        if (listProcess.running || root._streamPending)
            return
        root.listTimedOut = false
        root._streamPending = true
        root._listingsStarted += 1
        listProcess.running = true
        listTimeout.restart()
        if (root._powerOffDisk.length > 0)
            powerSectorsFile.item.reload()
    }

    Timer {
        id: listTimeout
        interval: root.listTimeoutMs
        repeat: false
        onTriggered: {
            if (!listProcess.running)
                return
            // Ending it is what lets the next poll run at all; a listing nobody can end froze the rail.
            root.listTimedOut = true
            listProcess.running = false
        }
    }

    // Decided 2026-09-08: the machine's row is its hostname alone; the kernel name stays the fallback for a box with no hostname, and r.device still names the disk for the actions.
    function hostLabel(fallback) {
        var host = String(hostnameFile.text() || "").trim()
        return host.length > 0 ? host : fallback
    }

    function rebuild() {
        var rows = Devices.parseDevices(root._listing, root.showUnmounted)
        var out = []
        for (var i = 0; i < rows.length; i++) {
            var r = rows[i]
            var label = r.kind === "disk" ? root.hostLabel(r.label) : r.label
            out.push({ path: r.path, label: label, group: "device", kind: r.kind,
                       device: r.device, mounted: r.mounted, removable: r.removable,
                       mediaRemovable: r.mediaRemovable === true, readOnly: r.readOnly === true, size: r.size,
                       glyph: r.locked === true ? "lock" : "drive", locked: r.locked === true,
                       fstype: r.fstype || "", fsver: r.fsver || "", loop: !!r.loop })
        }
        // Same rule as ui/NetworkMounts.qml's: an unchanged poll assigns nothing, see Mounts.sameEntries.
        if (!Mounts.sameEntries(root.entries, out))
            root.entries = out
        root.openWhenMounted()
    }

    // gio returns before udisks has published the mountpoint, so the poll after it is what
    // resolves the path; this is the one place a just-mounted volume is opened.
    function openWhenMounted() {
        if (root._pendingOpenDevice.length === 0)
            return
        for (var i = 0; i < root.entries.length; i++) {
            var e = root.entries[i]
            if (e.device === root._pendingOpenDevice && e.mounted) {
                root._pendingOpenDevice = ""
                mountTimeout.stop()
                root.opened(e.path)
                return
            }
        }
    }

    // The disk row and a mounted volume open directly; an unmounted volume mounts first, then
    // opens, because a user who picks a disk means to look inside it.
    function activate(index) {
        var e = root.entries[index]
        if (!e)
            return
        if (e.locked === true) {
            root.unlockRequested(e.device, e.label, Number(e.size) || 0, String(e.fstype || ""))
            return
        }
        if (e.mounted) {
            root.opened(e.path)
            return
        }
        root.mountVolume(e)
    }

    function reportFailure(headline, stderr) { root.operationResult(headline, Devices.mountDetail(stderr), true) }

    function mountVolume(e) {
        if (mountProcess.running) {
            root.message(Mounts.WORDS.anotherMounting, false)
            return
        }
        root._pendingOpenDevice = e.device
        root._pendingOpenLabel = e.label
        root._mountErr = ""
        mountProcess.command = ["gio", "mount", "-d", e.device]
        mountProcess.running = true
    }

    // RailAdditions rule 2's Unmount, which is not Eject: a fixed disk stays where it is and only
    // its filesystem goes away. gio is handed the mount point, the way eject below is, and the poll
    // that follows is what redraws the row as unmounted.
    function unmount(index) {
        // A chain owns unmountProcess for its legs, so a user unmount waits for the eject.
        if (root._powerOffDisk.length > 0) {
            root.message(Format.fill(Mounts.WORDS.stillEjecting, root._ejectLabel), false)
            return
        }
        var e = root.entries[index]
        if (!e || e.kind !== "volume" || !e.mounted)
            return
        if (unmountProcess.running) {
            root.message(Format.fill(Mounts.WORDS.stillUnmounting, root._unmountLabel), false)
            return
        }
        root.quiesce(e.path)
        root._unmountLabel = e.label
        root._unmountDevice = e.device
        root._unmountErr = ""
        root._unmounting = true
        unmountProcess.command = ["gio", "mount", "-u", e.path]
        unmountProcess.running = true
    }

    // One eject in flight at a time; the verdict timeout below ends the wait it starts.
    function armEject(e) {
        root._ejectDevice = e.device
        root._ejectLabel = e.label
        root._ejectLoop = e.loop === true
        root._ejectDetachFailed = false
        root._verdictFromListing = 0
    }

    // Locks the container behind an unmounted or ejected crypt, from the listing an eject was judged on when it has one.
    property var deviceLock: null
    function lockCrypt(device, label, listing) {
        if (deviceLock === null)
            deviceLock = Qt.createComponent("DeviceLock.qml").createObject(root, { host: root })
        return deviceLock.lockCryptAfter(listing !== undefined ? listing : root._listing, device, label)
    }

    // Eject by mount point, never -f (an open write loses data) or -e -d (gio-tool-mount.c:1264 mounts); a loop row takes -u, as -e never returns without a Drive.
    function eject(index) {
        var e = root.entries[index]
        if (!e || e.kind !== "volume" || !e.mounted)
            return
        if (ejectProcess.running || root._ejectDevice.length > 0) {
            root.message(Format.fill(Mounts.WORDS.stillEjecting, root._ejectLabel), false)
            return
        }
        // A non-removable USB disk is powered off, since an eject lets udiskie remount it; a loop row has no drive, so it takes -u below.
        var disk = Devices.powerOffDisk(e.device)
        if (!e.loop && disk.length > 0 && e.mediaRemovable !== true) {
            root.powerOff(e, disk)
            return
        }
        root.armEject(e)
        root.quiesce(e.path)
        root._ejectErr = ""
        ejectProcess.command = Devices.ejectCommand(e)
        ejectProcess.running = true
        // Replaces the arm prompt, and a stick mid-flush can take a while to come unmounted.
        root.message(Format.fill(Mounts.WORDS.ejecting, e.label), false)
    }

    // Unmount every volume, then stop the drive, so nothing is left for udiskie to remount.
    function powerOff(e, disk) {
        // A user unmount already in flight owns unmountProcess; adopting it would skip the queue.
        if (unmountProcess.running) {
            root.message(Format.fill(Mounts.WORDS.stillUnmountingTryAgain, e.label), false)
            return
        }
        root.quiesce(e.path)
        root.armEject(e)
        root._powerOffDisk = disk
        root._powerOffQueue = Devices.powerOffQueue(root._listing, disk, root.entries)
        root._powerSectors = ""
        root.message(Format.fill(Mounts.WORDS.ejecting, e.label), false)
        root.powerOffNext()
    }

    function powerOffNext() {
        // Every leg restarts the deadline, so 15 s bounds a stalled leg, not a flushing chain.
        powerOffTimeout.restart()
        if (root._powerOffQueue.length === 0) {
            root._ejectErr = ""
            ejectProcess.command = ["gio", "mount", "-t", root._powerOffDisk]
            ejectProcess.running = true
            return
        }
        var leg = root._powerOffQueue[0]
        root._powerOffQueue = root._powerOffQueue.slice(1)
        root._unmountErr = ""
        unmountProcess.command = ["gio", "mount", "-u", leg.path]
        unmountProcess.running = true
    }

    // A grown write counter is progress, so the deadline restarts instead of ending the chain.
    function notePowerSectors(body) {
        if (root._powerOffDisk.length === 0)
            return
        var sectors = Devices.writtenSectors(body)
        if (sectors.length === 0)
            return
        if (root._powerSectors.length > 0 && sectors !== root._powerSectors)
            powerOffTimeout.restart()
        root._powerSectors = sectors
    }

    // The chain's guard state in one line, so a failed eject names its guard through ipc.
    function ejectState() {
        return [root._ejectDevice, root._ejectLabel, root._powerOffDisk, root._powerOffQueue.length, root._lastVerdict, unmountProcess.running, ejectProcess.running].join("|")
    }

    // Nothing is judged while gio still runs, and only a listing started after it exited counts.
    // A listing that cannot be judged settles nothing, so the next poll tries again, until
    // ejectVerdictTimeout ends the wait.
    function judgeEject(body) {
        if (root._ejectDevice.length === 0 || root._verdictFromListing === 0 || root._listingsStarted < root._verdictFromListing)
            return
        var verdict = Eject.verdict(body, root._ejectDevice)
        if (verdict !== "unknown")
            root.reportEject(verdict, Eject.blockers(body, root._ejectDevice), body)
    }

    // "Safe to unplug" is a safety claim: only a real drive's "safe" verdict earns it.
    function reportEject(verdict, others, body) {
        if (root._ejectDevice.length === 0)
            return
        powerOffTimeout.stop()
        ejectVerdictTimeout.stop()
        // An unmounted loop row reads as safe to the listing; a failed detach still has to say so.
        var s = Eject.sentence(verdict === "safe" && root._ejectDetachFailed ? "attached" : verdict, root._ejectLabel, others, root._ejectLoop)
        if (!s.isError)
            root.lockCrypt(root._ejectDevice, root._ejectLabel, body)
        root._ejectDevice = ""
        // The newest verdict about this device is the true one, so it replaces the last one rather
        // than queueing behind it: a refusal is an error and stands until dismissed, and without
        // this the operator ejected the stick and went on reading "still mounted".
        root.forgetMessage(root._lastVerdict)
        root._lastVerdict = s.text
        root.message(s.text, s.isError)
    }

    Timer {
        id: mountTimeout
        interval: root.mountTimeoutMs
        repeat: false
        onTriggered: {
            if (root._pendingOpenDevice.length === 0)
                return
            root._pendingOpenDevice = ""
            root.message(Format.fill(Mounts.WORDS.noFolder, root._pendingOpenLabel), true)
        }
    }

    Timer {
        id: ejectVerdictTimeout
        interval: root.ejectVerdictMs
        repeat: false
        onTriggered: root.reportEject("unknown", [])
    }

    // A hung chain leg ends here with the guard released and a sentence.
    Timer {
        id: powerOffTimeout
        interval: root.powerOffWaitMs
        repeat: false
        onTriggered: {
            if (root._powerOffDisk.length === 0 || (!unmountProcess.running && !ejectProcess.running))
                return
            // Only the leg the deadline ends is marked, so a user unmount is never swallowed.
            if (unmountProcess.running) {
                root._unmountEndedLate = true
                unmountProcess.running = false
            } else {
                root._ejectEndedLate = true
                ejectProcess.running = false
            }
            ejectVerdictTimeout.stop()
            var label = root._ejectLabel
            root._powerOffDisk = ""
            root._powerOffQueue = []
            root._ejectDevice = ""
            // A verdict replaces the last one, so the next chain's safe sentence retires this error.
            var text = Format.fill(Mounts.WORDS.ejectUnfinished, label)
            root.forgetMessage(root._lastVerdict)
            root._lastVerdict = text
            root.message(text, true)
        }
    }

    Process {
        id: listProcess
        // PATH because a device-mapper leaf is not "/dev/" plus its kernel name, and MOUNTPOINTS
        // because one btrfs device carries several and the plain column shows whichever it likes,
        // which hid / behind /home here and left the system disk unidentifiable.
        // TRAN is the transport, asked for because RM alone misses a USB bridge: a WD My Passport
        // reports rm=false with tran=usb, and a drive you can unplug has to offer Eject (PR 74).
        // PARTTYPE, PTTYPE, PARTN and UUID are the hide rule's own columns (a firmware type, an installer ISO keep, a recovery label, the dedupe key); FSVER beside FSTYPE names LUKS1 or LUKS2; RO keeps Flash image off a write-protected card.
        command: ["lsblk", "--bytes", "--json", "-o", "NAME,PATH,LABEL,MOUNTPOINTS,RM,RO,TRAN,SIZE,TYPE,MODEL,FSTYPE,FSVER,PARTTYPENAME,PARTTYPE,PTTYPE,PARTN,UUID"]
        stdout: StdioCollector {
            id: listOut
            waitForEnd: true
            // The verdict is read here, from this run's own text, so it can never come off the
            // stale fallback onExited keeps for the rail.
            onStreamFinished: {
                if (root.listTimedOut)
                    return
                root._streamPending = false
                root._listOutput = text
                root.judgeEject(text)
            }
        }
        onExited: {
            listTimeout.stop()
            // A listing this timer ended collected nothing, and reading that as "no devices" would
            // empty the rail, taking Eject with it exactly when a device is misbehaving. The stream
            // guard is released here because a stream this timer cut off may never finish on its own.
            if (root.listTimedOut) {
                root._streamPending = false
            } else {
                root._listing = listOut.text || root._listOutput || ""
                root.rebuild()
            }
            // Last, so anything waiting on the first answer reads the listing it answered with.
            root.firstAnswered = true
        }
    }

    Process {
        id: mountProcess
        objectName: "mountProcess"
        stderr: StdioCollector { onStreamFinished: root._mountErr = this.text }
        onExited: function (exitCode) {
            // The wait starts here, not at launch: an admin polkit prompt longer than the
            // wait is a slow prompt, not a mount that never reported a folder to open.
            if (Devices.mountTimerStart(exitCode)) {
                mountTimeout.restart()
                root.poll()
                return
            }
            var label = root._pendingOpenLabel
            var sentence = Devices.mountError("mount", exitCode, root._mountErr, label)
            // "" names the already-mounted refusal, so the poll below opens it like a success.
            if (sentence.length === 0 && label.length > 0) {
                mountTimeout.restart()
                root.poll()
                return
            }
            mountTimeout.stop()
            root._pendingOpenDevice = ""
            root.reportFailure(sentence.length > 0 ? sentence : Format.fill(Mounts.WORDS.mountFailed, label), root._mountErr)
        }
    }

    Process {
        id: unmountProcess
        objectName: "unmountProcess"
        stderr: StdioCollector { onStreamFinished: root._unmountErr = this.text }
        // A spawn that fails raises this and never exited, so the flag ends here with every other end.
        onRunningChanged: if (!unmountProcess.running) root._unmounting = false
        onExited: function (exitCode) {
            // A power-off unmounts each volume first; a refusal stops the chain instead of
            // powering off under a volume that is still mounted.
            if (root._unmountEndedLate) {
                root._unmountEndedLate = false
                root.poll()
                return
            }
            if (root._powerOffDisk.length > 0) {
                if (exitCode !== 0) {
                    powerOffTimeout.stop()
                    root._powerOffDisk = ""
                    root._powerOffQueue = []
                    root._ejectDevice = ""
                    root.reportFailure(Devices.mountError("unmount", exitCode, root._unmountErr, root._ejectLabel), root._unmountErr)
                } else {
                    root.powerOffNext()
                }
                root.poll()
                return
            }
            if (exitCode !== 0)
                root.reportFailure(Devices.mountError("unmount", exitCode, root._unmountErr, root._unmountLabel), root._unmountErr)
            else if (root.lockCrypt(root._unmountDevice, root._unmountLabel))
                return
            root.poll()
        }
    }

    Process {
        id: ejectProcess
        objectName: "ejectProcess"
        stderr: StdioCollector { onStreamFinished: root._ejectErr = this.text }
        onExited: function (exitCode) {
            // A refused stop says so at once; a stop that ran is judged on the listing that
            // follows, because gio has exited 0 over a volume that was still mounted.
            if (root._ejectEndedLate) {
                root._ejectEndedLate = false
                root.poll()
                return
            }
            if (exitCode !== 0 && root._powerOffDisk.length > 0) {
                var sentence = Devices.mountError("eject", exitCode, root._ejectErr, root._ejectLabel)
                powerOffTimeout.stop()
                root._powerOffDisk = ""
                root._powerOffQueue = []
                root._ejectDevice = ""
                ejectVerdictTimeout.stop()
                root.reportFailure(sentence.length > 0 ? sentence : Format.fill(Mounts.WORDS.ejectFailed, root._ejectLabel), root._ejectErr)
                root.poll()
                return
            }
            if (root._powerOffDisk.length > 0)
                root._powerOffDisk = ""
            root._ejectDetachFailed = root._ejectLoop && exitCode === Devices.detachFailedExit
            root._verdictFromListing = root._listingsStarted + 1
            ejectVerdictTimeout.restart()
            root.poll()
        }
    }
}
