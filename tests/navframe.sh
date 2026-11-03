#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# Enter and Back draw no frame and dirty no item before the landing in List, Columns and Grid, offscreen with the real backend.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
command -v qs >/dev/null || { echo 'FAIL navframe: qs is missing'; exit 1; }
root=$(mktemp -d "$FIXTURE_ROOT/navframe-XXXXXXXX") || exit 1
sandbox_require "$root" || exit 1
: > "$root/$SANDBOX_MARKER" || exit 1
trap 'sandbox_remove "$root"' EXIT
mkdir -p "$root/config" "$root/fixture/a" "$root/fixture/e" "$root/bin" || exit 1
ln -s "$PWD/ui" "$root/config/flea" || exit 1
headless_commons "$root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$root/config/Ui" || exit 1
cp tests/navframe.qml "$root/config/shell.qml" || exit 1
# Eighty files make the rows scroll, a holds three, e is empty: 82 entries at the top.
for i in $(seq -w 1 80); do printf 'row %s\n' "$i" > "$root/fixture/file-$i.txt"; done
for i in 1 2 3; do printf 'a %s\n' "$i" > "$root/fixture/a/inner-$i.txt"; done
# The backend writes its own pid before it starts, so the probe can pause it while a listing is out.
printf '#!/bin/sh\n[ "$1" = --backend ] && echo $$ > "%s"\nexec "%s" "$@"\n' "$root/backend.pid" "$PWD/target/debug/flea" > "$root/bin/flea"
chmod +x "$root/bin/flea" || exit 1
failed=0
for view in list columns grid; do
    run="$root/run-$view"
    # An earlier view's pid must not be signalled when this view's backend never writes its own.
    : > "$root/backend.pid" || exit 1
    mkdir -p "$run/home" "$run/state/flea" "$run/cache" "$run/runtime" || exit 1
    chmod 700 "$run/runtime" || exit 1
    printf '{"updates":{"autoCheck":false},"view":"%s"}\n' "$view" > "$run/state/flea/ui.json" || exit 1
    env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$run/home" XDG_STATE_HOME="$run/state" XDG_CACHE_HOME="$run/cache" XDG_RUNTIME_DIR="$run/runtime" \
        FLEA_BIN="$root/bin/flea" FLEA_NAVFRAME_DIR="$root/fixture" FLEA_NAVFRAME_PID="$root/backend.pid" \
        FLEA_NAVFRAME_VIEW="$view" FLEA_NAVFRAME_ENTRIES=82 QT_LOGGING_RULES='qt.quick.dirty.debug=true' \
        QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
        timeout 40 qs -p "$root/config" > "$run/probe.log" 2>&1
    status=$?
    # A paused backend left behind by a failed probe is resumed so the timeout can end it.
    [ -s "$root/backend.pid" ] && kill -CONT "$(cat "$root/backend.pid")" 2>/dev/null
    # The probe's own lines, without the dirty-item trace, which only the check below reads.
    grep -v 'qt\.quick\.dirty' "$run/probe.log" | tail -n 60
    [ "$status" -eq 0 ] || { printf 'FAIL navframe %s: qs exit %s\n' "$view" "$status"; failed=1; }
    # Sample input: " DEBUG qml: NAVFRAME DONE list 31 checks, 0 failed"
    [ "$(grep -c "NAVFRAME DONE $view .* checks, 0 failed" "$run/probe.log")" -eq 1 ] \
        || { printf 'FAIL navframe %s: no single "NAVFRAME DONE ... 0 failed" line\n' "$view"; failed=1; }
    grep -qE 'TypeError|ReferenceError|Binding loop' "$run/probe.log" \
        && { printf 'FAIL navframe %s: the probe log holds a TypeError, ReferenceError or binding loop line\n' "$view"; failed=1; }
    # A run whose dirty category logged nothing would pass the window check below unseen.
    [ "$(grep -c 'qt\.quick\.dirty' "$run/probe.log")" -gt 0 ] \
        || { printf 'FAIL navframe %s: qt.quick.dirty logged no line in the whole run\n' "$view"; failed=1; }
    # Sample input: "NAVFRAME KEY list enter", " DEBUG qt.quick.dirty:    QSGNode: QQuickMouseArea(...) Content", "NAVFRAME HELD list enter".
    dirty=$(sed -n '/NAVFRAME KEY /,/NAVFRAME HELD /p' "$run/probe.log" | grep 'qt\.quick\.dirty' | head -5)
    [ -z "$dirty" ] || { printf 'FAIL navframe %s: items went dirty between a key and its landing:\n%s\n' "$view" "$dirty"; failed=1; }
    [ "$(grep -c 'NAVFRAME KEY ' "$run/probe.log")" -eq 2 ] \
        || { printf 'FAIL navframe %s: the probe measured %s keys, not 2\n' "$view" "$(grep -c 'NAVFRAME KEY ' "$run/probe.log")"; failed=1; }
done
[ "$failed" -eq 0 ] || exit 1
echo 'navframe: Enter and Back draw no frame before the landing in three views, and the listing gate still refuses input'
