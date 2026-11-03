#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# A camera RAW in Quick Look and the column, offscreen: the picture is the embedded copy, the caption reads its pixels, only at fit and only over a RAW, and a RAW with no preview is the unreadable state.
set -uo pipefail
. "$(dirname "$0")/../tools/flea-sandbox-guard"
. "$(dirname "$0")/qslog-gate.sh"
cd "$(dirname "$0")/.." || exit 1
for tool in qs ffmpeg; do
    command -v "$tool" >/dev/null || { printf 'FAIL preview-raw: %s is required\n' "$tool"; exit 1; }
done
test_root="$FIXTURE_ROOT/flea-preview-raw-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
mkdir -p "$test_root"/{config,fixture,home,state,cache,runtime} || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/preview-raw.qml "$test_root/config/shell.qml" || exit 1
# The embedded preview is a 1620x1080 JPEG, and the listing holds RAW-named files beside a JPEG; the stub backend names the preview for the RAW rows.
for spec in preview.jpg:1620x1080 c.jpg:800x600; do
    ffmpeg -y -f lavfi -i "testsrc=size=${spec#*:}" -frames:v 1 "$test_root/fixture/${spec%%:*}" >/dev/null 2>&1 \
        || { printf 'FAIL preview-raw: ffmpeg could not make %s\n' "${spec%%:*}"; exit 1; }
done
for name in a.cr2 b.nef d.dng; do printf 'II*\0\10\0\0\0\0\0\0\0\0\0' > "$test_root/fixture/$name"; done
log="$test_root/run.log"
( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" PVRAW_DIR="$test_root/fixture" FLEA_REDUCED_MOTION=1 \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
    timeout 90 qs -p "$test_root/config" > "$log" 2>&1 ) 2>/dev/null
status=$?
[ -z "${FLEA_CI_SUITE_LOGS:-}" ] || cp "$log" "$FLEA_CI_SUITE_LOGS/preview-raw.log" 2>/dev/null
grep -a 'PVRAW' "$log"
failures=0
qslog_crash preview-raw "$log" || failures=$((failures + 1))
# The probe ends itself with SIGTERM after its one DONE line, so 143 is the owned exit.
if [ "$status" -ne 143 ] || [ "$(grep -ac 'PVRAW DONE' "$log")" -ne 1 ] || [ "$(grep -ac 'PVRAW PASS' "$log")" -ne 1 ] \
    || grep -aqE 'PVRAW FAIL|TypeError|ReferenceError|Binding loop detected' "$log"; then
    printf 'FAIL preview-raw: the run did not hold (qs exit %s)\n' "$status"
    grep -aE 'TypeError|ReferenceError|Binding loop detected' "$log" | head -5
    failures=$((failures + 1))
fi
printf 'preview-raw: %s failed\n' "$failures"
[ "$failures" -eq 0 ]
