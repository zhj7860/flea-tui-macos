#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# The List rename editor on the last row keeps its error line inside the viewport, offscreen with no display or lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "rename-list-bottom.sh: qs is not installed, cannot build the list"
    exit 1
fi

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-rename-list-bottom.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/rename-scroll-pane.qml "$test_root/config/RenamePaneStub.qml" || exit 1
cp tests/rename-list-bottom.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 60 qs -p "$test_root/config" 2>&1)
line=$(printf '%s\n' "$output" | grep -a 'RENAMELISTBOTTOM DONE' | tail -1)
# The checks a full green flow makes: 1 on open, 3 once the refusal grows the row, 4 once the List is hidden.
expected_checks=8
# Sample: 'RENAMELISTBOTTOM DONE checks=8 failed=0'
checks=$(printf '%s\n' "$line" | sed -n 's/.*checks=\([0-9][0-9]*\) failed=.*/\1/p')
failed=$(printf '%s\n' "$line" | sed -n 's/.*failed=\([0-9][0-9]*\).*/\1/p')
noisy=$(printf '%s\n' "$output" | grep -aiE 'RENAMELISTBOTTOM FAIL|WARN|ERROR|Binding loop|failed to load|Unable to assign|Cannot assign|TypeError|ReferenceError|is not a function|is not defined')
if [ "$checks" != "$expected_checks" ] || [ "$failed" != 0 ] || [ -n "$noisy" ]; then
    printf 'FAIL the List bottom editor run is not clean: want %s checks and 0 failed, got %s and %s\n' "$expected_checks" "${checks:-no}" "${failed:-no}"
    printf '%s\n' "$output" | grep -aE 'RENAMELISTBOTTOM|ERROR|FAIL|WARN|TypeError|ReferenceError|Binding loop' | head -20
    exit 1
fi
printf 'RENAMELISTBOTTOM DONE checks=%s failed=0\n' "$checks"
printf '%s\n' "$output" | grep -a 'RENAMELISTBOTTOM grown' | tail -1
