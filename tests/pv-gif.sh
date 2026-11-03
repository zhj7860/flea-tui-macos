#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# An animated GIF in the Columns preview frame and Quick Look's image pane: the still first, the moving layer only for a GIF with frames and only after it, paused when covered or hidden, gone with the file; offscreen.
set -uo pipefail
. "$(dirname "$0")/../tools/flea-sandbox-guard"
. "$(dirname "$0")/qslog-gate.sh"
cd "$(dirname "$0")/.." || exit 1
for tool in qs ffmpeg; do
    command -v "$tool" >/dev/null || { printf 'FAIL pv-gif: %s is required\n' "$tool"; exit 1; }
done
test_root="$FIXTURE_ROOT/flea-pv-gif-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
mkdir -p "$test_root"/{config,fixture,home,state,cache,runtime} || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/pv-gif.qml "$test_root/config/shell.qml" || exit 1
fx="$test_root/fixture"
# A 24-frame GIF and a copy of it, a one-frame GIF, a PNG, and the first frame of each as the cache's still.
ffmpeg -y -nostdin -loglevel error -f lavfi -i testsrc=size=160x90:rate=12 -frames:v 24 "$fx/clip.gif" \
    && cp "$fx/clip.gif" "$fx/clip2.gif" \
    && ffmpeg -y -nostdin -loglevel error -f lavfi -i testsrc=size=160x90 -frames:v 1 "$fx/still.gif" \
    && ffmpeg -y -nostdin -loglevel error -f lavfi -i testsrc=size=160x90 -frames:v 1 "$fx/shot.png" \
    && ffmpeg -y -nostdin -loglevel error -i "$fx/clip.gif" -frames:v 1 "$fx/clip.png" \
    && ffmpeg -y -nostdin -loglevel error -i "$fx/still.gif" -frames:v 1 "$fx/still.png" \
    || { printf 'FAIL pv-gif: ffmpeg could not make the fixtures\n'; exit 1; }
log="$test_root/run.log"
( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" PVGIF_DIR="$fx" FLEA_REDUCED_MOTION=1 \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
    timeout 60 qs -p "$test_root/config" > "$log" 2>&1 ) 2>/dev/null
status=$?
[ -z "${FLEA_CI_SUITE_LOGS:-}" ] || cp "$log" "$FLEA_CI_SUITE_LOGS/pv-gif.log" 2>/dev/null
grep -a 'PVGIF' "$log"
failures=0
qslog_crash pv-gif "$log" || failures=$((failures + 1))
# The probe ends itself with SIGTERM after its one DONE line, so 143 is the owned exit.
if [ "$status" -ne 143 ] || [ "$(grep -ac 'PVGIF DONE' "$log")" -ne 1 ] || [ "$(grep -ac 'PVGIF PASS' "$log")" -ne 1 ] \
    || grep -aqE 'PVGIF FAIL|TypeError|ReferenceError|Binding loop detected' "$log"; then
    printf 'FAIL pv-gif: the run did not hold (qs exit %s)\n' "$status"
    grep -aE 'TypeError|ReferenceError|Binding loop detected' "$log" | head -5
    failures=$((failures + 1))
fi
printf 'pv-gif: %s failed\n' "$failures"
[ "$failures" -eq 0 ]
