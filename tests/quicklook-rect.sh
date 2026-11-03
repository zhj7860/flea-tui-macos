#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# Quick Look takes the window's height for tall content: code, a PDF and a portrait picture open at their rect on the first revealed frame, and no shown surface resizes.
set -uo pipefail
. "$(dirname "$0")/../tools/flea-sandbox-guard"
. "$(dirname "$0")/qslog-gate.sh"
cd "$(dirname "$0")/.." || exit 1
for tool in qs dbus-run-session ffmpeg; do
    command -v "$tool" >/dev/null || { printf 'FAIL quicklook-rect: %s is required\n' "$tool"; exit 1; }
done
test_root="$FIXTURE_ROOT/flea-quicklook-rect-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
mkdir -p "$test_root"/{config,fixture,home,state/flea,cache,runtime} || exit 1
chmod 700 "$test_root/runtime" || exit 1
printf '{}\n' > "$test_root/state/flea/ui.json"
headless_commons "$test_root" || exit 1
ln -s "$(readlink -m ui/boot/Ui)" "$test_root/config/Ui" || exit 1
ln -s "$test_root/config/flea/boot/fleatab.qml" "$test_root/config/fleatab.qml" || exit 1
cp -a ui "$test_root/config/flea" || exit 1
cp tests/quicklook-rect.qml "$test_root/config/shell.qml" || exit 1
# Code, two 12-page A4 PDFs (595 x 842 points), a landscape screenshot, a third such PDF, a portrait phone screenshot and a portrait shorter than the tall rect; the names sort in this order.
printf 'fn main() {\n    println!("tall");\n}\n' > "$test_root/fixture/a-main.rs"
for name in b-doc.pdf b-docs.pdf c-tall.pdf; do
    {
        printf '%%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Count 12/Kids['
        for page in {3..14}; do printf '%d 0 R ' "$page"; done
        printf ']>>endobj\n'
        for page in {3..14}; do printf '%d 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 595 842]>>endobj\n' "$page"; done
        printf 'trailer<</Root 1 0 R/Size 15>>\n%%%%EOF\n'
    } > "$test_root/fixture/$name"
done
for spec in c-land.jpg:1600x1200 d-portrait.png:1170x2532 e-small.png:200x400; do
    ffmpeg -y -f lavfi -i "testsrc=size=${spec#*:}" -frames:v 1 "$test_root/fixture/${spec%%:*}" >/dev/null 2>&1 \
        || { printf 'FAIL quicklook-rect: ffmpeg could not make %s\n' "${spec%%:*}"; exit 1; }
done
log="$test_root/run.log"
( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u QML_DISABLE_DISK_CACHE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" FLEA_BIN="$PWD/target/debug/flea" FLEA_PATH="$test_root/fixture" \
    FLEA_REDUCED_MOTION=1 QLRECT_UI="$test_root/config/flea" QLRECT_DIR="$test_root/fixture" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
    dbus-run-session -- bash -c 'timeout 120 qs -p "$1" > "$2" 2>&1' _ "$test_root/config" "$log" 2> "$test_root/bus.log" ) 2>/dev/null
status=$?
[ -z "${FLEA_CI_SUITE_LOGS:-}" ] || cp "$log" "$FLEA_CI_SUITE_LOGS/quicklook-rect.log" 2>/dev/null
grep -a 'QLRECT' "$log"
failures=0
qslog_crash quicklook-rect "$log" || failures=$((failures + 1))
# The probe ends itself with SIGTERM after its one DONE line, so 143 is the owned exit.
if [ "$status" -ne 143 ] || [ "$(grep -ac 'QLRECT DONE' "$log")" -ne 1 ] || [ "$(grep -ac 'QLRECT PASS' "$log")" -ne 1 ] \
    || grep -aqE 'QLRECT FAIL|TypeError|ReferenceError|Binding loop detected' "$log"; then
    printf 'FAIL quicklook-rect: the run did not hold (qs exit %s)\n' "$status"
    grep -aE 'TypeError|ReferenceError|Binding loop detected' "$log" | head -5
    failures=$((failures + 1))
fi
printf 'quicklook-rect: %s failed\n' "$failures"
[ "$failures" -eq 0 ]
