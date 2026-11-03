#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# The U1 proof and the unlock threat pins: the canary reaches udisksctl unlock on stdin alone, no newline, then EOF.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

CANARY='S3cr3t-canary-1006'

if ! command -v qs >/dev/null; then
    echo "unlock-stdin.sh: qs is not installed, cannot drive the unlock dialog"
    exit 1
fi

# A marked sandbox of its own under the fixture root, so cleanup deletes only what this run owns.
test_root=$(mktemp -d "$FIXTURE_ROOT/flea-unlock-stdin-XXXXXX") || exit 1
# The allocated path must be absolute and non-empty before the sandbox trusts it.
case $test_root in
  /*/*) ;;
  *) echo "FAIL: mktemp -d gave '$test_root', which is not an absolute path two components deep"; exit 1 ;;
esac
sandbox_require "$test_root" || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" "$test_root/bin" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/unlock-stdin.qml "$test_root/config/shell.qml" || exit 1
cp tests/unlock-stdin-find.js "$test_root/config/unlock-stdin-find.js" || exit 1
cp tests/UnlockKit.qml "$test_root/config/UnlockKit.qml" || exit 1
cp tests/UnlockSteps.qml "$test_root/config/UnlockSteps.qml" || exit 1

# The stub udisksctl refuses unlock twice then unlocks, every recorder is a cat that exits only on EOF, and a stub/mode word (hang, latesuccess, latefail, mounthang, mountfail, lockfail, comma joined) arms the later phases.
mkdir -p "$test_root/stub" || exit 1
cat > "$test_root/stub/udisksctl.live" <<'EOF'
#!/bin/sh
d="@STUB@"
n=0
if [ -f "$d/attempt" ]; then n=$(cat "$d/attempt"); fi
mode=""
if [ -f "$d/mode" ]; then mode=$(cat "$d/mode"); fi
has() { case ",$mode," in *",$1,"*) return 0 ;; esac; return 1; }
printf '%s\n' "$@" > "$d/argv$((n+1))"
env > "$d/childenv$((n+1))"
case "$1" in
  unlock)
    n=$((n+1)); printf '%s' "$n" > "$d/attempt"
    tr '\0' ' ' < "/proc/$$/cmdline" > "$d/cmdself$n"
    tr '\0' '\n' < "/proc/$$/environ" > "$d/envself$n"
    tr '\0' ' ' < "/proc/$PPID/cmdline" > "$d/cmdparent$n"
    keyfile=""; prev=""
    for a in "$@"; do [ "$prev" = "--key-file" ] && keyfile=$a; prev=$a; done
    # udisksctl opens --key-file as a path and never reads "-" as stdin, so the stub opens it the same way.
    if ! cat < "$keyfile" > "$d/stdin$n" 2>/dev/null; then
      echo "Error unlocking /dev/sdb1: Failed to open file \"$keyfile\": No such file or directory" >&2
      exit 1
    fi
    if [ -z "$mode" ] && [ "$n" -eq 1 ]; then
      echo "Fehler beim Entsperren von /dev/sdb1: GDBus.Error:org.freedesktop.UDisks2.Error.Failed: Fehler beim Aktivieren des Geräts: Operation nicht erlaubt" >&2
      exit 1
    fi
    if [ -z "$mode" ] && [ "$n" -eq 2 ]; then
      echo "Fehler: GDBus.Error:org.freedesktop.UDisks2.Error.NotAuthorized: Legitimierung wurde abgebrochen" >&2
      exit 1
    fi
    if [ -f "$d/unlocked" ]; then
      echo "Error unlocking /dev/sdb1: GDBus.Error:org.freedesktop.UDisks2.Error.Failed: Device /dev/sdb1 is already unlocked" >&2
      exit 1
    fi
    if has hang; then echo "$$" > "$d/hangpid"; exec sleep 60; fi
    if has latesuccess; then echo "$$" > "$d/hangpid"; while [ ! -f "$d/go" ]; do sleep 0.2; done; fi
    if has latefail; then echo "$$" > "$d/hangpid"; while [ ! -f "$d/go" ]; do sleep 0.2; done; echo "Error unlocking /dev/sdb1: GDBus.Error:org.freedesktop.UDisks2.Error.Failed: Device busy" >&2; exit 1; fi
    : > "$d/unlocked"
    echo "Unlocked /dev/sdb1 as /dev/dm-0."
    ;;
  mount)
    if has mounthang; then echo "$$" > "$d/mountpid"; exec sleep 60; fi
    if has mountfail; then
      echo "Error mounting /dev/dm-0: GDBus.Error:org.freedesktop.UDisks2.Error.Failed: not today" >&2
      exit 1
    fi
    echo "Mounted /dev/dm-0 at /run/media/gm/Backup."
    ;;
  lock)
    printf '%s\n' "$*" >> "$d/lockcalls"
    if has lockfail; then
      echo "Error locking /dev/sdb1: GDBus.Error:org.freedesktop.UDisks2.Error.DeviceBusy: busy" >&2
      exit 1
    fi
    rm -f "$d/unlocked"
    ;;
  *) exit 2 ;;
esac
EOF
sed -i "s|@STUB@|$test_root/stub|" "$test_root/stub/udisksctl.live" || exit 1
# The dead stub names an interpreter that does not exist, so exec fails and the child never starts.
printf '#!/nonexistent/interpreter\n' > "$test_root/stub/udisksctl.dead" || exit 1
chmod +x "$test_root/stub/udisksctl.live" "$test_root/stub/udisksctl.dead" || exit 1
ln -s "$test_root/stub/udisksctl.live" "$test_root/bin/udisksctl" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    PATH="$test_root/bin:$PATH" UNLOCK_TEST_ROOT="$test_root" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 90 qs -p "$test_root/config" 2>&1)
qs_status=$?

# Sample input, a probe line "  INFO qml: UNLOCKSTDIN PASS retry-unlocks-and-mounts", then the receipt "UNLOCKSTDIN DONE failures=0".
pass_count=$(printf '%s\n' "$output" | grep -c 'UNLOCKSTDIN PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'UNLOCKSTDIN FAIL')
done_count=$(printf '%s\n' "$output" | grep -c 'UNLOCKSTDIN DONE')
expected_passes=64
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
# The bytes: the secret alone, no trailing newline, on every attempt but one (twenty attempts reach a child, the dead one and the queued ones never do; the Cancel-before-start attempt closed stdin before any key was written, so its recorder holds EOF alone).
empty_stdins=0
for f in "$test_root"/stub/stdin*; do
    if [ ! -s "$f" ]; then
        empty_stdins=$((empty_stdins + 1))
    elif ! printf '%s' "$CANARY" | cmp -s - "$f"; then
        printf 'FAIL %s did not hold exactly the secret with no newline\n' "$f"
        verdict=1
    fi
done
[ "$(find "$test_root/stub" -name 'stdin*' | wc -l)" -eq 20 ] || { printf 'FAIL want 20 recorded unlock stdins\n'; verdict=1; }
[ "$empty_stdins" -eq 1 ] || { printf 'FAIL want exactly 1 empty early-cancel stdin, got %s\n' "$empty_stdins"; verdict=1; }
# UL9 plus the cancelled unlocks: every dialog that ended without a mounted volume locked the container once.
locks=$(grep -c '^lock --block-device /dev/sdb1$' "$test_root/stub/lockcalls" 2>/dev/null)
all_locks=$(wc -l < "$test_root/stub/lockcalls" 2>/dev/null)
if [ "${locks:-0}" -ne 10 ] || [ "${all_locks:-0}" -ne 11 ]; then
    printf 'FAIL want exactly 10 lock calls on /dev/sdb1 and one on /dev/sdc1, got %s of %s\n' "${locks:-0}" "${all_locks:-0}"
    verdict=1
fi
# The secret never reaches argv; the unlock line names the device and the key file only.
for f in "$test_root"/stub/argv* "$test_root/stub/lockcalls"; do
    if grep -qF "$CANARY" "$f"; then
        printf 'FAIL the passphrase reached argv in %s\n' "$f"
        verdict=1
    fi
done
grep -q -- '--key-file' "$test_root/stub/argv1" || { printf 'FAIL the unlock argv names no key file\n'; verdict=1; }
grep -q -- '/dev/sdb1' "$test_root/stub/argv1" || { printf 'FAIL the unlock argv names no device\n'; verdict=1; }
# The waiting child's cmdline and environ and its parent's cmdline carry no secret bytes.
for f in "$test_root"/stub/cmdself* "$test_root"/stub/envself* "$test_root"/stub/cmdparent* "$test_root"/stub/childenv*; do
    if grep -qF "$CANARY" "$f"; then
        printf 'FAIL the canary reached %s\n' "$f"
        verdict=1
    fi
done
[ -f "$test_root/stub/cmdself1" ] || { printf 'FAIL no live child dump was recorded\n'; verdict=1; }
# The child runs under LC_ALL=C, so udisksctl's own wording is deterministic.
grep -q '^LC_ALL=C$' "$test_root/stub/childenv1" || { printf 'FAIL the unlock child ran without LC_ALL=C\n'; verdict=1; }
# Every log the flow writes: the qs log carries no canary bytes.
if printf '%s\n' "$output" | grep -qF "$CANARY"; then
    printf 'FAIL the canary reached the qs log\n'
    verdict=1
fi
# S5: no Ipc.qml reader names the field, the secret holder or the passphrase.
for word in passphrase Passphrase _secret "field.text"; do
    if grep -qF "$word" ui/Ipc.qml; then
        printf 'FAIL ui/Ipc.qml names %s\n' "$word"
        verdict=1
    fi
done
# S7: no file written; the rig's own shell.qml types the canary, so the grep is proved against it as the control.
if [ "$(grep -rFl "$CANARY" "$test_root/config" | wc -l)" -eq 0 ]; then
    printf 'FAIL the control grep found no canary in the rig shell.qml\n'
    verdict=1
fi
if grep -rF "$CANARY" "$test_root/home" "$test_root/state" "$test_root/runtime" 2>/dev/null; then
    printf 'FAIL the canary reached a product-written file\n'
    verdict=1
fi
# The offscreen platform itself says it cannot mask a FloatingWindow; that one line is the platform's, never the dialog's.
platform_warning='This plugin does not support setting window masks'
# The dead stub phase makes Quickshell say once that it could not start udisksctl; any second such line is a real failure.
dead_warning='Process failed to start, likely because the binary could not be found. Command: QList("udisksctl", "unlock"'
if [ "$(printf '%s\n' "$output" | grep -acF "$dead_warning")" -ne 1 ]; then
    printf 'FAIL want exactly one failed-to-start warning from the dead stub\n'
    verdict=1
fi
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN|ERROR' | grep -vF "$platform_warning" | grep -vF "$dead_warning")
if [ -n "$warnings" ]; then
    printf 'FAIL the unlock harness logged a warning\n'
    printf '%s\n' "$warnings"
    verdict=1
fi
if [ "$verdict" -ne 0 ]; then
    printf '%s\n' "$output"
    exit 1
fi
printf '%s\n' "$output" | grep -o 'UNLOCKSTDIN PASS.*'
printf 'UNLOCKSTDIN STATUS qs_exit=%s done=1\n' "$qs_status"
