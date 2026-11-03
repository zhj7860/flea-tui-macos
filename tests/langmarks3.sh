#!/usr/bin/env bash
# Counts real delegates and builds the reference sheet through its original symlink harness.
set -uo pipefail
. "$(dirname "$0")/../tools/flea-sandbox-guard"
. "$(dirname "$0")/headless-commons.sh"
cd "$(dirname "$0")/.." || exit 1
command -v qs >/dev/null || { printf 'FAIL langmarks3: qs is required\n'; exit 1; }
sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-langmarks.XXXXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
mkdir -p "$test_root"/{config,spec,home,state,cache,runtime} || exit 1
chmod 700 "$test_root/runtime" || exit 1
bin=${FLEA_BIN:-$PWD/target/debug/flea}
env HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" "$bin" --ui-state '{"langMarks":true}' > "$test_root/seed.json" || exit 1
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
ln -s "$PWD/tests/langmark-count.js" "$test_root/config/langmark-count.js" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/langmarks3.qml "$test_root/config/shell.qml" || exit 1
printf 'P3\n1 1\n255\n255 0 0\n' > "$test_root/thumb.ppm"
probe() {
    env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
        XDG_RUNTIME_DIR="$test_root/runtime" LANGMARK_THUMB="$test_root/thumb.ppm" LANGMARK_SPEC_TEST=1 \
        QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
        timeout 15 qs -p "$1" > "$2" 2>&1
    local status=$?
    [[ "$status" == 0 || "$status" == 143 ]] || { cat "$2"; return 1; }
    if grep -aE 'LANGCOST FAIL|LANGMARK_SPEC FAIL|TypeError|ReferenceError|ERROR' "$2"; then return 1; fi
}
probe "$test_root/config" "$test_root/count.log" || exit 1
[[ "$(grep -ac 'LANGCOST PASS' "$test_root/count.log")" == 1 ]] \
    || { cat "$test_root/count.log"; printf 'FAIL langmarks3: no count receipt\n'; exit 1; }
grep -ao 'LANGCOST .*' "$test_root/count.log"
ln -s "$PWD/tests/langmark-spec.qml" "$test_root/spec/shell.qml" || exit 1
headless_commons "$test_root" "$test_root/spec/Commons" || exit 1
for unit in ui/*.qml ui/qmldir ui/js ui/Ui; do
    ln -s "$PWD/$unit" "$test_root/spec/${unit#ui/}" || exit 1
done
probe "$test_root/spec" "$test_root/spec.log" || exit 1
[[ "$(grep -ac 'LANGMARK_SPEC PASS marks=16' "$test_root/spec.log")" == 1 ]] \
    || { cat "$test_root/spec.log"; printf 'FAIL langmarks3: no reference-sheet receipt\n'; exit 1; }
grep -ao 'LANGMARK_SPEC .*' "$test_root/spec.log"

# Shift the loaded mark while keeping its Loader and the mark's dimensions unchanged.
mutant="$test_root/mutant"
mkdir -p "$mutant" || exit 1
cp -a ui "$mutant/flea" || exit 1
cp tests/langmarks3.qml "$mutant/shell.qml" || exit 1
cp tests/langmark-count.js "$mutant/langmark-count.js" || exit 1
headless_commons "$test_root" "$mutant/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$mutant/Ui" || exit 1
python3 - "$mutant/flea/LangMarkLoader.qml" <<'PY' || exit 1
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
anchor = '        anchors.fill: parent'
assert source.count(anchor) == 1, 'language mark anchors changed'
path.write_text(source.replace(anchor, anchor + '\n        anchors.leftMargin: 3\n        anchors.rightMargin: -3'))
PY
if probe "$mutant" "$test_root/mutant.log" > "$test_root/mutant-wrapper.log" 2>&1; then
    printf 'FAIL langmarks3: displaced loaded mark mutant passed\n'; exit 1
fi
for surface in Row GridTile ColumnRow; do
    grep -aq "LANGCOST FAIL $surface loaded mark leaves its glyph slot" "$test_root/mutant.log" \
        || { cat "$test_root/mutant-wrapper.log"; printf 'FAIL langmarks3: %s missed the displaced mark\n' "$surface"; exit 1; }
done
[ -z "${FLEA_CI_SUITE_LOGS:-}" ] || cp "$test_root/mutant.log" "$FLEA_CI_SUITE_LOGS/langmarks3-displaced.log" || exit 1
printf 'LANGCOST MUTANT displaced-mark rejected Row,GridTile,ColumnRow\n'

# A slug-dependent visibility binding must survive the live reuse sequence until Python is checked.
binding="$test_root/binding"
cp -a "$mutant" "$binding" || exit 1
cp ui/LangMarkLoader.qml "$binding/flea/LangMarkLoader.qml" || exit 1
python3 - "$binding/flea/LangMark.qml" "$binding/shell.qml" <<'PY' || exit 1
from pathlib import Path
import sys
mark, caller = map(Path, sys.argv[1:])
text = mark.read_text()
anchor = '    property string slug: ""'
assert text.count(anchor) == 1
mark.write_text(text.replace(anchor, anchor + '\n    visible: root.slug !== "python"'))
text = caller.read_text()
late = '''            // Destructive controls use the born fixtures only after every live reuse assertion.
            root.delegates = root.born
            root.checkMarks()
            root.visibilityControls()
'''
early = '            codeBar.name = "notes.ini"\n            root.checkMarks()\n'
assert text.count(late) == text.count(early) == 1
caller.write_text(text.replace(late, '').replace(early, early + '            root.visibilityControls()\n'))
PY
probe "$binding" "$test_root/binding-old.log" > "$test_root/binding-old-wrapper.log" 2>&1 \
    || { cat "$test_root/binding-old-wrapper.log"; printf 'FAIL langmarks3: early-control regression did not reproduce\n'; exit 1; }
[[ "$(grep -ac 'LANGCOST PASS' "$test_root/binding-old.log")" == 1 ]] \
    || { printf 'FAIL langmarks3: early control has no original false-positive receipt\n'; exit 1; }
cp tests/langmarks3.qml "$binding/shell.qml" || exit 1
if probe "$binding" "$test_root/binding-fixed.log" > "$test_root/binding-fixed-wrapper.log" 2>&1; then
    printf 'FAIL langmarks3: Python-invisible binding mutant passed\n'; exit 1
fi
for surface in Row GridTile ColumnRow; do
    grep -aq "LANGCOST INVISIBLE phase=3 surface=$surface slug=python" "$test_root/binding-fixed.log" \
        && grep -aq "LANGCOST FAIL $surface language mark is invisible" "$test_root/binding-fixed.log" \
        || { cat "$test_root/binding-fixed-wrapper.log"; printf 'FAIL langmarks3: %s missed the later Python visibility binding\n' "$surface"; exit 1; }
done
if [[ -n "${FLEA_CI_SUITE_LOGS:-}" ]]; then
    cp "$test_root/binding-old.log" "$FLEA_CI_SUITE_LOGS/langmarks3-binding-old.log" || exit 1
    cp "$test_root/binding-fixed.log" "$FLEA_CI_SUITE_LOGS/langmarks3-binding-fixed.log" || exit 1
fi
printf 'LANGCOST MUTANT python-invisible old-accepted=1 fixed-phase3-rejected=Row,GridTile,ColumnRow\n'
