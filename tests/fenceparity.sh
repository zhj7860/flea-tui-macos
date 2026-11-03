#!/usr/bin/env bash
# Compares painted fences in real List Quick Look and Columns windows, then rejects a column-only colour mutant.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. tests/qslog-gate.sh
. tests/headless-commons.sh
. tools/flea-sandbox-guard
for tool in qs bat dbus-run-session python3; do
    command -v "$tool" >/dev/null || { printf 'FAIL fenceparity: %s is required\n' "$tool"; exit 1; }
done
bin=${FLEA_BIN:-$PWD/target/debug/flea}
[ -x "$bin" ] || { printf 'FAIL fenceparity: build the backend first: %s\n' "$bin"; exit 1; }
sandbox_root_ok
box=$(mktemp -d "$SANDBOX_ROOT/flea-fenceparity.XXXXXXXX") || exit 1
: > "$box/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$box"; }
trap cleanup EXIT
mkdir -p "$box/fixture" || exit 1
python3 - "$box/fixture/fences.md" <<'PY' || exit 1
import sys
# Sample input: one Markdown document with a tagged Rust fence, an untagged fence and a 96-line Rust fence.
short = 'fn short() { let message = "hello"; println!("{}", message); }\n'
long = ''.join('fn line%d() { let count = %d; let word = "hello"; }\n' % (i, i) for i in range(96))
with open(sys.argv[1], 'w') as fixture:
    fixture.write('# Fence parity\n\n```rust\n' + short + '```\n\n```\nplain <tag> & text\n```\n\n```rust\n' + long + '```\n\nDocument tail.\n')
PY

run_leg() {
    local leg=$1 host=$2 mutant=$3 dir="$box/$1" status
    mkdir -p "$dir"/{config,home,state/flea,cache,runtime} || return 1
    chmod 700 "$dir/runtime" || return 1
    printf '{}\n' > "$dir/state/flea/ui.json"
    cp -a ui "$dir/config/flea" || return 1
    headless_commons "$box" "$dir/config/Commons" || exit 1
    ln -s "$(readlink -m ui/boot/Ui)" "$dir/config/Ui" || return 1
    ln -s "$dir/config/flea/boot/fleatab.qml" "$dir/config/fleatab.qml" || return 1
    cp tests/fenceparity.qml "$dir/config/shell.qml" || return 1
    cp tests/fenceparity.js "$dir/config/fenceparity.js" || return 1
    if [ "$mutant" = 1 ]; then
        python3 - "$dir/config/flea/MarkdownBlockView.qml" <<'PY' || return 1
import sys
from pathlib import Path
path = Path(sys.argv[1])
# Sample input: the shared fence's coloured binding; compact identifies only the Columns host.
needle = 'readonly property bool coloured: fenceBox.info !== ""'
source = path.read_text()
assert source.count(needle) == 1, 'the column-only mutant did not find its unique binding'
path.write_text(source.replace(needle, needle + ' && !view.preview.compact'))
PY
    fi
    ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$dir/home" XDG_STATE_HOME="$dir/state" XDG_CACHE_HOME="$dir/cache" XDG_RUNTIME_DIR="$dir/runtime" \
        FLEA_BIN="$bin" FLEA_PATH="$box/fixture" FLEA_REDUCED_MOTION=1 \
        FENCEPARITY_UI="$dir/config/flea" FENCEPARITY_HOST="$host" FENCEPARITY_OUT="$dir" \
        QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
        QT_LOGGING_RULES="$(qslog_rules)" \
        dbus-run-session -- bash -c 'timeout 90 qs -p "$1" > "$2" 2>&1' _ "$dir/config" "$dir/run.log" 2> "$dir/bus.log" ) 2>/dev/null
    status=$?
    qslog_nullptr "fenceparity $leg" < "$dir/run.log" || return 1
    qslog_crash "fenceparity $leg" "$dir/run.log" || return 1
    # Sample input: 'qml: FENCEPARITY DONE fences=3 failures=0' is the only complete, successful run.
    if [ "$status" -ne 0 ] || [ "$(grep -ac 'FENCEPARITY DONE fences=3 failures=0' "$dir/run.log")" -ne 1 ] \
        || grep -aqE 'FENCEPARITY FAIL|TypeError|ReferenceError|Binding loop detected|Unable to assign|Cannot assign' "$dir/run.log"; then
        printf 'FAIL fenceparity: %s did not finish (qs exit %s)\n' "$leg" "$status"
        grep -aE 'FENCEPARITY FAIL|TypeError|ReferenceError|Binding loop detected|Unable to assign|Cannot assign' "$dir/run.log" | head -3
        return 1
    fi
}
keep_evidence() {
    [ -n "${FLEA_CI_SUITE_LOGS:-}" ] || return 0
    local leg file
    for leg in list column mutant-column; do
        [ -d "$box/$leg" ] || continue
        for file in "$box/$leg/run.log" "$box/$leg"/*.png; do
            [ -f "$file" ] || continue
            cp "$file" "$FLEA_CI_SUITE_LOGS/fenceparity-$leg-${file##*/}" || return 1
        done
    done
    [ ! -f "$box/mutant.log" ] || cp "$box/mutant.log" "$FLEA_CI_SUITE_LOGS/fenceparity-mutant-verdict.log"
}
failures=0
run_leg list list 0 || failures=$((failures + 1))
run_leg column column 0 || failures=$((failures + 1))
if [ "$failures" -eq 0 ]; then
    python3 -B tests/fenceparity.py "$box/list/run.log" "$box/column/run.log" || failures=$((failures + 1))
fi
if [ "$failures" -eq 0 ]; then
    run_leg mutant-column column 1 || failures=$((failures + 1))
    if [ "$failures" -eq 0 ]; then
        python3 -B tests/fenceparity.py "$box/list/run.log" "$box/mutant-column/run.log" > "$box/mutant.log" 2>&1
        status=$?
        if [ "$status" -ne 1 ] || ! grep -qF 'token inks differ for fence 0' "$box/mutant.log"; then
            printf 'FAIL fenceparity: the column-only colour mutant was not rejected for its token inks (exit %s)\n' "$status"
            failures=$((failures + 1))
        else
            printf 'ok fenceparity: column-only colour mutant rejected for token inks\n'
        fi
    fi
fi
keep_evidence || failures=$((failures + 1))
printf 'fenceparity: real List and Columns windows, %s failed\n' "$failures"
[ "$failures" -eq 0 ]
