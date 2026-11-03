#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# Each folder's view as a real Pane navigates, switches tabs and enters or leaves Dual, with Remember each folder's view on and off: the real Pane over the real backend, offscreen.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "folderviews-flow.sh: qs is not installed, cannot run the pane"
    exit 1
fi
bin=${FLEA_BIN:-$PWD/target/debug/flea}
[ -x "$bin" ] || { echo "folderviews-flow.sh: build the backend first: $bin"; exit 1; }

# The probe copies the window's route: a view chosen on the chrome or asked of the secondary pane lands on the primary pane.
grep -Fq 'onViewChosen: function (mode) { primaryPane.chooseView(mode) }' ui/WindowBody.qml \
    || { echo "FAIL ui/WindowBody.qml does not send a view choice to the primary pane"; exit 1; }
grep -Fq 'onViewRequested: function (mode) { chrome.viewChosen(mode) }' ui/WindowBody.qml \
    || { echo "FAIL ui/WindowBody.qml does not send the secondary pane's view choice through the chrome's route"; exit 1; }

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-folderviews-flow.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

fixture="$test_root/home/fixture"
mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" "$fixture/a" "$fixture/b" "$fixture/c" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/folderviews-flow.qml "$test_root/config/shell.qml" || exit 1
for d in a b c; do
    for n in one two three; do printf 'x\n' > "$fixture/$d/$n.txt"; done
done

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
    FLEA_BIN="$bin" FOLDERVIEWS_DIR="$fixture" timeout 90 qs -p "$test_root/config" 2>&1)

# Sample input, the receipt: "  INFO qml: FOLDERVIEWS DONE checks=44 failed=0".
done_count=$(printf '%s\n' "$output" | grep -c 'FOLDERVIEWS DONE')
noisy=$(printf '%s\n' "$output" | grep -av 'does not support setting window masks' | grep -aiE 'WARN|ERROR|Binding loop|failed to load|Unable to assign|Cannot assign|TypeError|ReferenceError|is not a function|is not defined')
if [ "$done_count" -ne 1 ] || printf '%s\n' "$output" | grep -aq 'FOLDERVIEWS FAIL' || [ -n "$noisy" ]; then
    printf 'FAIL a folder drew a view other than its own\n'
    printf '%s\n' "$output" | grep -a 'FOLDERVIEWS'
    [ -n "$noisy" ] && printf '%s\n' "$noisy"
    exit 1
fi
printf '%s\n' "$output" | grep -a 'FOLDERVIEWS DONE'
