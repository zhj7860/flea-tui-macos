#!/usr/bin/env bash
# The shared fade of every dialog and menu: OutCubic, the shared open and close times, snapped under reduced motion, the card still while it fades out; offscreen, no display or lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
. "$(dirname "$0")/headless-commons.sh"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "reveal.sh: qs is not installed, cannot measure a fade"
    exit 1
fi

# A marked sandbox of its own under the fixture root, so cleanup deletes only what this run owns.
test_root=$(mktemp -d "$FIXTURE_ROOT/flea-reveal-XXXXXX") || exit 1
# GNU mktemp -d keeps a relative TMPDIR verbatim, so the path is checked absolute and two components deep.
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
headless_commons "$test_root" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/reveal.qml "$test_root/config/shell.qml" || exit 1
cp tests/qml-probe.js "$test_root/config/qml-probe.js" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 120 qs -p "$test_root/config" 2>&1)
qs_status=$?

# Every check a full green run makes, read off that run's own PASS line; a leg that stops running makes fewer and fails here.
expected_checks=110
# Sample input: "  INFO qml: REVEAL PASS 110 checks", then "REVEAL DONE failures=0", then the probe's own SIGTERM (143).
pass_count=$(printf '%s\n' "$output" | grep -c 'REVEAL PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'REVEAL FAIL')
done_count=$(printf '%s\n' "$output" | grep -c 'REVEAL DONE')
verdict=0
if [ "$qs_status" -ne 143 ]; then
    printf 'FAIL qs exited %s, want the owned self-kill 143 after DONE\n' "$qs_status"
    verdict=1
fi
if [ "$done_count" -ne 1 ]; then
    printf 'FAIL completion receipts %s, want exactly 1 DONE beside the PASS\n' "$done_count"
    verdict=1
fi
if ! printf '%s\n' "$output" | grep -q "REVEAL PASS $expected_checks checks"; then
    printf 'FAIL the run did not report PASS %s checks\n' "$expected_checks"
    verdict=1
fi
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL a dialog or menu fade left its curve, its time, its reduced-motion snap or its still card\n'
    printf '%s\n' "$output" | grep -aE 'REVEAL|ERROR|error'
    verdict=1
fi
# The offscreen platform itself says it cannot mask a FloatingWindow; that one line is the platform's, never the menu's.
platform_warning='This plugin does not support setting window masks'
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN|ERROR' | grep -vF "$platform_warning")
if [ -n "$warnings" ]; then
    printf 'FAIL the menu harness logged a warning\n'
    printf '%s\n' "$warnings"
    verdict=1
fi
if [ "$verdict" -ne 0 ]; then
    printf '%s\n' "$output"
    exit 1
fi
printf '%s\n' "$output" | grep -o 'REVEAL PASS.*'
printf 'REVEAL STATUS qs_exit=%s done=1\n' "$qs_status"
