#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# The Grid caption state names the drawn break (wrapAt, broken) so a query can straddle it, offscreen at text size 14 over the real Ipc.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "gridcapbreak.sh: qs is not installed, cannot draw a grid tile"
    exit 1
fi

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-gridcapbreak.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/gridcapbreak.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 30 qs -p "$test_root/config" 2>&1)

# Sample input, one probe line: "  INFO qml: GRIDCAPBREAK PASS base=14 window=1320 tiles=6 widths=162,157,153,148 queries=t-w,n-t,n-t,n-t"
pass_count=$(printf '%s\n' "$output" | grep -c 'GRIDCAPBREAK PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'GRIDCAPBREAK FAIL')
noisy=$(printf '%s\n' "$output" | grep -aiE 'Binding loop|failed to load|Unable to assign|Cannot assign|TypeError|ReferenceError|is not a function|is not defined')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ] || [ -n "$noisy" ]; then
    printf 'FAIL the grid caption break disagreed with the drawn lines\n'
    printf '%s\n' "$output" | grep -aiE 'GRIDCAPBREAK|ERROR|binding loop|TypeError|ReferenceError' | head -20
    printf '%s\n' "$noisy" | head -5
    exit 1
fi
printf '%s\n' "$output" | grep -o 'GRIDCAPBREAK \(PASS\|TIP\).*'
