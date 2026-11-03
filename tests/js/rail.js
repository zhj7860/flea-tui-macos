.import "../../ui/js/Devices.js" as Devices
.import "../../ui/js/Format.js" as Format
.import "../../ui/js/Mounts.js" as Mounts
.import "../../ui/js/Eject.js" as Eject
.import "../../ui/js/Cloud.js" as Cloud
.import "../../ui/js/NetFs.js" as NetFs
.import "../../ui/js/Messages.js" as Messages
.import "../../ui/js/Motion.js" as Motion
.import "sourcefixture.js" as Source

// RailAdditions rules 1 and 2: the volumes nothing has mounted, behind their own switch, and the
// menu those rows carry. Split out of tests/js/devices.js, which keeps the 0.2.1 rail's own parse.

// One internal disk carrying /, a second drive with five volumes, one of each exception the rule
// names. fstype and parttypename are what it reads, and tests/js/devices.js's live listing predates
// both columns, which is the other half of why this fixture is its own.
var unmountedBox = '{"blockdevices":['
                 + '{"name":"nvme0n1","path":"/dev/nvme0n1","label":null,"mountpoints":[null],"rm":false,"size":256060514304,"type":"disk","model":"KBG40ZNS256G","fstype":null,"parttypename":null,'
                 + '"children":[{"name":"nvme0n1p1","path":"/dev/nvme0n1p1","label":null,"mountpoints":["/"],"rm":false,"size":256060514304,"type":"part","model":null,"fstype":"btrfs","parttypename":"Linux filesystem"}]},'
                 + '{"name":"sdb","path":"/dev/sdb","label":null,"mountpoints":[null],"rm":false,"size":2000398934016,"type":"disk","model":"Samsung SSD 870","fstype":null,"parttypename":null,'
                 + '"children":[{"name":"sdb1","path":"/dev/sdb1","label":"Archive","mountpoints":[null],"rm":false,"size":1000398934016,"type":"part","model":null,"fstype":"ext4","parttypename":"Linux filesystem"},'
                 + '{"name":"sdb2","path":"/dev/sdb2","label":null,"mountpoints":[null],"rm":false,"size":536870912,"type":"part","model":null,"fstype":"vfat","parttypename":"EFI System"},'
                 + '{"name":"sdb3","path":"/dev/sdb3","label":null,"mountpoints":["[SWAP]"],"rm":false,"size":8589934592,"type":"part","model":null,"fstype":"swap","parttypename":"Linux swap"},'
                 + '{"name":"sdb4","path":"/dev/sdb4","label":null,"mountpoints":[null],"rm":false,"size":268435456,"type":"part","model":null,"fstype":null,"parttypename":"Linux filesystem"},'
                 + '{"name":"sdb5","path":"/dev/sdb5","label":null,"mountpoints":[null],"rm":false,"size":268435456,"type":"part","model":null,"fstype":"crypto_LUKS","parttypename":"Linux filesystem"}]}'
                 + ']}'

function labels(rows) {
    return rows.map(function (e) { return e.label }).join(",")
}

