#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# A release in flight outlives the surface that asked for it: the real window against gio doubles that take time.
set -u
cd "$(dirname "$0")/.." || exit 1
. "$PWD/tools/flea-sandbox-guard"
command -v qs >/dev/null || { echo 'FAIL hidden-release needs qs'; exit 1; }
command -v dbus-run-session >/dev/null || { echo 'FAIL hidden-release needs a private D-Bus session'; exit 1; }
real_gio=$(command -v gio) || { echo 'FAIL hidden-release needs a gio to stand behind its double'; exit 1; }
bin=${FLEA_BIN:-$PWD/target/debug/flea}
[[ -x "$bin" ]] || { echo 'FAIL hidden-release needs the built backend'; exit 1; }
sandbox_root_ok
probe=$(mktemp -d "$SANDBOX_ROOT/flea-hidden-release.XXXXXX") || exit 1
: > "$probe/$SANDBOX_MARKER" || exit 1
qs_pid=""
stop_qs() {
    [[ -n "$qs_pid" ]] || return 0
    local tick
    kill -TERM -- "-$qs_pid" 2>/dev/null || true
    for ((tick = 0; tick < 20; tick++)); do
        kill -0 -- "-$qs_pid" 2>/dev/null || break
        sleep 0.1
    done
    kill -0 -- "-$qs_pid" 2>/dev/null && kill -KILL -- "-$qs_pid" 2>/dev/null
    wait "$qs_pid" 2>/dev/null || true
    if kill -0 -- "-$qs_pid" 2>/dev/null; then
        printf 'FAIL hidden-release owned process group %s survived teardown\n' "$qs_pid"
        return 1
    fi
    qs_pid=""
}
cleanup() { stop_qs || return 1; sandbox_remove "$probe"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$probe"/{home,config,state,data,cache,runtime,bin} "$probe"/mnt/{Data,Busy,Slow,Rail,Other,Held} || exit 1
# A listing of an empty folder is not "ready", so each place holds one file.
for d in "$probe/home" "$probe"/mnt/*; do printf x > "$d/note.txt" || exit 1; done
chmod 700 "$probe/runtime"
# lsblk answers one second disk whose volumes are mounted until their gio unmount leaves a .done marker.
cat > "$probe/bin/lsblk" <<'SH'
#!/usr/bin/env bash
box=${FLEA_HR_BOX:?}
[[ "$box" == /* && -f "$box/.flea-test-sandbox" ]] || exit 90
volume() {
    local mountpoint=null
    [[ -e "$box/${1,,}.done" ]] || mountpoint="\"$box/mnt/$1\""
    printf '{"name":"sdb%s","path":"/dev/sdb%s","label":"%s","mountpoints":[%s],"rm":false,"tran":null,"size":1000398934016,"type":"part","model":null,"fstype":"ext4","parttypename":"Linux filesystem"}' "$2" "$2" "$1" "$mountpoint"
}
printf '{"blockdevices":[{"name":"nvme0n1","path":"/dev/nvme0n1","label":null,"mountpoints":[null],"rm":false,"tran":"nvme","size":256060514304,"type":"disk","model":"KBG40ZNS256G","fstype":null,"parttypename":null,"children":[{"name":"nvme0n1p1","path":"/dev/nvme0n1p1","label":null,"mountpoints":["/"],"rm":false,"tran":null,"size":256060514304,"type":"part","model":null,"fstype":"btrfs","parttypename":"Linux filesystem"}]},'
printf '{"name":"sdb","path":"/dev/sdb","label":null,"mountpoints":[null],"rm":false,"tran":"sata","size":2000398934016,"type":"disk","model":"Samsung SSD 870","fstype":null,"parttypename":null,"children":['
volume Data 1; printf ','; volume Busy 2; printf ','; volume Slow 3; printf ','; volume Rail 4; printf ','; volume Other 5; printf ','; volume Held 6
printf ']}]}\n'
SH
# Each unmount leaves a started marker, waits like a real one, and ends the way its volume is meant to.
cat > "$probe/bin/gio" <<'SH'
#!/usr/bin/env bash
box=${FLEA_HR_BOX:?}
[[ "$box" == /* && -f "$box/.flea-test-sandbox" ]] || exit 90
case "$*" in
    "mount -u $box/mnt/Data") : > "$box/data.started"; sleep 0.3; : > "$box/data.done" ;;
    "mount -u $box/mnt/Busy") : > "$box/busy.started"; sleep 0.3; echo "target is busy" >&2; exit 1 ;;
    "mount -u $box/mnt/Slow") : > "$box/slow.started"; sleep 1.5; : > "$box/slow.done" ;;
    "mount -u $box/mnt/Rail") : > "$box/rail.started"; sleep 0.6; : > "$box/rail.done" ;;
    "mount -u $box/mnt/Held") : > "$box/held.started"; sleep 4; : > "$box/held.ended"; echo "target is busy" >&2; exit 1 ;;
    *) exec REAL_GIO "$@" ;;
esac
SH
sed -i "s|REAL_GIO|$real_gio|" "$probe/bin/gio" || exit 1
chmod 700 "$probe/bin/lsblk" "$probe/bin/gio" || exit 1
env HOME="$probe/home" XDG_STATE_HOME="$probe/state" "$bin" --ui-state \
    '{"preview":{"column":false,"thumbnails":"off"},"updates":{"autoCheck":false}}' >/dev/null || exit 1
ln -s "$PWD/ui" "$probe/config/flea"
headless_commons "$probe" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$probe/config/Ui"
ln -s "$PWD/ui/boot/fleatab.qml" "$probe/config/fleatab.qml"
cp tests/hidden-release.qml "$probe/config/shell.qml"
log="$probe/qs.log"
env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u FLEA_SELECT \
    HOME="$probe/home" XDG_STATE_HOME="$probe/state" XDG_CONFIG_HOME="$probe/config" \
    XDG_DATA_HOME="$probe/data" XDG_CACHE_HOME="$probe/cache" XDG_RUNTIME_DIR="$probe/runtime" \
    PATH="$probe/bin:$PATH" FLEA_HR_BOX="$probe" \
    FLEA_PATH="$probe/mnt/Data" FLEA_BIN="$bin" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic \
    QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 setsid dbus-run-session -- qs -p "$probe/config" >"$log" 2>&1 </dev/null &
qs_pid=$!
for ((tick = 0; tick < 900; tick++)); do
    grep -aq 'HIDDEN_RELEASE DONE checks=[0-9]* failed=[0-9]*' "$log" && break
    sleep 0.1
done
stop_qs || exit 1
grep -aE 'HIDDEN_RELEASE|TypeError|ReferenceError|ERROR|Cannot assign' "$log"
# Sample input, the receipt: "  INFO qml: HIDDEN_RELEASE DONE checks=18 failed=0"
tally=$(grep -ao 'HIDDEN_RELEASE DONE checks=[0-9]* failed=[0-9]*' "$log" | tail -1)
[[ -n "$tally" ]] || { printf 'FAIL hidden-release produced no completion receipt inside 90s; log tail:\n'; tail -20 "$log"; exit 1; }
[[ "$tally" == *' failed=0' ]] || exit 1
if grep -aqE 'TypeError|ReferenceError|ERROR|Cannot assign' "$log"; then
    echo 'FAIL hidden-release logged an engine error beside its receipt'
    exit 1
fi
printf 'hidden-release: owned process group gone\n'
