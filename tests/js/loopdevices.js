.import "../../ui/js/Devices.js" as Devices
.import "../../ui/js/Eject.js" as Eject
.import "../../ui/js/Format.js" as Format
.import "../../ui/js/Mounts.js" as Mounts
.import "sourcefixture.js" as Source

// A loop-mounted .iso in the DEVICES rail: the one volume whose lsblk "rm" flag is never true
// even though it is as browsable as a stick's. tests/js/devices.js keeps the removable and
// system-disk cases.

function run(check) {
    // A .iso opened from the file list: gio loop-mounts it, giving it a partition table lsblk
    // reports the same way it would a real disk's, except "rm" is false throughout and the loop
    // device's own node is never itself mounted, only a partition under it is. Captured live from
    // lsblk after opening an Omarchy installer .iso, with the mount path made generic.
    var mountedIso = '{"blockdevices":['
                    + '{"name":"nvme0n1","path":"/dev/nvme0n1","label":null,"mountpoints":[null],"rm":false,"size":256060514304,"type":"disk","model":"KBG40ZNS256G",'
                    + '"children":[{"name":"nvme0n1p1","path":"/dev/nvme0n1p1","label":null,"mountpoints":["/"],"rm":false,"size":256060514304,"type":"part","model":null}]},'
                    + '{"name":"loop0","path":"/dev/loop0","label":null,"mountpoints":[null],"rm":false,"size":6224838656,"type":"loop","model":null,'
                    + '"children":[{"name":"loop0p1","path":"/dev/loop0p1","label":"OMARCHY_202608","mountpoints":["/run/media/user/OMARCHY_202608"],"rm":false,"size":6224838656,"type":"part","model":null},'
                    + '{"name":"loop0p2","path":"/dev/loop0p2","label":null,"mountpoints":[null],"rm":false,"size":24117248,"type":"part","model":null}]}'
                    + ']}'
    var iso = Devices.parseDevices(mountedIso)
    check("the mounted loop partition is a device row despite rm being false", iso.length, 2)
    check("the mounted loop partition takes the filesystem label", iso[1].label, "OMARCHY_202608")
    check("the mounted loop partition carries its device node for gio", iso[1].device, "/dev/loop0p1")
    check("the mounted loop partition carries the mountpoint lsblk reported", iso[1].path, "/run/media/user/OMARCHY_202608")
    check("the mounted loop partition reads as mounted", iso[1].mounted, true)
    check("the loop device's own row is not duplicated", iso.map(function (e) { return e.label }).join(","), "nvme0n1,OMARCHY_202608")
    check("the loop device's unmounted second partition is not a row", iso.some(function (e) { return e.device === "/dev/loop0p2" }), false)
    check("a mounted loop partition is not marked removable, since rm never goes true for one", iso[1].removable, false)
    // DeviceMounts.qml's eject() reads this to route a loop row to gio mount -u instead of -e:
    // -e hangs indefinitely on a loop volume (measured live), because it never carries a Drive
    // object the way a real disk's partition does, and gio's eject path waits on one regardless.
    check("the mounted loop partition is marked loop for eject to route around", iso[1].loop, true)
    // Eject unmounts it, then detaches only when the loop was not already set to autoclear.
    var loopEject = Devices.ejectCommand(iso[1])
    check("a loop row's eject uses a shell with argument-only paths", loopEject.slice(0, 2).join(" "), "sh -c")
    check("a loop row passes its validated backing-file path as argument 3", loopEject[6], "/sys/block/loop0/loop/backing_file")
    check("a loop row passes its validated autoclear path as argument 4", loopEject[7], "/sys/block/loop0/loop/autoclear")
    console.log("LOOP_EJECT_COMMAND " + JSON.stringify(loopEject))
    check("a failed detach exits with its own code, apart from a failed unmount", Devices.detachFailedExit, 3)
    check("a loop row's eject passes the mountpoint and the loop device as arguments",
          loopEject.slice(3, 6).join(" "), "sh /run/media/user/OMARCHY_202608 /dev/loop0")
    check("a stick's eject stays gio mount -e on its mountpoint",
          Devices.ejectCommand({ device: "/dev/sda1", path: "/run/media/user/128GB", loop: false }).join(" "),
          "gio mount -e /run/media/user/128GB")
    check("a loop row whose device is no loop node falls back to -u alone",
          Devices.ejectCommand({ device: "/dev/mapper/x", path: "/m", loop: true }).join(" "), "gio mount -u /m")
    for (var number of [0, 9, 10, 12, 1234]) {
        for (var suffix of ["", "p1", "p12"]) {
            var device = "/dev/loop" + number
            check("eject keeps the exact loop number for " + device + suffix,
                  Devices.ejectCommand({ device: device + suffix, path: "/m", loop: true }).slice(5).join("|"),
                  device + "|/sys/block/loop" + number + "/loop/backing_file|/sys/block/loop" + number + "/loop/autoclear")
        }
    }

    var hybrid = JSON.parse(mountedIso)
    hybrid.blockdevices[1].fstype = "iso9660"
    hybrid.blockdevices[1].label = "WHOLE_ISO"
    hybrid.blockdevices[1].mountpoints = ["/run/media/user/WHOLE_ISO"]
    var parents = Devices.parseDevices(JSON.stringify(hybrid))
    var parent = parents.filter(function (e) { return e.device === "/dev/loop0" })[0]
    check("a mounted hybrid loop parent is a row beside its mounted child", parents.length, 3)
    check("the mounted hybrid loop parent keeps its mountpoint", parent ? parent.path : "missing", "/run/media/user/WHOLE_ISO")
    check("the mounted hybrid loop parent keeps its loop eject route", parent ? Devices.ejectCommand(parent).slice(4, 6).join("|") : "missing",
          "/run/media/user/WHOLE_ISO|/dev/loop0")
    check("walking a mounted parent still finds its mounted child", parents.some(function (e) { return e.device === "/dev/loop0p1" }), true)

    var gone = '{"blockdevices":[{"name":"nvme0n1","path":"/dev/nvme0n1","mountpoints":["/"]}]}'
    var kept = '{"blockdevices":[{"name":"loop0","path":"/dev/loop0","children":[{"name":"loop0p1","path":"/dev/loop0p1","mountpoints":["/run/media/user/OMARCHY_202608"]}]}]}'
    check("exit 3 with an unmounted loop reports the failed detach", ejectMessage(3, gone),
          "Unmounted OMARCHY_202608, but its loop device is still attached.|true")
    check("exit 1 with the mount gone is judged ejected by the next listing", ejectMessage(1, gone), "Ejected OMARCHY_202608.|false")
    check("exit 1 with the mount kept reports still mounted", ejectMessage(1, kept), "OMARCHY_202608 is still mounted; close what is using it.|true")
    check("exit 0 with the mount gone reports ejected without an unplug line", ejectMessage(0, gone), "Ejected OMARCHY_202608.|false")
    check("exit 0 with the mount kept never reports success", ejectMessage(0, kept), "OMARCHY_202608 is still mounted; close what is using it.|true")
    var otherPartition = kept.replace('loop0p1', 'loop0p2')
    check("exit 0 with another partition mounted reports only the target ejected", ejectMessage(0, otherPartition), "Ejected OMARCHY_202608.|false")

    // With unmounted volumes shown, a loop device's unmounted partition stays out even when it
    // has a filesystem to browse: only the partition gio mounted is a row.
    var isoWithData = mountedIso.replace('"name":"loop0p2","path":"/dev/loop0p2","label":null,',
                                         '"name":"loop0p2","path":"/dev/loop0p2","label":"DATA","fstype":"ext4",')
    var shown = Devices.parseDevices(isoWithData, true)
    check("an unmounted loop partition with a filesystem is not a row with unmounted shown",
          shown.map(function (e) { return e.label }).join(","), "nvme0n1,OMARCHY_202608")

    // An entirely unmounted loop device (systemd, some package manager, ...) stays out, same as
    // before: "mounted" is the only signal that tells a browsable loop apart from one that has
    // nothing to do with anyone browsing files.
    var bareLoop = '{"blockdevices":['
                  + '{"name":"nvme0n1","path":"/dev/nvme0n1","label":null,"mountpoints":[null],"rm":false,"size":256060514304,"type":"disk","model":"KBG40ZNS256G",'
                  + '"children":[{"name":"nvme0n1p1","path":"/dev/nvme0n1p1","label":null,"mountpoints":["/"],"rm":false,"size":256060514304,"type":"part","model":null}]},'
                  + '{"name":"loop0","path":"/dev/loop0","label":"FLEATEST","mountpoints":[null],"rm":false,"size":67108864,"type":"loop","model":null}'
                  + ']}'
    check("an unmounted bare loop device is still not a device row", Devices.parseDevices(bareLoop).length, 1)
}

