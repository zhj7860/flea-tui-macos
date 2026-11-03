#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# A real ui/GridArea.qml draws List's match mark on each label's matched letters, offscreen with no display or lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "gridmark.sh: qs is not installed, cannot build the grid"
    exit 1
fi

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-gridmark.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/gridmark.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 30 qs -p "$test_root/config" 2>&1)

# Sample input, one probe line: "  INFO qml: GRIDMARK PASS armed=+4 keybuilt=0 states=same turn,cursor,rest wrap="s n""
pass_count=$(printf '%s\n' "$output" | grep -c 'GRIDMARK PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'GRIDMARK FAIL')
noisy=$(printf '%s\n' "$output" | grep -av 'does not support setting window masks' | grep -aiE 'Binding loop|Unable to assign|Cannot assign|TypeError|ReferenceError|is not a function|is not defined')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ] || [ -n "$noisy" ]; then
    printf 'FAIL a grid label drew no match mark, the wrong letters or ink, built it on a key, or warned\n'
    printf '%s\n' "$output" | grep -a 'GRIDMARK'
    [ -n "$noisy" ] && printf '%s\n' "$noisy" | head -20
    printf '%s\n' "$output" | tail -40
    exit 1
fi
printf '%s\n' "$output" | grep -o 'GRIDMARK PASS.*'
