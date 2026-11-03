#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# A shown column re-asks when its folder's remembered order changes, and drops a reply sorted under the old one.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "columnspeekorder.sh: qs is not installed, cannot drive the columns view"
    exit 1
fi

test_root="$FIXTURE_ROOT/flea-columnspeekorder-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/columnspeekorder.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 30 qs -p "$test_root/config" 2>&1)

# Sample input, one probe line: "  INFO qml: COLUMNSPEEKORDER PASS reorder=reask stale=dropped held=rows remember=reask quiet=none"
pass_count=$(printf '%s\n' "$output" | grep -c 'COLUMNSPEEKORDER PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'COLUMNSPEEKORDER FAIL')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL a peek column keeps rows drawn under an old folder order\n'
    printf '%s\n' "$output" | grep -a 'COLUMNSPEEKORDER FAIL'
    printf '%s\n' "$output" | grep -aE 'ERROR|error' | head -5
    exit 1
fi
printf '%s\n' "$output" | grep -o 'COLUMNSPEEKORDER PASS.*'
