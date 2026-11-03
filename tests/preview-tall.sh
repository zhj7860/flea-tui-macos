#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# A tall kind's frame fills the Columns preview from its top down to the name over one compact facts line, and i swaps that line for the table through the real state writer, offscreen at 1200 x 760 and 760 x 560.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
# qs exits 128 + SIGTERM when the probe kills itself after its receipt.
self_kill_exit=143

if ! command -v qs >/dev/null || ! command -v python3 >/dev/null; then
    echo "preview-tall.sh: qs and python3 are needed to build the column and its fixtures"
    exit 1
fi
bin=${FLEA_BIN:-$PWD/target/debug/flea}
[ -x "$bin" ] || { echo "preview-tall.sh: build the backend first: $bin"; exit 1; }

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-preview-tall.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/runtime" "$test_root/fixture" "$test_root/state-wide" "$test_root/state-narrow" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/preview-tall.qml "$test_root/config/shell.qml" || exit 1

# Files of the exact sizes and line counts the board's specimens state: 4.1 kB and 132 lines, 6.2 kB and 48, 900 B and 20.
python3 - "$test_root/fixture" <<'PY' || { echo "preview-tall.sh: the fixture failed"; exit 1; }
import struct, sys, zlib
dest = sys.argv[1]
def text(name, size, count, prefix):
    per, extra = divmod(size, count)
    body = ''.join((prefix + str(i)).ljust(per + (extra if i == count - 1 else 0) - 1, 'x') + '\n' for i in range(count))
    assert len(body.encode()) == size
    open(dest + '/' + name, 'w').write(body)
def png(name, w, h):
    raw = b''.join(b'\x00' + bytes([122, 162, 247]) * w for _ in range(h))
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    open(dest + '/' + name, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))
text('icons.rs', 4100, 132, 'let line_')
text('long.rs', 4100, 132, 'let line_')
text('notes.md', 6200, 48, 'Paragraph ')
text('plain.txt', 900, 20, 'row ')
open(dest + '/backup.zip', 'wb').write(b'z' * 9000)
png('shot.png', 64, 36)
png('phone.png', 18, 39)
PY

# run LABEL STATE_DIR WIDTH HEIGHT PHASE: one probe launch over the sandbox's own state directory.
run() {
    env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$test_root/home" XDG_STATE_HOME="$2" XDG_CONFIG_HOME="$test_root/home/.config" XDG_RUNTIME_DIR="$test_root/runtime" \
        QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
        FLEA_BIN="$bin" TALL_DIR="$test_root/fixture" TALL_W="$3" TALL_H="$4" TALL_PHASE="$5" timeout 90 qs -p "$test_root/config" 2>&1
}

verdict=0
# judge LABEL OUTPUT QS_STATUS EXPECTED_CHECKS
judge() {
    local label=$1 output=$2 status=$3 want=$4 passed noisy
    # Sample input: "  INFO qml: TALL QMLTALLY passed=61 failed=0".
    passed=$(printf '%s\n' "$output" | sed -n 's/.*TALL QMLTALLY passed=\([0-9]*\) failed=0$/\1/p')
    noisy=$(printf '%s\n' "$output" | grep -av 'does not support setting window masks\|Detected function' | grep -aiE 'WARN|ERROR|Binding loop|failed to load|Unable to assign|Cannot assign|TypeError|ReferenceError|is not a function|is not defined')
    if [ "$status" -ne "$self_kill_exit" ] || [ "$passed" != "$want" ] || printf '%s\n' "$output" | grep -aq 'TALL FAIL' || [ -n "$noisy" ]; then
        printf 'FAIL %s: qs exit %s, checks passed %s of %s\n' "$label" "$status" "${passed:-none}" "$want"
        printf '%s\n' "$output" | grep -a 'TALL FAIL\|QMLTALLY'
        [ -n "$noisy" ] && printf '%s\n' "$noisy"
        verdict=1
        return
    fi
    printf '%s\n' "$output" | grep -a 'TALL WIDTHS\|TALL OBJECTS\|TALL QMLTALLY' | sed 's/^.*TALL /TALL '"$label"' /'
}

for state in wide narrow; do
    env XDG_STATE_HOME="$test_root/state-$state" XDG_CONFIG_HOME="$test_root/home/.config" "$bin" --ui-state '{}' >/dev/null \
        || { echo "preview-tall.sh: could not seed the $state state"; exit 1; }
done

out=$(run wide "$test_root/state-wide" 1200 760 first); judge "1200x760" "$out" $? 68
# The mode the first launch wrote is the file's own, so the writer, not the probe, kept it.
python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))["previewFacts"] == "full" else 1)' "$test_root/state-wide/flea/ui.json" \
    || { echo "FAIL i did not write previewFacts full to ui.json"; verdict=1; }
out=$(run narrow "$test_root/state-narrow" 760 560 first); judge "760x560" "$out" $? 68
out=$(run relaunch "$test_root/state-wide" 1200 760 relaunch); judge "relaunch" "$out" $? 4
python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))["previewFacts"] == "compact" else 1)' "$test_root/state-wide/flea/ui.json" \
    || { echo "FAIL the relaunch's i did not write previewFacts compact to ui.json"; verdict=1; }
exit $verdict
