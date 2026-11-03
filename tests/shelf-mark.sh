#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# The shelf mark's measured bounds match its ink; offscreen, no display or lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "FAIL shelf-mark.sh: qs is not installed"
    exit 1
fi

test_root=$(mktemp -d "$FIXTURE_ROOT/flea-shelf-mark-XXXXXX") || exit 1
case $test_root in
    /*/*) ;;
    *) echo "FAIL shelf-mark.sh: mktemp returned a relative or empty path"; exit 1 ;;
esac
sandbox_require "$test_root" || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config/shelf" "$test_root/home" "$test_root/state" "$test_root/cache" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
cp shelf/FleaShelfMark.qml "$test_root/config/shelf/" || exit 1
headless_commons "$test_root" || exit 1
cp tests/shelf-mark.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" FLEA_SHELF_MARK_DIR="$test_root" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 QT_SCALE_FACTOR=1 \
    timeout 20 qs -p "$test_root/config" 2>&1)
qs_status=$?

# Sample input: "SHELFMARK PASS 12px bounds equal ink".
pass_count=$(printf '%s\n' "$output" | grep -c 'SHELFMARK PASS')
# Sample input: "SHELFMARK FAIL 12px bounds equal ink: 1.5857864376269049,1.5857864376269049,20.82842712474619,20.82842712474619".
fail_count=$(printf '%s\n' "$output" | grep -c 'SHELFMARK FAIL')
# Sample input: "SHELFMARK DONE 6 checks, 0 failed".
done_count=$(printf '%s\n' "$output" | grep -c 'SHELFMARK DONE')
# Sample input: "SHELFMARK DONE 6 checks, 0 failed".
exact_done_count=$(printf '%s\n' "$output" | grep -c 'SHELFMARK DONE 6 checks, 0 failed$')
verdict=0
if [ "$qs_status" -ne 143 ] || [ "$pass_count" -ne 6 ] || [ "$fail_count" -ne 0 ] \
    || [ "$done_count" -ne 1 ] || [ "$exact_done_count" -ne 1 ]; then
    printf 'FAIL shelf-mark.sh: qs_exit=%s passes=%s failures=%s receipts=%s\n' "$qs_status" "$pass_count" "$fail_count" "$done_count"
    verdict=1
fi
# Sample input: "SHELFMARK PASS 12px bounds equal ink" has no Qt warning; only offscreen Qt's window-mask warning is allowed.
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN|ERROR' \
    | grep -vF 'This plugin does not support setting window masks')
if [ -n "$warnings" ]; then
    printf 'FAIL shelf-mark.sh: unexpected Qt warning\n%s\n' "$warnings"
    verdict=1
fi
if [ "$verdict" -ne 0 ]; then
    printf '%s\n' "$output"
    exit 1
fi
if [ -n "${FLEA_CI_SUITE_LOGS:-}" ]; then
    mkdir -p "$FLEA_CI_SUITE_LOGS/shelf-mark-images" || exit 1
    cp "$test_root/mark-12.png" "$test_root/mark-24.png" "$FLEA_CI_SUITE_LOGS/shelf-mark-images/" || exit 1
fi
# Sample input: "SHELFMARK PASS 24px painted bounds equal box".
printf '%s\n' "$output" | grep -o 'SHELFMARK \(PASS\|DONE\).*'
