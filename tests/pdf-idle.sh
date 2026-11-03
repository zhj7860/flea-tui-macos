#!/bin/bash
. "$(dirname "$0")/headless-commons.sh"
# r35-pdfidle: real PreviewPdf and PdfViewer idle, walk, busy and hidden open rules, offscreen.
set -u
cd "$(dirname "$0")/.." || exit 1

pass=0
fail=0
ok()  { printf 'ok   %s\n' "$*"; pass=$((pass+1)); }
bad() { printf 'FAIL %s\n' "$*"; fail=$((fail+1)); }

for tool in qs magick; do
    command -v "$tool" >/dev/null || { echo "pdf-idle.sh: $tool is not installed"; exit 1; }
done

. "$PWD/tools/flea-sandbox-guard"
sandbox_forbidden /tmp && sandbox_refuse "pdf-idle: /tmp is inside a forbidden test target"
idle_root=$(mktemp -d /tmp/flea-pdf-idle.XXXXXXXX) || exit 1
FIXTURE_ROOT=$idle_root
sandbox_root_ok
idle_root=$SANDBOX_ROOT
readonly idle_root
printf 'Flea PDF idle sandbox\n' > "$idle_root/$SANDBOX_MARKER" || exit 1
idle_work="$idle_root/work"
readonly idle_work
cleanup() {
    local result=$?
    trap - EXIT
    sandbox_remove "$idle_work"
    [ "$result" -ne 0 ] && exit "$result"
    sandbox_remove "$idle_root/column.log"
    sandbox_remove "$idle_root/$SANDBOX_MARKER"
    [ -z "$(ls -A "$idle_root")" ] && rmdir "$idle_root"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sandbox_scratch "$idle_work"
mkdir -p "$idle_work"/{config,home,runtime,tmp} || exit 1
chmod 700 "$idle_work/runtime" || exit 1
ln -s "$PWD/tests/pdf-idle.qml" "$idle_work/config/shell.qml" || exit 1
headless_commons "$idle_work" || exit 1
ln -s /usr/share/omarchy/shell/Ui "$idle_work/config/Ui" || exit 1

# Two light pages for the walk legs, and one photographic page whose render outlasts the settle.
pdf_a="$idle_work/a.pdf"
pdf_b="$idle_work/b.pdf"
pdf_c="$idle_work/c.pdf"
pdf_heavy="$idle_work/heavy.pdf"
magick -size 1200x1500 xc:white -fill black -draw 'rectangle 0,0 1199,749' "$pdf_a" \
    || { echo "pdf-idle.sh: fixture a generation failed"; exit 1; }
magick -size 1200x1500 xc:white -fill black -draw 'rectangle 0,0 1199,749' "$pdf_c" \
    || { echo "pdf-idle.sh: fixture c generation failed"; exit 1; }
magick -size 1200x1500 xc:white -fill black -draw 'rectangle 0,0 1199,1349' "$pdf_b" \
    || { echo "pdf-idle.sh: fixture b generation failed"; exit 1; }
magick \( -size 6600x8250 xc:gray50 +noise Random -fill black -draw 'rectangle 0,0 6599,6187' -quality 80 \) \
    -compress jpeg "$pdf_heavy" || { echo "pdf-idle.sh: fixture heavy generation failed"; exit 1; }

log="$idle_root/column.log"
( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$idle_work/home" XDG_RUNTIME_DIR="$idle_work/runtime" TMPDIR="$idle_work/tmp" \
    XDG_CONFIG_HOME="$idle_work/home/.config" XDG_STATE_HOME="$idle_work/home/.local/state" \
    XDG_CACHE_HOME="$idle_work/home/.cache" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 \
    QT_FORCE_STDERR_LOGGING=1 \
    PDF_IDLE_UI="$PWD/ui" PDF_IDLE_A="$pdf_a" PDF_IDLE_B="$pdf_b" PDF_IDLE_C="$pdf_c" PDF_IDLE_HEAVY="$pdf_heavy" \
    timeout 280 qs -p "$idle_work/config" > "$log" 2>&1; exit $? ) 2>/dev/null
status=$?
# Sample input, one probe line: "  INFO qml: PDFIDLE PASS an isolated press opens on the fast path"
grep -a -o 'PDFIDLE \(PASS\|FAIL\|DONE\)[^\\]*' "$log" | sed 's/\x1b\[[0-9;]*m//g' | head -30
# Sample input, one probe line: "  INFO qml: PDFIDLE PASS the walk lands on the second document"
grep -a 'PDFIDLE PASS' "$log" | sed 's/.*PDFIDLE PASS /ok   /'
# Sample input, a failure line and the final line: "  INFO qml: PDFIDLE FAIL the walk lands on the second document", "  INFO qml: PDFIDLE DONE failures=0"
if grep -q 'PDFIDLE FAIL' "$log" || ! grep -q 'PDFIDLE DONE' "$log"; then
    bad "the harness did not finish (qs exit $status): $(grep -a 'PDFIDLE FAIL' "$log" | head -3 | tr '\n' ';') (log $log)"
    exit 1
fi
[ "$fail" -eq 0 ]
