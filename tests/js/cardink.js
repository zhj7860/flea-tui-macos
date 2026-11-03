.import "sourcefixture.js" as Source

// Decided FIELDS-01: card and footer error text and marks draw errorOnSurface; a bare error ink stays only in a border.color frame, its owner being the last property that starts a statement before it.
// Sample input: inkOwners(["Text { color: Theme.color.error }"]) answers ["color"].
function inkOwners(lines) {
    var owners = [], start = /(?:^|[{;])\s*(?:readonly\s+)?(?:property\s+[\w.<>]+\s+)?([\w.]+)\s*:(?!:)/g
    function lastOwner(text) {
        var name = null, m
        start.lastIndex = 0
        while ((m = start.exec(text)) !== null)
            name = m[1]
        return name
    }
    lines.forEach(function (line, i) {
        var ink = /Theme\.color\.error\b(?!OnSurface)/g, m
        while ((m = ink.exec(line)) !== null) {
            // A return or a brace with no owner first is a function body or an object edge, so the ink has no frame to belong to.
            var before = line.slice(0, m.index), owner = lastOwner(before), k = i
            while (owner === null && !/\breturn\b|[{}]/.test(before) && k > 0) {
                before = lines[--k]
                owner = lastOwner(before)
            }
            owners.push(owner)
        }
    })
    return owners
}

function run(check) {
    check("an inline object's error ink belongs to its own property", inkOwners(["Text { color: Theme.color.error }"]).join("|"), "color")
    check("a declared property's error ink belongs to that property", inkOwners(["    property color ink: Theme.color.error"]).join("|"), "ink")
    check("a returned error ink has no owner", String(inkOwners(["    border.color: x", "    function f() {", "        return Theme.color.error"])[0]), "null")
    check("a wrapped ternary's error ink belongs to the frame above it", inkOwners(["    border.color: bad", "        ? Theme.color.error : Theme.color.border"]).join("|"), "border.color")
    check("properties joined by a semicolon each own their own ink", inkOwners(["    border.color: x; color: Theme.color.error"]).join("|"), "color")
    check("a ternary's second branch keeps its statement's owner", inkOwners(["    color: a ? Theme.color.foreground : Theme.color.error"]).join("|"), "color")
    var errorCards = ["ui/BulkRenameDialog.qml", "ui/UnlockDialog.qml", "ui/PermissionsDialog.qml", "ui/OpenWithDialog.qml", "ui/MenuActionDialog.qml", "ui/NetworkDialog.qml",
                      "ui/ArchiveCompressDialog.qml", "ui/ArchivePasswordDialog.qml", "ui/ConvertDialog.qml", "ui/PickerSave.qml", "ui/PickerWindow.qml"]
    errorCards.forEach(function (file) {
        var bare = inkOwners(Source.source(file).split("\n")).filter(function (owner) { return owner !== "border.color" }).length
        check(file + " draws no card error ink on the window error role", bare, 0)
    })
}
