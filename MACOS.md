# Flea on macOS

This tree is upstream Flea 0.3.12 with its terminal interface and backend built for
Darwin. The GUI (`Quickshell` QML, Wayland) is **not** part of this port: Quickshell
needs Wayland, so `flea --gui` answers with an error and a bare `flea` on a terminal
opens the TUI. The Swift/AppKit window is a separate project.

## Build and run

```bash
cargo build --release
./target/release/flea --tui
```

Installed command, once `~/.local/bin` is on `PATH`:

```bash
flea --tui
flea --tui ~/APPS
flea ~/APPS          # macOS: a bare launch on a terminal is the TUI
```

The test suite's Darwin-relevant suites run with the usual command; see
[Testing on macOS](#testing-on-macos).

## Text size

A terminal UI draws into the terminal's cell grid, so the glyph size belongs to the terminal and
never to Flea: `src/tui` has no font or scale code at all. In cmux, which this port is developed in,
the terminal is Ghostty and the workspace font size is its own: **⌘⌃-** shrinks it, **⌘⌃=** grows
it and **⌘⌃0** resets it (`decreaseWorkspaceTerminalFontSize`,
`increaseWorkspaceTerminalFontSize` and `resetWorkspaceTerminalFontSize`), with
`~/.config/ghostty/config`'s `font-size` (18 here) as the base that `cmux reload-config` re-reads.
The zoom is scoped to the workspace, not to a page of the program running in it.

Flea's own `textSizeUp`, `textSizeDown` and `textSizeReset` rows in `keys.toml` (Ctrl+Shift+Plus,
Ctrl+Shift+Minus, Ctrl+Shift+0) drive the QML window's text ladder, which macOS does not build. The
TUI matches no action for them and its key sheet does not list them, which is why pressing the chord
there does nothing.

## The app bundle

`packaging/macos/build-app.sh [output]` builds `Flea.app` from the release binary: the desktop
entry's own mark becomes the icon, the version comes from `Cargo.toml`, and the bundle is ad hoc
signed. With no argument it writes `dist/Flea.app`; naming `/Applications` installs it:

```bash
packaging/macos/build-app.sh /Applications
open -a /Applications/Flea.app
```

A TUI needs a terminal and Finder gives none, so the bundle has two entrances, both of which
start the same binary:

- `Contents/MacOS/Flea` is the bundle's code. Launched from a terminal it execs the TUI in place
  and keeps the caller's directory; launched from Finder it hands `Contents/Resources/tui.command`
  to `open -a Terminal`, and that file runs the TUI from `$HOME`, because Finder's own directory
  is `/`.
- `Contents/Resources/flea` is the release binary. It sits in `Resources` and not beside the
  launcher on purpose: with a Mach-O in `Contents/MacOS` the ad hoc signature covers the script
  main executable and `codesign --verify --deep` then refuses the nested binary with
  `code object is not signed at all`. In `Resources` it is bundle data, the signature verifies,
  and it still starts its own backend through `current_exe()`.

Nothing depends on `flea` being on `PATH`: the TUI starts the binary inside its own bundle with
`--backend`. Copying the app to another Mac adds a quarantine attribute, which an ad hoc signature
cannot satisfy, so build it there or run `xattr -dr com.apple.quarantine Flea.app`.

### Any terminal program

`packaging/macos/build-tui-app.sh` is the same bundle for any TUI, so the tools Flea is opened
beside get the same double-clickable entry:

```bash
packaging/macos/build-tui-app.sh --name Todo --id com.jason.todo --binary ~/.local/bin/todo \
    --version 1.0 --keywords "todo,task" /Applications
packaging/macos/build-tui-app.sh --name Antigravity --id com.jason.antigravity \
    --binary ~/.local/bin/agy --version 1.5.0 --external \
    --keywords "antigravity,angravity,agy" /Applications
```

