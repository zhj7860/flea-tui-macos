#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# gridnarrow: a real ui/GridArea.qml keeps its drawn tiles and cursor across a narrowing, offscreen with no display or lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "gridnarrow.sh: qs is not installed, cannot build the grid"
    exit 1
fi

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-gridnarrow.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/gridnarrow.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 30 qs -p "$test_root/config" 2>&1)

# Sample input, one probe line: "  INFO qml: GRIDNARROW PASS drawn=27 pooled=2 cursor=45"
pass_count=$(printf '%s\n' "$output" | grep -c 'GRIDNARROW PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'GRIDNARROW FAIL')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL a filter count change rebuilt drawn tiles, lost the cursor tile, lit a rename editor or left tiles in an emptied hidden grid\n'
    printf '%s\n' "$output" | grep -a 'GRIDNARROW'
    printf '%s\n' "$output" | grep -aiE 'ERROR|error'
    printf '%s\n' "$output"
    exit 1
fi
printf '%s\n' "$output" | grep -o 'GRIDNARROW PASS.*'
