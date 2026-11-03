#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# The real ColumnsArea names a child column only for a folder under the cursor: a folder of files draws none.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "columnsdrawn.sh: qs is not installed, cannot drive the columns view"
    exit 1
fi

test_root="$FIXTURE_ROOT/flea-columnsdrawn-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/columnsdrawn.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 30 qs -p "$test_root/config" 2>&1)

# Sample input, one probe line: "  INFO qml: COLUMNSDRAWN PASS file-cursor=no-child folder-cursor=its-rows"
pass_count=$(printf '%s\n' "$output" | grep -c 'COLUMNSDRAWN PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'COLUMNSDRAWN FAIL')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL the child slot of the columns view names the wrong folder\n'
    printf '%s\n' "$output"
    exit 1
fi
printf '%s\n' "$output" | grep -o 'COLUMNSDRAWN PASS.*'
