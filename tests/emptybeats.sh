#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# The real ui/EmptyState.qml plays three beats of phrase and mark after each appearance, then rests on the third; offscreen.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "emptybeats.sh: qs is not installed, cannot draw an empty state"
    exit 1
fi

test_root="$FIXTURE_ROOT/flea-emptybeats-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/cache" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/emptybeats.qml "$test_root/config/shell.qml" || exit 1

# 5 s past the 100 s watchdog, so its timeout line prints before the kill.
output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 105 qs -p "$test_root/config" 2>&1)

# Sample input, one probe line: "  INFO qml: EMPTYBEATS PASS 21 checks"
expected_checks=21
pass_count=$(printf '%s\n' "$output" | grep -c 'EMPTYBEATS PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'EMPTYBEATS FAIL')
ran_checks=$(printf '%s\n' "$output" | grep -ao 'EMPTYBEATS PASS [0-9]* checks' | grep -o '[0-9]*')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ] || [ "${ran_checks:-0}" -ne "$expected_checks" ]; then
    printf 'FAIL the empty state did not rest after three beats, or ran %s checks and not %s\n' "${ran_checks:-0}" "$expected_checks"
    printf '%s\n' "$output" | grep -a 'EMPTYBEATS FAIL'
    printf '%s\n' "$output" | grep -aE 'ERROR|error' | grep -av 'EMPTYBEATS' | head -20
    exit 1
fi
printf '%s\n' "$output" | grep -o 'EMPTYBEATS PASS.*'
