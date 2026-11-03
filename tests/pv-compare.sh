#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# The Compare overlay in the real Quick Look: stub answers draw the board's hunk and each refusal at the recipe's geometry, y and the button copy once, then the live backend answers real files in its jail. Offscreen, in the flea-ci image.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

for tool in qs bwrap prlimit diff; do
    command -v "$tool" >/dev/null || { echo "pv-compare.sh: $tool is not on PATH; this suite runs in the flea-ci image"; exit 1; }
done
bin=${FLEA_BIN:-$PWD/target/debug/flea}
[ -x "$bin" ] || { echo "pv-compare.sh: build the backend first: $bin"; exit 1; }
qs_bin=$(command -v qs)
timeout_bin=$(command -v timeout)
# The deadline for the harness, in seconds.
RUN_BOUND=120
# One byte past Compare's size gate, and the regular-file count in the marked fixture.
OVER_LIMIT_BYTES=1048577
MARKS_COUNT=5000

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-pv-compare-XXXXXX") || exit 1
case $test_root in
  /*/*) ;;
  *) echo "FAIL: mktemp -d gave '$test_root', which is not an absolute path two components deep"; exit 1 ;;
esac
: > "$test_root/$SANDBOX_MARKER" || exit 1
trap 'sandbox_remove "$test_root"' EXIT

fixture="$test_root/fixture"
mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" "$fixture" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
ln -s "$PWD/ui/boot/fleatab.qml" "$test_root/config/fleatab.qml" || exit 1
cp tests/pv-compare.qml "$test_root/config/shell.qml" || exit 1

# Twenty lines each; lines 12 to 17 differ, which is the board's hunk (@@ -9,12 +9,12 @@).
head_lines() { for i in 1 2 3 4 5 6 7 8; do printf 'Line %s of the notes.\n' "$i"; done; printf '## Previews\n\nEach kind asks for what it shows.\n'; }
tail_lines() { printf 'Only the visible lines are asked for.\nA newer request cancels an older one.\nThe frame runs to the column bottom.\n'; }
{ head_lines; printf 'Thumbnails never load on phones.\nThe map holds every row.\nA taller preview costs nothing.\nPorts keep their slots.\nMarks ship one size.\nFacts fold into two lines.\n'; tail_lines; } > "$fixture/notes-a.md"
{ head_lines; printf 'Thumbnails stay cache-only on phones.\nThe map holds the visible rows.\nA taller preview costs what a shorter one did.\nPorts keep their slots while scrolling.\nMarks share one optical size.\nFacts fold into one line.\n'; tail_lines; } > "$fixture/notes-b.md"
{ head_lines; tail_lines; } > "$fixture/same-a.md"
cp "$fixture/same-a.md" "$fixture/same-b.md"
printf 'PNG\0data\n' > "$fixture/shot-a.png"
printf 'PNG\0other\n' > "$fixture/shot-b.png"
yes 'a log line' | head -c "$OVER_LIMIT_BYTES" > "$fixture/dump-a.log"
yes 'a log line' | head -c "$OVER_LIMIT_BYTES" > "$fixture/dump-b.log"
printf 'caf\351\n' > "$fixture/latin1.md"
mkdir -p "$fixture/marks" "$test_root/state/flea" || exit 1
for ((i = 0; i < MARKS_COUNT; i++)); do printf 'row %s\n' "$i" > "$fixture/marks/$(printf 'f%04d.txt' "$i")"; done
ln -s f0000.txt "$fixture/marks/z-link-a" || exit 1
ln -s f4800.txt "$fixture/marks/z-link-b" || exit 1

harnesses="pv-compare pv-compare-menu"
[ "${PVCMP_MENU_ONLY:-0}" -ne 1 ] || harnesses="pv-compare-menu"
for harness in $harnesses; do
# The temporary harness derives its total from the regular files and two links.
sed -E "s/^([[:space:]]*readonly property int rowCount:).*/\1 $((MARKS_COUNT + 2))/" "tests/$harness.qml" > "$test_root/config/shell.qml" || exit 1
printf '{"view":"list","sidebar":false}\n' > "$test_root/state/flea/ui.json"
log="$test_root/$harness.log"
env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    XDG_CONFIG_HOME="$test_root/home/.config" XDG_CACHE_HOME="$test_root/home/.cache" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=16 QT_FORCE_STDERR_LOGGING=1 \
    FLEA_BIN="$bin" FLEA_PATH="$fixture/marks" PVCMP_DIR="$fixture" PVCMP_UI="$PWD/ui" \
    dbus-run-session -- /bin/bash -c 'exec "$1" "$2" "$3" -p "$4" > "$5" 2>&1' _ \
        "$timeout_bin" "$RUN_BOUND" "$qs_bin" "$test_root/config" "$log" 2> "$test_root/$harness-bus.log"
status=$?
# WindowBody's completed drain sends SIGTERM to its own shell, as in watch-views.sh.
bad_exit=0
[ "$status" -eq 0 ] || { [ "$harness" = pv-compare-menu ] && [ "$status" -eq 143 ]; } || bad_exit=1
# Sample input, the receipt: "  INFO qml: PVCMP DONE 60 checks, 0 failed".
done_count=$(grep -ac 'PVCMP DONE' "$log")
noisy=$(grep -aiE 'WARN|ERROR|TypeError|ReferenceError|is not a function|is not defined|Binding loop|Unable to assign|Cannot assign' "$log" \
    | grep -av 'does not support setting window masks' | grep -avF '$HYPRLAND_INSTANCE_SIGNATURE is unset. Cannot connect to hyprland.')
grep -a 'PVCMP' "$log"
if [ "$done_count" -ne 1 ] || grep -aq 'PVCMP FAIL' "$log" || [ "$bad_exit" -ne 0 ] || [ -n "$noisy" ]; then
    printf 'FAIL %s: qs exit %s, receipts %s\n' "$harness" "$status" "$done_count"
    [ -n "$noisy" ] && printf '%s\n' "$noisy"
    exit 1
fi
done
exit 0
