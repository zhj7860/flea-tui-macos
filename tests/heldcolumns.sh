#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# A listing held past the wait reads loading, then waiting, then lands whole in Columns, offscreen with the real backend behind a holding proxy; it runs once at the shipped limit 3, and ui:cap_heldcolumns shoots limits 2 to 5.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
command -v qs >/dev/null || { echo 'FAIL heldcolumns: qs is missing'; exit 1; }
[ -x target/debug/flea ] || { echo 'FAIL heldcolumns: no target/debug/flea'; exit 1; }
root=$(mktemp -d "$FIXTURE_ROOT/heldcolumns-XXXXXXXX") || exit 1
sandbox_require "$root" || exit 1
: > "$root/$SANDBOX_MARKER" || exit 1
trap 'sandbox_remove "$root"' EXIT
mkdir -p "$root/config" "$root/fixture" "$root/bin" || exit 1
ln -s "$PWD/ui" "$root/config/flea" || exit 1
headless_commons "$root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$root/config/Ui" || exit 1
cp tests/heldcolumns.qml "$root/config/shell.qml" || exit 1
: > "$root/fixture/one.txt"; : > "$root/fixture/two.txt"
# The proxy is the one tests/ui.sh writes for the native case, so both hold a listing the same way.
sed -n '/^hanglisting_write_proxy() {/,/^EOS$/p' tests/ui.sh | sed '1,3d;$d' > "$root/bin/flea" || exit 1
head -n 1 "$root/bin/flea" | grep -q '^#!/usr/bin/env python3$' || { echo 'FAIL heldcolumns: the held-listing proxy was not read from tests/ui.sh'; exit 1; }
chmod +x "$root/bin/flea" || exit 1
failed=0
# The native case proves its reading shot is a loading shot by a live answer with no seam on each side of it, so both reads have to stay in it, in order, inside the case function.
body=$(sed -n '/^case_cap_heldcolumns() {/,/^}/p' tests/ui-captures-states.sh)
line_of() { grep -n -m1 -F -- "$1" <<<"$body" | cut -d: -f1; }
before=$(line_of 'heldcolumns_expect_loading "$n" "before its reading shot"') shot=$(line_of 'shot "heldcolumns-$n-reading"') after=$(line_of 'heldcolumns_expect_loading "$n" "after its reading shot"')
[ -n "$before" ] && [ -n "$shot" ] && [ -n "$after" ] && [ "$before" -lt "$shot" ] && [ "$shot" -lt "$after" ] \
    || { echo 'FAIL heldcolumns: ui:cap_heldcolumns lost its loading reads on each side of the reading shot'; failed=1; }
n=3
run="$root/run$n"
mkdir -p "$run/home" "$run/state/flea" "$run/cache" "$run/runtime" || exit 1
chmod 700 "$run/runtime" || exit 1
printf '{"updates":{"autoCheck":false},"view":"columns","columnsLimit":%s}\n' "$n" > "$run/state/flea/ui.json" || exit 1
env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$run/home" XDG_STATE_HOME="$run/state" XDG_CACHE_HOME="$run/cache" XDG_RUNTIME_DIR="$run/runtime" \
    FLEA_BIN="$root/bin/flea" FLEA_HANGLISTING_REAL="$PWD/target/debug/flea" FLEA_HANGLISTING_DELAY=12 \
    FLEA_HANGLISTING_MARKER="$root/held-$n" HELD_DIR="$root/fixture" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 40 qs -p "$root/config" > "$run/probe.log" 2>&1
status=$?
# Sample input: " DEBUG qml: HELDCOLUMNS DONE 5 checks, 0 failed"
grep -a -E 'HELDCOLUMNS (ok|FAIL|DONE)' "$run/probe.log" | sed 's/^.*qml: //'
[ "$status" -eq 0 ] || { printf 'FAIL heldcolumns: limit %s qs exit %s\n' "$n" "$status"; failed=1; }
[ "$(grep -c 'HELDCOLUMNS DONE .* checks, 0 failed' "$run/probe.log")" -eq 1 ] \
    || { printf 'FAIL heldcolumns: limit %s has no single "HELDCOLUMNS DONE ... 0 failed" line\n' "$n"; failed=1; }
grep -qE 'TypeError|ReferenceError|Binding loop' "$run/probe.log" \
    && { printf 'FAIL heldcolumns: limit %s logged a TypeError, ReferenceError or binding loop\n' "$n"; failed=1; }
[ "$failed" -eq 0 ] || exit 1
echo 'heldcolumns: a held Columns listing reads loading, waiting, then lands whole'
