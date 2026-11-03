#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# Cursor steps through a real Pane serialize no held row, offscreen with the real backend; counts only, no timing.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
command -v qs >/dev/null || { echo 'FAIL navcost: qs is missing'; exit 1; }
root=$(mktemp -d "$FIXTURE_ROOT/navcost-XXXXXXXX") || exit 1
sandbox_require "$root" || exit 1
: > "$root/$SANDBOX_MARKER" || exit 1
trap 'sandbox_remove "$root"' EXIT
mkdir -p "$root/config" "$root/home" "$root/state/flea" "$root/cache" "$root/runtime" "$root/fixture" || exit 1
chmod 700 "$root/runtime" || exit 1
ln -s "$PWD/ui" "$root/config/flea" || exit 1
headless_commons "$root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$root/config/Ui" || exit 1
cp tests/navcost.qml "$root/config/shell.qml" || exit 1
# Forty files fit one held window at this size, so no refetch replaces the counted rows.
files=40
for i in $(seq -w 1 "$files"); do printf 'row %s\n' "$i" > "$root/fixture/file-$i.txt"; done
printf '%s\n' '{"updates":{"autoCheck":false},"view":"list"}' > "$root/state/flea/ui.json" || exit 1
env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$root/home" XDG_STATE_HOME="$root/state" XDG_CACHE_HOME="$root/cache" XDG_RUNTIME_DIR="$root/runtime" \
    FLEA_BIN="$PWD/target/debug/flea" FLEA_NAVCOST_DIR="$root/fixture" FLEA_NAVCOST_FILES="$files" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 30 qs -p "$root/config" > "$root/probe.log" 2>&1
status=$?
cat "$root/probe.log"
[ "$status" -eq 0 ] || { printf 'FAIL navcost: qs exit %s\n' "$status"; exit 1; }
# Sample input, one probe line: " DEBUG qml: NAVCOST DONE 9 checks, 0 failed"
[ "$(grep -c 'NAVCOST DONE .* checks, 0 failed' "$root/probe.log")" -eq 1 ] \
    || { echo 'FAIL navcost: no single "NAVCOST DONE ... 0 failed" summary line'; exit 1; }
grep -qE 'NAVCOST FAIL|TypeError|ReferenceError|Binding loop' "$root/probe.log" \
    && { echo 'FAIL navcost: the probe log holds a NAVCOST FAIL, TypeError, ReferenceError or binding loop line'; exit 1; }
echo 'navcost: cursor steps serialize no held row and the menu identity keeps its content rule'
