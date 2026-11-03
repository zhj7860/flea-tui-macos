#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# A Columns view kept behind the list or the grid keeps its rows until a new row count reaches it, then holds and builds none, and its return draws every column whole in the first frame: the real Pane over the real backend, offscreen.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "columnshidden.sh: qs is not installed, cannot build the columns view"
    exit 1
fi
bin=${FLEA_BIN:-$PWD/target/debug/flea}
[ -x "$bin" ] || { echo "columnshidden.sh: build the backend first: $bin"; exit 1; }
rounds=${COLHID_ROUNDS:-1}
case "$rounds" in ''|*[!0-9]*|0*) echo "columnshidden.sh: COLHID_ROUNDS='$rounds' is not a positive integer"; exit 2 ;; esac

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-columnshidden.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" "$test_root/fixture/sub" "$test_root/fixture/empty" \
    "$test_root/fixture/hop/sixty" "$test_root/fixture/hop/empty" "$test_root/fixture/hop/three" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/columnshidden.qml "$test_root/config/shell.qml" || exit 1
# 280 files, a folder of 10, an empty one and hop: 283 rows, so the cursor can stand far below the first screen.
for i in $(seq -w 1 120); do printf 'x\n' > "$test_root/fixture/notes-$i.md"; done
for i in $(seq -w 1 60); do printf 'x\n' > "$test_root/fixture/north-$i.txt"; done
for i in $(seq -w 1 100); do printf 'x\n' > "$test_root/fixture/misc-$i.dat"; done
for i in $(seq -w 1 10); do printf 'x\n' > "$test_root/fixture/sub/notes-sub-$i.md"; done
# A shown hop through 60 rows, an empty folder and 3 rows fills the column's reuse pool; the switch to the grid leaves its height alone.
for i in $(seq -w 1 60); do printf 'x\n' > "$test_root/fixture/hop/sixty/row-$i.txt"; done
for i in 1 2 3; do printf 'x\n' > "$test_root/fixture/hop/three/row-$i.txt"; done

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    FLEA_BIN="$bin" COLHID_DIR="$test_root/fixture" COLHID_ROUNDS="$rounds" timeout 90 qs -p "$test_root/config" 2>&1)

# Sample input, the receipt: "  INFO qml: COLHID DONE 54 checks, 0 failed".
done_count=$(printf '%s\n' "$output" | grep -c 'COLHID DONE')
noisy=$(printf '%s\n' "$output" | grep -av 'does not support setting window masks' | grep -aiE 'WARN|ERROR|Binding loop|failed to load|Unable to assign|Cannot assign|TypeError|ReferenceError|is not a function|is not defined')
# Sample input: "  INFO qml: COLHID DONE 54 checks, 0 failed" gives 54, the count one round (46) plus the closing hop (8) makes.
checks=$(printf '%s\n' "$output" | sed -n 's/.*COLHID DONE \([0-9][0-9]*\) checks.*/\1/p')
# Each round runs 46 checks and the closing hop 8, so a probe that built no round or dropped a check does not equal the count asked for.
round_checks=46 hop_checks=8
if [ "$done_count" -ne 1 ] || [ "${checks:-0}" -ne $((hop_checks + round_checks * rounds)) ] || printf '%s\n' "$output" | grep -aq 'COLHID FAIL' || [ -n "$noisy" ]; then
    printf 'FAIL a hidden Columns view built rows, held them past a listing change, or its return drew a frame without them\n'
    printf '%s\n' "$output" | grep -a 'COLHID'
    [ -n "$noisy" ] && printf '%s\n' "$noisy"
    exit 1
fi
printf '%s\n' "$output" | grep -a -e 'COLHID SWITCH' -e 'rows a shown hop pooled'
printf '%s\n' "$output" | grep -a 'COLHID DONE'
