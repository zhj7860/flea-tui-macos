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
- The filesystem line in the status bar, from Darwin `statfs` (APFS, HFS+, exFAT,
  FAT32, SMB, NFS, ISO 9660, …).
- Volume table rebuilt from `/sbin/mount`, so per-mount rules (FAT/exFAT durability,
  network classes, noexec) read the same shape the Linux parser does.

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
  watches (including `IN_IGNORED` on removal, `IN_NONBLOCK` reads and deduplicated
  descriptors), a nonblocking wake pipe, `pidfd` waiting through `EVFILT_PROC` (with a
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
