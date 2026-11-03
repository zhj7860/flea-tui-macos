#!/usr/bin/env bash
# Real WindowBody toggles, shared windows, relaunch persistence and two negative controls.
set -uo pipefail
. "$(dirname "$0")/../tools/flea-sandbox-guard"
. "$(dirname "$0")/headless-commons.sh"
cd "$(dirname "$0")/.." || exit 1
for tool in qs dbus-run-session jq; do
    command -v "$tool" >/dev/null || { printf 'FAIL langtoggle: %s is required\n' "$tool"; exit 1; }
done
bin=${FLEA_BIN:-$PWD/target/debug/flea}
test_root=$(mktemp -d "$FIXTURE_ROOT/flea-langtoggle.XXXXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
mkdir -p "$test_root"/{config,home,state,cache,runtime,fixture/list,fixture/grid,fixture/columns} || exit 1
chmod 700 "$test_root/runtime" || exit 1
for view in list grid columns; do
    printf 'fn main() { let answer = 42; }\n' > "$test_root/fixture/$view/a.rs"
    printf 'plain note\n' > "$test_root/fixture/$view/notes.ini"
done
cp -a ui "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -m ui/boot/Ui)" "$test_root/config/Ui" || exit 1
ln -s "$test_root/config/flea/boot/fleatab.qml" "$test_root/config/fleatab.qml" || exit 1
cp tests/langtoggle.qml "$test_root/config/shell.qml" || exit 1
cp tests/langmark-count.js "$test_root/config/langmark-count.js" || exit 1
# Count the real backend requests in the test copy, including columns' directory peeks.
python3 - "$test_root/config/flea/Backend.qml" <<'PY' || exit 1
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
anchor = '    function send(object) {'
assert source.count(anchor) == 1, 'backend sender anchor changed'
replacement = '    property int langtoggleWalks: 0\n' + anchor + '\n        if (object.c === "list" || object.c === "peek") root.langtoggleWalks++'
path.write_text(source.replace(anchor, replacement))
PY
# Production has one body per process; this test gives each body's IPC handlers unique names.
python3 - "$test_root/config/flea" <<'PY' || exit 1
from pathlib import Path
import sys
root = Path(sys.argv[1])
for name, target in [('Ipc.qml', 'flea'), ('boot/fleatab.qml', 'fleatab')]:
    path = root / name
    source = path.read_text()
    anchor = 'target: "' + target + '"'
    assert source.count(anchor) == 1, 'IPC target anchor changed'
    path.write_text(source.replace(anchor, anchor + ' + String(root).replace(/[^a-zA-Z0-9]/g, "")'))
PY
seed=$(jq -cn --arg path "$test_root/fixture" '{view:"list",dual:{paths:[$path+"/list",$path+"/grid"],focus:0},
    rememberViewPerFolder:true,folderViews:{($path+"/list"):"list",($path+"/grid"):"grid",($path+"/columns"):"columns"},
    preview:{thumbnails:"off",column:false}}')
env HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" "$bin" --ui-state "$seed" > "$test_root/seed.json" || exit 1
jq -e '.langMarks == true' "$test_root/seed.json" >/dev/null || { printf 'FAIL langtoggle: schema default is not on\n'; exit 1; }

probe() {
    local leg="$1" log="$2" status
    env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
        XDG_RUNTIME_DIR="$test_root/runtime" FLEA_BIN="$bin" FLEA_PATH="$test_root/fixture/list" FLEA_REDUCED_MOTION=1 \
        LANGTOGGLE_FIXTURE="$test_root/fixture" \
        LANGTOGGLE_LEG="$leg" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software \
        QT_FORCE_STDERR_LOGGING=1 dbus-run-session -- bash -c 'timeout 75 qs -p "$1" > "$2" 2>&1' \
        _ "$test_root/config" "$log" 2> "$test_root/$leg-bus.log"
    status=$?
    [[ "$status" == 0 || "$status" == 143 ]] || return 1
    grep -aq "LANGTOGGLE DONE leg=$leg .* failures=0" "$log" || return 1
    ! grep -aE 'LANGTOGGLE FAIL|TypeError|ReferenceError|Binding loop|WARN|ERROR' "$log" \
        | grep -vF 'This plugin does not support setting window masks' > "$test_root/$leg-warnings.log"
}

probe peer "$test_root/peer.log" &
peer_pid=$!
# The observer must finish its default-on control before the writer disables marks.
end=$((SECONDS + 25))
until grep -aq 'LANGTOGGLE DEFAULT on=true' "$test_root/peer.log" 2>/dev/null; do
    if (( SECONDS >= end )); then wait "$peer_pid"; cat "$test_root/peer.log"; printf 'FAIL langtoggle: peer never became ready\n'; exit 1; fi
    sleep 0.05
done
probe fresh "$test_root/fresh.log"; fresh_rc=$?
wait "$peer_pid"; peer_rc=$?
probe again "$test_root/again.log"; again_rc=$?
probe saved-off "$test_root/saved-off.log"; saved_off_rc=$?
for leg in fresh peer again saved-off; do
    grep -ao 'LANGTOGGLE .*' "$test_root/$leg.log"
    [ -z "${FLEA_CI_SUITE_LOGS:-}" ] || cp "$test_root/$leg.log" "$FLEA_CI_SUITE_LOGS/langtoggle-$leg.log" || exit 1
done
if (( fresh_rc != 0 || peer_rc != 0 || again_rc != 0 || saved_off_rc != 0 )); then
    printf 'FAIL langtoggle: fresh=%s peer=%s again=%s saved-off=%s\n' "$fresh_rc" "$peer_rc" "$again_rc" "$saved_off_rc"
    exit 1
fi
env HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" "$bin" --ui-state '{"view":"dual","langMarks":true}' > "$test_root/dual.json" || exit 1
probe dual "$test_root/dual.log" || { cat "$test_root/dual.log"; printf 'FAIL langtoggle: dual panes did not switch\n'; exit 1; }
grep -ao 'LANGTOGGLE .*' "$test_root/dual.log"
env HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" "$bin" --ui-state '{"view":"list"}' > "$test_root/single.json" || exit 1

# The wrong schema default reaches the same real window through its validated state file.
env HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" "$bin" --ui-state '{"langMarks":false}' > "$test_root/default-false.json" || exit 1
if probe fresh "$test_root/default-false.log" || ! grep -aq 'LANGTOGGLE FAIL default-on setting' "$test_root/default-false.log"; then
    printf 'FAIL langtoggle: default-false mutant was not rejected\n'; exit 1
fi
printf 'LANGTOGGLE MUTANT default-false rejected by default-on setting\n'

# A live-only writer updates this engine but leaves the real ui.json for relaunch unchanged.
python3 - "$test_root/config/flea/ViewState.qml" <<'PY' || exit 1
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
before = 'function toggleLangMarks() { root.changeKey("langMarks", !root.langMarks) }'
after = 'function toggleLangMarks() { root.state = UiState.withKey(root.state, "langMarks", !root.langMarks) }'
assert source.count(before) == 1, 'language-toggle writer anchor changed'
path.write_text(source.replace(before, after))
PY
env HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" "$bin" --ui-state '{"langMarks":true}' > "$test_root/nonpersist.json" || exit 1
probe again "$test_root/nonpersist-live.log" || { cat "$test_root/nonpersist-live.log"; printf 'FAIL langtoggle: live-only control did not switch off\n'; exit 1; }
if probe saved-off "$test_root/nonpersist-again.log" || ! grep -aq 'LANGTOGGLE FAIL saved-off setting' "$test_root/nonpersist-again.log"; then
    printf 'FAIL langtoggle: nonpersisting mutant was not rejected on relaunch\n'; exit 1
fi
printf 'LANGTOGGLE MUTANT nonpersisting rejected by saved-off setting\n'
if [ -n "${FLEA_CI_SUITE_LOGS:-}" ]; then
    cp "$test_root/default-false.log" "$FLEA_CI_SUITE_LOGS/langtoggle-default-false.log" || exit 1
    cp "$test_root/nonpersist-again.log" "$FLEA_CI_SUITE_LOGS/langtoggle-nonpersisting.log" || exit 1
fi
printf 'langtoggle: live panes and windows, teardown, persistence and both negative controls passed\n'
