# Flea TUI on macOS

This working tree is upstream Flea 0.3.12 with the TUI and its backend built
for Darwin. It is a terminal file manager, not the Swift/AppKit GUI port in
`~/APPS/flea`.

## Build and run

```bash
cargo build --release
./target/release/flea --tui
```

Installed command:

```text
~/.local/bin/flea
```

```bash
flea --tui
flea --tui ~/APPS
```

## Terminal entry

Inside the TUI, `Ctrl+T` opens Terminal.app in the directory currently shown.
The implementation uses:

```text
/usr/bin/open -a Terminal <directory>
```

`flea --terminal <directory>` performs the same handoff outside the TUI.

## Port shape

- `src/sys.rs` provides the Darwin layer: kqueue-backed inotify-compatible
  directory watches, a nonblocking wake pipe, pidfd waiting through
  `EVFILT_PROC`, close-on-exec sweeps and poll helpers.
- `src/macos_compat.rs` supplies the remaining Linux libc names: `pipe2`,
  `close_range`, xattr wrappers, `renameat2`, allocator no-ops and related
  symbols.
- `src/backend/scan.rs` uses Darwin's `struct dirent`, `__error` and a
  `std::fs` fallback for typeless entries.
- `src/tui/terminal.rs` uses Terminal.app instead of `xdg-terminal-exec`.

Linux-only desktop integrations stay absent: bwrap thumbnails, gvfs, udev,
Hyprland and the Omarchy shell. Thumbnails therefore report disabled when the
Linux sandbox helpers are not present; browsing, navigation, views, file
operations available through the TUI, and the terminal entry still work.

The binary is registered in TUI Workspace:

```bash
tui-workspace list
tui-workspace add flea ~/.local/bin/flea --category Files --keyword file -- --tui
```
