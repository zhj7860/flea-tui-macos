#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# Pre-capture thumb ask: isolated press asks once before capture, column off asks nothing, walk asks after settle.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "preview-earlyask.sh: qs is not installed, cannot drive the columns view"
    exit 1
fi
if ! command -v python3 >/dev/null; then
    echo "preview-earlyask.sh: python3 is not installed, cannot build the thumbnail fixture"
    exit 1
fi

test_root="$FIXTURE_ROOT/flea-preview-earlyask-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" "$test_root/fixture" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/preview-earlyask.qml "$test_root/config/shell.qml" || exit 1
# Six real 8x8 PNGs the stub backend answers with, so frames decode and swaps release.
python3 - "$test_root/fixture" <<'EOF' || exit 1
import struct, sys, zlib
d = sys.argv[1]
def png(rgb):
    raw = b"".join(b"\x00" + bytes(rgb) * 8 for _ in range(8))
    def chunk(t, b):
        c = struct.pack(">I", len(b)) + t + b
        return c + struct.pack(">I", zlib.crc32(t + b) & 0xffffffff)
    ihdr = struct.pack(">IIBBBBB", 8, 8, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
for i in range(6):
    open("%s/c%d.png" % (d, i), "wb").write(png((200 - i * 20, 30 + i * 10, 60)))
EOF

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    PREVIEW_EARLYASK_FIXTURE="$test_root/fixture" \
    timeout 60 qs -p "$test_root/config" 2>&1)

# Sample input, one probe line: "  INFO qml: PREVIEWEARLYASK PASS isolated=precapture once=1 walk=silent-then-one columnoff=silent"
pass_count=$(printf '%s\n' "$output" | grep -c 'PREVIEWEARLYASK PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'PREVIEWEARLYASK FAIL')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL the early ask missed its order, its count, or the walk silence\n'
    printf '%s\n' "$output"
    exit 1
fi
printf '%s\n' "$output" | grep -o 'PREVIEWEARLYASK PASS.*'
