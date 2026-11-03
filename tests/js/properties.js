.import "sourcefixture.js" as Source
.import "../../ui/js/Format.js" as Format

function run(check) {
    // Properties pairs come from the dialog's own Repeater model, so the Tags pair is proven where it is built.
    var dialogSource = Source.source("ui/MenuActionDialog.qml")
    var modelSlice = Source.slice(dialogSource, "model: root.action", "Column {")
    var pairsOf = eval("(function(root, Format) { return (" + modelSlice.replace(/^model:\s*/, "").replace(/\s+$/, "") + "); })")
    function propertiesFacts(tags) {
        return {action: "properties", facts: {ok: true, path: "/fixture/note.txt", kind: "File", bytes: 13,
            modified: 1758835200, mode: "0644", owner: "gm", uid: 1000, gid: 1000, tags: tags}}
    }
    function tagPairs(pairs) {
        return pairs.filter(function (pair) { return pair[0] === "Tags" })
    }
    var untagged = pairsOf(propertiesFacts([]), Format)
    check("an untagged item shows no Tags pair", tagPairs(untagged).length, 0)
    check("an untagged item shows no None label", JSON.stringify(untagged).indexOf("None"), -1)
    var tagged = pairsOf(propertiesFacts(["Red", "Blue"]), Format)
    check("a tagged item shows one Tags pair", tagPairs(tagged).length, 1)
    check("the Tags pair holds both tags", tagPairs(tagged)[0][1], "Red, Blue")
    // A facts reply without a tags key reads as untagged instead of throwing.
    var noKey = propertiesFacts([])
    delete noKey.facts.tags
    check("a reply with no tags key shows no Tags pair", tagPairs(pairsOf(noKey, Format)).length, 0)
    // The Link target pair stays outside the Tags branch, for a tagged and an untagged link alike.
    function linkFacts(tags) {
        var facts = propertiesFacts(tags)
        facts.facts.symlink = true
        facts.facts.target = "/fixture/real.txt"
        return facts
    }
    function names(pairs) {
        return pairs.map(function (pair) { return pair[0] }).join(",")
    }
    var untaggedLink = pairsOf(linkFacts([]), Format)
    check("an untagged link ends with its Link target", JSON.stringify(untaggedLink[untaggedLink.length - 1]),
        JSON.stringify(["Link target", "/fixture/real.txt"]))
    var taggedLink = pairsOf(linkFacts(["Red"]), Format)
    check("a tagged link ends with Link target and draws Tags after Size", names(taggedLink.slice(-2)) + "|" + names(taggedLink.slice(2, 4)), "Group,Link target|Size,Tags")
    // The board's Tagged file draws Tags right after Size, and after Contains for a folder.
    check("a tagged file orders its pairs as the board does", names(tagged), "Path,Type,Size,Tags,Modified,Permissions,Owner,Group")
    var folderFacts = propertiesFacts(["Red"])
    folderFacts.facts.directory = true
    check("a tagged folder puts Tags after Contains", names(pairsOf(folderFacts, Format)), "Path,Type,Size,Contains,Tags,Modified,Permissions,Owner,Group")
    // The video and photo pairs sit between Size and Modified, as the board draws them; a card with none is unchanged.
    function withExtra(extraPairs) {
        var reply = propertiesFacts([])
        reply.extraPairs = extraPairs
        return reply
    }
    check("a card with no extra pairs reads as before", names(pairsOf(withExtra(undefined), Format)), "Path,Type,Size,Modified,Permissions,Owner,Group")
    check("the video pairs land between Size and Modified", names(pairsOf(withExtra([["Codecs", "H.264 · AAC"], ["Bit rate", "8.1 Mb/s"]]), Format)),
        "Path,Type,Size,Codecs,Bit rate,Modified,Permissions,Owner,Group")
    check("the photo pairs land between Size and Modified", names(pairsOf(withExtra([["Camera", "x"], ["Lens", "y"], ["Exposure", "z"], ["Taken", "t"]]), Format)),
        "Path,Type,Size,Camera,Lens,Exposure,Taken,Modified,Permissions,Owner,Group")
    // Tags follow the extra pairs and come before Modified, so a card with both keeps the board's order.
    var taggedVideo = withExtra([["Codecs", "H.264 · AAC"], ["Bit rate", "8.1 Mb/s"]])
    taggedVideo.facts.tags = ["Red"]
    check("a tagged card puts Tags after the extra pairs", names(pairsOf(taggedVideo, Format)),
        "Path,Type,Size,Codecs,Bit rate,Tags,Modified,Permissions,Owner,Group")
}
