# Field bench manifest

Written by tools/flea-bench-manifest. Every measurement below is read off the installed artefact.
The host name and the checkout path are generalised for publication; no measured value is touched.
Wording outside the measurements was made neutral after the run; every number, version and setting is as the tool
recorded it. The text as first recorded is in this file's history before commit b91358a5.

## Run

- date: 2026-09-02T20:27:22-04:00
- host: the bench box, kernel 7.1.9-arch1-2
- fixture: /home/flea-sandbox/flea-media-btrfs
- fixture payload: 2000 visible entries, filesystem btrfs
- TUI terminal: kitty 0.48.2-1
- flea launch line: FLEA_BIN=<repo>/target/release/flea FLEA_UI=<repo>/ui setsid nohup <repo>/target/release/flea --gui /home/flea-sandbox/flea-media-btrfs
- load average at start: 0.45 1.27 1.43
- waited 10 seconds for the box to go idle before starting
- TUI preview target: /home/flea-sandbox/flea-media-btrfs/photo_0.jpg
- fixture payload assertion: PASSED, 2000 visible entries against the expected 2000

## Correction, 2026-09-03: strata's three rows were re-measured

**strata's rows in `media-rc-2044.csv` come from a run on 2026-09-03, not from the 2026-09-02
batch above. No other entrant was re-run and no other number moved.**

The batch reported strata as having produced nothing, and that was the instrument and not the
entrant. strata persists no thumbnail: it renders each one in a sandboxed helper that writes
`result.png` into `/tmp/strata-preview-<pid>-<n>`, reads it into a 256-entry, 64 MiB in-memory
cache, and deletes the directory on drop. Every instrument in this harness counted
`~/.cache/thumbnails`, which is structurally blind to that, so strata's work column read `0`,
then `unmeasurable`, and its time sat below the rule unranked for the whole v0.1.0 release while
it drew six of the eight formats offered.

The re-run measures that work by a live watch attached across the same run that takes the timing,
so `thumbs_n` and `thumbs_by_format` come out of the same three runs as `settled_ms`, `pss_kb` and
`cpu_tree_s` rather than being borrowed from `capability.md`, which is a different instrument on a
different day. Two watches, because neither answers both questions: an `inotifywait` on `/tmp`
counts each `result.png` closing, and an `inotifywait` on the fixture directory names the file that
earned it, because bwrap binds the input into the helper's namespace without moving the dentry.
strata thumbnails one file at a time, so the two are paired, and all three runs recorded **205
renders against exactly 205 fixture opens**.

Everything else was held: `tools/flea-field-bench` with `ONLY=strata DROP_THUMBS=yes`, the same
fixture, the same v0.6.1 build, caches dropped before each of the three runs, and the same idle
gate. Two differences are disclosed rather than hidden.

- **The kill list was scoped to strata.** The box carried two of the operator's own packaged Flea
  processes, and a full-field run would have closed them. `ONLY` now scopes both the kill list and
  the start-up refusal to the entrant named.
- **Those two processes were resident for the re-run and were not for the batch.** A resident Qt
  process can understate another process's PSS by sharing library pages. It did not here: strata's
  PSS came out 1.7 MB **higher** than on 2026-09-02, 71964 kB against 70254, and its settle time
  landed within 0.04 percent of it, 30792 ms against 30780.

The raw cache reading survives in `thumbs_by_dir` as `fail=0;large=0`, which is a true statement
about the cache and a false one about the entrant.

## Fixture by extension

```
    600 jpg
    400 mp4
    200 webp
    200 txt
    200 png
    200 heic
    100 webm
    100 mkv
      0 no extension
```

- excluded from the denominator: 200 .txt files, which no thumbnailer attempts
- thumbnailable denominator: 1800, from 2000 visible entries less the 200 above

## Package freshness

- last full system upgrade: [2026-09-02T00:22:38-0400] [PACMAN] starting full system upgrade
- age at run time: 20 hours