It takes `--name`, `--binary`, `--id`, `--args` (space separated, such as `--tui`), `--icon`
(an `.svg` or `.png`), `--version` and `--keywords` (Finder's `kMDItemKeywords`, written as the
bundle's own extended attribute after signing, so it is never part of the seal). The output
directory is the last argument and defaults to `./dist`.

**`--external` is for a program that updates itself.** Measured with `agy`: run from inside a
bundle it staged `.new.tar.gz` in `Contents/Resources` and rewrote its own binary, which adds and
changes files under the seal (`codesign --verify`: `a sealed resource is missing or invalid`) and
leaves the update behind in the app. External mode copies nothing and both entrances exec the
installed path, whose updates and resources stay where its updater expects them; the bundle is
then a few kilobytes and its signature holds. `--link` (a symlink inside the bundle) was tried
first and does not help for that program, because it writes beside the link. `build-app.sh` is Flea's own call of it: release build, version from `Cargo.toml`, the
desktop entry's mark as the icon.

A Finder launch needs no index: the bundle appears in Finder, the Dock and Open With either way.

### The Applications view (⌥Q)

macOS 26 removed Launchpad; the Launchpad key now opens Spotlight's **Applications** location,
which reads the Spotlight index. Two volume indexes must be on, and `mdutil -s /` alone does not
say so: `/` is the sealed system volume, while `/Applications` and `$HOME` live on
`/System/Volumes/Data`.

```bash
mdutil -s /System/Volumes/Data            # Indexing enabled?
sudo mdutil -i on /System/Volumes/Data    # the one that holds /Applications and $HOME
sudo mdutil -i on /                       # the system volume, for /System/Applications
mdimport -i /Applications/Flea.app /Applications/Todo.app /Applications/Antigravity.app
mdfind "kMDItemCFBundleIdentifier == 'com.thisisgm.flea'"
```

An app in the Applications view is an item whose `kMDItemContentType` is
`com.apple.application-bundle` (the Application importer sets it for these script bundles too, and
`mdls` shows `kMDItemKind = Application`). The first build of the Data index takes a while, and
results are partial until it finishes; `mdimport` on a bundle answers at once. `mdutil -i off
/System/Volumes/Data` turns it back off, and Spotlight's privacy list excludes single folders
instead.

## Tabs

`t` opens a tab on the folder on screen, `w` or `Ctrl+W` closes the current one, and `1` to `9`
switch; closing the last tab closes Flea. A **right-click on a tab** opens the strip's own menu —
**Close Tab**, **Close Other Tabs** and **New Tab** — with `Tab`/arrows and Enter, Escape to
dismiss. Closing a tab other than the current one leaves the pane where it is; closing the current
one opens its neighbour.

## Terminal entry

Inside the TUI, `Ctrl+T` opens Terminal.app in the directory currently shown, and the
right-click/`menu` entry **Open in terminal** does the same. The handoff is:

```text
/usr/bin/open -a Terminal <directory>
```

`flea --terminal <directory>` performs the same handoff outside the TUI (used by the
"Open in terminal" action too). The terminal outlives Flea, is detached from Flea's
process group, and inherits no `FLEA_*` variables or file descriptors above 2.

To open a *new* Flea window rather than a plain shell, use Ctrl+T for the shell and run
`flea --tui` there; Terminal.app cannot launch a command with a working directory
without AppleScript automation permission, which this port does not request.

## The menu

`m` opens the menu on the row under the cursor: **open**, **open path**, **copy path**,
**remove**, **show hidden** (or **hide hidden**) and **taildrop**. **open path** reveals the item
where the desktop keeps it rather than opening the file: Finder selects it on macOS
(`open -R <path>`), and on other systems the folder it lives in is handed to the desktop's
handler, since `gio` has no reveal. **remove** is the `dd` trash on the row (or the marked
selection): it is undoable with `Ctrl+Z`, and on macOS it moves the item to the freedesktop Trash
under `~/.local/share/Trash`, not Finder's `~/.Trash`. The first four rows need a row under the
cursor, the hidden-files toggle never does, and Taildrop needs a selected row and a reachable
device.

## The mouse

The wheel moves the listing's cursor: over the listing, over the parents rail, and over the
preview column whenever the preview has nothing to scroll — a folder, a picture, a short text
file, a media frame. Only a preview with more lines than the pane holds (a long text file) or a
PDF page stack takes the wheel for itself, and that is what the pane is for. A click selects the
row under it, and a click on the preview focuses the preview until Esc returns the keyboard to
the listing.

## Copy and paste

`Ctrl+C` / `y` puts the selected files on the macOS pasteboard **both as a file list and as their
paths as text**: Finder, the Desktop and every file-aware application paste the files, and a text
field pastes the paths. `Ctrl+X` / `x` cuts and `Ctrl+V` / `p` pastes files into the folder on
screen. The paths also stay in the session, so the same keys work with no pasteboard at all.

The pasteboard is written through AppleScriptObjC — a small `osascript` script kept at
`~/.cache/flea/clipboard.applescript` — because `pbcopy` writes text only and AppleScript's
`set the clipboard to {POSIX file ...}` writes a file list only. The paths reach the script as
argv, so no name can ever be read as script text. Reading asks the pasteboard for its file list
first (a Finder copy, or any app's file copy, arrives that way) and falls back to its file URL, so
a copy made elsewhere pastes here; a clipboard holding only text pastes nothing, the one exception
being a text line that is itself an existing absolute path. `Ctrl+V` uses a foreign file list as a
copy even if this session cut something earlier: only this session's own cut moves.

**Cmd+C is not ours to bind.** A terminal application never receives the Command chords — the
terminal copies and pastes on them — so Flea's Finder chords are Ctrl, exactly the rule `keys.toml`
states for the GUI. A terminal that forwards them can be configured to: Ghostty's
`keybind = cmd+c=text:\x03` (and `cmd+x=text:\x18`, `cmd+v=text:\x16`) sends the control keys
Flea reads, at the cost of the terminal's own copy and paste on those chords.

## Search results

The **f** page's results are a listing of their own, so the row menu and the clipboard keys
work there exactly as in a folder: `m` opens open / open path / copy path / remove / show hidden /
taildrop on the row under the cursor, `Ctrl+C` / `Ctrl+X` put the result paths on the pasteboard,
and the menu's **remove** trashes a result (undoable with `Ctrl+Z`). `Ctrl+V` in the page pastes
into the folder the search began in, since the page's own listing base is the filesystem root
(`/`); `show hidden` re-runs the query with hidden rows included instead of leaving the page.
Opening a result — Enter or the menu's **open** — opens a file, and a folder navigates into it and
ends the search: Back from that folder lands on the folder the page was opened from.

While the walk is still running the page says so, and the file operations refuse with
"Wait for search to settle before a file operation": a result's index moves as more matches
arrive, so a write by row would name another file by the time it ran.

## What works

- Listing, sorting, all four views (list, columns, grid, two panes), tabs, hidden
  files, filtering, search, path bar, preview column, keymap sheet.
- Navigation and history; entering a folder, parent, page forward, per-folder view
  memory.
- File operations: copy, move, rename (no-replace via `renamex_np(RENAME_EXCL)`),
  duplicate, trash (freedesktop trash under `~/.local/share/Trash`, undoable from
  Flea), permanent delete, new folder, new file, bulk rename.
- Live updates: the listed folder and the columns' neighbours watch through kqueue and
  re-list when an outside change lands.
- Drag and drop inside the terminal (path paste), bulk selection, inline text preview.
- Opening a file hands it to LaunchServices (`/usr/bin/open`), the counterpart of `gio open`.
  An application bundle is a directory to the filesystem and one program to the person, so the
  opener's "3 means navigate" answer is every folder **except** a `.app`; those reach LaunchServices
  and launch, in the listing, in a search result and through `flea --open` alike.
- The filesystem line in the status bar, from Darwin `statfs` (APFS, HFS+, exFAT,
  FAT32, SMB, NFS, ISO 9660, …).
- Volume table rebuilt from `/sbin/mount`, so per-mount rules (FAT/exFAT durability,
  network classes, noexec) read the same shape the Linux parser does.

## Whole-Mac search, indexed by Flea itself

**f** opens a **search page** of its own in the TUI, and its scope is always **every disk**: the
answer comes from Flea's own name index, never from walking the folder on screen. The page has a
heading row — **Name, Path, Modified** — and every result draws exactly those three columns: the
file's own name, the folder holding it, and its age in the listing's own short form (`12 min`,
`3 h`, `Nov 30`). **Files are answers, and so is an application bundle** (`.app` is a directory to the
filesystem and the thing a person searches for; Enter launches it with LaunchServices instead of
browsing its `Contents`). Nothing else that is a folder is a row, and a file that merely sits under
a folder whose name carries the query is not one either,
so searching `Flea` never lists `Sources/Flea/` or `Sources/Flea/Keymap.swift` — only a file whose
own name matches. Enter on a result opens it.

**The snapshot is a fast path, not the authority.** When the index answers a query with nothing, the
backend runs the same home walk it uses while the index is being built, so a file written after the
snapshot was taken is still found (measured here: 2.0 s over a 300,000-entry home) while a hit still
answers from memory in microseconds. No Spotlight and no Everything: Flea builds and keeps its own
name index, and it is also the answer on a box where Spotlight is switched off (measured here:
`mdutil -s /` says "Indexing disabled").

- **The query is Everything's search syntax**, limited to what a name index can answer: a space is
  AND, `|` is OR, `!` negates, `< >` group, `"` keeps text literal, and `*` / `?` are wildcards
  anchored to the whole name. `case:`/`nocase:`, `path:`/`nopath:`, `wholefilename:`/`exact:`,
  `ext:`, `startwith:` and `endwith:` are honoured. A plain term is a **case-insensitive substring
  of the file's own name** (not a fuzzy subsequence), so `flea` lists only names that contain it.
  The metadata functions (`size:`, `dm:`, `dc:`, `da:`, `attrib:`, `type:`, `content:`, ...) and
  `regex:` answer one sentence in the status line instead of a silent empty list, because this
  index stores names only. Examples: `flea keymap` (and), `flea|cmux` (or), `!flea` (not),
  `<flea|cmux> qml` (group), `*.qml` (wildcard), `case:Flea`, `wholefilename:"Makefile"`,
  `path:APPS`, `ext:swift;md`, `startwith:flea`, `endwith:.log`.
- **The query line's small filter** is the only narrowing: `[all disks]` is the default, and
  **Tab** flips it to `[in <folder>]`, which keeps only results at or below the folder the
  search began in. Tab again searches every disk. The filter rides the same request as a
  `"under"` prefix, so it narrows before ranking rather than trimming a capped head, and both the
  snapshot and the filter use the folder's canonical path, so a folder reached through a link
  still matches.
- **The results follow the typing**, as Everything's do: every edit asks the index on the next
  loop tick (the loop polls every 100 ms, so a fast typist still sees one answer per letter
  rather than a queue of them), the cursor goes to the top of the new answer, and the count is
  drawn on the query line itself (`search: … · 12 matches`) and in the page's title. **Up**,
  **Down**, **PageUp** and **PageDown** walk the results while the line is still open — the view
  follows the cursor, and Home/End stay the field's own — so a query never has to be "committed"
  before it can be browsed. Enter only closes the line — it never asks twice for an answer already
  drawn — and the page keeps its heading and rows, so `j`, Enter and `m` act on the results. **f**
  again reopens the line on the running query; erasing it leaves the page blank with a hint;
  **Escape** leaves the page and puts the folder it was opened from back. Opening a folder from the results
  is an ordinary navigation and leaves the page too.
- The snapshot covers `$HOME`, `/Applications` and every mounted volume. Caches, Trash, `.git`,
  `node_modules`, `target`, `DerivedData`, `.cache`, `.Spotlight-V100` and `.fseventsd` are
  listed but never descended, and the index stops at 1.5 million entries.
- It lives in `~/Library/Caches/flea/locate.idx` (or `$XDG_CACHE_HOME/flea/locate.idx`), is
  read on the first whole-Mac search of a process and rebuilt behind the answer once it is 12
  hours old.
- **An application installed a minute ago is found now, not after that rebuild.** A root directory
  whose mtime is newer than the snapshot (installing an app moves `/Applications`; the bundle's
  own timestamps are preserved by the installer, so the root is the signal) has children the
  snapshot cannot know: those added children are walked into a small side index on the first
  search and answered beside the snapshot's rows, so the search finds the new bundle while the
  snapshot itself stays untouched. The walk skips the same directories the snapshot skips
  (`.Trash`, caches, VCS objects), and the side index is reused for every later search in the
  process, so only the first one after an install pays the walk (tens of milliseconds on a release
  build for a normal app bundle).
- **A TUI backend warms the snapshot at launch** (`FLEA_INDEX_WARM` is set by `src/tui/wire.rs`,
  so the window and every script read and build nothing): the file is loaded in the background
  and the first search answers from memory instead of paying the read in the search. A missing
  snapshot is not built at launch, because that walk would belong to a launch nobody asked to
  index yet.
- **The first whole-Mac search of a fresh install** walks the home tree instead (measured 1.0
  to 1.5 s to the first answer on this box) and starts the snapshot in the background; the build
  takes about 5 to 10 s and writes roughly 170 MB. Every later launch answers from the file:
  measured **0.05 s** from a cold process to a ranked answer over **675,493 indexed entries**
  (68 ms end to end over 170 MB in the release build on this box).
- One answer carries at most 20,000 ranked rows, kept in the listing so copy, trash, preview
  and the columns view work on results unchanged; the status line reports the rows it holds and
  the population it looked through. Narrow the query to see past the head.
- The answer is ordered by the file's own name, the listing's own natural comparator, and then by
  full path; a query matching everything then costs one pass over the index, not a sort of the
  whole Mac.
- **A long name or folder is cut, not allowed to hide the other column.** The name keeps its
  start (`…` at the end), the folder keeps its tail (`…inner/deeper`), and the date keeps its
  right-hand column, so the three columns line up under their headings however deep the path is.
- **The preview text is selectable, read-only.** Dragging over the preview pane selects the cells
  it covers (drawn in reverse video) and releasing copies exactly that text to the system
  clipboard, with the count in the status line (`Copied 4 characters`); it joins lines with
  newlines, keeps the cells the drag covered, and a plain click clears the selection. Nothing is
  editable: the same cells a terminal's own selection would take, taken by Flea because mouse
  reporting belongs to the TUI. A new preview, a scroll or a resize drops the selection.
- **`m` on a result opens the same menu a listing row does**, and its second row, **copy path**,
  puts the cursor row's absolute path on the system clipboard as plain text — `pbcopy` on a Mac,
  `wl-copy` on a Wayland session — and says so in the status line, even while the search line
  is showing. It is text, not a file copy: paste it into a terminal or an editor.
- A reload (`F5`) repeats the same whole-disk search with its folder filter; it never falls back
  to walking the folder the answer's base names.

## What is Linux-only here

These paths need kernel features with no Darwin equivalent, and refuse cleanly rather
than misbehaving:

- **Sandboxed helper programs**, and therefore video/PDF/office thumbnails, archive
  extraction and app icons: they run under `bwrap` + `prlimit` + Landlock/seccomp on
  Linux. Without those, settings say thumbnails are disabled and every preview that
  needs an external decoder reports that error. The inline text preview still works,
  because Flea reads those bytes itself. Running third-party decoders unsandboxed is
  deliberately not done implicitly.
- **Permissions editing** (chmod through a held `O_PATH` descriptor and `fchmodat2`);
  the dialog refuses with its own message.
- **GVFS/SFTP/SMB remotes, Dropbox/Taildrop, phone (AFC/MTP) mounts**, disk-image
  flashing, encryption unlock, Hyprland key installation, the Omarchy shelf plugin and
  the Quickshell GUI. `flea --gui` exits with a message saying so.
- **Wayland clipboard integration** (`wl-clipboard` owner tracking); file copy/paste
  inside Flea is unaffected.

## Port shape

- `src/sys.rs` provides the Darwin layer: kqueue-backed inotify-compatible directory
  watches (synthetic, never-reused watch descriptors, `IN_IGNORED` on removal,
  `IN_NONBLOCK` reads and per-kqueue deduplication), a nonblocking wake pipe, `pidfd` waiting through `EVFILT_PROC` (with a
  triggered user event for a child that exited before the wait began), close-on-exec
  sweeps, poll helpers and `F_FULLFSYNC` writeback.
- `src/macos_compat.rs` supplies the remaining Linux libc names as `#[no_mangle]`
  functions: `pipe2`, `close_range`, `eventfd` (refused), xattr wrappers,
  `renameat2`, `posix_fadvise`, allocator and `prctl` no-ops, `name_to_handle_at`
  (refused) and `__errno_location` → `__error`.
- `src/backend/scan.rs` reads Darwin's `struct dirent` (64-bit inode form) and
  resolves typeless entries through `std::fs` instead of a hand-copied `struct stat`.
- `src/oflags.rs` carries Darwin's `O_NOFOLLOW`, `O_DIRECTORY`, `O_NONBLOCK` and
  `O_CLOEXEC`, so symlink and FIFO guards hold.
- `src/backend/fsinfo.rs` reads Darwin's 2168-byte `struct statfs` and maps its type
  names onto the Linux magic numbers the rest of the tree compares.
- `src/backend/mountinfo.rs` turns `/sbin/mount` into mountinfo lines, with Darwin's
  `dev_t` packing.
- `src/tui/terminal.rs` and `src/terminal.rs` use Terminal.app instead of
  `xdg-terminal-exec`.

## Testing on macOS

```bash
cargo test --bin flea tui::                    # 134 pass: rendering, input, model, keymap
cargo test --bin flea backend::watch           # kqueue watch semantics
cargo test --bin flea backend::peekwatch       # column watches
cargo test --bin flea backend::mountinfo       # Darwin mount-line parser
cargo test --bin flea backend::scan            # dirent layout and listing
cargo test --bin flea backend::fsinfo          # statfs fields
```

The upstream suite is written against Linux kernel and desktop facilities. Suites
that assert them (gio/GVFS trash bookkeeping, `bwrap` sandbox argv, `/proc` walks,
case-sensitive hardlink twins, Wayland clipboard, Landlock/seccomp, Hyprland) fail or
skip on macOS by design; they were left intact so the Linux build keeps its coverage.
The Darwin-relevant suites above, plus `runfile`, `uistore`, `open`, `tags` and
`renamecompat` where they do not need `/proc` or a case-sensitive filesystem, pass.
