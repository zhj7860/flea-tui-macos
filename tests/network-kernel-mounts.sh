#!/usr/bin/env bash
# Issue #257: fake gio and mountinfo text into the real NetworkMounts.rebuild; the stub gio logs every call, so kernel rows classify from text and release once.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

test_root="$FIXTURE_ROOT/flea-network-kernel-mounts-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/bin" "$test_root/home" "$test_root/config" "$test_root/mutant"
# One config per leg: the shipped files linked, except the mutant leg's NetworkMounts.qml, a sed edit written inside the sandbox.
make_config() {
    local dir=$1 nm=$2
    ln -s "$nm" "$dir/NetworkMounts.qml"
    ln -s "$PWD/ui/MountListing.qml" "$dir/MountListing.qml"
    ln -s "$PWD/ui/NetworkPlaces.qml" "$dir/NetworkPlaces.qml"
    ln -s "$PWD/ui/GvfsBridge.qml" "$dir/GvfsBridge.qml"
    ln -s "$PWD/ui/js" "$dir/js"
    ln -s "$PWD/tests/network-kernel-mounts.qml" "$dir/shell.qml"
}
make_config "$test_root/config" "$PWD/ui/NetworkMounts.qml"
gio_log="$test_root/gio.log"
fuse_log="$test_root/fuse.log"

cat > "$test_root/bin/gio" <<'EOS'
#!/bin/sh
echo "$*" >> "$FLEA_TEST_GIO_LOG"
case "$1 $2" in
  "mount -u") exit 0 ;;
  "mount -li") exit 0 ;;
esac
exit 64
EOS
chmod +x "$test_root/bin/gio"

cat > "$test_root/bin/fusermount3" <<'EOS'
#!/bin/sh
echo "$*" >> "$FLEA_TEST_FUSE_LOG"
exit 0
EOS
chmod +x "$test_root/bin/fusermount3"

command -v strace >/dev/null || { echo "FAIL strace is not installed, so the automount trace cannot run"; exit 1; }
idle_path=/mnt/flea-idle-automount
# One leg: qs under strace, every call that names a path traced, so a stat, statfs or open of the idle automount shows in the file.
run_leg() {
    env \
        FLEA_TEST_GIO_LOG="$gio_log" \
        FLEA_TEST_FUSE_LOG="$fuse_log" \
        HOME="$test_root/home" \
        PATH="$test_root/bin:/usr/bin:/bin" \
        QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic \
        QT_FORCE_STDERR_LOGGING=1 \
        timeout 15 strace -f --seccomp-bpf -qq -o "$2" -e trace=%file qs -p "$1" 2>&1
}

output=$(run_leg "$test_root/config" "$test_root/trace.log")

# 22 checks: 16 row checks, 2 automount checks and 4 flow checks; the qml counts what passed, so a dropped check fails here.
pass_count=$(printf '%s\n' "$output" | grep -cE 'NETWORK_KERNEL_MOUNTS DONE checks=22([^0-9]|$)')
fail_count=$(printf '%s\n' "$output" | grep -c 'NETWORK_KERNEL_MOUNTS FAIL')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL kernel mounts did not list, open and unmount\n%s\n' "$output"
    exit 1
fi
# Sample input: the gio log holds only "mount -u file:///mnt/kmount-iso", the cifs unmount, beside one fusermount3 call for the rclone unmount.
calls=$(cat "$gio_log" 2>/dev/null || true)
if [ "$calls" != "mount -u file:///mnt/kmount-iso" ]; then
    printf 'FAIL gio heard more than the one unmount:\n%s\n%s\n' "$calls" "$output"
    exit 1
fi
fuse_calls=$(cat "$fuse_log" 2>/dev/null || true)
want_fuse="$(printf -- '-u /mnt/kmount-rclone\n-u %s/gdrive' "$test_root/home")"
if [ "$fuse_calls" != "$want_fuse" ]; then
    printf 'FAIL fusermount3 heard more than the one unmount:\n%s\n%s\n' "$fuse_calls" "$output"
    exit 1
fi

# Sample input, one trace line: 'openat(AT_FDCWD, "/proc/self/mountinfo", O_RDONLY|O_CLOEXEC) = 25'; it proves the trace saw qs open /proc/self/mountinfo, so a trace with no automount line is a live trace.
if ! grep -q '"/proc/self/mountinfo"' "$test_root/trace.log"; then
    printf 'FAIL the trace never saw qs open /proc/self/mountinfo, so a trace with no automount line proves nothing\n'
    exit 1
fi
touched=$(grep -c "$idle_path" "$test_root/trace.log")
if [ "$touched" -ne 0 ]; then
    printf 'FAIL the rail reached the idle automount %s, which would trigger the mount:\n' "$idle_path"
    grep "$idle_path" "$test_root/trace.log" | head -5
    exit 1
fi

# Mutant: the rail opens every autofs mountpoint it reads; the same trace must now name the idle path, or the check above cannot fail.
sed -e '/^    function rebuild(mountinfoText) {/i\    FileView { id: mutantProbe; blockLoading: true; printErrors: false }' \
    -e '/var kernels = Cloud.parseNetworkMounts(infoText)/a\        infoText.split("\\n").forEach(function (l) { if (l.indexOf(" - autofs ") > 0) mutantProbe.path = l.split(" ")[4] })' \
    "$PWD/ui/NetworkMounts.qml" > "$test_root/mutant/NetworkMounts.qml"
if cmp -s "$PWD/ui/NetworkMounts.qml" "$test_root/mutant/NetworkMounts.qml" || [ "$(grep -c 'mutantProbe' "$test_root/mutant/NetworkMounts.qml")" -ne 2 ]; then
    printf 'FAIL the mutant edit did not apply to ui/NetworkMounts.qml\n'
    exit 1
fi
mkdir "$test_root/mutant/config"
make_config "$test_root/mutant/config" "$test_root/mutant/NetworkMounts.qml"
{ run_leg "$test_root/mutant/config" "$test_root/mutant/trace.log" >/dev/null; } 2>/dev/null
if ! grep -q "$idle_path" "$test_root/mutant/trace.log"; then
    printf 'FAIL the mutant that opens the idle automount left no trace line, so the trace check is blind\n'
    exit 1
fi

printf 'mutant leg red as wanted: %s\n' "$(grep -m1 "$idle_path" "$test_root/mutant/trace.log")"
printf 'network-kernel-mounts: gio rows join mountinfo rows, open direct, unmount once, idle automount never touched\n'
