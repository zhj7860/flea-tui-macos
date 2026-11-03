.import "../../ui/js/BulkRename.js" as BulkRename
.import "sourcefixture.js" as Source

// Bulk rename card decisions, each line's reason checked against a forward-scan oracle.
function oracleReasonFor(name, index, allNew) {
    var text = String(name)
    if (text.length === 0) return "empty"
    if (text.indexOf("/") >= 0) return "contains /"
    if (text === "." || text === ".." || text.indexOf("\u0000") >= 0 || text.indexOf("\r") >= 0 || text.indexOf("\n") >= 0) return "invalid"
    if (unescape(encodeURIComponent(text)).length > 255) return "too long"
    for (var j = index + 1; j < allNew.length; j++) {
        if (String(allNew[j]) === text) return "same as line " + (j + 1)
    }
    return ""
}
function oracleCounts(oldNames, newNames) {
    var renamed = 0, unchanged = 0, invalid = 0
    for (var i = 0; i < newNames.length; i++) {
        if (oracleReasonFor(newNames[i], i, newNames) !== "") invalid += 1
        else if (String(newNames[i]) === String(oldNames[i])) unchanged += 1
        else renamed += 1
    }
    return { renamed: renamed, unchanged: unchanged, invalid: invalid }
}
function sameReasons(a, b) {
    if (a.length !== b.length) return false
    for (var i = 0; i < a.length; i++) if (a[i] !== b[i]) return false
    return true
}
function checkCase(check, label, oldNames, newNames) {
    var want = []
    for (var i = 0; i < newNames.length; i++) want.push(oracleReasonFor(newNames[i], i, newNames))
    var got = BulkRename.reasons(newNames)
    check(label + " reasons match the forward scan", sameReasons(got, want), true)
    var wc = oracleCounts(oldNames, newNames)
    var gc = BulkRename.counts(oldNames, newNames, got)
    check(label + " counts triple matches", JSON.stringify(gc), JSON.stringify(wc))
}
function lcg(seed) {
    var s = seed
    return function () { s = (s * 1103515245 + 12345) & 0x7fffffff; return s / 0x7fffffff }
}
// This engine refuses a patched builtin and a replaced global Map, so the pass is rebuilt from the file's text with a counting Map in scope.
function countedReasons(counter) {
    class CountingMap extends Map {
        has(k) { counter.ops += 1; return super.has(k) }
        get(k) { counter.ops += 1; return super.get(k) }
        set(k, v) { counter.ops += 1; return super.set(k, v) }
    }
    var text = Source.slice(Source.source("ui/js/BulkRename.js"), "function reasons(", "// Counts split")
    var scope = new Function("Map", "WORDS", "utf8Bytes", "NAME_BYTES", "return " + text)
    return scope(CountingMap, BulkRename.WORDS, BulkRename.utf8Bytes, BulkRename.NAME_BYTES)
}

