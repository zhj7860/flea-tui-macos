#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# Quick Look on code and text over the real backend and bat: the bar, the gutter, w and its memory, the binary and too-large frames. Offscreen, in the flea-ci image.
set -uo pipefail
. "$(dirname "$0")/../tools/flea-sandbox-guard"
. "$(dirname "$0")/qslog-gate.sh"
cd "$(dirname "$0")/.." || exit 1
for tool in qs bat dbus-run-session; do
    command -v "$tool" >/dev/null || { printf 'FAIL quicklook-code: %s is required; this suite runs in the flea-ci image\n' "$tool"; exit 1; }
done
bin=${FLEA_BIN:-$PWD/target/debug/flea}
[ -x "$bin" ] || { printf 'FAIL quicklook-code: build the backend first: %s\n' "$bin"; exit 1; }
test_root="$FIXTURE_ROOT/flea-quicklook-code-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
mkdir -p "$test_root"/{config,fixture,home,state/flea,cache,runtime} || exit 1
chmod 700 "$test_root/runtime" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -m ui/boot/Ui)" "$test_root/config/Ui" || exit 1
ln -s "$test_root/config/flea/boot/fleatab.qml" "$test_root/config/fleatab.qml" || exit 1
cp -a ui "$test_root/config/flea" || exit 1
cp tests/quicklook-code-defaults.qml "$test_root/config/shell.qml" || exit 1
mkdir -p "$test_root/defaults-state/flea" || exit 1

# Read absent wrap through the actual singleton, before the full suite's navigation writes defaults.
defaults_probe() {
    local mode=$1 label=$2 log="$test_root/defaults-$2.log" status
    case "$mode" in
        empty) printf '{}\n' > "$test_root/defaults-state/flea/ui.json" ;;
        off) printf '{"langMarks":false}\n' > "$test_root/defaults-state/flea/ui.json" ;;
        seeded) env HOME="$test_root/home" XDG_STATE_HOME="$test_root/defaults-state" "$bin" --ui-state '{"langMarks":false}' > "$test_root/defaults-seed.json" || return 1 ;;
        *) return 1 ;;
    esac
    cp "$test_root/defaults-state/flea/ui.json" "$test_root/defaults-input-$label.json" || return 1
    env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$test_root/home" XDG_STATE_HOME="$test_root/defaults-state" XDG_CACHE_HOME="$test_root/cache" \
        XDG_RUNTIME_DIR="$test_root/runtime" QLCODE_DEFAULTS="$mode" FLEA_BIN="$bin" \
        QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
        dbus-run-session -- bash -c 'timeout 10 qs -p "$1" > "$2" 2>&1' _ "$test_root/config" "$log" 2> "$test_root/defaults-$label-bus.log"
    status=$?
    if [[ -n "${FLEA_CI_SUITE_LOGS:-}" ]]; then cp "$log" "$FLEA_CI_SUITE_LOGS/quicklook-defaults-$label.log" || return 1; fi
    cmp "$test_root/defaults-input-$label.json" "$test_root/defaults-state/flea/ui.json" || return 1
    [[ "$status" == 0 ]] && grep -aq "QLDEFAULT DONE mode=$mode failures=0" "$log" \
        && ! grep -aqE 'QLDEFAULT FAIL|TypeError|ReferenceError|Unable to assign|Cannot assign' "$log"
}
for mode in empty off; do
    defaults_probe "$mode" "$mode" || { cat "$test_root/defaults-$mode.log"; printf 'FAIL quicklook-code: absent-wrap %s context\n' "$mode"; exit 1; }
    grep -ao 'QLDEFAULT .*' "$test_root/defaults-$mode.log"
done
# Explicit schema false masks this mutant; both genuinely missing-key contexts must reject it.
python3 - "$test_root/config/flea/ViewState.qml" <<'PY' || exit 1
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
anchor = 'readonly property bool previewWrap: root.preview.wrap === true'
assert source.count(anchor) == 1, 'wrap fallback anchor changed'
path.write_text(source.replace(anchor, 'readonly property bool previewWrap: root.preview.wrap !== false'))
PY
defaults_probe seeded seeded-mutant || { cat "$test_root/defaults-seeded-mutant.log"; printf 'FAIL quicklook-code: schema-seeded masking control\n'; exit 1; }
for mode in empty off; do
    if defaults_probe "$mode" "$mode-mutant" > "$test_root/defaults-$mode-wrapper.log" 2>&1; then
        printf 'FAIL quicklook-code: missing-wrap-true mutant passed %s\n' "$mode"; exit 1
    fi
    grep -aq "QLDEFAULT FAIL mode=$mode missing-wrap fallback got=true expected=false" "$test_root/defaults-$mode-mutant.log" \
        || { cat "$test_root/defaults-$mode-wrapper.log"; printf 'FAIL quicklook-code: %s missed wrap fallback mutant\n' "$mode"; exit 1; }
