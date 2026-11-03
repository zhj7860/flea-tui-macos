#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# A PDF in the Columns preview fills the frame's width with its pages stacked under one another and a scroll knob, builds only the pages near the frame, and Quick Look keeps one page with its strip, offscreen at 1200 x 760 and 760 x 560.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
# qs exits 128 + SIGTERM when the probe kills itself after its receipt.
self_kill_exit=143

if ! command -v qs >/dev/null || ! command -v python3 >/dev/null; then
    echo "preview-pdf-flow.sh: qs and python3 are needed to build the column and its fixtures"
    exit 1
fi

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-preview-pdf-flow.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/runtime" "$test_root/fixture" "$test_root/state" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/preview-pdf-flow.qml "$test_root/config/shell.qml" || exit 1

# A 12-page report and a 1-page receipt; each page carries a bar whose length is its number, so no two pages look alike.
python3 - "$test_root/fixture" <<'PY' || { echo "preview-pdf-flow.sh: the fixture failed"; exit 1; }
import sys
dest = sys.argv[1]
def pdf(name, sizes):
    objs = []
    kids = ' '.join('%d 0 R' % (3 + 2 * i) for i in range(len(sizes)))
    objs.append('<< /Type /Catalog /Pages 2 0 R >>')
    objs.append('<< /Type /Pages /Kids [%s] /Count %d >>' % (kids, len(sizes)))
    for i, (w, h) in enumerate(sizes):
        bar = 40 + 40 * (i % 12)
        stream = '0.1 0.1 0.1 rg 30 %d %d 24 re f' % (h - 60, bar)
        objs.append('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] /Contents %d 0 R >>' % (w, h, 4 + 2 * i))
        objs.append('<< /Length %d >>\nstream\n%s\nendstream' % (len(stream), stream))
    out = b'%PDF-1.4\n'
    offsets = []
    for n, body in enumerate(objs, 1):
        offsets.append(len(out))
        out += ('%d 0 obj\n%s\nendobj\n' % (n, body)).encode()
    xref = len(out)
    out += ('xref\n0 %d\n0000000000 65535 f \n' % (len(objs) + 1)).encode()
    for off in offsets:
        out += ('%010d 00000 n \n' % off).encode()
    out += ('trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n' % (len(objs) + 1, xref)).encode()
    open(dest + '/' + name, 'wb').write(out)
# A file that is not a PDF, handed to a slot's image by the test.
open(dest + '/broken.pdf', 'wb').write(b'not a pdf\n')
pdf('report.pdf', [(612, 792)] * 12)
pdf('receipt.pdf', [(226, 640)])
pdf('slip.pdf', [(612, 300)])
pdf('big.pdf', [(612, 792)] * 500)
PY

# run LABEL WIDTH HEIGHT: one probe launch over the sandbox's own state directory.
run() {
    env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CONFIG_HOME="$test_root/home/.config" XDG_RUNTIME_DIR="$test_root/runtime" \
        QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
        FLOW_DIR="$test_root/fixture" FLOW_W="$2" FLOW_H="$3" timeout 120 qs -p "$test_root/config" 2>&1
}

verdict=0
# judge LABEL OUTPUT QS_STATUS EXPECTED_CHECKS
judge() {
    local label=$1 output=$2 status=$3 want=$4 passed noisy
    # Sample input: "  INFO qml: FLOW QMLTALLY passed=41 failed=0".
    passed=$(printf '%s\n' "$output" | sed -n 's/.*FLOW QMLTALLY passed=\([0-9]*\) failed=0$/\1/p')
    # The two injected warnings name broken.pdf, the document the failure checks hand to a slot's image; no other warning passes.
    noisy=$(printf '%s\n' "$output" | grep -av 'does not support setting window masks\|Detected function' | grep -avE 'PdfPageImage at @flea/PreviewPdf\.qml\[[0-9]+:[0-9]+\]: (document and source properties in conflict: preferring document source QUrl\("[^"]*/fixture/broken\.pdf"\)|Error decoding: [^ ]*/fixture/broken\.pdf: Unsupported image format)' | grep -aiE 'WARN|ERROR|Binding loop|failed to load|Unable to assign|Cannot assign|TypeError|ReferenceError|is not a function|is not defined|in conflict')
    if [ "$status" -ne "$self_kill_exit" ] || [ "$passed" != "$want" ] || printf '%s\n' "$output" | grep -aq 'FLOW FAIL' || [ -n "$noisy" ]; then
        printf 'FAIL %s: qs exit %s, checks passed %s of %s\n' "$label" "$status" "${passed:-none}" "$want"
        printf '%s\n' "$output" | grep -a 'FLOW FAIL\|FLOW COUNTS\|QMLTALLY'
        [ -n "$noisy" ] && printf '%s\n' "$noisy"
        verdict=1
        return
    fi
    printf '%s\n' "$output" | grep -a 'FLOW COUNTS\|FLOW QMLTALLY' | sed 's/^.*FLOW /FLOW '"$label"' /'
}

out=$(run wide 1200 760); judge "1200x760" "$out" $? 57
out=$(run narrow 760 560); judge "760x560" "$out" $? 57
exit $verdict
