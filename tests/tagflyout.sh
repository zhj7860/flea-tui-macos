#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# A Tags flyout choice toggles in place and leaves the menu and flyout open, and Copy as still closes; the real pane and backend, offscreen, no display or lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "tagflyout.sh: qs is not installed, cannot build the pane"
    exit 1
fi
command -v dbus-run-session >/dev/null || { echo 'FAIL tagflyout needs private D-Bus'; exit 1; }
bin=${FLEA_BIN:-$PWD/target/debug/flea}
[[ -x "$bin" ]] || { echo 'FAIL tagflyout needs the candidate backend'; exit 1; }

test_root="$FIXTURE_ROOT/flea-tagflyout-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root"/{home,config,state,data,cache,runtime} "$test_root/home/fixture" || exit 1
chmod 700 "$test_root/runtime" || exit 1
printf 'one\n' > "$test_root/home/fixture/a.txt"
printf 'two\n' > "$test_root/home/fixture/b.txt"
# Enough more rows that a selection of the first and the last cannot sit inside one held window.
touch "$test_root/home/fixture"/f{001..500}.txt || exit 1
# One of the two files carries Blue, so Blue reads mixed over both; a filesystem without user xattrs cannot hold the fixture.
python3 - "$test_root/home/fixture/a.txt" <<'PY' || { echo 'FAIL tagflyout: the fixture filesystem stores no user.xdg.tags'; exit 1; }
import os, sys
os.setxattr(sys.argv[1], "user.xdg.tags", b"Blue")
assert os.getxattr(sys.argv[1], "user.xdg.tags") == b"Blue"
PY
env HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" "$bin" --ui-state \
    '{"view":"list","keys":"default","preview":{"column":false,"thumbnails":"off"},"updates":{"autoCheck":false},"display":{"textSize":{"mode":14}}}' >/dev/null || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
ln -s "$PWD/ui/boot/fleatab.qml" "$test_root/config/fleatab.qml" || exit 1
cp tests/tagflyout.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u FLEA_SELECT \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CONFIG_HOME="$test_root/config" \
    XDG_DATA_HOME="$test_root/data" XDG_CACHE_HOME="$test_root/cache" XDG_RUNTIME_DIR="$test_root/runtime" \
    FLEA_PATH="$test_root/home/fixture" FLEA_BIN="$bin" GIO_USE_VOLUME_MONITOR=unix QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic \
    QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
    timeout 60 dbus-run-session -- qs -p "$test_root/config" 2>&1)
status=$?

# Sample input: "  INFO qml: TAGFLYOUT PASS 70 checks" then "  INFO qml: TAGFLYOUT DONE failures=0", then the probe's own SIGTERM (143); a failed check logs "TAGFLYOUT FAIL <name>".
readonly qs_status=143
if [ "$status" -ne "$qs_status" ] || ! printf '%s\n' "$output" | grep -aq 'TAGFLYOUT DONE failures=0' \
        || printf '%s\n' "$output" | grep -aq 'TAGFLYOUT FAIL'; then
    printf 'FAIL a Tags flyout choice closed the menu, moved a row, or the leg did not finish (qs exit %s)\n' "$status"
    printf '%s\n' "$output" | grep -aE 'TAGFLYOUT|ERROR|error' | head -30
    exit 1
fi
# The offscreen platform itself says it cannot mask a FloatingWindow; that one line is the platform's, never the menu's.
platform_warning='This plugin does not support setting window masks'
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN' | grep -vF "$platform_warning")
if [ -n "$warnings" ]; then
    printf 'FAIL the Tags flyout leg logged a warning\n%s\n' "$warnings" | head -10
    exit 1
fi
printf '%s\n' "$output" | grep -ao 'TAGFLYOUT PASS.*'
