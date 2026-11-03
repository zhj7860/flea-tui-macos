#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# listprebuild: quiet turns prebuild parked rows for the next List landing, which adopts them with 0 built.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "listprebuild.sh: qs is not installed, cannot build the view"
    exit 1
fi

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-listprebuild.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/listprebuild.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 60 qs -p "$test_root/config" 2>&1)
# Sample input, one probe line: "  INFO qml: LISTPREBUILD DONE warmRows=47 parked=0"
if ! printf '%s\n' "$output" | grep -q "LISTPREBUILD DONE"; then
    printf 'FAIL listprebuild did not finish clean\n'
    printf '%s\n' "$output" | grep -ao 'LISTPREBUILD .*'
    printf '%s\n' "$output" | tail -40
    exit 1
fi
printf '%s\n' "$output" | grep -o 'LISTPREBUILD .*'
errors=$(printf '%s\n' "$output" | grep -aE 'qml: .*(Error|TypeError|ReferenceError|Unable)|QML .*(Error|error)|@flea/[^ ]*: (Error|TypeError|ReferenceError)|Binding loop' | head -5)
if [ -n "$errors" ]; then
    printf 'FAIL listprebuild logged QML errors\n%s\n' "$errors"
    exit 1
fi
