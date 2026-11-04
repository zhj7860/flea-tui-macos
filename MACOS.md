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
- The filesystem line in the status bar, from Darwin `statfs` (APFS, HFS+, exFAT,
  FAT32, SMB, NFS, ISO 9660, …).
- Volume table rebuilt from `/sbin/mount`, so per-mount rules (FAT/exFAT durability,
  network classes, noexec) read the same shape the Linux parser does.

## Whole-Mac search, indexed by Flea itself

`f` opens the search line; **Tab** cycles its scope: **Here** (the folder on screen), **Home**,
and **This Mac**. Enter on a result opens a file or walks into a folder, exactly like a
listing row. No Spotlight and no Everything: Flea builds and keeps its own name index, and it
is also the answer on a box where Spotlight is switched off (measured here: `mdutil -s /` says
"Indexing disabled").

- The snapshot covers `$HOME`, `/Applications` and every mounted volume. Caches, Trash, `.git`,
  `node_modules`, `target`, `DerivedData`, `.cache`, `.Spotlight-V100` and `.fseventsd` are
  listed but never descended, and the index stops at 1.5 million entries.
- It lives in `~/Library/Caches/flea/locate.idx` (or `$XDG_CACHE_HOME/flea/locate.idx`), is
  read on the first whole-Mac search of a process and rebuilt behind the answer once it is 12
  hours old.
- **The first whole-Mac search of a fresh install** walks the home tree instead (measured 1.0
  to 1.5 s to the first answer on this box) and starts the snapshot in the background; the build
  takes about 5 to 10 s and writes roughly 170 MB. Every later launch answers from the file:
  measured **0.05 s** from a cold process to a ranked answer over **675,493 indexed entries**.
- One answer carries at most 20,000 ranked rows, kept in the listing so copy, trash, preview
  and the columns view work on results unchanged; the status line reports the rows it holds and
  the population it looked through. Narrow the query to see past the head.
- Ranking is the same subsequence score the folder search uses: an exact name leads, a match in
  the file's own name beats one in a parent directory, and shorter paths win ties.

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
