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
