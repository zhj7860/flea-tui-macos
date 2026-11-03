#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# Back and Forward return the cursor to the row they left in every view, offscreen with no display or lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "cursorback.sh: qs is not installed, cannot drive the window"
    exit 1
fi

# A destructive test writes and deletes only inside a mktemp -d root of its own with a marker file.
sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-cursorback.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

# The binary the probe's shell stage shells out to for its ui-state write.
bin=${FLEA_BIN:-$PWD/target/debug/flea}
command -v dbus-run-session >/dev/null || { echo 'FAIL cursorback needs private D-Bus'; exit 1; }
command -v rg >/dev/null || { echo 'FAIL cursorback needs ripgrep for its tally, count and warning gates'; exit 1; }
[[ -x "$bin" ]] || { echo 'FAIL cursorback needs the candidate backend'; exit 1; }

# One probe run in the given view; dual launches straight into dual, where both panes build at startup.
run_probe() {
    local view=$1 want_checks=$2 tag=$3 dual_env=
    local root="$test_root/$tag"
    mkdir -p "$root"/{home,config,state,data,cache,runtime} "$root/home/fixture"/{alpha,mid,zeta} || exit 1
    chmod 700 "$root/runtime" || exit 1
    printf 'inside mid\n' > "$root/home/fixture/mid/inner.txt" || exit 1
    printf 'first in mid\n' > "$root/home/fixture/mid/aaa.txt" || exit 1
    env HOME="$root/home" XDG_STATE_HOME="$root/state" "$bin" --ui-state \
        "{\"view\":\"$view\",\"keys\":\"default\",\"preview\":{\"column\":false,\"thumbnails\":\"off\"},\"updates\":{\"autoCheck\":false},\"display\":{\"textSize\":{\"mode\":14}}}" >/dev/null || exit 1
    ln -s "$PWD/ui" "$root/config/flea" || exit 1
    headless_commons "$root" || exit 1
    ln -s "$(readlink -f ui/boot/Ui)" "$root/config/Ui" || exit 1
    ln -s "$PWD/ui/boot/fleatab.qml" "$root/config/fleatab.qml" || exit 1
    cp tests/cursorback.qml "$root/config/shell.qml" || exit 1
    if [ "$tag" = dual ]; then dual_env=CURSORBACK_DUAL=1; fi
    local log="$root/qs.log"
    # Sample input: "CURSORBACK DONE failures=0" beside "CURSORBACK PASS checks=51" (the dual run answers 8).
    env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u FLEA_SELECT \
        HOME="$root/home" XDG_STATE_HOME="$root/state" XDG_CONFIG_HOME="$root/config" \
        XDG_DATA_HOME="$root/data" XDG_CACHE_HOME="$root/cache" XDG_RUNTIME_DIR="$root/runtime" \
        FLEA_PATH="$root/home/fixture" FLEA_BIN="$bin" $dual_env GIO_USE_VOLUME_MONITOR=unix QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic \
        QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
        timeout 120 dbus-run-session -- qs -p "$root/config" > "$log" 2>&1
    local status=$?
    [[ "$status" == 143 ]] || { printf 'FAIL cursorback %s: qs exit %s, expected the owned self-kill 143 after DONE\n' "$tag" "$status"; return 1; }
    rg -q "CURSORBACK DONE failures=0" "$log" || { echo "FAIL cursorback $tag: tally is not every check passed"; return 1; }
    [[ "$(rg -c 'CURSORBACK ok ' "$log")" == "$want_checks" ]] || { echo "FAIL cursorback $tag: passed count"; return 1; }
    if rg 'CURSORBACK FAIL|TypeError|ReferenceError|ERROR|Cannot assign|WARN' "$log" | rg -vF 'This plugin does not support setting window masks'; then
        echo "FAIL cursorback $tag: a failed check or an engine warning"
        return 1
    fi
    printf 'CURSORBACK %s STATUS qs_exit=%s checks=%s\n' "$tag" "$status" "$want_checks"
}

verdict=0
run_probe list 51 views || verdict=1
run_probe dual 8 dual || verdict=1
if [ "$verdict" -ne 0 ]; then
    rg 'CURSORBACK' "$test_root"/*/qs.log
    exit 1
fi
printf 'CURSORBACK STATUS checks=59\n'