function run(check) {
    var off = Devices.parseDevices(unmountedBox, false)
    // Unlock (U039): a locked container is a rail row wherever it sits, even with the switch off.
    check("with the switch off the rail is 0.2.1 plus the locked container", labels(off), "nvme0n1,Samsung SSD 870")
    var on = Devices.parseDevices(unmountedBox, true)
    check("the volume nothing mounted joins the rail, and only it beside the locked one", labels(on), "nvme0n1,Archive,Samsung SSD 870")
    check("the unmounted volume reads as unmounted", on[1].mounted, false)
    check("it has no mountpoint to open, so it has no path", on[1].path, "")
    check("it keeps the RailDetails column's own size", on[1].size, 1000398934016)
    check("it is not removable, so nothing offers to eject a fixed disk", on[1].removable, false)
    check("and it carries its device node, which is what gio mounts", on[1].device, "/dev/sdb1")
    var unmountedEntry = { path: on[1].path, label: on[1].label, group: "device", kind: on[1].kind,
                           device: on[1].device, mounted: on[1].mounted, removable: on[1].removable }
    check("the volume nothing mounted still offers Mount",
          solid(Mounts.railMenu(unmountedEntry)).map(function (r) { return r.label }).join(","), "Mount")
    // A stick is a row either way, so it is the one that says what the switch does to an existing row.
    var stickBox = '{"blockdevices":[{"name":"sda","path":"/dev/sda","label":null,"mountpoints":[null],"rm":true,"size":124656812032,"type":"disk","model":"USB Flash Disk","fstype":null,"parttypename":null,'
              + '"children":[{"name":"sda1","path":"/dev/sda1","label":"128GB","mountpoints":["/run/media/gm/128GB"],"rm":true,"size":124656812032,"type":"part","model":null,"fstype":"vfat","parttypename":"W95 FAT32"}]}]}'
    check("and a mounted stick is still a row with the switch off",
          labels(Devices.parseDevices(stickBox, false)), "128GB")

    // Rule 1's three exceptions, each named by lsblk rather than guessed from a name.
    check("swap is not a place to browse", labels(on).indexOf("sdb3"), -1)
    check("the EFI system partition is the box's own plumbing", labels(on).indexOf("sdb2"), -1)
    check("a volume with no filesystem has nothing to mount", labels(on).indexOf("sdb4"), -1)
    // Unlock (U039): the locked container's menu is the dialog, not the mount its activation used to attempt.
    var lockedRow = null
    for (var l = 0; l < on.length; l++) {
        if (on[l].locked === true)
            lockedRow = on[l]
    }
    check("a locked LUKS container is a rail row", lockedRow !== null, true)
    // The parsed row itself, not a hand-built one: the menu reads group, kind and locked too.
    check("and its menu is Unlock", Mounts.railMenu(Object.assign({ group: "device" }, lockedRow)).map(function (r) { return r.label + ":" + r.action }).join(","), "Unlock:unlockVolume")

    // A USB LUN with media but no filesystem is not a rail row, removable or not.
    function bootBox(sda) {
        return '{"blockdevices":['
            + '{"name":"nvme0n1","path":"/dev/nvme0n1","label":null,"mountpoints":[null],"rm":false,"size":256060514304,"type":"disk","model":"KBG40ZNS256G","fstype":null,"parttypename":null,'
            + '"children":[{"name":"nvme0n1p1","path":"/dev/nvme0n1p1","label":null,"mountpoints":["/"],"rm":false,"size":256060514304,"type":"part","model":null,"fstype":"btrfs","parttypename":"Linux filesystem"}]},'
            + sda + ']}'
    }
    var bootLun = '{"name":"sda","path":"/dev/sda","label":null,"mountpoints":[null],"rm":true,"tran":"usb","size":4194304,"type":"disk","model":"USB bootloader","fstype":null,"parttypename":null}'
    check("a no-filesystem USB LUN is not a row with the switch on", labels(Devices.parseDevices(bootBox(bootLun), true)), "nvme0n1")
    check("a no-filesystem USB LUN is not a row with the switch off", labels(Devices.parseDevices(bootBox(bootLun), false)), "nvme0n1")
    var bootChild = '{"name":"sda","path":"/dev/sda","label":null,"mountpoints":[null],"rm":false,"tran":"usb","size":4194304,"type":"disk","model":"USB bootloader","fstype":null,"parttypename":null,'
        + '"children":[{"name":"sda1","path":"/dev/sda1","label":null,"mountpoints":[null],"rm":false,"tran":null,"size":4194304,"type":"part","model":null,"fstype":null,"parttypename":null}]}'
    check("a no-filesystem child on a USB disk is not a row either", labels(Devices.parseDevices(bootBox(bootChild), true)), "nvme0n1")
    check("null, empty and absent fstype all mean no filesystem",
        [bootLun, bootLun.replace('"fstype":null', '"fstype":""'), bootLun.replace(',"fstype":null', '')].every(function (leaf) {
            return labels(Devices.parseDevices(bootBox(leaf), true)) === "nvme0n1"
        }), true)
    check("the same LUN with a filesystem is still a row", labels(Devices.parseDevices(bootBox(bootLun.replace('"fstype":null', '"fstype":"vfat"')), true)), "nvme0n1,USB bootloader")
    function stickPart(leaf) {
        return '{"name":"sda","path":"/dev/sda","label":null,"mountpoints":[null],"rm":true,"tran":"usb","size":124656812032,"type":"disk","model":"USB bootloader","fstype":null,"parttypename":null,'
            + '"children":[' + leaf + ']}'
    }
    function romLeaf(fs) {
        var fstype = fs === null ? "null" : '"' + fs + '"'
        return '{"name":"sr0","path":"/dev/sr0","label":null,"mountpoints":[null],"rm":true,"size":0,"type":"rom","model":"MATSHITA DVD+/-RW UJ8FB","fstype":' + fstype + '}'
    }
    var espLeaf = '{"name":"sda1","path":"/dev/sda1","label":"BOOT","mountpoints":[null],"rm":true,"tran":null,"size":536870912,"type":"part","model":null,"fstype":"vfat","parttypename":"EFI System","parttype":"c12a7328-f81f-11d2-ba4b-00a0c93ec93b","pttype":"gpt","partn":1,"uuid":"A1B2-C3D4"}'
    check("an EFI system partition on a stick is hidden on every setting", labels(Devices.parseDevices(bootBox(stickPart(espLeaf)), true)), "nvme0n1")
    check("and it stays hidden with the switch off", labels(Devices.parseDevices(bootBox(stickPart(espLeaf)), false)), "nvme0n1")
    var cryptLeaf = '{"name":"sda1","path":"/dev/sda1","label":null,"mountpoints":[null],"rm":true,"tran":null,"size":8589934592,"type":"part","model":null,"fstype":"crypto_LUKS","parttypename":"Linux filesystem"}'
    check("an unmounted crypto_LUKS stick partition is still a row", labels(Devices.parseDevices(bootBox(stickPart(cryptLeaf)), true)), "nvme0n1,USB bootloader")
    check("a no-filesystem leaf that is somehow mounted is still a row",
        labels(Devices.parseDevices(bootBox(bootLun.replace('[null]', '["/run/media/gm/BOOT"]')), true)), "nvme0n1,USB bootloader")
    check("an empty rom stays hidden through the same guard", labels(Devices.parseDevices(bootBox(romLeaf(null)), true)), "nvme0n1")
    check("an iso9660 rom is still a row", labels(Devices.parseDevices(bootBox(romLeaf("iso9660")), true)), "nvme0n1,MATSHITA DVD+/-RW UJ8FB")

    // Every hidden class below hides on every setting.
    function hideLeaf(leaf) { return labels(Devices.parseDevices(bootBox(stickPart(leaf)), true)) }
    function hideLeafOff(leaf) { return labels(Devices.parseDevices(bootBox(stickPart(leaf)), false)) }
    var sysLeaf = '{"name":"sda1","path":"/dev/sda1","label":"System Reserved","mountpoints":[null],"rm":false,"tran":null,"size":52428800,"type":"part","model":null,"fstype":"ntfs","parttypename":null,"parttype":"0x7","pttype":"dos","partn":1,"uuid":"2222222222222222"}'
    check("System Reserved hides on every setting", hideLeaf(sysLeaf), "nvme0n1")
    check("and it stays hidden with the switch off", hideLeafOff(sysLeaf), "nvme0n1")
    var winLeaf = '{"name":"sda2","path":"/dev/sda2","label":null,"mountpoints":[null],"rm":false,"tran":null,"size":524288000,"type":"part","model":null,"fstype":"ntfs","parttypename":null,"parttype":"0x27","pttype":"dos","partn":2,"uuid":"3333333333333333"}'
    check("a 0x27 WinRE partition hides", hideLeaf(winLeaf), "nvme0n1")
    var msrLeaf = '{"name":"sda1","path":"/dev/sda1","label":null,"mountpoints":[null],"rm":false,"tran":null,"size":16777216,"type":"part","model":null,"fstype":"ntfs","parttypename":null,"parttype":"e3c9e316-0b5c-4db8-817d-f92df00215ae","pttype":"gpt","partn":1,"uuid":null}'
    check("an MSR partition hides", hideLeaf(msrLeaf), "nvme0n1")
    var pvLeaf = '{"name":"sda1","path":"/dev/sda1","label":null,"mountpoints":[null],"rm":false,"tran":null,"size":1073741824,"type":"part","model":null,"fstype":"LVM2_member","parttypename":null,"parttype":"0x8e","pttype":"dos","partn":1,"uuid":"44444444-4444-4444-4444-444444444444"}'
    check("an LVM PV hides", hideLeaf(pvLeaf), "nvme0n1")
    check("and it stays hidden with the switch off", hideLeafOff(pvLeaf), "nvme0n1")
    var raidLeaf = '{"name":"sda1","path":"/dev/sda1","label":null,"mountpoints":[null],"rm":false,"tran":null,"size":1073741824,"type":"part","model":null,"fstype":"linux_raid_member","parttypename":null,"parttype":"0xfd","pttype":"dos","partn":1,"uuid":"55555555-5555-5555-5555-555555555555"}'
    check("a RAID member hides", hideLeaf(raidLeaf), "nvme0n1")
    var swapLeaf = '{"name":"sda1","path":"/dev/sda1","label":null,"mountpoints":["[SWAP]"],"rm":true,"tran":null,"size":268435456,"type":"part","model":null,"fstype":"swap","parttypename":"Linux swap","parttype":"0x82","pttype":"dos","partn":1,"uuid":"66666666-6666-6666-6666-666666666666"}'
    check("swap on a stick hides on every setting", hideLeaf(swapLeaf), "nvme0n1")
    check("and it stays hidden with the switch off", hideLeafOff(swapLeaf), "nvme0n1")
    var nofsLeaf = '{"name":"sda1","path":"/dev/sda1","label":null,"mountpoints":[null],"rm":true,"tran":null,"size":268435456,"type":"part","model":null,"fstype":null,"parttypename":null,"parttype":null,"pttype":"dos","partn":1,"uuid":null}'
    check("a partition with no filesystem hides", hideLeaf(nofsLeaf), "nvme0n1")
    var isoLeaf = '{"name":"sda1","path":"/dev/sda1","label":"FLEA-ISO","mountpoints":[null],"rm":true,"tran":null,"size":1073741824,"type":"part","model":null,"fstype":"iso9660","parttypename":null,"parttype":"0x0","pttype":"dos","partn":1,"uuid":"88888888-8888-8888-8888-888888888888"}'
    check("an isohybrid ISO partition stays a row", hideLeaf(isoLeaf), "nvme0n1,FLEA-ISO")
    var dataLeaf = '{"name":"sda1","path":"/dev/sda1","label":"DATA","mountpoints":["/home/gm/Data"],"rm":true,"tran":null,"size":124656812032,"type":"part","model":null,"fstype":"vfat","parttypename":"W95 FAT32","parttype":"0xb","pttype":"dos","partn":1,"uuid":"A1B2-C3D4"}'
    check("a user drive mounted under home stays a row", hideLeaf(dataLeaf), "nvme0n1,DATA")
    var dupBody = '{"blockdevices":[{"name":"nvme0n1","path":"/dev/nvme0n1","label":null,"mountpoints":[null],"rm":false,"size":256060514304,"type":"disk","model":"KBG40ZNS256G","fstype":null,"parttypename":null,"children":[{"name":"nvme0n1p1","path":"/dev/nvme0n1p1","label":null,"mountpoints":["/"],"rm":false,"size":256060514304,"type":"part","model":null}]},'
        + '{"name":"sda","path":"/dev/sda","label":null,"mountpoints":[null],"rm":true,"tran":"usb","size":124656812032,"type":"disk","model":"Stick","fstype":null,"parttypename":null,"children":[{"name":"sda1","path":"/dev/sda1","label":"A","mountpoints":["/run/media/gm/A"],"rm":true,"size":1000,"type":"part","model":null,"fstype":"vfat","uuid":"9998"},{"name":"sda1","path":"/dev/sda1","label":"A","mountpoints":["/run/media/gm/A"],"rm":true,"size":1000,"type":"part","model":null,"fstype":"vfat","uuid":"9997"}]}]}'
    check("a repeated PATH names one row, not two", Devices.parseDevices(dupBody, true).length, 2)
    var isoBody = '{"blockdevices":[{"name":"nvme0n1","path":"/dev/nvme0n1","label":null,"mountpoints":[null],"rm":false,"size":256060514304,"type":"disk","model":"KBG40ZNS256G","fstype":null,"parttypename":null,"children":[{"name":"nvme0n1p1","path":"/dev/nvme0n1p1","label":null,"mountpoints":["/"],"rm":false,"size":256060514304,"type":"part","model":null}]},'
        + '{"name":"sda","path":"/dev/sda","label":null,"mountpoints":[null],"rm":true,"tran":"usb","size":1000,"type":"disk","model":"StickA","fstype":null,"parttypename":null,"children":[{"name":"sda1","path":"/dev/sda1","label":"ISO-A","mountpoints":[null],"rm":true,"size":1000,"type":"part","model":null,"fstype":"iso9660","parttype":"0x0","pttype":"dos","partn":1,"uuid":"2026-09-01-10-00-00-00"}]},'
        + '{"name":"sdb","path":"/dev/sdb","label":null,"mountpoints":[null],"rm":true,"tran":"usb","size":1000,"type":"disk","model":"StickB","fstype":null,"parttypename":null,"children":[{"name":"sdb1","path":"/dev/sdb1","label":"ISO-B","mountpoints":[null],"rm":true,"size":1000,"type":"part","model":null,"fstype":"iso9660","parttype":"0x0","pttype":"dos","partn":1,"uuid":"2026-09-01-10-00-00-00"}]}]}'
    check("two sticks sharing one ISO image keep both rows", labels(Devices.parseDevices(isoBody, true)), "nvme0n1,ISO-A,ISO-B")
    var btrfsBody = '{"blockdevices":[{"name":"nvme0n1","path":"/dev/nvme0n1","label":null,"mountpoints":[null],"rm":false,"size":256060514304,"type":"disk","model":"KBG40ZNS256G","fstype":null,"parttypename":null,"children":[{"name":"nvme0n1p1","path":"/dev/nvme0n1p1","label":null,"mountpoints":["/"],"rm":false,"size":256060514304,"type":"part","model":null}]},'
        + '{"name":"sdb","path":"/dev/sdb","label":null,"mountpoints":[null],"rm":false,"size":1000,"type":"disk","model":null,"fstype":null,"parttypename":null,"children":[{"name":"sdb1","path":"/dev/sdb1","label":null,"mountpoints":["/mnt/a"],"rm":false,"size":1000,"type":"part","model":null,"fstype":"btrfs","uuid":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}]},'
        + '{"name":"sdc","path":"/dev/sdc","label":null,"mountpoints":[null],"rm":false,"size":1000,"type":"disk","model":null,"fstype":null,"parttypename":null,"children":[{"name":"sdc1","path":"/dev/sdc1","label":null,"mountpoints":["/mnt/b"],"rm":false,"size":1000,"type":"part","model":null,"fstype":"btrfs","uuid":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}]}]}'
    check("two btrfs paths sharing one UUID name one row", Devices.parseDevices(btrfsBody, true).length, 2)
    var remountBody = '{"blockdevices":[{"name":"sda","path":"/dev/sda","label":null,"mountpoints":[null],"rm":true,"tran":"usb","size":1000,"type":"disk","model":"Stick","fstype":null,"parttypename":null,"children":['
        + '{"name":"sda1","path":"/dev/sda1","label":"A","mountpoints":[null],"rm":true,"size":1000,"type":"part","model":null,"fstype":"vfat","uuid":"9998"},'
        + '{"name":"sda1","path":"/dev/sda1","label":"A","mountpoints":["/run/media/gm/A"],"rm":true,"size":1000,"type":"part","model":null,"fstype":"vfat","uuid":"9997"}]}]}'
    var remounted = Devices.parseDevices(remountBody, true)
    check("a mounted copy replaces its unmounted first row", remounted.length === 1 && remounted[0].mounted === true && remounted[0].path === "/run/media/gm/A", true)

    // Rule 2's rows, which only a row from rule 1 carries.
    function solid(rows) { return rows.filter(function (r) { return r.separator !== true }) }
    var unmounted = { group: "device", kind: "volume", mounted: false, removable: false }
    check("an unmounted volume offers the mount its own activation does",
          solid(Mounts.railMenu(unmounted)).map(function (r) { return r.label + ":" + r.action }).join(","), "Mount:mountVolume")
    var mounted = { group: "device", kind: "volume", mounted: true, removable: false }
    check("a mounted one offers the open beside the release",
          solid(Mounts.railMenu(mounted)).map(function (r) { return r.label + ":" + r.action }).join(","),
          "Open:open,Unmount:unmountVolume")
    var stick = { group: "device", kind: "volume", mounted: true, removable: true }
    check("and Eject stays where it stands today, on a volume somebody can pull out",
          solid(Mounts.railMenu(stick)).map(function (r) { return r.label }).join(","), "Open,Unmount,Eject,Flash image")
    check("and an unmounted one offers Mount and the way in from a drive",
          solid(Mounts.railMenu({ group: "device", kind: "volume", mounted: false, removable: true })).map(function (r) { return r.label }).join(","), "Mount,Flash image")

    // Every mounted volume offers Unmount with the switch off, so Ctrl+E releases it.
    var twoDisk = '{"blockdevices":['
        + '{"name":"nvme0n1","path":"/dev/nvme0n1","label":null,"mountpoints":[null],"rm":false,"size":256060514304,"type":"disk","model":"KBG40ZNS256G","fstype":null,"parttypename":null,'
        + '"children":[{"name":"nvme0n1p1","path":"/dev/nvme0n1p1","label":null,"mountpoints":["/"],"rm":false,"size":256060514304,"type":"part","model":null,"fstype":"btrfs","parttypename":"Linux filesystem"}]},'
        + '{"name":"nvme1n1","path":"/dev/nvme1n1","label":null,"mountpoints":[null],"rm":false,"size":1000398934016,"type":"disk","model":"Samsung SSD 870","fstype":null,"parttypename":null,'
        + '"children":[{"name":"nvme1n1p1","path":"/dev/nvme1n1p1","label":"Data","mountpoints":["/mnt/data"],"rm":false,"size":1000398934016,"type":"part","model":null,"fstype":"ext4","parttypename":"Linux filesystem"}]},'
        + '{"name":"sda","path":"/dev/sda","label":null,"mountpoints":[null],"rm":true,"size":124656812032,"type":"disk","model":"USB Flash Disk","fstype":null,"parttypename":null,'
        + '"children":[{"name":"sda1","path":"/dev/sda1","label":"128GB","mountpoints":["/run/media/gm/128GB"],"rm":true,"size":124656812032,"type":"part","model":null,"fstype":"vfat","parttypename":"W95 FAT32"}]}]}'
    function railEntryOf(row) {
        return { path: row.path, label: row.label, group: "device", kind: row.kind,
                 device: row.device, mounted: row.mounted, removable: row.removable, glyph: "drive" }
    }
    var railRows = Devices.parseDevices(twoDisk, false).map(railEntryOf)
    function railRow(label) {
        for (var i = 0; i < railRows.length; i++)
            if (railRows[i].label === label) return railRows[i]
        return null
    }
    function railActions(entry) {
        return solid(Mounts.railMenu(entry)).map(function (r) { return r.label }).join(",")
    }
    // The flags reach the pane only as the backend's fsinfo line, through Messages.route into the shipped PaneWire.onFsInfo.
    var onFsInfoBody = Source.block(Source.source("ui/PaneWire.qml"),
        "function onFsInfo(fs, free, path, storageClass, tagable, systemVolume)", "ui/PaneWire.qml")
    function answer(pane, line) {
        var onFsInfo = new Function("root", "pane", "ExtThumbs", "ViewState",
            "return function (fs, free, path, storageClass, tagable, systemVolume) {" + onFsInfoBody + "}")(
            { pane: pane }, pane, { verdict: function () { return "" } }, { preview: "" })
        Messages.route({ fsInfo: onFsInfo }, JSON.parse(line))
    }
    // Sample output, src/backend/fsinfo.rs: {"t":"fsinfo","fs":"btrfs","free":7,"path":"/home/gm","class":"","tagable":false,"system":true}
    var tagRoot = { path: "/home/gm", recentMode: "", fsName: "", fsFree: 0, storageClass: "", storageKnown: false,
                    systemVolume: false, canTag: false, extVerdict: "", listArea: null, said: "",
                    message: function (t) { this.said = t }, ejectHidden: function () {} }
    answer(tagRoot, '{"t":"fsinfo","fs":"btrfs","free":7,"path":"/home/gm","class":"","tagable":true}')
    check("the fsinfo line also carries the tag verdict", tagRoot.canTag, true)
    function fsInfoLine(path, system) {
        var line = { t: "fsinfo", fs: "btrfs", free: 7, path: path, "class": "", tagable: false }
        if (system)
            line.system = true
        return JSON.stringify(line)
    }
    check("the fixture writes the backend's own fsinfo line, as src/backend/fsinfo.rs pins it",
          Source.source("src/backend/fsinfo.rs").indexOf('r#"' + fsInfoLine("/home/gm", true) + '"#') >= 0, true)
    // facts: system rides the line for facts.from (default path), and a Recent mode opens after that line lands.
    function ejector(path, entries, railCursor, facts) {
        var f = facts || {}
        var root = { path: path, recentMode: "", fsName: "", fsFree: 0, storageClass: "", storageKnown: false,
                     systemVolume: false, extVerdict: "", listArea: null, said: "", told: 0, handed: 0,
                     message: function (t) { this.said = t; this.told += 1 }, ejectHidden: function () { this.handed += 1 } }
        answer(root, fsInfoLine(f.from || path, f.system === true))
        root.recentMode = f.recent || ""
        var rail = entries === null ? null : { entries: entries, cursorIndex: railCursor || 0, released: [],
                     releaseChosen: function (a, k) { this.released.push(a + ":" + k) } }
        Eject.release(root, rail, railCursor !== undefined)
        return { said: root.said, told: root.told, handed: root.handed, released: rail ? rail.released : [] }
    }
    check("a mounted internal volume offers Open and Unmount with the switch off",
          railActions(railRow("Data")), "Open,Unmount")
    var dataOut = ejector("/mnt/data/photos", railRows)
    check("Ctrl+E inside it releases that volume and says nothing",
          dataOut.released.join(",") + "|" + dataOut.said, "unmountVolume:/dev/nvme1n1p1|")
    check("with the switch off a mounted stick offers Open, Unmount, Eject and Flash image",
          railActions(railRow("128GB")), "Open,Unmount,Eject,Flash image")
    check("and Ctrl+E still picks eject there",
          Eject.releaseFromRows(Mounts.railMenu(railRow("128GB"))), "eject")
    var bareStick = '{"blockdevices":[{"name":"nvme0n1","path":"/dev/nvme0n1","label":null,"mountpoints":[null],"rm":false,"size":1,"type":"disk","model":"KBG40ZNS256G","fstype":null,"parttypename":null,'
        + '"children":[{"name":"nvme0n1p1","path":"/dev/nvme0n1p1","label":null,"mountpoints":["/"],"rm":false,"size":1,"type":"part","model":null,"fstype":"btrfs","parttypename":"Linux filesystem"}]},'
        + '{"name":"sda","path":"/dev/sda","label":null,"mountpoints":[null],"rm":true,"size":2,"type":"disk","model":"Stick","fstype":null,"parttypename":null,'
        + '"children":[{"name":"sda1","path":"/dev/sda1","label":"USB","mountpoints":[null],"rm":true,"size":2,"type":"part","model":null,"fstype":"vfat","parttypename":"W95 FAT32"}]}]}'
    var idleRows = Devices.parseDevices(bareStick, false).map(railEntryOf)
    check("an unmounted stick offers Mount and Flash image with the switch off",
          railActions(idleRows[1]), "Mount,Flash image")
    check("Ctrl+E on an unmounted volume row releases nothing",
          Eject.releaseFromRows(Mounts.railMenu(idleRows[1])), "")
    var systemSentence = "This folder is on a system volume, which Flea never unmounts"
    var noVolume = "This folder is not on a volume Flea can unmount"
    check("Ctrl+E under home names the system volume when the backend says a system mountpoint holds it",
          ejector("/home/user/Documents", railRows, undefined, { system: true }).said, systemSentence)
    var cloudRows = railRows.concat([{ label: "gdrive", group: "network", kind: "cloud",
        uri: "", path: "/home/u/gdrive", mounted: true, glyph: "server" }])
    check("Ctrl+E inside a cloud row names no volume",
          ejector("/home/u/gdrive/notes/f.txt", cloudRows, undefined).said, noVolume)
    // Rail shown, hidden (device rows only) or NETWORK off: the flag alone decides, set for home and unset for a FUSE mount in it.
    var homePlace = { label: "Home", group: "places", kind: "place", path: "/home/u", glyph: "home" }
    function homeThenFuse(rows) {
        return ejector("/home/u", rows, undefined, { system: true }).said + "|" + ejector("/home/u/mergerfs/notes", rows).said
    }
    check("home names the system volume and a FUSE mount in it names none, with the rail shown",
          homeThenFuse(cloudRows), systemSentence + "|" + noVolume)
    check("and the same with the rail hidden, where only the device rows are read",
          homeThenFuse(railRows), systemSentence + "|" + noVolume)
    check("and the same with the rail shown and NETWORK off",
          homeThenFuse([homePlace].concat(railRows)), systemSentence + "|" + noVolume)
    check("a folder reached through a link into a data volume names no system volume, whatever its path says",
          ejector("/home/user/Data/photos", railRows, undefined).said, noVolume)
    check("a Recent history spans mounts, so it names no system volume however the last folder was flagged",
          ejector("/", railRows, undefined, { system: true, recent: "results" }).said, noVolume)
    check("Ctrl+E under a GVFS folder names no volume",
          ejector("/run/user/1000/gvfs/smb-share:server=x,share=y/docs/f.txt", railRows, undefined).said, noVolume)
    check("Ctrl+E on a kernel network mount no row holds names no volume",
          ejector("/mnt/nas/docs", railRows, undefined).said, noVolume)
    check("a late fsinfo line for the folder just left never flags the one now shown",
          ejector("/srv/media", railRows, undefined, { system: true, from: "/home/user/Documents" }).said, noVolume)
    // A favourite carries its folder's path and a menu of its own but releases nothing, so it never stands for the volume that holds a folder.
    var photos = { label: "Photos", group: "favourite", kind: "favourite", path: "/mnt/data/photos", storedPath: "/mnt/data/photos", glyph: "folder" }
    var documents = { label: "Docs", group: "favourite", kind: "favourite", path: "/home/user/Documents", storedPath: "~/Documents", glyph: "folder" }
    var shadowed = ejector("/mnt/data/photos/2024", [photos].concat(railRows))
    check("a favourite inside a volume does not shadow that volume's release",
          shadowed.released.join(",") + "|" + shadowed.said, "unmountVolume:/dev/nvme1n1p1|")
    check("a favourite over a system folder does not hide the system volume sentence",
          ejector("/home/user/Documents/notes", [documents].concat(railRows), undefined, { system: true }).said, systemSentence)
    check("a favourite over a folder no volume row holds names no volume",
          ejector("/mnt/data/photos/2024", [photos]).said, noVolume)
    // Every branch of Ctrl+E ends in one whole sentence, or hands the key on: the hidden rail's flow, or the rail's release.
    function ending(run) { return run.told + " said|" + run.handed + " handed|" + run.released.length + " released" }
    check("a hidden rail hands the key to its one-shot flow and says nothing itself",
          ending(ejector("/mnt/data/photos", null)), "0 said|1 handed|0 released")
    check("a listing inside a mounted volume hands its release to the rail and says nothing itself",
          ending(ejector("/mnt/data/photos", railRows)), "0 said|0 handed|1 released")
    check("a system folder says its sentence once and releases nothing",
          ending(ejector("/home/user", railRows, undefined, { system: true })), "1 said|0 handed|0 released")
    check("a folder no volume holds says its sentence once and releases nothing",
          ending(ejector("/mnt/data2", railRows)), "1 said|0 handed|0 released")
    check("the rail's own disk row says its sentence once and releases nothing",
          ending(ejector("/home/user", railRows, 0)), "1 said|0 handed|0 released")
    check("a rail row with nothing to release says so once",
          ending(ejector("/home/user", [photos], 0)) + "|" + ejector("/home/user", [photos], 0).said,
          "1 said|0 handed|0 released|Photos has nothing to eject or unmount")
    check("Ctrl+E on the system disk names that drive",
          ejector("/home/user", railRows, 0).said, "nvme0n1 is the system drive, which Flea never unmounts")
    var cashRow = { label: "CASH$$", group: "device", kind: "disk", device: "/dev/sda", path: "/", mounted: true, glyph: "drive" }
    check("a label holding dollar signs is printed as written",
          ejector("/", [cashRow], 0).said, "CASH$$ is the system drive, which Flea never unmounts")
    check("and both busy sentences fill a label whole",
          [Mounts.WORDS.stillUnmounting, Mounts.WORDS.stillEjecting].map(function (w) { return Format.fill(w, "CASH$$") }).join("|"),
          "Still unmounting CASH$$; wait for its result|Still ejecting CASH$$; wait for its result")

    // CloudMounts: a FUSE mount inside the home folder shows in NETWORK under its
    // folder's name. Sample input, /proc/self/mountinfo lines (id parent maj:min root
    // mountpoint options, then fstype source superoptions):
    // 23 1 8:1 / /home/u/gdrive rw,nosuid,nodev - fuse.rclone remote: rw,user_id=1000,group_id=1000
    // 24 1 8:1 / /home/u/My\040Drive rw,nosuid,nodev - fuse.rclone remote: rw,user_id=1000,group_id=1000
    // 31 1 0:27 / /home/u/ProtonDrive rw,nosuid,nodev - fuse.protondrive proton: rw,user_id=1000
    // 18 1 8:1 / /home/u rw,nosuid,nodev - btrfs /dev/sda1 rw
    // 40 1 0:40 / /run/user/1000/gvfs rw,nosuid,nodev - fuse.gvfsd-fuse gvfsd-fuse rw,user_id=1000
    var mountsBody = "23 1 8:1 / /home/u/gdrive rw,nosuid,nodev - fuse.rclone remote: rw,user_id=1000,group_id=1000\n"
        + "24 1 8:1 / /home/u/My\\040Drive rw,nosuid,nodev - fuse.mergerfs merge: rw,user_id=1000,group_id=1000\n"
        + "31 1 0:27 / /home/u/ProtonDrive rw,nosuid,nodev - fuse.protondrive proton: rw,user_id=1000\n"
        + "18 1 8:1 / /home/u rw,nosuid,nodev - btrfs /dev/sda1 rw\n"
        + "40 1 0:40 / /run/user/1000/gvfs rw,nosuid,nodev - fuse.gvfsd-fuse gvfsd-fuse rw,user_id=1000\n"
    var clouds = Cloud.parseCloudMounts(mountsBody, "/home/u")
    check("only non-network FUSE inside home parses to a cloud row", clouds.length, 1)
    check("a network fstype inside home is never a cloud row",
          clouds.some(function (c) { return c.path === "/home/u/gdrive" || c.path === "/home/u/ProtonDrive" }), false)
    check("the row names the folder's own octal-decoded path", clouds[0].path, "/home/u/My Drive")
    check("the home directory itself is not a cloud mount",
          clouds.some(function (c) { return c.path === "/home/u" }), false)
    check("the gvfs FUSE mount is not inside home and stays out",
          clouds.some(function (c) { return c.path.indexOf("/run/") === 0 }), false)
    check("an empty body parses to nothing", Cloud.parseCloudMounts("", "/home/u").length, 0)
    check("garbage parses to nothing", Cloud.parseCloudMounts("not mountinfo at all\n", "/home/u").length, 0)
    check("no home means no rows", Cloud.parseCloudMounts(mountsBody, "").length, 0)
    check("a stacked mountpoint names one row, not two",
          Cloud.parseCloudMounts(mountsBody + "44 1 0:44 / /home/u/My\\040Drive rw - fuse.mergerfs merge: rw\n", "/home/u").length, 1)

    // The row itself: a server mark and a green square, and no menu at defaults, like
    // Dropbox's row, because the tool that made the mount owns it.
    var grow = { label: "gdrive", group: "network", kind: "cloud", uri: "", path: "/home/u/gdrive", mounted: true, glyph: "server" }
    check("a cloud row draws the server mark", grow.glyph, "server")
    check("a cloud row offers no menu row", Mounts.railMenu(grow).length, 0)
    check("and no right-click row either", Mounts.rowMenu(grow).length, 0)
    check("and no eject mark either", Eject.releasable(grow), false)

    // One shared network list: NetFs answers what Rust netfs answers, so the rail and the loop agree.
    check("nfs names network", NetFs.isNetworkFstype("nfs"), true)
    check("nfs4 names network", NetFs.isNetworkFstype("nfs4"), true)
    check("cifs names network", NetFs.isNetworkFstype("cifs"), true)
    check("smb3 names network", NetFs.isNetworkFstype("smb3"), true)
    check("smb2 names network too", NetFs.isNetworkFstype("smb2"), true)
    check("davfs names network", NetFs.isNetworkFstype("davfs"), true)
    check("fuse.sshfs names network", NetFs.isNetworkFstype("fuse.sshfs"), true)
    check("fuse.rclone names network", NetFs.isNetworkFstype("fuse.rclone"), true)
    check("fuse.s3fs names network", NetFs.isNetworkFstype("fuse.s3fs"), true)
    check("fuse.gvfsd-fuse names network for the storage class", NetFs.isNetworkFstype("fuse.gvfsd-fuse"), true)
    check("ext4 stays local", NetFs.isNetworkFstype("ext4"), false)
    check("bare fuse stays local", NetFs.isNetworkFstype("fuse"), false)
    check("fuseblk stays local", NetFs.isNetworkFstype("fuseblk"), false)
    check("the document portal stays local", NetFs.isNetworkFstype("fuse.portal"), false)
    check("a local mergerfs stays local", NetFs.isNetworkFstype("fuse.mergerfs"), false)
    check("gocryptfs stays local", NetFs.isNetworkFstype("fuse.gocryptfs"), false)
    check("protondrive names network again", NetFs.isNetworkFstype("fuse.protondrive"), true)
    check("nfsd stays local", NetFs.isNetworkFstype("nfsd"), false)
    check("a bare sshfs stays local", NetFs.isNetworkFstype("sshfs"), false)
    // Kernel and outside-home FUSE mounts become NETWORK rows without a per-row stat.
    var netBody = "30 1 0:45 / /mnt/nas rw - nfs nas:/share rw\n"
        + "31 1 0:46 / /media/smb rw - cifs //nas/media rw\n"
        + "32 1 0:47 / /mnt/ssh rw - fuse.sshfs user@h:/ rw\n"
        + "33 1 0:48 / /home/u/gdrive rw - fuse.rclone remote: rw\n"
        + "40 1 0:40 / /run/user/1000/gvfs rw - fuse.gvfsd-fuse gvfsd-fuse rw\n"
    var nets = Cloud.parseNetworkMounts(netBody)
    check("kernel nfs, cifs, outside-home sshfs and inside-home rclone become rows", nets.length, 4)
    check("the inside-home rclone is a share row with its fstype",
        nets.some(function (n) { return n.path === "/home/u/gdrive" && n.fstype === "fuse.rclone" }), true)
    check("the gvfs root never becomes a row",
        nets.some(function (n) { return n.path.indexOf("/run/") === 0 }), false)
    // The portal, the bridge, the server proc and a local FUSE mount never become rows.
    var narrowBody = "10 1 0:50 / /run/user/1000/doc rw - fuse.portal portal rw\n"
        + "11 1 0:40 / /run/user/1000/gvfs rw - fuse.gvfsd-fuse gvfsd-fuse rw\n"
        + "12 1 0:51 / /proc/fs/nfsd rw - nfsd nfsd rw\n"
        + "13 1 8:1 / /mnt/merge rw - fuse.mergerfs merge rw\n"
        + "14 1 0:45 / /mnt/nas rw - nfs nas:/share rw\n"
    var narrow = Cloud.parseNetworkMounts(narrowBody)
    check("portal, bridge, nfsd and mergerfs beside one NFS yield exactly it",
        narrow.length === 1 && narrow[0].path === "/mnt/nas", true)
    check("fuse.gvfsd-fuse alone gives no row, gvfs shows those shares itself",
        Cloud.parseNetworkMounts("40 1 0:40 / /run/user/1000/gvfs rw - fuse.gvfsd-fuse gvfsd-fuse rw\n").length, 0)
    check("an in-home protondrive line is one network row",
        Cloud.parseNetworkMounts("31 1 0:27 / /home/u/ProtonDrive rw,nosuid,nodev - fuse.protondrive proton: rw,user_id=1000\n").length, 1)
    check("and never a cloud row",
        Cloud.parseCloudMounts("31 1 0:27 / /home/u/ProtonDrive rw,nosuid,nodev - fuse.protondrive proton: rw,user_id=1000\n", "/home/u").length, 0)
    // Issue #257 round 2: mountinfo rows are the rows and gio only lends names, so what stays here is the mark split the rail draws from the fstype.
    check("cifs draws the eject mark", NetFs.isCifsFstype("cifs"), true)
    check("smb2 draws it too", NetFs.isCifsFstype("smb2"), true)
    check("smb3 draws it too", NetFs.isCifsFstype("smb3"), true)
    check("smbfs draws it too", NetFs.isCifsFstype("smbfs"), true)
    check("the split reads case-insensitively", NetFs.isCifsFstype("CIFS"), true)
    check("nfs keeps its square", NetFs.isCifsFstype("nfs"), false)
    check("nfs4 keeps its square too", NetFs.isCifsFstype("nfs4"), false)
    check("sshfs keeps its square", NetFs.isCifsFstype("fuse.sshfs"), false)
    check("rclone keeps its square", NetFs.isCifsFstype("fuse.rclone"), false)
    check("a local fstype keeps its square", NetFs.isCifsFstype("ext4"), false)
    check("no fstype at all keeps its square", NetFs.isCifsFstype(""), false)
    runCursorFollow(check)
    runSlide(check)
}

