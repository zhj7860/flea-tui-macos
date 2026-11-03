#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# The first Space on a PDF, a clip, a picture or a text file compiles nothing: the kind's unit and Quick Look's own were held ready while the cursor rested, and a window that never rests on a kind never holds its unit.
set -uo pipefail
. "$(dirname "$0")/../tools/flea-sandbox-guard"
. "$(dirname "$0")/qslog-gate.sh"
cd "$(dirname "$0")/.." || exit 1
for tool in qs dbus-run-session ffmpeg python3; do
    command -v "$tool" >/dev/null || { printf 'FAIL quicklook-firstkind: %s is required\n' "$tool"; exit 1; }
done
test_root="$FIXTURE_ROOT/flea-quicklook-firstkind-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
mkdir -p "$test_root"/{config,fixture/mixed/a-dir,fixture/filesonly} || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -m ui/boot/Ui)" "$test_root/config/Ui" || exit 1
ln -s "$test_root/config/flea/boot/fleatab.qml" "$test_root/config/fleatab.qml" || exit 1
cp -a ui "$test_root/config/flea" || exit 1
cp tests/quicklook-firstkind.qml "$test_root/config/shell.qml" || exit 1
mixed="$test_root/fixture/mixed"
# One folder holding every kind, a folder first so the launch rests on no file; the legs land on one kind and the rest stay unrested.
seq -f 'line %g of the notes' 40 > "$mixed/b-notes.txt" || exit 1
ffmpeg -y -f lavfi -i "testsrc=size=160x120" -frames:v 1 "$mixed/c-pic.png" >/dev/null 2>&1 \
    || { printf 'FAIL quicklook-firstkind: ffmpeg could not make c-pic.png\n'; exit 1; }
ffmpeg -y -f lavfi -i "testsrc=size=320x240" -frames:v 1 "$test_root/page.jpg" >/dev/null 2>&1 \
    || { printf 'FAIL quicklook-firstkind: ffmpeg could not make page.jpg\n'; exit 1; }
python3 -I tests/quicklook-hold-pdf.py "$test_root/page.jpg" "$mixed/d-doc.pdf" \
    || { printf 'FAIL quicklook-firstkind: could not make d-doc.pdf\n'; exit 1; }
ffmpeg -y -f lavfi -i "testsrc=size=160x120:rate=10" -t 1 -pix_fmt yuv420p "$mixed/e-clip.mp4" >/dev/null 2>&1 \
    || { printf 'FAIL quicklook-firstkind: ffmpeg could not make e-clip.mp4\n'; exit 1; }
