#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# 31 Columns Back landings over a real ColumnsArea offscreen, each whole in its first frame.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
command -v qs >/dev/null || { echo 'FAIL columnsback: qs is missing'; exit 1; }
rounds=${FLEA_COLUMNSBACK_ROUNDS:-1}
case "$rounds" in ''|*[!0-9]*|0*) echo "FAIL columnsback: FLEA_COLUMNSBACK_ROUNDS='$rounds' is not a positive integer"; exit 2 ;; esac
ui_dir=${FLEA_COLUMNSBACK_UI:-$PWD/ui}
[ -f "$ui_dir/ColumnsArea.qml" ] || { echo "FAIL columnsback: no ColumnsArea.qml under $ui_dir"; exit 1; }
root=$(mktemp -d "$FIXTURE_ROOT/columnsback-XXXXXXXX") || exit 1
sandbox_require "$root" || exit 1
: > "$root/$SANDBOX_MARKER" || exit 1
trap 'sandbox_remove "$root"' EXIT
mkdir -p "$root/config" "$root/home" "$root/state" "$root/runtime" || exit 1
chmod 700 "$root/runtime" || exit 1
ln -s "$ui_dir" "$root/config/flea" || exit 1
headless_commons "$root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$root/config/Ui" || exit 1
cp tests/columnsback.qml "$root/config/shell.qml" || exit 1
for round in $(seq "$rounds"); do
    env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$root/home" XDG_STATE_HOME="$root/state" XDG_RUNTIME_DIR="$root/runtime" \
        QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
        timeout 120 qs -p "$root/config" > "$root/probe.log" 2>&1
    status=$?
    # Sample input: " INFO qml: CB LAND launch=1 shape=back1 key2ask=0 ask2land=12 landTurn=9 firstFrame=24 whole=24 late=0 ...".
    grep -a -E 'CB (LAND|LATE|DOWN|BENCH)|COLUMNSBACK' "$root/probe.log" | sed 's/^.*qml: //'
    grep -qE 'TypeError|ReferenceError|Binding loop' "$root/probe.log" \
        && { grep -E 'TypeError|ReferenceError|Binding loop' "$root/probe.log" | head -5; echo "FAIL columnsback: round $round logged a TypeError, ReferenceError or binding loop"; exit 1; }
    [ "$(grep -c 'COLUMNSBACK PASS' "$root/probe.log")" -eq 1 ] && [ "$(grep -c 'COLUMNSBACK FAIL' "$root/probe.log")" -eq 0 ] \
        || { tail -n 20 "$root/probe.log"; echo "FAIL columnsback: round $round (qs exit $status) did not land every Back whole in its first frame"; exit 1; }
done
echo "columnsback: $rounds rounds of 31 Columns Back landings drew parent, active and child whole in their first frame"