## Entrants

```
flea       gui  source b857757 (clean), release binary built 2026-09-02T20:13:50-04:00, 972008 bytes
nautilus   gui  nautilus 50.2.2-1
thunar     gui  thunar 4.20.9-1
pcmanfm    gui  pcmanfm 1.4.0-2
nemo       gui  nemo 6.6.4-1
dolphin    gui  dolphin 26.08.0-4
strata     gui  source v0.6.1 committed 2026-09-01, built locally from this checkout
yazi       tui  yazi 26.8.15-1
mc         tui  mc 4.8.33-1
broot      tui  broot 1.59.0-1
nnn        tui  nnn 5.3-1
lf         tui  lf 42-1
ranger     tui  ranger 1.9.4-5
xplr       tui  xplr 1.0.1-1
superfile  tui  superfile 1.6.0-1
```

strata is the one entrant pacman did not install. It is built here from the v0.6.1 tag in a
local checkout. **The project also publishes a prebuilt x86_64 binary for that tag and it was
not used**: this harness does not download and execute a third-party binary unattended, and
every packaged entrant is itself built from source by the distribution, so building from the
tag is more consistent with the field than fetching one binary would be. Build flags may differ
from the published release, which is equally true of every AUR entrant in the list.

## The TUI group's configuration, as it ran

Provenance per entrant is in `tools/flea-bench-tui/README.md`. lf's is AUTHORED HERE
because lf ships no image preview at all; every other file came from that project's own docs.

### README.md

```
# The TUI group's configuration, and where every line of it came from

This directory is the `XDG_CONFIG_HOME` the field bench hands to every TUI entrant. The operator's
own `~/.config` is never read by a benched entrant and never written by one, so a run is
reproducible on another box and the operator's ranger, nnn and superfile settings are left alone.

The rule is **bench as-intended**: each entrant runs in the configuration its own project
documents, not in whatever stock Omarchy happens to leave it in, and not in a tuned one. The others
are expected to get slower, and that is the point: it is the only version of this group that
supports a capability claim.

The guard on that rule, which is the load-bearing part: **do not tune.** No flag is chosen because
it helps or hurts a number. A slow documented default is a result.

## Per entrant

| entrant | image preview | where the configuration came from |
|---|---|---|
| yazi | native Kitty graphics protocol | **Nothing configured.** Stock, and it was only ever blocked by `foot`. |
| ranger | Kitty protocol | The two lines its own shipped `rc.conf` documents, at `/usr/share/doc/ranger/config/rc.conf`. Needs `python-pillow`, which is installed. |
| superfile | `chafa` | **Nothing configured.** Its own docs name `chafa` as the requirement and it detects it. |
| nnn | `preview-tui`, the plugin it ships | The plugin at `/usr/share/nnn/plugins/preview-tui`, wired the way its own header documents: `NNN_FIFO`, `NNN_PLUG`, and a kitty with `allow_remote_control` and `listen_on`. The bench symlinks the shipped plugin into `nnn/plugins/` at run time rather than committing a copy of it here. |
| lf | `kitten icat` | **AUTHORED HERE.** lf ships no image preview: its own `lfrc.example` has no preview lines. The shape is lf's documented `previewer` and `cleaner` hooks. lf's row carries this caveat in the manifest. |
| mc, broot, xplr | none | **No image preview feature exists.** That is a capability finding, not a configuration gap, and it is permanent for those three. |

## The terminal is part of the configuration

`kitty/kitty.conf` is the bench's own, for two reasons. A number that depends on whatever font size
somebody set last week is not reproducible, and `nnn`'s preview plugin needs `allow_remote_control`,
which is not a thing to switch on in an operator's real terminal.

The group ran in `foot` before this. Recorded at the time: foot supports sixel only, while yazi and the rest prefer
the Kitty protocol, so `thumbs_n 0` across all eight entrants was the harness's terminal choice and
not a result about the entrants.

## These results are a new baseline

The as-intended numbers are **not comparable to the as-shipped numbers already collected**. Any
document carrying both says so rather than merging the two tables.
```