function run(check) {
    check("find replaces every hit",
        BulkRename.applyFindReplace(["IMG_1.HEIC", "notes.txt"], "IMG_", "trip-").join(","),
        "trip-1.HEIC,notes.txt")
    check("empty find leaves names alone",
        BulkRename.applyFindReplace(["a.txt"], "", "x").join(","), "a.txt")
    check("duplicate names name the other line",
        BulkRename.reasons(["trip-4121.MOV", "trip-4121.MOV"])[0], "same as line 2")
    check("a slash is refused with the board reason",
        BulkRename.reasons(["a", "b", "c", "trip/4123.HEIC"])[3], "contains /")
    check("an empty name is refused",
        BulkRename.reasons(["", "b"])[0], "empty")
    check("an unchanged name carries no reason",
        BulkRename.reasons(["IMG_4120.HEIC", "x"])[0], "")
    check("footer names renamed and unchanged",
        BulkRename.footer(5, 1, 0), "5 renamed \u00b7 1 unchanged")
    check("footer names invalid too",
        BulkRename.footer(3, 1, 2), "3 renamed \u00b7 1 unchanged \u00b7 2 invalid")
    check("the card title carries the count",
        BulkRename.title(6), "Rename 6 items")
    check("counts split renamed, unchanged and invalid",
        JSON.stringify(BulkRename.counts(["a", "b", "c"], ["a", "b2", "b2"], BulkRename.reasons(["a", "b2", "b2"]))),
        JSON.stringify({renamed: 1, unchanged: 1, invalid: 1}))
    check("a short newNames reads empty, never undefined",
        BulkRename.nameAt(["a"], 0) + "|" + BulkRename.nameAt(["a"], 1), "a|")
    check("the Tab order walks Find Replace lines buttons",
        BulkRename.focusStops(2).join(","), "find,replace,line 1,line 2,edit,cancel,rename")
    check("Tab from Replace enters the first name line",
        BulkRename.nextStop("replace", false, 2), "line 1")
    check("Tab from the last line reaches Edit in terminal",
        BulkRename.nextStop("line 2", false, 2), "edit")
    check("Shift+Tab from the first line returns to Replace",
        BulkRename.nextStop("line 1", true, 2), "replace")
    check("Tab wraps from Rename to Find",
        BulkRename.nextStop("rename", false, 2), "find")
    checkCase(check, "two invalid lines", ["a", "b", "c", "d"], ["x", "x", "y/z", "d"])
    checkCase(check, "three-way duplicates", ["o1", "o2", "o3"], ["a", "a", "a"])
    checkCase(check, "a swap names no duplicate", ["a.txt", "b.txt"], ["b.txt", "a.txt"])
    checkCase(check, "empty names", ["a", "b"], ["", "b"])
    checkCase(check, "slash names", ["a", "b"], ["a/b", "b"])
    checkCase(check, "dot names", ["a", "b"], [".", "b"])
    checkCase(check, "dotdot names", ["a", "b"], ["..", "b"])
    checkCase(check, "nul names", ["a", "b"], ["a\u0000b", "b"])
    checkCase(check, "cr names", ["a", "b"], ["a\rb", "b"])
    checkCase(check, "lf names", ["a", "b"], ["a\nb", "b"])
    check("a name over 255 bytes is refused",
        BulkRename.reasons(["a".repeat(256), "b"])[0], "too long")
    check("a name of 255 bytes is not",
        BulkRename.reasons(["a".repeat(255), "b"])[0], "")
    check("the limit counts UTF-8 bytes, not characters",
        BulkRename.reasons(["\u00e9".repeat(128), "\u00e9".repeat(127) + "a"]).join("|"), "too long|")
    check("a surrogate pair counts four bytes",
        BulkRename.reasons(["\ud83d\ude00".repeat(64), "\ud83d\ude00".repeat(63) + "abc"]).join("|"), "too long|")
    checkCase(check, "long names", ["a", "b", "c"], ["x".repeat(300), "\u4e2d".repeat(86), "\u4e2d".repeat(85)])
    var next = lcg(12345)
    var pool = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "a/b", "", ".", ".."]
    var oldBig = []
    var newBig = []
    for (var i = 0; i < 2000; i++) {
        oldBig.push("old" + ("0000" + i).slice(-4) + ".txt")
        newBig.push(pool[Math.floor(next() * pool.length)] + (next() < 0.3 ? next().toFixed(0) : ""))
    }
    var wantBig = []
    for (var k = 0; k < newBig.length; k++) wantBig.push(oracleReasonFor(newBig[k], k, newBig))
    var gotBig = BulkRename.reasons(newBig)
    check("seeded 2000 names match the forward scan", sameReasons(gotBig, wantBig), true)
    var wcBig = oracleCounts(oldBig, newBig)
    var gcBig = BulkRename.counts(oldBig, newBig, gotBig)
    check("seeded 2000 counts triple matches", JSON.stringify(gcBig), JSON.stringify(wcBig))
    var counter = { ops: 0 }
    var rebuilt = countedReasons(counter)(newBig)
    check("the counted copy answers what the real pass answers", sameReasons(rebuilt, gotBig), true)
    check("one pass makes one to four map ops per name", counter.ops >= newBig.length && counter.ops <= 4 * newBig.length, true)
    // A name read twice is a second pass over the input, which the map count cannot see.
    var reads = 0
    var counting = newBig.map(function (s) { return { toString: function () { reads += 1; return s } } })
    check("the counting names give the same reasons", sameReasons(BulkRename.reasons(counting), wantBig), true)
    check("one pass reads each name once", reads, newBig.length)
    check("the dialog's column gap stays the literal 14, not a text size scaled token",
        Source.source("ui/BulkRenameDialog.qml").indexOf("readonly property int columnGap: 14\n") >= 0, true)
}
