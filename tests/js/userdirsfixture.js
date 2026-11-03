// Each value is the literal shell double-quoted text stored in user-dirs.dirs.
var cases = [
    ["escaped quote", '"$HOME/Photo\\"Inbox"', '/home/test/Photo"Inbox'],
    ["escaped backslash", '"$HOME/Photo\\\\Inbox"', '/home/test/Photo\\Inbox'],
    ["escaped dollar", '"$HOME/Photo\\$HOME"', '/home/test/Photo$HOME'],
    ["escaped leading dollar", '"/media/\\$HOME/Inbox"', '/media/$HOME/Inbox'],
    ["escaped backquote", '"$HOME/Photo\\`Inbox"', '/home/test/Photo`Inbox'],
    ["leading HOME token", '"$HOME/Inbox"', '/home/test/Inbox'],
    ["absolute path", '"/media/Inbox"', '/media/Inbox'],
    ["surrounding whitespace", '  "$HOME/Inbox"  ', '/home/test/Inbox'],
    ["trailing comment", '"$HOME/Inbox" # local inbox', '/home/test/Inbox'],
    ["trailing spaces then comment", '"$HOME/Inbox"   # local inbox', '/home/test/Inbox'],
    ["trailing quoted comment", '"$HOME/Inbox" # "local inbox"', '/home/test/Inbox'],
    ["literal dollar mid-path", '"$HOME/Inbox$local"', '/home/test/Inbox$local'],
    ["multiple trailing slashes", '"$HOME/Inbox///" # local inbox', '/home/test/Inbox'],
    ["unterminated value", '"$HOME/Inbox', null],
    ["dangling escape", '"$HOME/Inbox\\', null],
    ["concatenated quotes", '"$HOME/Photo"Inbox"', '/home/test/Photo'],
    ["trailing content", '"$HOME/Inbox"junk', '/home/test/Inbox'],
    ["backslash makes any next character literal", '"$HOME/Photo\\q"', '/home/test/Photoq'],
    ["unescaped dollar", '"$HOME/Photo$HOME"', '/home/test/Photo$HOME'],
    ["unescaped backquote", '"$HOME/Photo`Inbox"', '/home/test/Photo`Inbox'],
    ["HOME is literal after an absolute prefix", '"/media/$HOME/Inbox"', '/media/$HOME/Inbox'],
    ["HOME token has a suffix", '"$HOMEwork/Inbox"', null],
    ["relative path", '"Inbox"', null],
    ["escaped absolute prefix is relative", '"\\/media/Inbox"', null],
    ["escaped HOME prefix is relative", '"\\$HOME/Inbox"', null],
    ["single-quoted value", "'$HOME/Inbox'", null],
    ["unquoted value", '$HOME/Inbox', null]
]

function body(value) {
    return 'XDG_DOWNLOAD_DIR=' + value + '\nXDG_PICTURES_DIR="$HOME"\nXDG_VIDEOS_DIR="$HOME"'
}

function duplicateRoles(check, newestPaths, userDirs) {
    for (var i = 0; i < cases.length; i++) {
        var sample = cases[i]
        var text = body('"$HOME/Original"') + '\nXDG_DOWNLOAD_DIR=' + sample[1]
        var expected = [sample[2] === null ? "/home/test/Original" : sample[2]]
        check("duplicate role defaults: " + sample[0], JSON.stringify(newestPaths(text, "/home/test")), JSON.stringify(expected))
        check("duplicate role rail: " + sample[0],
              JSON.stringify(userDirs(text, "/home/test").map(function (entry) { return entry.path })), JSON.stringify(expected))
    }
    var bodies = [
        ['XDG_DOWNLOAD_DIR="relative"\nXDG_PICTURES_DIR="$HOME/Photos"\nXDG_DOWNLOAD_DIR="$HOME/Inbox"\nXDG_VIDEOS_DIR="$HOME"',
         ["/home/test/Inbox", "/home/test/Photos"]],
        [body('"$HOME/Original"') + '\nXDG_DOWNLOAD_DIR="$HOME"\nXDG_DOWNLOAD_DIR="relative"', []],
        [body('"$HOME"') + '\nXDG_DOWNLOAD_DIR="$HOME/Inbox"\nXDG_DOWNLOAD_DIR="$HOME/Unterminated', ["/home/test/Inbox"]],
        ['XDG_PICTURES_DIR="$HOME/Old Photos"\nXDG_DOWNLOAD_DIR="$HOME/Inbox"\nXDG_PICTURES_DIR="$HOME/Photos"\nXDG_VIDEOS_DIR="$HOME"',
         ["/home/test/Photos", "/home/test/Inbox"]]
    ]
    for (var j = 0; j < bodies.length; j++) {
        var rail = userDirs(bodies[j][0], "/home/test")
        check("duplicate role rail order " + j, JSON.stringify(rail.map(function (entry) { return entry.path })), JSON.stringify(bodies[j][1]))
        check("duplicate role final labels " + j, rail.map(function (entry) { return entry.label }).join("|"),
              bodies[j][1].map(function (path) { return path.substring(path.lastIndexOf("/") + 1) }).join("|"))
        check("duplicate role rail and defaults agree " + j,
              JSON.stringify(newestPaths(bodies[j][0], "/home/test").sort()), JSON.stringify(bodies[j][1].slice().sort()))
    }
}
