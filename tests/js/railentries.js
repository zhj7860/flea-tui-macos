.import "../../ui/js/Devices.js" as Devices
.import "../../ui/js/Menu.js" as Menu
.import "../../ui/js/Mounts.js" as Mounts
.import "sourcefixture.js" as Source

// What ui/DeviceMounts.qml writes reaches the rail and its menu, every field compared by Mounts.sameEntries; the lsblk write-protect flag keeps Flash image off the row.

// An SD reader with one mounted card; ro is "true", "false", or "" for a listing that carries no RO column.
function stickRow(name, label, ro) {
    var flag = ro === "" ? "" : '"ro":' + ro + ','
    return '{"name":"' + name + '","path":"/dev/' + name + '","label":null,"mountpoints":[null],"rm":true,' + flag + '"size":8000000000,"type":"disk","model":"SD Reader",'
        + '"children":[{"name":"' + name + '1","path":"/dev/' + name + '1","label":"' + label + '","mountpoints":["/run/media/gm/' + label + '"],"rm":true,' + flag
        + '"size":8000000000,"type":"part","model":null,"fstype":"vfat","parttype":"0xb","pttype":"dos","partn":1,"uuid":"A1B2-' + name + '"}]}'
}

function listing(rows) {
    return '{"blockdevices":[' + rows.join(",") + ']}'
}

function run(check) {
    // A poll that changes only one field the builder writes must not compare equal, or the rail keeps the old value.
    var luks = { path: "/run/media/gm/vault", label: "vault", group: "device", kind: "volume", device: "/dev/sdb1", mounted: true, glyph: "drive",
                 fstype: "crypto_LUKS", fsver: "1", locked: true, removable: true, mediaRemovable: true, readOnly: false }
    check("an identical locked row compares equal", Mounts.sameEntries([luks], [Object.assign({}, luks)]), true)
    check("a container converted from LUKS1 to LUKS2 reaches the live rail", Mounts.sameEntries([luks], [Object.assign({}, luks, { fsver: "2" })]), false)
    check("a media-removable flip reaches the live rail", Mounts.sameEntries([luks], [Object.assign({}, luks, { mediaRemovable: false })]), false)
    check("a write-protect flip reaches the live rail", Mounts.sameEntries([luks], [Object.assign({}, luks, { readOnly: true })]), false)

    // The lsblk row, the builder and the menu in a line: a write-protected card never offers Flash image.
    var both = listing([stickRow("sdb", "LOCKED", "true"), stickRow("sdc", "OPEN", "false")])
    var parsed = Devices.parseDevices(both)
    check("lsblk's RO column reaches the volume row", parsed.map(function (r) { return r.label + "=" + r.readOnly }).join(","), "LOCKED=true,OPEN=false")
    check("a listing with no RO column reads every volume writable",
          Devices.parseDevices(listing([stickRow("sdb", "BARE", "")])).map(function (r) { return r.readOnly }).join(","), "false")
    var rail = { _listing: both, showUnmounted: false, entries: [],
                 hostLabel: function (fallback) { return fallback }, openWhenMounted: function () {} }
    new Function("root", "Devices", "Mounts", Source.slice(Source.source("ui/DeviceMounts.qml"), "    function rebuild() {", "    // gio returns before") + "; rebuild()")(rail, Devices, Mounts)
    function menuOf(label) {
        return Menu.railEntries(rail.entries.filter(function (r) { return r.label === label })[0]).filter(function (r) { return !r.separator }).map(function (r) { return r.label }).join("|")
    }
    check("a write-protected stick through the rail never offers Flash image", menuOf("LOCKED"), "Open|Unmount|Eject")
    check("and its writable twin through the same rail still does", menuOf("OPEN"), "Open|Unmount|Eject|Flash image")
    check("the rail's lsblk asks for the RO column, or every volume reads writable", Source.source("ui/DeviceMounts.qml").indexOf("MOUNTPOINTS,RM,RO,TRAN,") >= 0, true)
    var lsblk = Source.source("ui/DeviceMounts.qml")
    check("the lsblk comment says why PARTTYPE, PTTYPE, PARTN and UUID are fetched, in whole lines",
        lsblk.indexOf("a firmware type, an installer ISO keep, a recovery label, the dedupe key); FSVER beside FSTYPE") >= 0
        && lsblk.indexOf("a firmware type, an\n") < 0, true)
}