done
cp ui/ViewState.qml "$test_root/config/flea/ViewState.qml" || exit 1
printf 'QLDEFAULT MUTANT missing-wrap-true schema-seeded-accepted=1 empty-rejected=1 explicit-off-rejected=1\n'
cp tests/quicklook-code.qml "$test_root/config/shell.qml" || exit 1
cp tests/langmark-count.js "$test_root/config/langmark-count.js" || exit 1
env HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" "$bin" --ui-state '{"langMarks":true}' > "$test_root/seed.json" || exit 1

# Sorted by name: a Markdown note, two Rust files (the first of 132 lines), a text file, a remote-route text file with markup, a NUL file, a file over 1 MiB, and 60 lines with a 6,000-character one at line 40.
fixture="$test_root/fixture"
printf '# Notes\n\nplain words, no code\n' > "$fixture/00-notes.md"
for i in $(seq 1 132); do printf 'fn f%d() { let s = "x"; }\n' "$i"; done > "$fixture/01-icons.rs"
for i in $(seq 1 132); do printf 'fn g%d() { let s = "y"; }\n' "$i"; done > "$fixture/02-more.rs"
for i in $(seq 1 8); do printf 'plain words on line %d\n' "$i"; done > "$fixture/03-plain.txt"
printf 'first line\n<img src="http://127.0.0.1:9/x">\na & b\n' > "$fixture/03-remote.txt"
printf 'text\0text\n' > "$fixture/04-nul.txt"
yes 'a log line' | head -c 1048577 > "$fixture/05-over.log"
for i in $(seq 1 60); do
    if [ "$i" -eq 40 ]; then printf 'fn long() { let s = "'; head -c 6000 /dev/zero | tr '\0' x; printf '"; }\n'
    else printf 'fn l%d() {}\n' "$i"; fi
done > "$fixture/06-long.rs"
printf 'name,value\nfirst,1\nsecond,2\n' > "$fixture/07-table.csv"
printf 'name\tvalue\nfirst\t1\nsecond\t2\n' > "$fixture/08-table.tsv"

failures=0
legs=0
# run_leg NAME: one qs run; the second leg starts on the ui.json the first one left.
run_leg() {
    local leg=$1 log="$test_root/$1.log" status loops
    ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
        XDG_RUNTIME_DIR="$test_root/runtime" FLEA_BIN="$bin" FLEA_PATH="$fixture" FLEA_REDUCED_MOTION=1 \
        QLCODE_UI="$test_root/config/flea" QLCODE_STATE="$test_root/state" QLCODE_RUN="$leg" \
        QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
        dbus-run-session -- bash -c 'timeout 240 qs -p "$1" > "$2" 2>&1' _ "$test_root/config" "$log" 2> "$test_root/$leg-bus.log" ) 2>/dev/null
    status=$?
    legs=$((legs + 1))
    [ -z "${FLEA_CI_SUITE_LOGS:-}" ] || cp "$log" "$FLEA_CI_SUITE_LOGS/quicklook-code-$leg.log" 2>/dev/null
    grep -a 'QLCODE \(PASS\|FAIL\|DONE\)' "$log" | sed "s/^/$leg: /"
    loops=$(grep -ac 'Binding loop detected' "$log")
    if [ "$loops" -ne 0 ]; then
        printf 'FAIL quicklook-code: %s leg logged %s binding loop(s)\n' "$leg" "$loops"
        failures=$((failures + 1))
    fi
    qslog_crash "quicklook-code $leg" "$log" || failures=$((failures + 1))
    if [ "$status" -ne 0 ] || [ "$(grep -ac 'QLCODE DONE' "$log")" -ne 1 ] || grep -aqE 'QLCODE FAIL|TypeError|ReferenceError|Unable to assign|Cannot assign' "$log"; then
        printf 'FAIL quicklook-code: %s leg did not hold (qs exit %s)\n' "$leg" "$status"
        grep -aE 'TypeError|ReferenceError|Unable to assign|Cannot assign' "$log" | head -5
        failures=$((failures + 1))
    fi
}
run_leg fresh
run_leg again
printf 'quicklook-code: %s legs, %s failed\n' "$legs" "$failures"
[ "$failures" -eq 0 ]
