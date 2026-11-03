#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# flingframe: a fling frame in List, Grid and Columns does the work of the rows entering and nothing else, counted headless with no clock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "flingframe.sh: qs is not installed, cannot build the view"
    exit 1
fi

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-flingframe.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/flingframe.qml "$test_root/config/shell.qml" || exit 1
cp tests/FlingMeasure.qml "$test_root/config/FlingMeasure.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 120 qs -p "$test_root/config" 2>&1)
# Sample input, one probe line: "  INFO qml: FLINGFRAME DONE"
if ! printf '%s\n' "$output" | grep -q "FLINGFRAME DONE"; then
    # The probe's own reasons lead, so the first FAIL line a runner keeps says what moved.
    printf 'FAIL flingframe: %s\n' "$(printf '%s\n' "$output" | grep -ao 'FLINGFRAME FAIL.*' | head -1 | cut -c17-)"
    printf '%s\n' "$output" | grep -ao 'FLINGFRAME .*'
    printf '%s\n' "$output" | tail -40
    exit 1
fi
printf '%s\n' "$output" | grep -o 'FLINGFRAME .*'
errors=$(printf '%s\n' "$output" | grep -aE 'qml: .*(Error|TypeError|ReferenceError|Unable)|QML .*(Error|error)|@flea/[^ ]*: (Error|TypeError|ReferenceError)|Binding loop' | head -5)
if [ -n "$errors" ]; then
    printf 'FAIL flingframe logged QML errors\n%s\n' "$errors"
    exit 1
fi