// After an unlock the shipped ui/UnlockHost.qml follow puts the cursor on the crypt row, sliced from the file over a stub rail.
function hostRoot() {
    // lsblk names the crypt row /dev/mapper/luks-*, where udisksctl said /dev/dm-0, so the row is found by its mountpoint.
    return { sidebar: { deviceEntries: [{ device: "/dev/sdb1", path: "" },
        { device: "/dev/mapper/luks-a", path: "/run/media/u/Backup" }],
        placesEntries: [0, 1], networkEntries: [0], cursorIndex: 1 }, pendingPath: "" }
}
function hostBody(marker) {
    var src = Source.source("ui/UnlockHost.qml")
    return Source.slice(src, marker, "    Loader {")
}
function followOn(path) {
    var root = hostRoot()
    var body = hostBody("    function followUnlocked(path) {") + hostBody("    function landCursor(stash) {")
    new Function("root", "path", body + "; root.followUnlocked = followUnlocked; root.landCursor = landCursor; followUnlocked(path);")(root, path)
    return root.sidebar.cursorIndex + "|" + root.pendingPath
}
function landOn(path, stash, cursor) {
    var root = hostRoot()
    root.pendingPath = path
    root.sidebar.cursorIndex = cursor
    var body = hostBody("    function landCursor(stash) {")
    new Function("root", "stash", body + "; root.landCursor = landCursor; return landCursor(stash);")(root, stash)
    return root.sidebar.cursorIndex + "|" + root.pendingPath
}

