#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# The first answer of a search builds no row and no layout in list, columns and grid, and a first key typed with f draws one answer: the real Pane over the real backend, offscreen.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "search-warm.sh: qs is not installed, cannot run the pane"
    exit 1
fi
bin=${FLEA_BIN:-$PWD/target/debug/flea}
[ -x "$bin" ] || { echo "search-warm.sh: build the backend first: $bin"; exit 1; }

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-search-warm.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" "$test_root/fixture/deep" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/search-warm.qml "$test_root/config/shell.qml" || exit 1
# Three rows in the folder, 150 matches below it: the first answer grows every view past its viewport.
printf 'x\n' > "$test_root/fixture/a.txt"
printf 'x\n' > "$test_root/fixture/b.txt"
for i in $(seq -w 1 150); do printf 'x\n' > "$test_root/fixture/deep/notes-$i.md"; done
# Ten thousand folders with no match keep the walk running past a key typed with f, and a box that walks them past the swap cap is checked on the cap's path.
mkdir -p "$test_root/fixture/pad" && (cd "$test_root/fixture/pad" && mkdir $(seq -f 'd%05g' 1 10000)) || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 QSG_RENDER_LOOP=basic \
    FLEA_BIN="$bin" WARM_DIR="$test_root/fixture" timeout 60 qs -p "$test_root/config" 2>&1)

# Sample input, the receipt: "  INFO qml: SEARCHWARM DONE checks=15 failed=0".
done_count=$(printf '%s\n' "$output" | grep -c 'SEARCHWARM DONE')
noisy=$(printf '%s\n' "$output" | grep -av 'does not support setting window masks' | grep -aiE 'WARN|ERROR|Binding loop|failed to load|Unable to assign|Cannot assign|TypeError|ReferenceError|is not a function|is not defined')
if [ "$done_count" -ne 1 ] || printf '%s\n' "$output" | grep -aq 'SEARCHWARM FAIL' || [ -n "$noisy" ]; then
    printf 'FAIL a first answer built rows or layouts, or a first key drew more than one answer\n'
    printf '%s\n' "$output" | grep -aE 'SEARCHWARM|WARN|ERROR|Binding loop|TypeError|ReferenceError'
    exit 1
fi
printf '%s\n' "$output" | grep -a 'SEARCHWARM'
