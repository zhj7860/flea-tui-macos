#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# columnsprebuild: quiet turns prebuild parked rows in the active Columns column; the next landing adopts them with 0 built.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "columnsprebuild.sh: qs is not installed, cannot build the view"
    exit 1
fi

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-columnsprebuild.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/columnsprebuild.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 60 qs -p "$test_root/config" 2>&1)
# Sample input, one probe line: "  INFO qml: COLUMNSPREBUILD PASS warmRows=55 ticks=19 created=55"
pass_count=$(printf '%s\n' "$output" | grep -c 'COLUMNSPREBUILD PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'COLUMNSPREBUILD FAIL')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL the active column built rows at a landing, or its prebuild pool broke a rule\n'
    printf '%s\n' "$output" | grep -aE 'COLUMNSPREBUILD|ERROR|error' | head -20
    exit 1
fi
printf '%s\n' "$output" | grep -o 'COLUMNSPREBUILD PASS.*'
errors=$(printf '%s\n' "$output" | grep -aE 'qml: .*(Error|TypeError|ReferenceError|Unable)|QML .*(Error|error)|@flea/[^ ]*: (Error|TypeError|ReferenceError)|Binding loop' | head -5)
if [ -n "$errors" ]; then
    printf 'FAIL columnsprebuild logged QML errors\n%s\n' "$errors"
    exit 1
fi