// Sample input: exit 3 and a listing with the loop gone drive the shipped exit handler to its emitted message.
function ejectMessage(exitCode, listing) {
    var source = Source.source("ui/DeviceMounts.qml")
    var process = source.substring(source.indexOf("        id: ejectProcess"))
    var exited = Source.block(process, "onExited: function (exitCode)", "ui/DeviceMounts.qml")
    var verdict = Source.slice(source, "    function judgeEject(", "    Timer {")
    var messages = []
    var stale = '{"blockdevices":[{"name":"loop0","children":[{"name":"loop0p1","mountpoints":["/old-mount"]}]}]}'
    var root = { _ejectDevice: "/dev/loop0p1", _ejectLabel: "OMARCHY_202608", _ejectLoop: true,
        _ejectDetachFailed: false, _ejectEndedLate: false, _powerOffDisk: "", _powerOffQueue: [],
        _verdictFromListing: 0, _listingsStarted: 7, _lastVerdict: "",
        lockCrypt: function () {}, forgetMessage: function () {},
        message: function (text, error) { messages.push(text + "|" + error) },
        poll: function () {
            this.judgeEject(stale)
            this._listingsStarted += 1
            this.judgeEject(listing)
        } }
    var timer = { stop: function () {}, restart: function () {} }
    new Function("root", "Devices", "Eject", "Format", "Mounts", "powerOffTimeout", "ejectVerdictTimeout", "exitCode",
        verdict + "; root.reportEject = reportEject; root.judgeEject = judgeEject; " + exited)(root, Devices, Eject, Format, Mounts, timer, timer, exitCode)
    return messages.join(";")
}
