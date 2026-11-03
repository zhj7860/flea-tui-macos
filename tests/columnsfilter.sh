#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# U3 columnsfilter: the "/" filter narrows the Columns active column and the grid through the List strip itself, Esc restores, and a navigation forgets the filter as in List.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "columnsfilter.sh: qs is not installed, cannot drive the columns view"
    exit 1
fi

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-columnsfilter.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/columnsfilter.qml "$test_root/config/shell.qml" || exit 1
cp tests/columnsfilter-fixture.js "$test_root/config/columnsfilter-fixture.js" || exit 1
cp tests/button-probe.js "$test_root/config/button-probe.js" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 30 qs -p "$test_root/config" 2>&1)

# Sample input, one probe line: "  INFO qml: COLUMNSFILTER PASS active=6-of-12 grid=6-of-12 strip=list esc=restored nav=forgotten parent=kept commit=enter-kept walk=j-k-kept preview=follows escape=name-kept stamps=columns-grid nomatch=empty-esc-restored-backspace-match hidden=no-marks"
pass_count=$(printf '%s\n' "$output" | grep -c 'COLUMNSFILTER PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'COLUMNSFILTER FAIL')
noisy=$(printf '%s\n' "$output" | grep -av 'does not support setting window masks' | grep -aiE 'WARN|ERROR|Binding loop|failed to load|Unable to assign|Cannot assign|TypeError|ReferenceError|is not a function|is not defined')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ] || [ -n "$noisy" ]; then
    printf 'FAIL the columns filter narrowed, restored, or forgot nothing it should have, or the probe logged a QML error\n'
    printf '%s\n' "$output" | grep -a 'COLUMNSFILTER'
    printf '%s\n' "$output" | grep -aiE 'ERROR|error'
    printf '%s\n' "$output"
    exit 1
fi
printf '%s\n' "$output" | grep -o 'COLUMNSFILTER \(rowitems\|armed\|PASS\).*'
