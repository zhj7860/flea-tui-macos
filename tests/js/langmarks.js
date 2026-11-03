.import "../../ui/js/LangMarks.js" as LangMarks
.import "../../ui/js/LangMarkPaths.js" as LangMarkPaths

// Original language logos share the file page; unmapped files keep their kind glyph.

function run(check) {
    // Every mapped extension answers its board slug.
    var mapped = {
        ".c": "c", ".h": "c",
        ".cpp": "cplusplus", ".hpp": "cplusplus", ".cc": "cplusplus",
        ".go": "go", ".rs": "rust", ".py": "python",
        ".js": "javascript", ".mjs": "javascript", ".cjs": "javascript",
        ".ts": "typescript", ".tsx": "react", ".jsx": "react",
        ".java": "openjdk", ".kt": "kotlin", ".swift": "swift", ".zig": "zig",
        ".lua": "lua", ".rb": "ruby", ".php": "php", ".pl": "perl",
        ".sh": "gnubash", ".bash": "gnubash", ".zsh": "zsh", ".fish": "fishshell",
        ".nix": "nixos", ".qml": "qt",
        ".html": "html5", ".css": "css", ".scss": "sass", ".vue": "vuedotjs",
        ".md": "markdown", ".markdown": "markdown", ".mkd": "markdown",
        ".json": "json", ".toml": "toml",
        ".yaml": "yaml", ".yml": "yaml",
        ".xml": "xml", ".sql": "sqlite", ".db": "sqlite"
    }
    for (var ext in mapped) {
        check("extension " + ext + " maps to " + mapped[ext],
            LangMarks.slugForFile("main" + ext), mapped[ext])
    }

    // The board's filename rows carry no extension to match on.
    check("Dockerfile maps to docker", LangMarks.slugForFile("Dockerfile"), "docker")
    check("Makefile maps to gnu", LangMarks.slugForFile("Makefile"), "gnu")
    check("CMakeLists.txt maps to cmake", LangMarks.slugForFile("CMakeLists.txt"), "cmake")
    check(".gitignore maps to git", LangMarks.slugForFile(".gitignore"), "git")
    check(".gitattributes maps to git", LangMarks.slugForFile(".gitattributes"), "git")

    // The ambiguous ones: .h is C's (C++ spells .hpp), .ts is TypeScript's (.tsx is React's).
    check(".h stays C beside C++", LangMarks.slugForFile("x.h"), "c")
    check(".ts stays TypeScript beside TSX", LangMarks.slugForFile("x.ts"), "typescript")
    check(".tsx is React, not TypeScript", LangMarks.slugForFile("x.tsx"), "react")
    check(".jsx is React, not JavaScript", LangMarks.slugForFile("x.jsx"), "react")
    check(".mjs is JavaScript", LangMarks.slugForFile("x.mjs"), "javascript")
    check(".yml is YAML", LangMarks.slugForFile("x.yml"), "yaml")

    // Matching is case-insensitive, because the board's rows are lowercase and checkouts are not.
    check("MAIN.RS still maps", LangMarks.slugForFile("MAIN.RS"), "rust")
    check("dockerfile in any case still maps", LangMarks.slugForFile("dockerfile"), "docker")

    // The fallback: no badge rows (.cs .ini .conf .vim .log) and everything else keep the kind glyph.
    var plain = ["constructor", "__proto__", "toString", "x.cs", "x.ini", "x.conf", "x.vim", "x.log", "x.txt", "x.o", "x", ".bashrc", "Makefile.am"]
    for (var i = 0; i < plain.length; i++) {
        check("unmapped " + plain[i] + " falls back to the kind glyph",
            LangMarks.slugForFile(plain[i]), "")
    }

    // A row that is not a file never wears a logo: directories, symlinks and empty rows.
    var LNK = 0o120777
    var REG = 0o100644
    check("a directory named main.py keeps its folder", LangMarks.slugForRow({ n: "main.py", d: true, p: REG }), "")
    check("a symlink named main.py keeps its link mark", LangMarks.slugForRow({ n: "main.py", d: false, p: LNK }), "")
    check("an undefined row answers empty", LangMarks.slugForRow(undefined), "")
    check("a null row answers empty", LangMarks.slugForRow(null), "")
    check("a real code file answers its slug", LangMarks.slugForRow({ n: "main.rs", d: false, p: REG }), "rust")

    // The key list covers every map result and exactly the demand-loaded geometry.
    var expectedKeys = Object.keys(LangMarkPaths.PATHS).sort().join(",")
    check("language keys match the complete SVG key set", LangMarks.KEYS.slice().sort().join(","), expectedKeys)
    check("language keys have no duplicates", LangMarks.KEYS.length, Object.keys(LangMarkPaths.PATHS).length)
    for (var key in LangMarks.FILES) {
        check("named file key " + key + " appears in the language list", LangMarks.KEYS.indexOf(LangMarks.FILES[key]) >= 0, true)
    }
    for (var k = 0; k < LangMarks.KEYS.length; k++) {
        check("baked path data for key " + LangMarks.KEYS[k], LangMarkPaths.pathFor(LangMarks.KEYS[k]).length > 0, true)
    }

    // Every slug the map can produce resolves to real baked path data, or the row draws nothing.
    for (var e in mapped) {
        var slug = mapped[e]
        check("extension key " + e + " appears in the language list", LangMarks.KEYS.indexOf(slug) >= 0, true)
        check("baked path data for " + slug, LangMarkPaths.pathFor(slug).length > 0, true)
    }
    check("an unknown slug answers empty, never a logo", LangMarkPaths.pathFor("no-such-lang"), "")
}
