#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# Properties on a folder counts its contents in place under fed replies, whole from its first frame; offscreen, no display or lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "menu-contents.sh: qs is not installed, cannot draw the card"
    exit 1
fi

# A marked sandbox of its own under the fixture root, so cleanup deletes only what this run owns.
test_root=$(mktemp -d "$FIXTURE_ROOT/flea-menu-contents-XXXXXX") || exit 1
# The allocated path must be absolute and non-empty before the sandbox trusts it.
case $test_root in
  /*/*) ;;
  *) echo "FAIL: mktemp -d gave '$test_root', which is not an absolute path two components deep"; exit 1 ;;
esac
sandbox_require "$test_root" || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/menu-contents.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 60 qs -p "$test_root/config" 2>&1)
qs_status=$?

# Sample input, the receipt: "  INFO qml: MENUCONTENTS DONE checks=85 failed=0"; the probe self-kills (143) after it, and a PASS beside any other status is a double's.
expected_checks=85
pass_count=$(printf '%s\n' "$output" | grep -c 'MENUCONTENTS PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'MENUCONTENTS FAIL')
done_count=$(printf '%s\n' "$output" | grep -c "MENUCONTENTS DONE checks=$expected_checks failed=0")
verdict=0
if [ "$qs_status" -ne 143 ]; then
    printf 'FAIL qs exited %s, want the owned self-kill 143 after DONE\n' "$qs_status"
    verdict=1
fi
if [ "$done_count" -ne 1 ]; then
    printf 'FAIL completion receipts %s, want exactly 1 DONE with %s checks and no failure\n' "$done_count" "$expected_checks"
    verdict=1
fi
if [ "$pass_count" -ne "$expected_checks" ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL the card did not count a folder in place, whole from its first frame\n'
    printf '%s\n' "$output" | grep -aE 'MENUCONTENTS|ERROR|error'
    verdict=1
fi
# The offscreen platform itself says it cannot mask a FloatingWindow; that one line is the platform's, never the card's.
platform_warning='This plugin does not support setting window masks'
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN|ERROR' | grep -vF "$platform_warning")
if [ -n "$warnings" ]; then
    printf 'FAIL the card harness logged a warning\n'
    printf '%s\n' "$warnings"
    verdict=1
fi
if [ "$verdict" -ne 0 ]; then
    printf '%s\n' "$output"
    exit 1
fi
printf 'MENUCONTENTS PASS %s checks, the folder counts in place and closes with menuaction close\n' "$expected_checks"
printf 'MENUCONTENTS STATUS qs_exit=%s done=1\n' "$qs_status"
