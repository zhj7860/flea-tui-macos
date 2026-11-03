.pragma library

.import "Format.js" as Format

// Logos are simple-icons geometry (CC0 1.0), trademarks of their owners; see README.

// Sample input: "main.rs" -> "rust", "Dockerfile" -> "docker", "notes.txt" -> "".
var EXTS = {
    ".c": "c", ".h": "c",
    ".cpp": "cplusplus", ".hpp": "cplusplus", ".cc": "cplusplus",
    ".go": "go",
    ".rs": "rust",
    ".py": "python",
    ".js": "javascript", ".mjs": "javascript", ".cjs": "javascript",
    ".ts": "typescript",
    ".tsx": "react", ".jsx": "react",
    ".java": "openjdk",
    ".kt": "kotlin",
    ".swift": "swift",
    ".zig": "zig",
    ".lua": "lua",
    ".rb": "ruby",
    ".php": "php",
    ".pl": "perl",
    ".sh": "gnubash", ".bash": "gnubash",
    ".zsh": "zsh",
    ".fish": "fishshell",
    ".nix": "nixos",
    ".qml": "qt",
    ".html": "html5",
    ".css": "css",
    ".scss": "sass",
    ".vue": "vuedotjs",
    ".md": "markdown", ".markdown": "markdown", ".mkd": "markdown",
    ".json": "json",
    ".toml": "toml",
    ".yaml": "yaml", ".yml": "yaml",
    ".xml": "xml",
    ".sql": "sqlite", ".db": "sqlite"
}

// Basenames with no extension to match; a leading dot never counts as one.
var FILES = {
    "dockerfile": "docker",
    "makefile": "gnu",
    "cmakelists.txt": "cmake",
    ".gitignore": "git",
    ".gitattributes": "git"
}

// Language keys live with the filename map; SVG paths load only with LangMark.
var KEYS = [
    "c", "cmake", "cplusplus", "css", "docker",
    "fishshell", "git", "gnu", "gnubash", "go",
    "html5", "javascript", "json", "kotlin", "lua",
    "markdown", "nixos", "openjdk", "perl", "php",
    "python", "qt", "react", "ruby", "rust",
    "sass", "sqlite", "swift", "toml", "typescript",
    "vuedotjs", "xml", "yaml", "zig", "zsh"
]

// Fixed spellings: .h is C, .ts is TypeScript; matching is case-insensitive.
// Sample input: "main.rs" -> "rust", "Dockerfile" -> "docker", "notes.txt" -> "".
function slugForFile(name) {
    var lower = String(name).toLowerCase()
    var base = lower
    var slash = lower.lastIndexOf("/")
    if (slash >= 0) {
        base = lower.slice(slash + 1)
    }
    var file = Object.prototype.hasOwnProperty.call(FILES, base) ? FILES[base] : ""
    if (file) {
        return file
    }
    var dot = base.lastIndexOf(".")
    if (dot > 0) {
        var slug = EXTS[base.slice(dot)]
        if (slug) {
            return slug
        }
    }
    return ""
}

// Directories, symlinks and null rows never wear a logo.
function slugForRow(row) {
    if (row === null || row === undefined || row.d === true) {
        return ""
    }
    if (Format.isSymlink(row.p)) {
        return ""
    }
    return slugForFile(row.n)
}

// Ordinary rows build on demand; search keeps its bounded warm chain through result reuse.
function syncMark(owner, glyph, url, readyStatus) {
    if (!glyph) return
    if (owner.langWarm !== true && (owner.thumbDrawn || owner.langSlug === "")) {
        if (owner.langLoader !== null) {
            owner.langLoader.active = false
            owner.langLoader.destroy()
            owner.langLoader = null
        }
        return
    }
    if (owner.langLoader !== null) return
    var component = Qt.createComponent(url)
    if (component.status !== readyStatus)
        throw new Error("Language mark Loader did not load: " + component.errorString())
    owner.langLoader = component.createObject(glyph.parent, { owner: owner, glyph: glyph })
    component.destroy()
    if (owner.langLoader === null)
        throw new Error("Language mark Loader could not be created")
}