### kitty/kitty.conf

```
# The bench's own terminal configuration, not the operator's. A benchmark whose numbers depend on
# whatever font size somebody set last week is not reproducible, and nnn's preview plugin needs
# remote control switched on, which is not something to turn on in an operator's real terminal.
allow_remote_control yes
listen_on unix:/tmp/flea-bench-kitty

# A fixed grid, so every entrant is handed the same viewport and the same amount of preview to draw.
font_size 12
remember_window_size no
initial_window_width 1600
initial_window_height 1000
confirm_os_window_close 0
```

### lf/cleaner.sh

```
#!/bin/sh
# Without this the previous image stays on screen over the next file's preview.
kitten icat --clear --stdin no --transfer-mode file </dev/null >/dev/tty
```

### lf/lfrc

```
# lf ships no image preview at all: its own lfrc.example at /usr/share/doc/lf/lfrc.example has no
# preview lines in it. AUTHORED HERE, so lf's row carries that caveat. The shape is lf's documented
# previewer hook, with kitty's own icat kitten as the image path.
set previewer /tmp/tmp.kmp2qHOFP2/lf/previewer.sh
set cleaner /tmp/tmp.kmp2qHOFP2/lf/cleaner.sh
```

### lf/previewer.sh

```
#!/bin/sh
# lf calls a previewer with the file and the preview pane geometry: $1 file, $2 width, $3 height,
# $4 x, $5 y. Exiting 1 tells lf not to cache the output, which is what an image preview needs.
case "$1" in
  *.jpg|*.jpeg|*.png|*.webp|*.heic|*.gif)
    kitten icat --stdin no --transfer-mode file --place "${2}x${3}@${4}x${5}" "$1" </dev/null >/dev/tty
    exit 1
    ;;
esac
head -100 "$1"
```

### nnn/plugins/preview-tui

23174 bytes, not reprinted: this is the file the entrant's own package ships.

### ranger/rc.conf

```
# ranger ships preview_images false and preview_images_method w3m, so out of the box it draws no
# image in any terminal. These are the two lines its own shipped rc.conf documents for a
# Kitty-protocol terminal, at /usr/share/doc/ranger/config/rc.conf, and nothing else is changed.
set preview_images true
set preview_images_method kitty
```

## Libraries the entrants render through

An absent one is a capability fact about this field, not a gap in the record.

```
qt6-base               6.11.2-2
gtk3                   1:3.24.52-1
gtk4                   1:4.22.4-1
glib2                  2.88.3-1
ffmpegthumbnailer      2.3.0-2
libheif                1.23.1-4
webp-pixbuf-loader     absent
qt6-imageformats       6.11.2-1
chafa                  1.18.2-2
ueberzugpp             2.9.10-1
```

## Run close

- ended: 2026-09-02T20:43:42-04:00
- load average at end: 1.29 2.04 1.92

## Formats produced, refused, and never attempted

The formats come from the fixture's own key map, not from any one run's output, so a format
an entrant never reached still gets a line. Produced is a thumbnail written. Refused is a
failure marker the thumbnailer left. Never attempted is neither, which on this fixture mostly
means the entrant settled before reaching those names: they sort by format, clip before image
before notes before photo. **A never-attempted count is not a capability claim.**

**strata's line below is counted by the live watch described under "Correction" above, not by
this cache.** Its instrument is named there and it is not the one the other six rows used; what
the two have in common is that each counts thumbnails the entrant actually drew on this fixture.

