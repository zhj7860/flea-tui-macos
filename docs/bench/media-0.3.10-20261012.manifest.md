# Field bench manifest

Written by tools/flea-bench-manifest. Every line below is read off the installed artefact, except the two
entrant corrections listed under "Merged run" at the end.

## Run

- date: 2026-10-12T21:54:40-04:00
- host: minipc, kernel 7.2.8-5-omarchy-bore
- fixture: /home/flea-sandbox/flea-media-btrfs
- fixture kind: btrfs
- fixture payload: 2000 visible entries, filesystem btrfs
- TUI terminal: kitty 0.49.2-1
- flea launch line: FLEA_BIN=/home/flea-sandbox/n.LPqVdHoc/arms/f9c48884fa9e/target/release/flea FLEA_UI=/home/flea-sandbox/n.LPqVdHoc/arms/f9c48884fa9e/ui QML_DISK_CACHE_PATH=/home/flea-sandbox/n.LPqVdHoc/arms/f9c48884fa9e/target/qmlcache XDG_STATE_HOME=/tmp/flea-bench-state.BMcsFd setsid nohup /home/flea-sandbox/n.LPqVdHoc/arms/f9c48884fa9e/target/release/flea --gui /home/flea-sandbox/flea-media-btrfs
- load average at start: 0.48 0.93 1.16
- waited 50 seconds for the box to go idle before starting
- Quickshell QML cache at start: 17277 entries
- settle gap: 500 ms of quiet ticks
- settle clock watches the entrant tree plus: none
- TUI preview target: /home/flea-sandbox/flea-media-btrfs/photo_0.jpg
- fixture payload assertion: PASSED, 2000 visible entries against the expected 2000

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

- last full system upgrade: [2026-10-11T11:24:49-0400] [PACMAN] starting full system upgrade
- age at run time: 34 hours
- WARNING: this run is more than 24 hours past the last upgrade, so the packaged entrants are not necessarily current

## Entrants

```
flea       gui  source 5816ab88 untagged (DIRTY), release binary built 2026-10-12T21:50:50-04:00, 5059184 bytes
flea-anchor gui  source 1de9d979 untagged (DIRTY), release binary built 2026-10-12T21:52:12-04:00, 3808712 bytes
nautilus   gui  nautilus 51.0.1-2
thunar     gui  thunar 4.20.10-1
pcmanfm    gui  pcmanfm 1.4.0-2
nemo       gui  nemo 6.6.4-1
dolphin    gui  dolphin 26.08.2-1
strata     gui  source v1.0.0 committed 2026-10-12, built locally from this checkout
flea-tui   tui  source 5816ab88 untagged (DIRTY), release binary built 2026-10-12T21:50:50-04:00, 5059184 bytes
yazi       tui  yazi 26.9.1-2
mc         tui  mc 4.8.33-1
broot      tui  broot 1.61.0-1
nnn        tui  nnn 5.3-1
lf         tui  lf 42-1
ranger     tui  ranger 1.9.4-5
xplr       tui  xplr 1.0.1-1
superfile  tui  superfile 1.6.0-1
```

strata is the one entrant pacman did not install. It is built here from the v1.0.0 tag in a
local checkout. **The project also publishes a prebuilt x86_64 binary for that tag and it was
not used**: this harness does not download and execute a third-party binary unattended, and
every packaged entrant is itself built from source by the distribution, so building from the
tag is more consistent with the field than fetching one binary would be. Build flags may differ
from the published release, which is equally true of every AUR entrant in the list.

## The TUI bracket's configuration, as it ran

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

