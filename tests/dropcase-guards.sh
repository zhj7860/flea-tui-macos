#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# Drive tests/dropline-peek.qml (the activity observer names the pane for a peek column's drag line instead of reading its null pane), then check that cap_dropmods puts focus back on Flea before it sends the key after a foreign drop.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

# A foreign drop leaves focus on the probe window, and key() refuses any key while focus is off the pid ipc points at, so the case focuses Flea between the first probe drop and the next seek.
case_body=$(sed -n '/^case_cap_dropmods()/,/^}/p' tests/ui-captures-dropmods.sh)
between=$(printf '%s\n' "$case_body" | sed -n '/the probe never logged the plain drop/,/seek_row_named "probe2.txt"/p')
if ! printf '%s\n' "$between" | grep -q 'seek_row_named "probe2.txt"' || ! printf '%s\n' "$between" | grep -Eq '^[[:space:]]*cap_dropmods_focus_pid([[:space:]]|;|$)'; then
    printf 'FAIL cap_dropmods seeks probe2.txt with focus still on the probe window, so key() refuses it\n'
    exit 1
fi

if ! command -v qs >/dev/null; then
    echo "dropcase-guards.sh: qs is not installed, cannot drive the columns view"
    exit 1
fi

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-dropcase-guards.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/dropline-peek.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 30 qs -p "$test_root/config" 2>&1)

noisy=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|is not a function|is not defined|Binding loop')
# Sample input, the one probe line: "  INFO qml: DROPLINEPEEK DONE checks=5 failed=0"
if ! printf '%s\n' "$output" | grep -q 'DROPLINEPEEK DONE checks=[1-9][0-9]* failed=0$' || [ -n "$noisy" ]; then
    printf 'FAIL the activity observer threw or named a wrong owner for a drag line, or the probe logged a QML error\n'
    printf '%s\n' "$output" | grep -a 'DROPLINEPEEK'
    printf '%s\n' "$output" | grep -aiE 'ERROR|error'
    [ -n "$noisy" ] && printf '%s\n' "$noisy" | head -20
    exit 1
fi
printf '%s\n' "$output" | grep -o 'DROPLINEPEEK DONE.*'
