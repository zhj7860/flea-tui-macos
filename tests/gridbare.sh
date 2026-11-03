#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# A Grid press, click, double click, right click or drag lifts a tile only from its icon box or painted caption; offscreen, no display or lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "gridbare.sh: qs is not installed, cannot draw a grid"
    exit 1
fi

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-gridbare.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/gridbare.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 60 qs -p "$test_root/config" 2>&1)

# Sample input, one probe line: "  INFO qml: GRIDBARE PASS gestures=96 icon=hit caption=short,wrapped margin=band".
pass_count=$(printf '%s\n' "$output" | grep -c 'GRIDBARE PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'GRIDBARE FAIL')
# The offscreen platform itself says it cannot mask a FloatingWindow; the suite unsets HYPRLAND_INSTANCE_SIGNATURE itself. Neither line is the grid's.
platform_warning='This plugin does not support setting window masks'
hyprland_warning='$HYPRLAND_INSTANCE_SIGNATURE is unset. Cannot connect to hyprland.'
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN|ERROR' | grep -vF "$platform_warning" | grep -vF "$hyprland_warning")
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ] || [ -n "$warnings" ]; then
    printf 'FAIL a Grid cell lifts its tile from its margin, or a tile stopped lifting from its icon or caption\n'
    printf '%s\n' "$output" | grep -aE 'GRIDBARE|TypeError|ReferenceError|WARN|ERROR' | grep -vF "$platform_warning" | grep -vF "$hyprland_warning" | head -40
    exit 1
fi
printf '%s\n' "$output" | grep -o 'GRIDBARE PASS.*'