// UL10: the cursor usually sits on the locked row the user activated, so the follow survives the rebuild while it still sits there.
function settleOn(cursor, locked) {
    var root = hostRoot()
    root.pendingPath = "/run/media/u/Backup"
    root.sidebar.cursorIndex = cursor
    root.lockedCursor = locked
    var body = hostBody("    function landCursor(stash) {")
    new Function("root", body + "; root.settleFollow = settleFollow; root.landCursor = landCursor; settleFollow();")(root)
    return root.sidebar.cursorIndex + "|" + root.pendingPath
}
// Sample input: the cursor on rail index 3 with device /dev/sdb1 answers 3 when that is the locked row, else -1.
function cursorOnRow(cursor, device) {
    var root = hostRoot()
    root.sidebar.cursorIndex = cursor
    var body = hostBody("    function cursorOnRow(device) {")
    return new Function("root", "device", body + "; return cursorOnRow(device);")(root, device)
}

function runCursorFollow(check) {
    check("the cursor lands on the unlocked row", followOn("/run/media/u/Backup"), "4|")
    check("a miss stashes for the next rebuild", followOn("/run/media/u/Gone"), "1|/run/media/u/Gone")
    check("a landed rebuild clears the stash", landOn("/run/media/u/Backup", false, -1), "4|")
    check("a missed rebuild without stash clears", landOn("/run/media/u/Gone", false, -1), "-1|")
    check("a cursor still on the locked row follows to the crypt row", settleOn(3, 3), "4|")
    check("a cursor that moved off the locked row drops the follow", settleOn(1, 3), "1|")
    check("no cursor at all still follows", settleOn(-1, -1), "4|")
    check("a cursor on a row that was never the locked one drops the follow", settleOn(3, -1), "3|")
    check("the cursor on the locked row is recorded at its rail index", cursorOnRow(3, "/dev/sdb1"), 3)
    check("the cursor on another device row records nothing", cursorOnRow(4, "/dev/sdb1"), -1)
    check("the cursor on a places row records nothing", cursorOnRow(1, "/dev/sdb1"), -1)
    check("no cursor records nothing", cursorOnRow(-1, "/dev/sdb1"), -1)
    check("opening the dialog records where the cursor sat",
        Source.source("ui/UnlockHost.qml").indexOf("root.lockedCursor = root.cursorOnRow(device)") >= 0, true)
}


