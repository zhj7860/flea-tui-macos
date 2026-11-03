#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# Quick Look's hold, between Space and the card's first frame: a press, the wheel, a move, a reopen in the close fade, a stalled show() and a press on text and a PDF.
set -uo pipefail
. "$(dirname "$0")/../tools/flea-sandbox-guard"
. "$(dirname "$0")/qslog-gate.sh"
cd "$(dirname "$0")/.." || exit 1
for tool in qs dbus-run-session ffmpeg python3; do
    command -v "$tool" >/dev/null || { printf 'FAIL quicklook-hold: %s is required\n' "$tool"; exit 1; }
done
test_root="$FIXTURE_ROOT/flea-quicklook-hold-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
mkdir -p "$test_root"/{config,fixture,home,state/flea,cache,runtime} || exit 1
chmod 700 "$test_root/runtime" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -m ui/boot/Ui)" "$test_root/config/Ui" || exit 1
ln -s "$test_root/config/flea/boot/fleatab.qml" "$test_root/config/fleatab.qml" || exit 1
cp -a ui "$test_root/config/flea" || exit 1
cp tests/quicklook-hold.qml "$test_root/config/shell.qml" || exit 1
# A picture whose decode starts only once show() returns and takes a few ms, far inside the cap counted from there.
ffmpeg -y -f lavfi -i "testsrc=size=1600x1200" -frames:v 1 "$test_root/fixture/b-mid.jpg" >/dev/null 2>&1 \
    || { printf 'FAIL quicklook-hold: ffmpeg could not make b-mid.jpg\n'; exit 1; }
# Two 8000x8000 pictures decode for far longer than the cap; Quick Look draws its own decode uncached, so a reopen waits again.
for name in d-large.png e-large.png; do
    ffmpeg -y -f lavfi -i "testsrc=size=8000x8000" -frames:v 1 "$test_root/fixture/$name" >/dev/null 2>&1 \
        || { printf 'FAIL quicklook-hold: ffmpeg could not make %s\n' "$name"; exit 1; }
done
# Other kinds for a press during the hold: text that loads off the GUI thread, and a PDF whose page renders for a while.
seq -f 'line %g of the notes' 20000 > "$test_root/fixture/f-notes.txt" || exit 1
ffmpeg -y -f lavfi -i "testsrc=size=3000x4000" -frames:v 1 "$test_root/page.jpg" >/dev/null 2>&1 \
    || { printf 'FAIL quicklook-hold: ffmpeg could not make page.jpg\n'; exit 1; }
python3 -I tests/quicklook-hold-pdf.py "$test_root/page.jpg" "$test_root/fixture/h-page.pdf" \
    || { printf 'FAIL quicklook-hold: could not make h-page.pdf\n'; exit 1; }
# Thumbnails off, so no cached interim lets a picture land early.
printf '{"preview":{"thumbnails":"off"}}\n' > "$test_root/state/flea/ui.json"
log="$test_root/run.log"
( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" FLEA_BIN="$PWD/target/debug/flea" FLEA_PATH="$test_root/fixture" \
    FLEA_REDUCED_MOTION="" QLHOLD_UI="$test_root/config/flea" QLHOLD_DIR="$test_root/fixture" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
    QT_LOGGING_RULES="$(qslog_rules)" \
    dbus-run-session -- bash -c 'timeout 120 qs -p "$1" > "$2" 2>&1' _ "$test_root/config" "$log" 2> "$test_root/bus.log" ) 2>/dev/null
status=$?
[ -z "${FLEA_CI_SUITE_LOGS:-}" ] || cp "$log" "$FLEA_CI_SUITE_LOGS/quicklook-hold.log" 2>/dev/null
grep -a 'QLHOLD \(STEP\|FAIL\|DONE\)' "$log"
failures=0
qslog_nullptr quicklook-hold < "$log" || failures=$((failures + 1))
qslog_crash quicklook-hold "$log" || failures=$((failures + 1))
if [ "$status" -ne 0 ] || [ "$(grep -ac 'QLHOLD DONE' "$log")" -ne 1 ] || grep -aqE 'QLHOLD FAIL|TypeError|ReferenceError|Binding loop detected' "$log"; then
    printf 'FAIL quicklook-hold: the run did not hold (qs exit %s)\n' "$status"
    grep -aE 'TypeError|ReferenceError|Binding loop detected' "$log" | head -3
    failures=$((failures + 1))
fi
printf 'quicklook-hold: %s failed\n' "$failures"
[ "$failures" -eq 0 ]
