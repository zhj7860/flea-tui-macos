#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# "Hidden files last" orders one folder the same way through a pane's list and sort, a column's peek and the chooser's list and header sort: the real backend, offscreen.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "hiddenlast-views.sh: qs is not installed, cannot build the chooser"
    exit 1
fi
bin=${FLEA_BIN:-$PWD/target/debug/flea}
[ -x "$bin" ] || { echo "hiddenlast-views.sh: build the backend first: $bin"; exit 1; }

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-hiddenlast-views.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state/flea" "$test_root/runtime" "$test_root/fixture/.config" "$test_root/fixture/Alpha" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/hiddenlast-views.qml "$test_root/config/shell.qml" || exit 1
printf 'x\n' > "$test_root/fixture/.hidden" || exit 1
printf 'x\n' > "$test_root/fixture/.zeta" || exit 1
printf 'x\n' > "$test_root/fixture/beta" || exit 1
printf 'x\n' > "$test_root/fixture/gamma" || exit 1
# The setting starts on, and a header sort is not remembered, so the second pass lists the folder in its plain order.
printf '{"hiddenLast":true,"rememberSort":false}' > "$test_root/state/flea/ui.json" || exit 1
request=$(printf '{"mode":"open","folder":"%s","title":"Hidden last"}' "$test_root/fixture")

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    FLEA_BIN="$bin" FLEA_PICKER="$request" FLEA_PICKER_REPLY="$test_root/reply.json" HLV_DIR="$test_root/fixture" \
    timeout 60 qs -p "$test_root/config" 2>&1)

# Sample input, the receipt: "  INFO qml: HLV DONE 12 checks, 0 failed".
done_count=$(printf '%s\n' "$output" | grep -c 'HLV DONE')
noisy=$(printf '%s\n' "$output" | grep -av 'does not support setting window masks' | grep -aiE 'WARN|ERROR|Binding loop|failed to load|Unable to assign|Cannot assign|TypeError|ReferenceError|is not a function|is not defined')
if [ "$done_count" -ne 1 ] || printf '%s\n' "$output" | grep -aq 'HLV FAIL' || [ -n "$noisy" ]; then
    printf 'FAIL hidden files are not last in every view the setting names\n'
    printf '%s\n' "$output" | grep -a 'HLV'
    [ -n "$noisy" ] && printf '%s\n' "$noisy"
    exit 1
fi
printf '%s\n' "$output" | grep -a 'HLV'
