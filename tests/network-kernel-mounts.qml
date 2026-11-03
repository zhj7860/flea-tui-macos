//@ pragma ShellId flea-network-kernel-mounts-test

import QtQuick
import Quickshell
import Quickshell.Io
import "js/Mounts.js" as Mounts
import "js/Eject.js" as Eject

// Issue #257: kernel NFS/CIFS mounts gio lists as file:// become share rows when mountinfo names a network fstype there; fake texts go through the real NetworkMounts.rebuild.
ShellRoot {
    id: root
    property bool finished: false
    property int checks: 0

    function finish(message) {
        if (root.finished)
            return
        root.finished = true
        console.log(message)
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
    function fail(why) { root.finish("NETWORK_KERNEL_MOUNTS FAIL " + why) }
    // Every passed check counts here, so the DONE line reports what ran and the shell compares it.
    function ok(name) {
        root.checks++
        console.log("NETWORK_KERNEL_MOUNTS ok=" + name)
    }
    function eq(name, actual, expected) {
        if (JSON.stringify(actual) !== JSON.stringify(expected))
            root.fail(name + " got " + JSON.stringify(actual) + " want " + JSON.stringify(expected))
        else
            root.ok(name)
    }

    property string gioText: "Drive(0): fixture\n  Type: GProxyDrive (GProxyVolumeMonitorGoa)\n"
        + "Mount(0): photos -> file:///mnt/kmount-photos\n  Type: GDaemonMount\n"
        + "Mount(1): iso-images -> file:///mnt/kmount-iso\n  Type: GDaemonMount\n"
        + "Mount(2): isos on 192.168.1.10 -> smb://192.168.1.10/isos/\n  Type: GDaemonMount\n"
        + "Mount(3): 32GB USB Drive -> file:///run/media/gm/32GB%20USB%20Drive/\n  Type: GDaemonMount\n"
        + "Mount(4): idle-share -> file:///mnt/kmount-idle\n  Type: GDaemonMount\n"
    property string minfo: "30 1 0:45 / /mnt/kmount-photos rw - nfs4 nas:/exports/photos rw\n"
        + "31 1 0:46 / /mnt/kmount-iso rw - cifs //nas/isos rw\n"
        + "32 1 8:2 / /run/media/gm/32GB\\040USB\\040Drive rw - ext4 /dev/sdb1 rw\n"
        + "33 1 0:47 / /mnt/kmount-idle rw - autofs systemd-1 rw\n"
        + "34 1 0:48 / /mnt/kmount-bulk rw - nfs nas:/exports/bulk rw\n"

    // A systemd automount: idle is the autofs line alone, triggered stacks the real fstype on the same mountpoint; tests/network-kernel-mounts.sh traces any syscall naming the idle path.
    property string idleAutomount: "/mnt/flea-idle-automount"
    property string automountLines: "37 1 0:60 / /mnt/flea-live-automount rw - autofs systemd-1 rw,fd=44,pgrp=1,timeout=0,minproto=5,maxproto=5,direct\n"
        + "38 37 0:61 / /mnt/flea-live-automount rw - nfs4 nas:/exports/live rw\n"
        + "39 1 0:62 / " + root.idleAutomount + " rw - autofs systemd-1 rw,fd=45,pgrp=1,timeout=0,minproto=5,maxproto=5,direct\n"

    // The stub gio logs every call and the backend stays null, so a gio or backend call under the mountpoint cannot pass silently.
    NetworkMounts {
        id: network
        onOpened: function (path) {
            if (path !== "/mnt/kmount-iso") {
                root.fail("opened=" + path)
                return
            }
            root.ok("open-direct")
            var at = root.indexOf("file:///mnt/kmount-iso")
            if (at < 0) {
                root.fail("iso row gone before unmount")
                return
            }
            network.unmount(at)
        }
        onMessage: function (text, isError) {
            if (text === "Unmounted iso-images" && !isError) {
                root.ok("unmount")
                var rt = root.indexOf("/mnt/kmount-rclone")
                if (rt < 0) {
                    root.fail("rclone row gone before unmount")
                    return
                }
                network.unmount(rt)
            } else if (text === "Unmounted kmount-rclone" && !isError) {
                root.ok("funmount")
                var hd = root.indexOf(Quickshell.env("HOME") + "/gdrive")
                if (hd < 0) {
                    root.fail("home rclone row gone before unmount")
                    return
                }
                network.unmount(hd)
            } else if (text === "Unmounted gdrive" && !isError) {
                root.ok("funmount-home")
                root.finish("NETWORK_KERNEL_MOUNTS DONE checks=" + root.checks)
            } else if (text !== "") {
                root.fail("message=" + text + " error=" + isError)
            }
        }
    }

    function indexOf(uri) {
        for (var i = 0; i < network.entries.length; i++)
            if (network.entries[i].uri === uri)
                return i
        return -1
    }

    function entryFields(e) {
        return { label: e.label, kind: e.kind, group: e.group, path: e.path, uri: e.uri,
                 fstype: e.fstype, mounted: e.mounted, glyph: e.glyph, editable: e.editable }
    }

    Timer {
        interval: 100
        running: true
        repeat: false
        onTriggered: {
            network._mountListing = root.gioText
            network.bookmarksText = ""
            var home = Quickshell.env("HOME")
            network.rebuild(root.minfo + "35 1 0:50 / " + home + "/gdrive rw - fuse.rclone remote: rw\n"
                + "36 1 0:51 / /mnt/kmount-rclone rw - fuse.rclone remote: rw\n"
                + root.automountLines)
            var entries = network.entries
            root.eq("count", entries.length, 7)
            if (root.finished)
                return
            var share = entries[0]
            var photos = entries[1]
            var iso = entries[2]
            var bulk = entries[3]
            var drive = entries[4]
            var rout = entries[5]
            var shareMenu = Mounts.railMenu(share).filter(function (r) { return !r.separator })
            root.eq("photos", root.entryFields(photos),
                { label: "photos", kind: "share", group: "network", path: "/mnt/kmount-photos",
                  uri: "file:///mnt/kmount-photos", fstype: "nfs4", mounted: true, glyph: "server", editable: false })
            if (root.finished)
                return
            root.eq("iso", root.entryFields(iso),
                { label: "iso-images", kind: "share", group: "network", path: "/mnt/kmount-iso",
                  uri: "file:///mnt/kmount-iso", fstype: "cifs", mounted: true, glyph: "server", editable: false })
            if (root.finished)
                return
            root.eq("gvfs-share-kept", { label: share.label, kind: share.kind, path: share.path, uri: share.uri },
                { label: "isos", kind: "share", path: "", uri: "smb://192.168.1.10/isos/" })
            if (root.finished)
                return
            // FUSE with a network fstype is a share row wherever it is mounted, with the same items, square and path release as every other kernel row.
            var homePath = Quickshell.env("HOME") + "/gdrive"
            root.eq("inhome-share", root.entryFields(drive),
                { label: "gdrive", kind: "share", group: "network", path: homePath,
                  uri: homePath, fstype: "fuse.rclone", mounted: true, glyph: "server", editable: false })
            if (root.finished)
                return
            var driveMenu = Mounts.railMenu(drive).filter(function (r) { return !r.separator })
            root.eq("inhome-menu", driveMenu.map(function (r) { return r.label + ":" + r.action + ":" + r.glyph }),
                shareMenu.slice(0, 2).map(function (r) { return r.label + ":" + r.action + ":" + r.glyph }))
            if (root.finished)
                return
            root.eq("inhome-mark", Eject.releasable(drive), false)
            if (root.finished)
                return
            // FUSE outside home is a share row with the same items and the path release.
            root.eq("outhome", root.entryFields(rout),
                { label: "kmount-rclone", kind: "share", group: "network", path: "/mnt/kmount-rclone",
                  uri: "/mnt/kmount-rclone", fstype: "fuse.rclone", mounted: true, glyph: "server", editable: false })
            if (root.finished)
                return
            // A kernel mount gio never lists still shows a row: the leaf label, the path as its own release argument, and the same Open and Unmount items with no mark.
            root.eq("unlisted", root.entryFields(bulk),
                { label: "kmount-bulk", kind: "share", group: "network", path: "/mnt/kmount-bulk",
                  uri: "/mnt/kmount-bulk", fstype: "nfs", mounted: true, glyph: "server", editable: false })
            if (root.finished)
                return
            // The row items a kernel row draws match the gvfs share row's: the same Open and Unmount items, and the mark split following the fstype instead of the scheme.
            var isoMenu = Mounts.railMenu(iso).filter(function (r) { return !r.separator })
            root.eq("menu", isoMenu.map(function (r) { return r.label + ":" + r.action + ":" + r.glyph }),
                shareMenu.slice(0, 2).map(function (r) { return r.label + ":" + r.action + ":" + r.glyph }))
            if (root.finished)
                return
            root.eq("mark-cifs", Eject.releasable(iso), Eject.releasable({ group: "network", kind: "share", uri: "smb://h/d/", mounted: true }))
            if (root.finished)
                return
            root.eq("mark-nfs", Eject.releasable(photos), false)
            if (root.finished)
                return
            var bulkMenu = Mounts.railMenu(bulk).filter(function (r) { return !r.separator })
            root.eq("unlisted-menu", bulkMenu.map(function (r) { return r.label + ":" + r.action + ":" + r.glyph }),
                shareMenu.slice(0, 2).map(function (r) { return r.label + ":" + r.action + ":" + r.glyph }))
            if (root.finished)
                return
            root.eq("unlisted-mark", Eject.releasable(bulk), false)
            if (root.finished)
                return
            var routMenu = Mounts.railMenu(rout).filter(function (r) { return !r.separator })
            root.eq("outhome-menu", routMenu.map(function (r) { return r.label + ":" + r.action + ":" + r.glyph }),
                shareMenu.slice(0, 2).map(function (r) { return r.label + ":" + r.action + ":" + r.glyph }))
            if (root.finished)
                return
            root.eq("outhome-mark", Eject.releasable(rout), false)
            if (root.finished)
                return
            // An idle automount is an autofs line, not a network fstype: it draws no row, so the rail has nothing to open there.
            root.eq("idle-automount-no-row", entries.filter(function (e) {
                return JSON.stringify(e).indexOf("flea-idle-automount") >= 0 }).length, 0)
            if (root.finished)
                return
            // Once the share is mounted the stacked line wins and the row reads like every other kernel row.
            root.eq("live-automount", root.entryFields(entries[6]),
                { label: "flea-live-automount", kind: "share", group: "network", path: "/mnt/flea-live-automount",
                  uri: "/mnt/flea-live-automount", fstype: "nfs4", mounted: true, glyph: "server", editable: false })
            if (root.finished)
                return
            network.activate(root.indexOf("file:///mnt/kmount-iso"), null)
        }
    }

    Timer {
        interval: 8000
        running: true
        repeat: false
        onTriggered: root.fail("timeout")
    }
}
