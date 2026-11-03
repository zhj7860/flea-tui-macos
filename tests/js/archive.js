.import "../../ui/js/Archive.js" as Archive
.import "../../ui/js/ArchiveCard.js" as ArchiveCard
.import "../../ui/js/Convert.js" as Convert
.import "../../ui/js/Messages.js" as Messages

function run(check) {
    check("the longest extension is matched first, so tar.gz is not read as gz",
          Archive.isArchive("backup.tar.gz") + "|" + Archive.extractDir("backup.tar.gz"),
          "true|backup")
    check("every form the table names is an archive",
          [".zip", ".7z", ".tgz", ".tar", ".tar.xz", ".tar.zst", ".tar.bz2"].map(function (e) {
              return Archive.isArchive("x" + e)
          }).join(","),
          "true,true,true,true,true,true,true")
    // Flea reads rar and writes none: the row offers Extract, and src/backend/archive.rs never puts
    // rar in the compress submenu because nothing in the Arch repositories writes one.
    check("a rar is an archive, whatever case it is spelled in",
          Archive.isArchive("holiday.rar") + "|" + Archive.isArchive("HOLIDAY.RAR"), "true|true")
    check("and an extract unpacks it under its own name", Archive.extractDir("holiday.rar"), "holiday")
    check("and nothing else is",
          Archive.isArchive("notes.txt") + "|" + Archive.isArchive("x.zipper") + "|" + Archive.isArchive("zip"),
          "false|false|false")
    check("an extract unpacks into the archive's own name with the extension taken off",
          Archive.extractDir("photos.zip") + "|" + Archive.extractDir("backup.tar.zst"),
          "photos|backup")
    check("a name with no archive extension is its own directory name",
          Archive.extractDir("plain"), "plain")

    // #165: Extract is per extension class; ui/Pane.qml feeds these bits from the formats line.
    var both = {archive: true, sevenZip: true, zip: true}
    var seven_only = {archive: false, sevenZip: true, zip: true}
    var tar_only = {archive: true, sevenZip: false, zip: true}
    var neither = {archive: false, sevenZip: false, zip: false}
    check("a box with both tools reads every class", [".zip", ".7z", ".tar.gz", ".rar", ".tgz"].map(function (e) {
        return Archive.canExtract("x" + e, both)
    }).join(","), "true,true,true,true,true")
    check("a box with only 7z reads its own class and the zip class, and no tar",
          Archive.canExtract("x.zip", seven_only) + "|" + Archive.canExtract("x.rar", seven_only)
          + "|" + Archive.canExtract("x.tar.zst", seven_only), "true|true|false")
    check("a box with only bsdtar reads everything but the 7z class",
          Archive.canExtract("x.zip", tar_only) + "|" + Archive.canExtract("x.7z", tar_only), "true|false")
    check("a box with neither reads nothing",
          Archive.canExtract("x.zip", neither) + "|" + Archive.canExtract("x.tar", neither), "false|false")
    check("a missing capability object is not a capability", Archive.canExtract("x.zip", undefined), false)
    check("the zip capability accepts the exact .zip boundary", Archive.canExtract(".zip", {zip: true}), true)
    check("the zip capability accepts the exact .rar boundary", Archive.canExtract(".rar", {zip: true}), true)
    check("the 7z capability accepts the exact .7z boundary", Archive.canExtract(".7z", {sevenZip: true}), true)
    check("the disabled row's reason names the missing program",
          Archive.extractHint(["7z"]) + "|" + Archive.extractHint(["zip", "tar", "tar.gz"]) + "|" + Archive.extractHint([]),
          "bsdtar is not installed|7-Zip is not installed|No archive tool is installed")

    var transferCalls = []
    var messageRoot = {transferStarted: function (id, n, moving, extract) {
        transferCalls.push([id, n, moving, extract].join("|"))
    }}
    Messages.route(messageRoot, {t: "transferstarted", id: 4, n: 2, moving: true})
    check("ordinary transferstarted keeps its three-field schema", transferCalls.join(","), "4|2|true|false")
    transferCalls = []
    Messages.route(messageRoot, {t: "extractstarted", id: 5})
    check("the new extract start reaches the existing card as an extract", transferCalls.join(","), "5|1|false|true")

    check("one row compresses under its own name",
          Archive.archiveStem(["notes.txt"], "claude"), "notes")
    check("several compress under the directory holding them",
          Archive.archiveStem(["a.txt", "b.txt"], "claude"), "claude")
    check("and with no directory name to use, under a plain one",
          Archive.archiveStem(["a.txt", "b.txt"], ""), "archive")

    // The submenu is exactly what the backend probed, so a box with no 7zip never offers .7z.
    check("the submenu is the probed table and never a fixed list",
          Archive.formatEntries(["zip", "tar.zst"]).map(function (e) { return e.id + "=" + e.label }).join("|"),
          "zip=.zip|tar.zst=.tar.zst")
    check("each leaf carries the sheet's own wording beside the flyout's",
          Archive.formatEntries(["zip", "tar.zst"]).map(function (e) { return e.sheetLabel }).join("|"),
          "Compress to .zip|Compress to .tar.zst")
    check("each format row draws the board's file mark, never the flyout's archive box",
          Archive.formatEntries(["zip", "7z"]).map(function (e) { return e.glyph }).join("|"), "file|file")
    check("an empty table offers nothing at all",
          Archive.formatEntries([]).length, 0)

    // Convert never writes over the file it was given, whichever of the two words it uses.
    check("a different format is a conversion and the name says so",
          Convert.destName("shot.png", "jpg"), "shot (converted).jpg")
    check("the same format is a strip and the name says that instead",
          Convert.destName("shot.png", "png"), "shot (stripped).png")
    check("a leading dot on the format is accepted",
          Convert.destName("shot.png", ".webp"), "shot (converted).webp")
    check("case does not decide which of the two words it is",
          Convert.destName("shot.PNG", "png"), "shot (stripped).png")
    check("a name with no extension still converts",
          Convert.destName("shot", "jpg"), "shot (converted).jpg")
    check("the format that starts picked is never the one the file already is",
          Convert.defaultFormat("shot.jpg") + "|" + Convert.defaultFormat("shot.png"),
          "png|jpg")
    var source = {path: "/pictures/album.with.dots/photo.png", name: "photo.png", menuId: 17}
    check("the output keeps the captured full source directory",
          Convert.destination(source, "jpg"), "/pictures/album.with.dots/photo (converted).jpg")
    check("a root source has one output separator",
          Convert.destination({path: "/photo.png", name: "photo.png"}, "webp"), "/photo (converted).webp")
    check("an attributed reply matches the captured source",
          Convert.matchesReply(source, 5, {requestId: 5, source: source.path}), true)
    check("an older format probe cannot replace the current result",
          Convert.matchesReply(source, 6, {requestId: 5, source: source.path}), false)
    check("another source cannot complete this dialog even with the same request id",
          Convert.matchesReply(source, 5, {requestId: 5, source: "/elsewhere/photo.png"}), false)

    // Archives040: the listing and extraction widen past zip/tar/7z/rar, through 7z alone.
    check("a deb, rpm, apk, jar, cab, cpio, appimage and iso are archives too",
          [".deb", ".rpm", ".apk", ".jar", ".cab", ".cpio", ".AppImage", ".iso"].map(function (e) {
              return Archive.isArchive("x" + e)
          }).join(","),
          "true,true,true,true,true,true,true,true")
    check("and an extract unpacks a package under its own name",
          Archive.extractDir("driver.deb") + "|" + Archive.extractDir("debian-13.iso"),
          "driver|debian-13")
    check("a disk image lists only, so it offers no extract",
          Archive.canExtract("debian-13.iso", both) + "|" + Archive.canExtract("debian-13.ISO", both),
          "false|false")
    check("while every package extracts through 7z alone",
          [".deb", ".rpm", ".apk", ".jar", ".cab", ".cpio", ".AppImage"].map(function (e) {
              return Archive.canExtract("x" + e, both)
          }).join(","),
          "true,true,true,true,true,true,true")
    check("and a box without 7z reads none of the widened formats",
          Archive.canExtract("x.deb", tar_only) + "|" + Archive.canExtract("x.iso", tar_only),
          "false|false")

    // Archives040: the compress submenu gains "With password…" after a separator, hidden with no 7z.
    check("the password row is hidden where 7z is missing",
          Archive.passwordEntry([]).length, 0)
    check("and it names the key mark where 7z is installed",
          Archive.passwordEntry(["7z"]).map(function (e) {
              return (e.separator === true ? "sep" : e.id + "=" + e.label + "=" + e.glyph)
          }).join("|"),
          "sep|compressPassword=With password…=key")

    // Archives040: the wrong-password and encrypted markers are backend codes, never sentences.
    check("a wrong password is told from any other failure",
          Archive.wrongPassword("wrong-password") + "|"
          + Archive.wrongPassword("the archive tool failed"),
          "true|false")
    check("and its sentence is one template filled once",
          ArchiveCard.wrongPasswordSentence("backup.7z"),
          "That password did not open backup.7z.")
    check("an encrypted archive asks for its password",
          Archive.needsPassword("encrypted") + "|" + Archive.needsPassword("the archive tool wrote nothing"),
          "true|false")
}
