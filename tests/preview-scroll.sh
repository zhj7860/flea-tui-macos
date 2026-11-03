#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# Pages and scrolls the Columns preview through the real Pane, preserving focus and each file's session position.
set -u
cd "$(dirname "$0")/.." || exit 1
. "$PWD/tools/flea-sandbox-guard"
sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-preview-scroll.XXXXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
bin=${FLEA_BIN:-$PWD/target/debug/flea}
[ -x "$bin" ] || { echo "FAIL preview-scroll: backend missing at $bin"; exit 1; }
tools/flea-qmllint-gate || exit 1
mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" "$test_root/fixture" "$test_root/shots" || exit 1
chmod 700 "$test_root/runtime" || exit 1
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/preview-scroll.qml "$test_root/config/shell.qml" || exit 1
python3 - "$test_root/fixture" <<'PY'
import pathlib, struct, sys, zlib
root = pathlib.Path(sys.argv[1])
preview_max_bytes = 1024 * 1024
for name in ('00-long.rs', '01-other.rs'):
    (root / name).write_text('\n'.join('fn line_%d() { let value = %d; }' % (i, i) for i in range(1, 133)))
(root / '02-short.txt').write_text('\n'.join('short %d' % i for i in range(10)))
for name in ('03-long.md', '04-other.md'):
    (root / name).write_text('\n\n'.join('Paragraph %d with **bold** words.' % i for i in range(132)))
def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
(root / '05-image.png').write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 16, 16, 8, 2, 0, 0, 0))
    + chunk(b'IDAT', zlib.compress((b'\x00' + b'\x55\x88\xaa' * 16) * 16)) + chunk(b'IEND', b''))
(root / '06-empty.txt').write_text('')
(root / '07-large.md').write_text('large\n' + 'x' * preview_max_bytes)
for name, delimiter in (('08-long.csv', ','), ('09-long.tsv', '\t')):
    (root / name).write_text(delimiter.join(('name', 'value')) + '\n'
        + '\n'.join(delimiter.join(('row%d' % i, str(i))) for i in range(1, 133)))
PY
env XDG_STATE_HOME="$test_root/state" XDG_CONFIG_HOME="$test_root/home/.config" "$bin" --ui-state '{}' >/dev/null || exit 1
env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CONFIG_HOME="$test_root/home/.config" \
    XDG_CACHE_HOME="$test_root/home/.cache" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
    FLEA_BIN="$bin" PREVIEW_SCROLL_DIR="$test_root/fixture" PREVIEW_SCROLL_OUT="$test_root/shots" timeout 120 qs -p "$test_root/config" > "$test_root/probe.log" 2>&1
status=$?
cat "$test_root/probe.log" | grep -a 'PVSCROLL'
if [ -n "${FLEA_CI_SUITE_LOGS:-}" ]; then
    for shot in "$test_root/shots"/capture-*.png; do
        [ -f "$shot" ] || continue
        cp -- "$shot" "$FLEA_CI_SUITE_LOGS/preview-scroll-$(basename "$shot")" || exit 1
    done
fi
noisy=$(grep -aiE 'WARN|ERROR|TypeError|ReferenceError|Binding loop|Unable to assign|Cannot assign|is not a function' "$test_root/probe.log" \
    | grep -av 'does not support setting window masks' | grep -avF '$HYPRLAND_INSTANCE_SIGNATURE is unset. Cannot connect to hyprland.')
if [ "$status" -ne 0 ] || ! grep -aq 'PVSCROLL DONE .*checks, 0 failed' "$test_root/probe.log" || [ -n "$noisy" ]; then
    printf 'FAIL preview-scroll: qs exit %s\n' "$status"
    [ -z "$noisy" ] || printf '%s\n' "$noisy"
    exit 1
fi