- flea produced mkv 6, mp4 24, webm 6; refused nothing; never attempted heic 200, jpg 600, mkv 94, mp4 376, png 200, txt 200, webm 94, webp 200
- nautilus produced heic 13, mp4 400, png 14, webm 100, webp 14; refused nothing; never attempted heic 187, jpg 600, mkv 100, png 186, txt 200, webp 186
- thunar produced mkv 37, mp4 148, webm 36; refused nothing; never attempted heic 200, jpg 600, mkv 63, mp4 252, png 200, txt 200, webm 64, webp 200
- pcmanfm produced mp4 400, png 105, webm 100; refused nothing; never attempted heic 200, jpg 600, mkv 100, png 95, txt 200, webp 200
- nemo produced jpg 45, webp 15; refused nothing; never attempted heic 200, jpg 555, mkv 100, mp4 400, png 200, txt 200, webm 100, webp 185
- dolphin produced jpg 50, mkv 84, mp4 335, webm 83; refused nothing; never attempted heic 200, jpg 550, mkv 16, mp4 65, png 200, txt 200, webm 17, webp 200
- strata produced mkv 34, mp4 137, webm 34; refused nothing; never attempted heic 200, jpg 600, mkv 66, mp4 263, png 200, txt 200, webm 66, webp 200
- yazi: a TUI previews the cursor file and fills no grid, so it writes no thumbnails at all
- mc: a TUI previews the cursor file and fills no grid, so it writes no thumbnails at all
- broot: a TUI previews the cursor file and fills no grid, so it writes no thumbnails at all
- nnn: a TUI previews the cursor file and fills no grid, so it writes no thumbnails at all
- lf: a TUI previews the cursor file and fills no grid, so it writes no thumbnails at all
- ranger: a TUI previews the cursor file and fills no grid, so it writes no thumbnails at all
- xplr: a TUI previews the cursor file and fills no grid, so it writes no thumbnails at all
- superfile: a TUI previews the cursor file and fills no grid, so it writes no thumbnails at all

## The TUI group's preview timing

- mc, xplr, superfile: no image preview feature at all, so nothing was there to time. The -1 in
  preview_ms is that fact and not a slow preview.

## The equal-work column

`cpu_tree_s` is the column to compare work on, for every entrant and not for Flea alone: a
column carrying CPU-seconds for one entrant and wall-seconds for the rest is the incomparable
rank this harness now refuses. It is on every row above.

**What it does not yet include.** Flea thumbnails the viewport by design and every other entrant
thumbnails the directory, so this column is comparable in units and not in work until Flea is
driven through the whole listing. When that lands, the residual bias belongs here too: the
driver's own cost falls in omarchy-drive's tree and is excluded, while Flea's cost of
servicing that drive is included and no other entrant pays it. That biases against Flea, which is the
safe direction, and it is not a reason to leave the number out.

## Rank refusals

- yazi run 1: n/a: tui in kitty
- mc run 1: n/a: tui in kitty
- broot run 1: n/a: tui in kitty
- nnn run 1: n/a: tui in kitty
- lf run 1: n/a: tui in kitty
- ranger run 1: n/a: tui in kitty
- xplr run 1: n/a: tui in kitty
- superfile run 1: n/a: tui in kitty
- yazi run 2: n/a: tui in kitty
- mc run 2: n/a: tui in kitty
- broot run 2: n/a: tui in kitty
- nnn run 2: n/a: tui in kitty
- lf run 2: n/a: tui in kitty
- ranger run 2: n/a: tui in kitty
- xplr run 2: n/a: tui in kitty
- superfile run 2: n/a: tui in kitty
- yazi run 3: n/a: tui in kitty
- mc run 3: n/a: tui in kitty
- broot run 3: n/a: tui in kitty
- nnn run 3: n/a: tui in kitty
- lf run 3: n/a: tui in kitty
- ranger run 3: n/a: tui in kitty
- xplr run 3: n/a: tui in kitty
- superfile run 3: n/a: tui in kitty
- the ranked rows differ in thumbnail work by 16x, from 36 to 605, so their settle times are not ranked against each other
