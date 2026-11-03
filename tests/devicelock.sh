#!/usr/bin/env bash
# Two overlapping DeviceLock locks each run, and each refusal names its own drive.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "devicelock.sh: qs is not installed, cannot drive the device lock"
    exit 1
fi

# A marked sandbox of its own under the fixture root, so cleanup deletes only what this run owns.
test_root=$(mktemp -d "$FIXTURE_ROOT/flea-devicelock-XXXXXX") || exit 1
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
# Only DeviceLock.qml and its js are linked, as siblings, the way tests/mount-listing.sh links its one component: a whole-ui import would parse every ui file.
ln -s "$PWD/ui/DeviceLock.qml" "$test_root/config/DeviceLock.qml" || exit 1
ln -s "$PWD/ui/js" "$test_root/config/js" || exit 1

# The harness drives the real DeviceLock with two overlapping locks against a stub udisksctl that holds each lock two seconds, then refuses it.
cat > "$test_root/config/shell.qml" <<'QML_EOF'
//@ pragma ShellId flea-devicelock-test

import QtQuick
import Quickshell
import Quickshell.Io
import "js/Unlock.js" as Unlock

// The real DeviceLock over a stub udisksctl that refuses every lock: two overlapping locks each run, and each refusal names its own drive.
ShellRoot {
    id: shell

    property var failures: []
    property int ticks: 0
    property int phase: 0
    property int waits: 0
    property var said: []
    property int polls: 0

    // Two unlocked crypts on two sticks, so each lock takes its own container.
    property string listing: '{"blockdevices":['
        + '{"name":"sdb","path":"/dev/sdb","type":"disk","rm":true,"mountpoints":[null],'
        + '"children":[{"name":"sdb1","path":"/dev/sdb1","type":"part","fstype":"crypto_LUKS","mountpoints":[null],'
        + '"children":[{"name":"luks-vault","path":"/dev/mapper/luks-vault","type":"crypt","mountpoints":["/run/media/gm/vault"]}]}]},'
        + '{"name":"sdc","path":"/dev/sdc","type":"disk","rm":true,"mountpoints":[null],'
        + '"children":[{"name":"sdc1","path":"/dev/sdc1","type":"part","fstype":"crypto_LUKS","mountpoints":[null],'
        + '"children":[{"name":"luks-stick","path":"/dev/mapper/luks-stick","type":"crypt","mountpoints":["/run/media/gm/stick"]}]}]}'
        + ']}'

    function log(line) { console.log("DEVICELOCK " + line) }
    function quit() { Quickshell.execDetached(["kill", String(Quickshell.processId)]) }
    function check(name, cond, detail) {
        if (cond) shell.log("PASS " + name)
        else shell.failures.push(name + " got " + detail)
    }
    function step(next) { shell.phase = next; shell.waits = 0 }
    function until(done, ticks) {
        if (!done && shell.waits++ < ticks) return true
        shell.waits = 0
        return false
    }
    function finish() {
        for (var i = 0; i < shell.failures.length; i++)
            shell.log("FAIL " + shell.failures[i])
        shell.log("DONE failures=" + shell.failures.length)
        shell.phase = 99
        shell.quit()
    }

    Item {
        id: host
        function message(text, isError) { shell.said.push(String(text)) }
        function poll() { shell.polls += 1 }
    }

    DeviceLock {
        id: locker
        host: host
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: shell.advance()
    }

    function advance() {
        shell.ticks += 1
        if (shell.ticks < 2) return
        if (shell.phase === 0) {
            var first = locker.lockCryptAfter(shell.listing, "/dev/mapper/luks-vault", "vault")
            var second = locker.lockCryptAfter(shell.listing, "/dev/mapper/luks-stick", "stick")
            shell.check("both overlapping locks start", first === true && second === true, first + "|" + second)
            shell.step(1)
        } else if (shell.phase === 1) {
            if (shell.until(shell.said.length === 2, 200)) return
            shell.check("each refusal names its own drive",
                shell.said.length === 2 && shell.said[0] === Unlock.lockNote("vault")
                    && shell.said[1] === Unlock.lockNote("stick"), shell.said.join(" | "))
            shell.check("the drained queue polls once the locks have settled", shell.polls === 1, shell.polls)
            shell.finish()
        }
    }
}
QML_EOF

# Every lock is held two seconds so the second call lands while the first runs, then refused.
cat > "$test_root/bin/udisksctl" <<'STUB_EOF'
#!/bin/sh
d="@STUB@"
printf '%s\n' "$*" >> "$d/lockcalls"
case "$1" in
  lock)
    sleep 2
    echo "Error locking $4: GDBus.Error:org.freedesktop.UDisks2.Error.DeviceBusy: busy" >&2
    exit 1
    ;;
  *) exit 2 ;;
esac
STUB_EOF
sed -i "s|@STUB@|$test_root/stub|" "$test_root/bin/udisksctl" || exit 1
chmod 700 "$test_root/bin/udisksctl" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    PATH="$test_root/bin:$PATH" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 90 qs -p "$test_root/config" 2>&1)
qs_status=$?

# Sample input, a probe line "  INFO qml: DEVICELOCK PASS both overlapping locks start".
pass_count=$(printf '%s\n' "$output" | grep -c 'DEVICELOCK PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'DEVICELOCK FAIL')
done_count=$(printf '%s\n' "$output" | grep -c 'DEVICELOCK DONE')
expected_passes=3
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
# Both containers were locked, each behind its own call.
if ! grep -qx 'lock --block-device /dev/sdb1' "$test_root/stub/lockcalls" 2>/dev/null; then
    printf 'FAIL no lock call took /dev/sdb1\n'
    verdict=1
fi
if ! grep -qx 'lock --block-device /dev/sdc1' "$test_root/stub/lockcalls" 2>/dev/null; then
    printf 'FAIL no lock call took /dev/sdc1\n'
    verdict=1
fi
if [ "$(wc -l < "$test_root/stub/lockcalls" 2>/dev/null)" -ne 2 ]; then
    printf 'FAIL want exactly 2 lock calls, one per drive\n'
    verdict=1
fi
# The offscreen platform itself says it cannot mask a FloatingWindow; that one line is the platform's, never the lock's.
platform_warning='This plugin does not support setting window masks'
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN|ERROR' | grep -vF "$platform_warning")
if [ -n "$warnings" ]; then
    printf 'FAIL the device lock harness logged a warning\n'
    printf '%s\n' "$warnings"
    verdict=1
fi
if [ "$verdict" -ne 0 ]; then
    printf '%s\n' "$output"
    exit 1
fi
printf '%s\n' "$output" | grep -o 'DEVICELOCK PASS.*'
printf 'DEVICELOCK STATUS qs_exit=%s done=1\n' "$qs_status"
