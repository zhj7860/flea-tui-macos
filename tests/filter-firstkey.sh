#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# First-key counter: per-keystroke delegate builds, backend calls and viewport moves over a real List, offscreen. Prints FIRSTKEY lines and a DONE receipt.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "filter-firstkey.sh: qs is not installed, cannot build the list"
    exit 1
fi

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-filterfirstkey.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/filter-firstkey.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 30 qs -p "$test_root/config" 2>&1)

# Sample input, one probe line: "  INFO qml: FIRSTKEY key1sync objects=317 built=0 ..."
pass_count=$(printf '%s\n' "$output" | grep -c 'FIRSTKEY PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'FIRSTKEY FAIL')
done_count=$(printf '%s\n' "$output" | grep -c 'FIRSTKEY DONE')
noisy=$(printf '%s\n' "$output" | grep -av 'does not support setting window masks' | grep -aiE 'WARN|ERROR|Binding loop|failed to load|Unable to assign|Cannot assign|TypeError|ReferenceError|is not a function|is not defined')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ] || [ "$done_count" -ne 1 ] || [ -n "$noisy" ]; then
    printf 'FAIL the first key built synchronously, its marks never landed, or the list warned\n'
    printf '%s\n' "$output" | grep -a 'FIRSTKEY'
    [ -n "$noisy" ] && printf '%s\n' "$noisy" | head -20
    exit 1
fi
printf '%s\n' "$output" | grep -a 'FIRSTKEY'
