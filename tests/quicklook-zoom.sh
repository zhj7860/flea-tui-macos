#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# Quick Look's image zoom on the real Preview: + steps, one full decode, the band and knobs, a drag, 0, a move, a reopen, a small picture, an SVG and a failed SVG redraw, offscreen.
set -uo pipefail
. "$(dirname "$0")/../tools/flea-sandbox-guard"
. "$(dirname "$0")/qslog-gate.sh"
cd "$(dirname "$0")/.." || exit 1
for tool in qs ffmpeg; do
    command -v "$tool" >/dev/null || { printf 'FAIL quicklook-zoom: %s is required\n' "$tool"; exit 1; }
done
test_root="$FIXTURE_ROOT/flea-quicklook-zoom-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
mkdir -p "$test_root"/{config,fixture,home,state,cache,runtime} || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/quicklook-zoom.qml "$test_root/config/shell.qml" || exit 1
# Two pictures larger than the surface, one smaller than it, and a vector.
for spec in large.png:3000x2000 large2.png:2400x1600 small.png:120x68; do
    ffmpeg -y -f lavfi -i "testsrc=size=${spec#*:}" -frames:v 1 "$test_root/fixture/${spec%%:*}" >/dev/null 2>&1 \
        || { printf 'FAIL quicklook-zoom: ffmpeg could not make %s\n' "${spec%%:*}"; exit 1; }
done
cat > "$test_root/fixture/vector.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="400" height="300"><rect width="400" height="300" fill="#7aa2f7"/><circle cx="200" cy="150" r="80" fill="#e0af68"/></svg>
SVG
log="$test_root/run.log"
( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" QLZOOM_DIR="$test_root/fixture" FLEA_REDUCED_MOTION=1 \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
    timeout 90 qs -p "$test_root/config" > "$log" 2>&1 ) 2>/dev/null
status=$?
[ -z "${FLEA_CI_SUITE_LOGS:-}" ] || cp "$log" "$FLEA_CI_SUITE_LOGS/quicklook-zoom.log" 2>/dev/null
grep -a 'QLZOOM' "$log"
failures=0
qslog_crash quicklook-zoom "$log" || failures=$((failures + 1))
# The probe ends itself with SIGTERM after its one DONE line, so 143 is the owned exit.
if [ "$status" -ne 143 ] || [ "$(grep -ac 'QLZOOM DONE' "$log")" -ne 1 ] || [ "$(grep -ac 'QLZOOM PASS' "$log")" -ne 1 ] \
    || grep -aqE 'QLZOOM FAIL|TypeError|ReferenceError|Binding loop detected' "$log"; then
    printf 'FAIL quicklook-zoom: the run did not hold (qs exit %s)\n' "$status"
    grep -aE 'TypeError|ReferenceError|Binding loop detected' "$log" | head -5
    failures=$((failures + 1))
fi
printf 'quicklook-zoom: %s failed\n' "$failures"
[ "$failures" -eq 0 ]
