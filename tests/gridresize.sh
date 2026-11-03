#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# A resized Grid still draws every tile's row, offscreen with the real backend, after width or height changes.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
command -v qs >/dev/null || { echo 'FAIL gridresize: qs is missing'; exit 1; }
failed=0
for case_name in narrow-far narrow-still widen-mid height-mid; do
root=$(mktemp -d "$FIXTURE_ROOT/gridresize-XXXXXXXX") || exit 1
sandbox_require "$root" || exit 1
: > "$root/$SANDBOX_MARKER" || exit 1
trap 'sandbox_remove "$root"' EXIT
mkdir -p "$root/config" "$root/fixture" "$root/run/home" "$root/run/state/flea" "$root/run/cache" "$root/run/runtime" || exit 1
chmod 700 "$root/run/runtime" || exit 1
ln -s "$PWD/ui" "$root/config/flea" || exit 1
headless_commons "$root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$root/config/Ui" || exit 1
cp tests/gridresize.qml "$root/config/shell.qml" || exit 1
# Two thousand files: more than the held window at either width, so a far scroll lands past it.
for i in $(seq -w 1 2000); do printf 'row %s\n' "$i" > "$root/fixture/file-$i.txt"; done
printf '{"updates":{"autoCheck":false},"view":"list"}\n' > "$root/run/state/flea/ui.json" || exit 1
env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$root/run/home" XDG_STATE_HOME="$root/run/state" XDG_CACHE_HOME="$root/run/cache" XDG_RUNTIME_DIR="$root/run/runtime" \
    FLEA_BIN="$PWD/target/debug/flea" FLEA_GV_DIR="$root/fixture" FLEA_GV_ENTRIES=2000 FLEA_GR_CASE="$case_name" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 90 qs -p "$root/config" > "$root/probe.log" 2>&1
status=$?
grep -a 'GRIDRESIZE' "$root/probe.log" | tail -n 40
case_failed=0
[ "$status" -eq 0 ] || { printf 'FAIL gridresize %s: qs exit %s\n' "$case_name" "$status"; case_failed=1; }
[ "$(grep -ac 'GRIDRESIZE DONE .* checks, 0 failed' "$root/probe.log")" -eq 1 ] \
    || { printf 'FAIL gridresize %s: no single "GRIDRESIZE DONE ... 0 failed" line\n' "$case_name"; case_failed=1; }
errors=$(grep -aE 'TypeError|ReferenceError|Binding loop' "$root/probe.log" | head -5)
[ -z "$errors" ] || { printf 'FAIL gridresize %s: the probe log holds a TypeError, ReferenceError or binding loop line:\n%s\n' "$case_name" "$errors"; case_failed=1; }
[ "$case_failed" -eq 0 ] || failed=1
sandbox_remove "$root"
done
[ "$failed" -eq 0 ] || exit 1
echo 'gridresize: a Grid narrowed while scrolled, narrowed with no scroll, widened, or grown in height draws the row of every tile it shows'