The group ran in `foot` before this. foot supports sixel only, while yazi and the rest prefer
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
listen_on unix:/tmp/tmp.Up9IkT0SOG/flea-bench-kitty

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
set previewer /tmp/tmp.Up9IkT0SOG/lf/previewer.sh
set cleaner /tmp/tmp.Up9IkT0SOG/lf/cleaner.sh
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
qt6-base               6.12.0-2
gtk3                   1:3.24.52-2
gtk4                   1:4.24.1-1
glib2                  2.90.1-1
ffmpegthumbnailer      2.3.1-1
libheif                1.23.6-1
webp-pixbuf-loader     absent
qt6-imageformats       6.12.0-1
chafa                  1.18.3-1
ueberzugpp             2.9.10-1
```

## Run close

- ended: 2026-10-12T21:56:23-04:00
- load average at end: 0.62 0.88 1.12
- Quickshell QML cache at end: 17277 entries
- tested Flea's own QML cache at end: 176 entries in /home/flea-sandbox/n.LPqVdHoc/arms/f9c48884fa9e/target/qmlcache

## Formats produced, refused, and never attempted

The formats come from the fixture's own key map, not from any one run's output, so a format
an entrant never reached still gets a line. Produced is a thumbnail written. Refused is a
failure marker the thumbnailer left. Never attempted is neither, which on this fixture mostly
means the entrant settled before reaching those names: they sort by format, clip before image
before notes before photo. **A never-attempted count is not a capability claim.**

- flea produced mkv 7, mp4 29, webm 7; refused nothing; never attempted heic 200, jpg 600, mkv 93, mp4 371, png 200, txt 200, webm 93, webp 200
- flea-anchor produced mkv 7, mp4 29, webm 7; refused nothing; never attempted heic 200, jpg 600, mkv 93, mp4 371, png 200, txt 200, webm 93, webp 200
- strata: nothing reached the thumbnail cache, so this run makes no format claim about it either way; tools/flea-bench-capability is the instrument that answers what it can draw
- flea-tui: a TUI previews the cursor file and fills no grid, so it writes no thumbnails at all

## The TUI bracket's preview timing

- flea-tui: no image preview feature at all, so nothing was there to time. The -1 in
  preview_ms is that fact and not a slow preview.

## The equal-work column

`cpu_tree_s` is the column to compare work on, for every entrant and not for Flea alone: a
column carrying CPU-seconds for one entrant and wall-seconds for the rest is the incomparable
rank this harness now refuses. It is on every row above.

**It is read from a control group of the run's own.** Each entrant run is a leaf cgroup that
the launching shell joins before it forks the entrant, and `cpu_tree_s` is that leaf's
`usage_usec`, plus a declared helper living outside it (thunar's tumblerd). The older sum of
reaped ticks is kept as `cpu_reaped_s` and is blind to a decode under bwrap: measured, ten
sandboxed decodes added 0.01 s to it against 0.95 s run bare. A column from before 0.3.2 is
that blind figure and compares only against `cpu_reaped_s`. A TUI row's group holds its
terminal too, so that bracket's column includes kitty's own drawing, the same kitty for each.

**What it does not yet include.** Flea thumbnails the viewport by design and every rival
thumbnails the directory, so this column is comparable in units and not in work until Flea is
driven through the whole listing. When that lands, the residual bias belongs here too: the
driver's own cost falls in omarchy-drive's tree and is excluded, while Flea's cost of
servicing that drive is included and no rival pays it. That biases against Flea, which is the
safe direction, and it is not a reason to leave the number out.

## Rank refusals

- strata run 1: unranked: its watches saw 0 renders for 86 opened fixture files so neither is a count
- flea-tui run 1: n/a: tui in kitty
- strata run 2: unranked: its watches saw 0 renders for 86 opened fixture files so neither is a count
- flea-tui run 2: n/a: tui in kitty
- strata run 3: unranked: its watches saw 0 renders for 86 opened fixture files so neither is a count
- flea-tui run 3: n/a: tui in kitty

## Merged run

- phase A (flea, flea-anchor, flea-tui, strata): run root field039.BrghYUKo on the bench host
- phase B (dolphin, thunar, nemo, pcmanfm, nautilus): run root field039.tX4cAYd4 on the bench host
- this manifest is phase A's; strata ran the v1.0.0 build at /home/flea-sandbox/strata-100 and its row
  above names that tag (the generator had read the v0.19.0 checkout at ~/Work/strata)
- flea ran from f9c48884, the pre-reword id of 5816ab88 (same tree), the 0.3.10 version commit; the
  entrant lines above name 5816ab88, and the launch line keeps the build path as it ran. The v0.3.10 tag
  adds only lint fixes with no runtime change, tests and docs after it
- flea-tui ran with no terminal rival in this run, so its rows are left out of these CSVs
- flea-anchor is v0.3.9: tag v0.3.9 points at 1de9d979; the bench host's clone carries no tags, so the line
  says untagged
- DIRTY on flea and flea-anchor is the bench harness's marker patch (18 console.log timing lines and one
  objectName, in 13 UI files, applied identically to every Flea arm); the code is otherwise the named commit
- in this run flea launched before flea-anchor in every run. An order check after it, same host, ran both
  video fixtures with each version launched first in one run of 5 and second in another (roots
  field039.aI4bSZkf with 0.3.10 first and field039.yt9Ik8WL with 0.3.9 first). Medians of the 10 runs per
  version: 2,000-file media fixture 0.3.10 502.5 ms, 0.3.9 502.5 ms; 1,700-file matched fixture 0.3.10
  507.5 ms, 0.3.9 503.5 ms. Every one of those runs fell between 494 and 585 ms
