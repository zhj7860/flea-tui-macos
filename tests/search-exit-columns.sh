#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# Escape out of a live search lands the folder whole in list, columns and grid: the real Pane over the real backend, offscreen.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "search-exit-columns.sh: qs is not installed, cannot build the columns view"
    exit 1
fi
bin=${FLEA_BIN:-$PWD/target/debug/flea}
[ -x "$bin" ] || { echo "search-exit-columns.sh: build the backend first: $bin"; exit 1; }

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-search-exit-columns.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" "$test_root/fixture/sub" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/search-exit-columns.qml "$test_root/config/shell.qml" || exit 1
# 280 files and the sub folder: the fixture tests/ui-noblank.sh case_searchnoblank lists natively.
for i in $(seq -w 1 120); do printf 'x\n' > "$test_root/fixture/notes-$i.md"; done
for i in $(seq -w 1 60); do printf 'x\n' > "$test_root/fixture/north-$i.txt"; done
for i in $(seq -w 1 100); do printf 'x\n' > "$test_root/fixture/misc-$i.dat"; done
for i in $(seq -w 1 10); do printf 'x\n' > "$test_root/fixture/sub/notes-sub-$i.md"; done

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    FLEA_BIN="$bin" EXITCOLS_DIR="$test_root/fixture" timeout 60 qs -p "$test_root/config" 2>&1)

# Sample input, the receipt: "  INFO qml: EXITCOLS DONE 27 checks, 0 failed", 9 checks for each of the 3 exits.
done_count=$(printf '%s\n' "$output" | grep -c 'EXITCOLS DONE 27 checks, 0 failed$')
noisy=$(printf '%s\n' "$output" | grep -av 'does not support setting window masks' | grep -aiE 'WARN|ERROR|Binding loop|failed to load|Unable to assign|Cannot assign|TypeError|ReferenceError|is not a function|is not defined')
if [ "$done_count" -ne 1 ] || printf '%s\n' "$output" | grep -aq 'EXITCOLS FAIL' || [ -n "$noisy" ]; then
    printf 'FAIL the columns exit did not land the folder whole\n'
    printf '%s\n' "$output" | grep -a 'EXITCOLS'
    [ -n "$noisy" ] && printf '%s\n' "$noisy"
    exit 1
fi
printf '%s\n' "$output" | grep -a 'EXITCOLS DONE'
