#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# The UnlockHost one-shot poller proof: the CLI card's DeviceMounts poller ends with its first listing, never starts on a touched card, latches past an erase, retries a timeout, and a null call rail reads the remembered rail's LUKS version. Offscreen, no display or device.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "unlock-poller.sh: qs is not installed, cannot drive the unlock host"
    exit 1
fi

# A marked sandbox of its own under the fixture root, so cleanup deletes only what this run owns.
test_root=$(mktemp -d "$FIXTURE_ROOT/flea-unlock-poller-XXXXXX") || exit 1
case $test_root in
  /*/*) ;;
  *) echo "FAIL: mktemp -d gave '$test_root', which is not an absolute path two components deep"; exit 1 ;;
esac
sandbox_require "$test_root" || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" "$test_root/bin" "$test_root/stub" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/unlock-poller.qml "$test_root/config/shell.qml" || exit 1
cp tests/unlock-stdin-find.js "$test_root/config/unlock-stdin-find.js" || exit 1

# The stand-in for the real lsblk: waits for the harness's go flag, then answers with the armed body.
cat > "$test_root/bin/lsblk" <<EOF
#!/bin/sh
while [ ! -f "$test_root/stub/go" ]; do sleep 0.05; done
cat "$test_root/stub/body.json"
EOF
chmod 700 "$test_root/bin/lsblk" || exit 1
# A locked loop container lists under its shimmed name, as tests/ui-captures-unlock.sh renames it.
cat > "$test_root/stub/body-row.json" <<'JSON'
{"blockdevices":[{"name":"cap-loop9","path":"/dev/loop9","label":null,"mountpoints":[null],"rm":true,"tran":null,"size":33554432,"type":"loop","model":null,"fstype":"crypto_LUKS","fsver":"2"}]}
JSON
printf '{"blockdevices":[]}\n' > "$test_root/stub/body-empty.json" || exit 1
cp "$test_root/stub/body-row.json" "$test_root/stub/body.json" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    PATH="$test_root/bin:$PATH" UNLOCK_TEST_ROOT="$test_root" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 90 qs -p "$test_root/config" 2>&1)
qs_status=$?

# Sample input, a probe line "  INFO qml: UNLOCKPOLLER PASS first-listing-stops-the-poller", then the receipt "UNLOCKPOLLER DONE failures=0".
pass_count=$(printf '%s\n' "$output" | grep -c 'UNLOCKPOLLER PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'UNLOCKPOLLER FAIL')
done_count=$(printf '%s\n' "$output" | grep -c 'UNLOCKPOLLER DONE')
expected_passes=31
verdict=0
if [ "$qs_status" -ne 143 ]; then
    printf 'FAIL qs exited %s, want the owned self-kill 143 after DONE\n' "$qs_status"
    verdict=1
fi
if [ "$done_count" -ne 1 ]; then
    printf 'FAIL completion receipts %s, want exactly 1 DONE beside the PASS\n' "$done_count"
    verdict=1
fi
if [ "$pass_count" -ne "$expected_passes" ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL want %s PASS and 0 FAIL, got %s PASS and %s FAIL\n' "$expected_passes" "$pass_count" "$fail_count"
    verdict=1
fi
# The offscreen platform itself says it cannot mask a FloatingWindow; that one line is the platform's, never the host's.
platform_warning='This plugin does not support setting window masks'
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN|ERROR' | grep -vF "$platform_warning")
if [ -n "$warnings" ]; then
    printf 'FAIL the unlock poller harness logged a warning\n'
    printf '%s\n' "$warnings"
    verdict=1
fi
if [ "$verdict" -ne 0 ]; then
    printf '%s\n' "$output"
    exit 1
fi
printf '%s\n' "$output" | grep -o 'UNLOCKPOLLER PASS.*'
printf 'UNLOCKPOLLER STATUS qs_exit=%s done=1\n' "$qs_status"
