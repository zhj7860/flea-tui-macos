#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# A live search draws each folder's size in the frame its row appears: the real Pane over the real backend, offscreen.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "search-sizes.sh: qs is not installed, cannot run the pane"
    exit 1
fi
bin=${FLEA_BIN:-$PWD/target/debug/flea}
[ -x "$bin" ] || { echo "search-sizes.sh: build the backend first: $bin"; exit 1; }

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-search-sizes.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

# The folder stands inside HOME, so the search scope is HOME and the folder's own rows are named apart from its answers.
fixture="$test_root/home/fixture"
mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" "$fixture/deep" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/search-sizes.qml "$test_root/config/shell.qml" || exit 1
# Sand and scroll folders each hold one file of its own size, so every folder size is distinct; "s" lists both, "sc" only scroll.
for i in 1 2 3 4; do
    mkdir -p "$fixture/sand-$i" "$fixture/scroll-$i" || exit 1
    head -c $((i * 100 + 7)) /dev/zero > "$fixture/sand-$i/part.bin" || exit 1
    head -c $((i * 1000)) /dev/zero > "$fixture/scroll-$i/part.bin" || exit 1
done
mkdir -p "$fixture/deep/sand-deep-1" "$fixture/deep/scroll-deep-1" || exit 1
head -c 517 /dev/zero > "$fixture/deep/sand-deep-1/part.bin" || exit 1
head -c 1517 /dev/zero > "$fixture/deep/scroll-deep-1/part.bin" || exit 1
printf 'x\n' > "$fixture/sand-a.txt"
printf 'x\n' > "$fixture/scroll-a.txt"
for i in $(seq -w 1 10); do printf 'x\n' > "$fixture/data-$i.bin"; done

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
    FLEA_BIN="$bin" SIZES_DIR="$fixture" timeout 60 qs -p "$test_root/config" 2>&1)

# Sample input, the receipt: "  INFO qml: SEARCHSIZES DONE checks=21 failed=0".
done_count=$(printf '%s\n' "$output" | grep -c 'SEARCHSIZES DONE')
noisy=$(printf '%s\n' "$output" | grep -av 'does not support setting window masks' | grep -aiE 'WARN|ERROR|Binding loop|failed to load|Unable to assign|Cannot assign|TypeError|ReferenceError|is not a function|is not defined')
if [ "$done_count" -ne 1 ] || printf '%s\n' "$output" | grep -aq 'SEARCHSIZES FAIL' || [ -n "$noisy" ]; then
    printf 'FAIL a folder row drew its size after the frame it appeared in\n'
    printf '%s\n' "$output" | grep -a 'SEARCHSIZES'
    [ -n "$noisy" ] && printf '%s\n' "$noisy"
    exit 1
fi
printf '%s\n' "$output" | grep -a 'SEARCHSIZES COUNTS'
printf '%s\n' "$output" | grep -a 'SEARCHSIZES DONE'
