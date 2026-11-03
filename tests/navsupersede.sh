#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# A navigation made while a listing is out is taken, not refused: the newest folder lands, the folder let go never draws, offscreen with the real backend.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
command -v qs >/dev/null || { echo 'FAIL navsupersede: qs is missing'; exit 1; }
root=$(mktemp -d "$FIXTURE_ROOT/navsupersede-XXXXXXXX") || exit 1
sandbox_require "$root" || exit 1
: > "$root/$SANDBOX_MARKER" || exit 1
trap 'sandbox_remove "$root"' EXIT
mkdir -p "$root/config" "$root/fixture/a" "$root/fixture/b" "$root/bin" || exit 1
ln -s "$PWD/ui" "$root/config/flea" || exit 1
headless_commons "$root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$root/config/Ui" || exit 1
cp tests/navsupersede.qml "$root/config/shell.qml" || exit 1
# Six files and two folders make eight entries in the start folder; a and b hold three files each under names no other folder has.
for i in 1 2 3 4 5 6; do printf 'row %s\n' "$i" > "$root/fixture/file-$i.txt"; done
for i in 1 2 3; do printf 'a %s\n' "$i" > "$root/fixture/a/inner-a-$i.txt"; printf 'b %s\n' "$i" > "$root/fixture/b/inner-b-$i.txt"; done
# The backend writes its own pid before it starts, so the probe can pause it while a listing is out.
printf '#!/bin/sh\n[ "$1" = --backend ] && echo $$ > "%s"\nexec "%s" "$@"\n' "$root/backend.pid" "$PWD/target/debug/flea" > "$root/bin/flea"
chmod +x "$root/bin/flea" || exit 1
run="$root/run"
mkdir -p "$run/home" "$run/state/flea" "$run/cache" "$run/runtime" || exit 1
chmod 700 "$run/runtime" || exit 1
printf '{"updates":{"autoCheck":false},"view":"list"}\n' > "$run/state/flea/ui.json" || exit 1
env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$run/home" XDG_STATE_HOME="$run/state" XDG_CACHE_HOME="$run/cache" XDG_RUNTIME_DIR="$run/runtime" \
    FLEA_BIN="$root/bin/flea" FLEA_NAVSUPERSEDE_DIR="$root/fixture" FLEA_NAVSUPERSEDE_PID="$root/backend.pid" \
    FLEA_NAVSUPERSEDE_ENTRIES=8 \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 40 qs -p "$root/config" > "$run/probe.log" 2>&1
status=$?
# A paused backend left behind by a failed probe is resumed so the timeout can end it.
[ -s "$root/backend.pid" ] && kill -CONT "$(cat "$root/backend.pid")" 2>/dev/null
tail -n 60 "$run/probe.log"
failed=0
[ "$status" -eq 0 ] || { printf 'FAIL navsupersede: qs exit %s\n' "$status"; failed=1; }
# Sample input: " DEBUG qml: NAVSUPERSEDE DONE 24 checks, 0 failed"
[ "$(grep -c 'NAVSUPERSEDE DONE .* checks, 0 failed' "$run/probe.log")" -eq 1 ] \
    || { echo 'FAIL navsupersede: no single "NAVSUPERSEDE DONE ... 0 failed" line'; failed=1; }
grep -qE 'TypeError|ReferenceError|Binding loop' "$run/probe.log" \
    && { echo 'FAIL navsupersede: the probe log holds a TypeError, ReferenceError or binding loop line'; failed=1; }
[ "$failed" -eq 0 ] || exit 1
echo 'navsupersede: a second folder asked for while a listing is out is taken, lands alone, and Back skips the one that never landed'