python3 -I -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1], "w").writestr("note.txt", "a note")' "$mixed/f-pack.zip" || exit 1
# A folder of two files, so a launch rests the cursor on a file with no key pressed.
printf 'a note\n' > "$test_root/fixture/filesonly/a-notes.txt"
cp "$mixed/c-pic.png" "$test_root/fixture/filesonly/b-pic.png" || exit 1
failures=0
legs=0
# run_leg LEG DIR FIRST TOTAL OPEN STEPS: one fresh qs process over the steps "name|unit,..."; a unit of "" is a file Quick Look holds nothing for.
run_leg() {
    local leg=$1 dir=$2 first=$3 total=$4 open=$5 steps=$6
    local leg_root="$test_root/$leg" log="$test_root/$leg/run.log" status
    mkdir -p "$leg_root"/{home,state/flea,cache,runtime} || exit 1
    chmod 700 "$leg_root/runtime" || exit 1
    printf '{}\n' > "$leg_root/state/flea/ui.json"
    ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u QML_DISABLE_DISK_CACHE \
        HOME="$leg_root/home" XDG_STATE_HOME="$leg_root/state" XDG_CACHE_HOME="$leg_root/cache" \
        XDG_RUNTIME_DIR="$leg_root/runtime" FLEA_BIN="${QLFK_BIN:-$PWD/target/debug/flea}" FLEA_PATH="$test_root/fixture/$dir" \
        QLFK_UI="$test_root/config/flea" QLFK_LEG="$leg" QLFK_FIRST="$first" QLFK_TOTAL="$total" QLFK_OPEN="$open" QLFK_STEPS="$steps" \
        QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 QT_LOGGING_RULES="$(qslog_rules "qt.qml.diskcache.debug=true")" \
        dbus-run-session -- bash -c 'timeout 120 qs -p "$1" > "$2" 2>&1' _ "$test_root/config" "$log" 2> "$leg_root/bus.log" ) 2>/dev/null
    status=$?
    legs=$((legs + 1))
    [ -z "${FLEA_CI_SUITE_LOGS:-}" ] || cp "$log" "$FLEA_CI_SUITE_LOGS/quicklook-firstkind-$leg.log" 2>/dev/null
    # Sample input, one probe line: "  INFO qml: QLFK REST pdf step=1 d-doc.pdf unit=PdfViewer.qml held=PdfViewer.qml base=true libs=libQt6Pdf.so pss=61234 objects=700".
    grep -a 'QLFK \(LAUNCH\|IDLE\|MOVE\|REST\|KEY\|KEYRETURNED\|CAP\|OPENED\|COST\|FAIL\|DONE\)' "$log" | sed 's/\x1b\[[0-9;]*m//g; s/^.*QLFK /QLFK /' | sed "s/^/$leg: /"
    if ! qslog_nullptr "quicklook-firstkind $leg" < "$log"; then
        failures=$((failures + 1))
    fi
    if ! qslog_crash "quicklook-firstkind $leg" "$log"; then
        failures=$((failures + 1))
    fi
    if [ "$status" -ne 0 ] || [ "$(grep -ac 'QLFK DONE' "$log")" -ne 1 ] || grep -aqE 'QLFK FAIL|TypeError|ReferenceError|Binding loop detected' "$log"; then
        printf 'FAIL quicklook-firstkind: %s leg did not hold (qs exit %s)\n' "$leg" "$status"
        grep -aE 'TypeError|ReferenceError|Binding loop detected' "$log" | head -3
        failures=$((failures + 1))
    fi
    # A leg that opens Quick Look: every unit compiled before the key, none between the key and the card's reveal.
    if [ "$open" = 1 ]; then
        local clean unit before inside
        clean=$(sed 's/\x1b\[[0-9;]*m//g' "$log")
        unit=${steps##*|}
        before=$(sed -n '1,/QLFK KEY /p' <<< "$clean" | grep -a 'from disk cache' | sed 's/.*Error loading \(.*\) from disk cache.*/\1/')
        inside=$(sed -n '/QLFK KEY /,/QLFK OPENED /p' <<< "$clean" | grep -a 'from disk cache' | sed 's/.*Error loading \(.*\) from disk cache.*/\1/')
        if [ -z "$before" ]; then
            printf 'FAIL quicklook-firstkind: %s leg has no compile trace before the key, so a silent log proves nothing\n' "$leg"
            failures=$((failures + 1))
        elif ! grep -aq "/$unit" <<< "$before"; then
            printf 'FAIL quicklook-firstkind: %s leg never compiled %s before the key\n' "$leg" "$unit"
            failures=$((failures + 1))
        fi
        if [ -n "$inside" ]; then
            printf 'FAIL quicklook-firstkind: %s leg compiled inside the first open: %s\n' "$leg" "$(printf '%s' "$inside" | tr '\n' ' ')"
            failures=$((failures + 1))
        fi
    fi
}
run_leg launch filesonly a-notes.txt 2 0 ""
run_leg text mixed a-dir 6 1 "b-notes.txt|PreviewText.qml"
run_leg image mixed a-dir 6 1 "c-pic.png|PreviewImage.qml"
run_leg pdf mixed a-dir 6 1 "d-doc.pdf|PdfViewer.qml"
run_leg video mixed a-dir 6 1 "e-clip.mp4|PreviewMedia.qml"
run_leg nounit mixed a-dir 6 0 "f-pack.zip|"
run_leg all mixed a-dir 6 1 "b-notes.txt|PreviewText.qml,c-pic.png|PreviewImage.qml,d-doc.pdf|PdfViewer.qml,e-clip.mp4|PreviewMedia.qml"
printf 'quicklook-firstkind: %s legs, %s failed\n' "$legs" "$failures"
[ "$failures" -eq 0 ]
