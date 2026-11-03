#!/usr/bin/env bash
# Drives every column move, no-carry navigation, superseding landing, and real cap and loading minimum offscreen.
. "$(dirname "$0")/headless-commons.sh"
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
command -v qs >/dev/null || { echo 'FAIL columnsmoves: qs is missing'; exit 1; }
sandbox_root_ok
root=$(mktemp -d "$SANDBOX_ROOT/columnsmoves-XXXXXXXX") || exit 1
: > "$root/$SANDBOX_MARKER" || exit 1
trap 'sandbox_remove "$root"' EXIT
mkdir -p "$root/config" "$root/home" "$root/state" "$root/cache" "$root/runtime" || exit 1
chmod 700 "$root/runtime" || exit 1
ln -s "$PWD/ui" "$root/config/flea" || exit 1
headless_commons "$root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$root/config/Ui" || exit 1
cp tests/columnsmoves.qml "$root/config/shell.qml" || exit 1
cp tests/columnsframes.js "$root/config/columnsframes.js" || exit 1
env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$root/home" XDG_STATE_HOME="$root/state" XDG_CACHE_HOME="$root/cache" XDG_RUNTIME_DIR="$root/runtime" \
    FLEA_BIN="$PWD/target/debug/flea" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 120 qs -p "$root/config" > "$root/moves.log" 2>&1
status=$?
grep -a 'COLUMNMOVES' "$root/moves.log" | sed 's/^.*qml: //'
# Sample input: " INFO qml: COLUMNMOVES DONE 12 moves, 0 failed".
if [ "$status" -ne 0 ] || ! grep -q 'COLUMNMOVES DONE 12 moves, 0 failed' "$root/moves.log" \
    || grep -qE 'TypeError|ReferenceError|Binding loop|COLUMNMOVES (FAIL|CONTROL FAIL)' "$root/moves.log"; then
    tail -n 25 "$root/moves.log"
    echo "FAIL columnsmoves: column move frames or timers (qs exit $status)"
    exit 1
fi

for mutant in previous-read cap-start minimum-start expire-start loading-copy old-begin; do
    leg="$root/$mutant"
    sandbox_require "$leg" || exit 1
    mkdir -p "$leg/config" "$leg/home" "$leg/state" "$leg/cache" "$leg/runtime" || exit 1
    : > "$leg/$SANDBOX_MARKER" || exit 1
    chmod 700 "$leg/runtime" || exit 1
    cp -a "$PWD/ui" "$leg/ui" || exit 1
    python3 - "$leg/ui/ColumnsLanding.qml" "$mutant" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
mutant = sys.argv[2]
source = path.read_text()
changes = {
    'previous-read': ('root : root.previous', 'root : null'),
    'cap-start': ('cap.start()', 'cap.stop()'),
    'minimum-start': ('minShow.start()', 'minShow.stop()'),
    'expire-start': ('state.expired = true',
                     '{ state.expired = true; for (var path of Object.keys(state.held)) root.earlyMark(path, true) }'),
    'loading-copy': ('loading: reading', 'loading: false'),
    'old-begin': ('if (!carry) root.previous = null\n        else if (root.target === root.area.pane.path)',
                  'if (root.target === root.area.pane.path)'),
}
before, after = changes[mutant]
assert source.count(before) == 1, f'{mutant}: mutation target was not unique'
source = source.replace(before, after, 1)
if mutant == 'expire-start':
    signature = 'function markShown(path, shown) {'
    assert source.count(signature) == 1, 'expire-start: shown handler was not unique'
    source = source.replace(signature, 'function markShown(path, shown) {}\n    function earlyMark(path, shown) {', 1)
path.write_text(source)
PY
    [ "$?" -eq 0 ] || exit 1
    ln -s "$leg/ui" "$leg/config/flea" || exit 1
    headless_commons "$leg" || exit 1
    ln -s "$(readlink -f ui/boot/Ui)" "$leg/config/Ui" || exit 1
    cp tests/columnsmoves.qml "$leg/config/shell.qml" || exit 1
    cp tests/columnsframes.js "$leg/config/columnsframes.js" || exit 1
    env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$leg/home" XDG_STATE_HOME="$leg/state" XDG_CACHE_HOME="$leg/cache" XDG_RUNTIME_DIR="$leg/runtime" \
        FLEA_BIN="$PWD/target/debug/flea" \
        QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
        timeout 120 qs -p "$leg/config" > "$leg/moves.log" 2>&1
    status=$?
    case $mutant in
        previous-read) expected='CONTROL FAIL superseding request keeps the on-screen ancestor' ;;
        cap-start) expected='CONTROL FAIL real cap timer replaces held rows with reading' ;;
        minimum-start) expected='CONTROL FAIL real minimum timer releases the reply timed out' ;;
        expire-start) expected='CONTROL FAIL reply during the shown minimum stays covered' ;;
        loading-copy) expected='CONTROL FAIL superseding landing carries the shown reading state' ;;
        old-begin) expected='CONTROL FAIL hidden navigations keep no previous landing' ;;
    esac
    if [ -n "${FLEA_CI_SUITE_LOGS:-}" ]; then
        cp "$leg/moves.log" "$FLEA_CI_SUITE_LOGS/columnsmoves-$mutant.control.log" || exit 1
    fi
    if [ "$status" -ne 0 ] || ! grep -qF "$expected" "$leg/moves.log" \
        || grep -qE 'TypeError|ReferenceError|Binding loop' "$leg/moves.log"; then
        tail -n 25 "$leg/moves.log"
        echo "FAIL columnsmoves: $mutant was not rejected by its regression control (qs exit $status)"
        exit 1
    fi
    if [ "$mutant" = old-begin ] && ! grep -qF 'CONTROL FAIL begin with no carry keeps no previous landing' "$leg/moves.log"; then
        tail -n 25 "$leg/moves.log"
        echo 'FAIL columnsmoves: old-begin was not rejected by the single-step no-carry control'
        exit 1
    fi
    echo "COLUMNMOVES MUTANT rejected $mutant by its regression control"
done
