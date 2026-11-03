#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# No row-indexed request leaves while an exit holds the walk: the real List and GridArea run their planners over held walk rows, then over the landed folder, offscreen with no display.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "search-exit-reads.sh: qs is not installed, cannot build the views"
    exit 1
fi

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-search-exit-reads.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/search-exit-reads.qml "$test_root/config/shell.qml" || exit 1
cp tests/search-exit-reads-pane.qml "$test_root/config/ExitPaneStub.qml" || exit 1

total=0
bad=0
for mode in list grid; do
    output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
        QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 EXITREADS_MODE="$mode" \
        timeout 60 qs -p "$test_root/config" 2>&1)
    # Sample input, one probe line: "  INFO qml: EXITREADS MODE list checks=7 failed=0"
    line=$(printf '%s\n' "$output" | grep -a 'EXITREADS MODE' | tail -1)
    mode_lines=$(printf '%s\n' "$output" | grep -ac "EXITREADS MODE $mode ")
    checks=$(printf '%s\n' "$line" | sed -n 's/.*checks=\([0-9][0-9]*\) failed=.*/\1/p')
    failed=$(printf '%s\n' "$line" | sed -n 's/.*failed=\([0-9][0-9]*\).*/\1/p')
    noisy=$(printf '%s\n' "$output" | grep -aiE 'EXITREADS FAIL|WARN|ERROR|Binding loop|failed to load|Unable to assign|Cannot assign|TypeError|ReferenceError|is not a function|is not defined')
    if [ "$mode_lines" -ne 1 ] || [ -z "$checks" ] || [ "$failed" != 0 ] || [ -n "$noisy" ]; then
        bad=$((bad + 1))
        printf 'FAIL the %s view sent a row-indexed request under the held exit\n' "$mode"
        printf '%s\n' "$output"
        continue
    fi
    total=$((total + checks))
done

if [ "$bad" -ne 0 ]; then
    exit 1
fi
printf 'EXITREADS DONE checks=%d failed=0\n' "$total"
