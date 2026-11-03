#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# A live search draws only the query its rows answered: the real Pane over the real backend, offscreen.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "search-answered.sh: qs is not installed, cannot run the pane"
    exit 1
fi
bin=${FLEA_BIN:-$PWD/target/debug/flea}
[ -x "$bin" ] || { echo "search-answered.sh: build the backend first: $bin"; exit 1; }

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-search-answered.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" "$test_root/fixture/sub" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/search-answered.qml "$test_root/config/shell.qml" || exit 1
# 280 files and the sub folder: the fixture tests/ui-noblank.sh case_searchnoblank lists natively.
for i in $(seq -w 1 120); do printf 'x\n' > "$test_root/fixture/notes-$i.md"; done
for i in $(seq -w 1 60); do printf 'x\n' > "$test_root/fixture/north-$i.txt"; done
for i in $(seq -w 1 100); do printf 'x\n' > "$test_root/fixture/misc-$i.dat"; done
for i in $(seq -w 1 10); do printf 'x\n' > "$test_root/fixture/sub/notes-sub-$i.md"; done

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    FLEA_BIN="$bin" ANSWERED_DIR="$test_root/fixture" timeout 60 qs -p "$test_root/config" 2>&1)

# Sample input, the receipt: "  INFO qml: SEARCHANSWERED DONE checks=24 failed=0".
done_count=$(printf '%s\n' "$output" | grep -c 'SEARCHANSWERED DONE')
noisy=$(printf '%s\n' "$output" | grep -av 'does not support setting window masks' | grep -aiE 'WARN|ERROR|Binding loop|failed to load|Unable to assign|Cannot assign|TypeError|ReferenceError|is not a function|is not defined')
if [ "$done_count" -ne 1 ] || printf '%s\n' "$output" | grep -aq 'SEARCHANSWERED FAIL' || [ -n "$noisy" ]; then
    printf 'FAIL rows drew a query they had not answered\n'
    printf '%s\n' "$output" | grep -a 'SEARCHANSWERED'
    [ -n "$noisy" ] && printf '%s\n' "$noisy"
    exit 1
fi
printf '%s\n' "$output" | grep -a 'SEARCHANSWERED STAMPS'
printf '%s\n' "$output" | grep -a 'SEARCHANSWERED DONE'
