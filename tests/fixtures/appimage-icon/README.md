# AppImage icon fixtures

These two minimal SquashFS v4 files exercise the actual 7z reader. Both contain
an executable `AppRun` and a valid one-pixel red RGBA `app.png`. The first also
contains `.DirIcon` as a symbolic link to `app.png`; the second has no `.DirIcon`.
The Rust test prefixes each filesystem with the host's real ELF `/usr/bin/true`
and retains the ready-thumbnail URI and recorded-missing-icon assertions.

`generate.py` writes the fixed filesystem structures directly, following the
[SquashFS disk structures](https://github.com/plougher/squashfs-tools/blob/master/squashfs-tools/squashfs_fs.h).
All metadata and data blocks are uncompressed, inode and filesystem times are
zero, ownership is root, ordering and modes are fixed, and the PNG uses a fixed
stored zlib stream. No host timestamp, file metadata or encoder version enters
the result. `SHA256SUMS` records both images, and the Rust test checks those
SHA-256 values through 7z before reading either image.

Check the committed bytes without writing:

```sh
python3 tests/fixtures/appimage-icon/generate.py --check
```

To rebuild, create a fresh scratch directory with `mktemp -d` under the current
worktree's authorized scratch root, add `.flea-test-sandbox`, then run
`python3 tests/fixtures/appimage-icon/generate.py --output /absolute/scratch/root`.
The generator requires that marker and refuses to overwrite an existing output.
Compare its images and checksums with this directory before replacing them.
Neither generation nor the real-reader test needs mksquashfs.
