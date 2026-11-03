#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# An AppImage row draws its published icon in List, Grid and Columns and the terminal mark without one, offscreen with no display or lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "appimage-icon.sh: qs is not installed, cannot build the views"
    exit 1
fi

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-appimage-icon.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/appimage-icon.qml "$test_root/config/shell.qml" || exit 1
# The row's published icon: a 16x16 PNG, written here so no binary is tracked.
python3 - "$test_root/icon.png" <<'PY' || exit 1
import struct, sys, zlib
def chunk(kind, data):
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))
rows = b"".join(b"\x00" + b"\x20\x80\xc0" * 16 for _ in range(16))
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 16, 16, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")
open(sys.argv[1], "wb").write(png)
PY

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    FLEA_APPICON_PNG="$test_root/icon.png" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 30 qs -p "$test_root/config" 2>&1)

# Sample input, one probe line: "  INFO qml: APPIMAGE_ICON PASS views=list,grid,columns modes=media,images,off"
pass_count=$(printf '%s\n' "$output" | grep -c 'APPIMAGE_ICON PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'APPIMAGE_ICON FAIL')
noisy=$(printf '%s\n' "$output" | grep -av 'does not support setting window masks' | grep -aiE 'Binding loop|Unable to assign|Cannot assign|TypeError|ReferenceError|is not a function|is not defined')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ] || [ -n "$noisy" ]; then
    printf 'FAIL an AppImage row did not draw its icon, or drew the mark over one, or an Off setting drew it\n'
    printf '%s\n' "$output" | grep -a 'APPIMAGE_ICON'
    [ -n "$noisy" ] && printf '%s\n' "$noisy" | head -20
    printf '%s\n' "$output" | tail -40
    exit 1
fi
printf '%s\n' "$output" | grep -o 'APPIMAGE_ICON PASS.*'