// The auto-hidden rail slides on x in the shell's curve and builds once; docked mode keeps its own Loader condition.
function runSlide(check) {
    var rail = Source.source("ui/PaneRail.qml")
    check("the pointer rests 120 ms at the edge before the rail opens", Motion.dwellMs, 120)
    check("the show reads the open duration", rail.indexOf("root.revealed ? Motion.durMs.open : Motion.durMs.close") >= 0, true)
    check("the slide eases on OutCubic", rail.indexOf("easing.type: Easing.OutCubic") >= 0, true)
    check("the slide is off with reduced motion", Source.slice(rail, "Behavior on slide", "NumberAnimation").indexOf("enabled: !Theme.reducedMotion") >= 0, true)
    check("the dwell timer reads the token", Source.slice(rail, "id: dwell", "onTriggered").indexOf("interval: Motion.dwellMs") >= 0, true)
    check("the strip is one row lead-in wide", Source.slice(rail, "id: strip", "enabled:").indexOf("width: Theme.spacing.rowPaddingX") >= 0, true)
    check("the rail moves on x and not on width", Source.slice(rail, "id: rail", "visible:").indexOf("x: root.overlay ? (root.slide - 1) * width : 0") >= 0, true)
    check("visible drops when the hide slide ends", rail.indexOf("visible: !root.held && (!root.overlay || root.slide > 0)") >= 0, true)
    check("an auto-hide Sidebar stays built after its first reveal", rail.indexOf("(root.overlay ? (root.built || root.releaseHold) : (!root.hidden || root.releaseHold))") >= 0, true)
    check("a withdrawn rail reads zero width", rail.indexOf("railWidth: root.hidden ? 0 : rail.width") >= 0, true)
}
