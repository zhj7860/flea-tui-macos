#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# Ok item lines through the real ui/PaneWire.qml handlers: held, folded on the beat, and flushed before a failure, a sample or the done line; offscreen.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "transferhold.sh: qs is not installed, cannot drive the pane wire"
    exit 1
fi

# A marked sandbox of its own under the fixture root, so cleanup deletes only what this run owns.
test_root=$(mktemp -d "$FIXTURE_ROOT/flea-transferhold-XXXXXX") || exit 1
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
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/transferhold.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    PREVIEW_UI="$PWD/ui" \
    timeout 60 qs -p "$test_root/config" 2>&1)
qs_status=$?

# Sample input: "  INFO qml: TRANSFERHOLD PASS a-thousand-ok-lines-wait", then one "TRANSFERHOLD DONE failures=0" and a self-kill (143).
pass_count=$(printf '%s\n' "$output" | grep -c 'TRANSFERHOLD PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'TRANSFERHOLD FAIL')
done_count=$(printf '%s\n' "$output" | grep -c 'TRANSFERHOLD DONE failures=0$')
expected_passes=19
verdict=0
if [ "$qs_status" -ne 143 ]; then
    printf 'FAIL qs exited %s, want the owned self-kill 143 after DONE\n' "$qs_status"
    verdict=1
fi
if [ "$done_count" -ne 1 ]; then
    printf 'FAIL completion receipts %s, want exactly 1 DONE\n' "$done_count"
    verdict=1
fi
if [ "$pass_count" -ne "$expected_passes" ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL the wire did not land every leg\n'
    printf '%s\n' "$output" | grep -aE 'TRANSFERHOLD|ERROR|error'
    verdict=1
fi
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError')
if [ -n "$warnings" ]; then
    printf 'FAIL the harness logged a script error\n'
    printf '%s\n' "$warnings"
    verdict=1
fi
if [ "$verdict" -ne 0 ]; then
    printf '%s\n' "$output"
    exit 1
fi
printf '%s\n' "$output" | grep -o 'TRANSFERHOLD PASS.*'
printf 'TRANSFERHOLD STATUS qs_exit=%s done=1\n' "$qs_status"
