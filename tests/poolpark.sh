#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# poolpark: a real list, grid and columns view over a stub pane reuse their pooled delegates on a warm Enter, with nothing stale.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "poolpark.sh: qs is not installed, cannot build the views"
    exit 1
fi

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-poolpark.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/poolpark.qml "$test_root/config/shell.qml" || exit 1
# Every row of both folders gets a real 1x1 PNG, so a thumbnailed row decodes a picture instead of logging a missing file.
mkdir -p "$test_root/poolthumb" || exit 1
printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==' | base64 -d > "$test_root/poolthumb/one.png" || exit 1
for i in $(seq -f %04g 0 342); do ln "$test_root/poolthumb/one.png" "$test_root/poolthumb/a_$i.png" && ln "$test_root/poolthumb/one.png" "$test_root/poolthumb/b_$i.png" || exit 1; done

rc=0
for view in list grid columns; do
    output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
        QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
        POOLPARK_VIEW="$view" POOLPARK_THUMBS="$test_root/poolthumb" timeout 60 qs -p "$test_root/config" 2>&1)
    # Sample input, one probe line: "  INFO qml: POOLPARK DONE grid"
    if ! printf '%s\n' "$output" | grep -q "POOLPARK DONE $view"; then
        printf 'FAIL poolpark %s did not finish clean\n' "$view"
        printf '%s\n' "$output" | tail -40
        rc=1
        continue
    fi
    printf '%s\n' "$output" | grep -o 'POOLPARK .*'
    errors=$(printf '%s\n' "$output" | grep -aE 'qml: .*(Error|TypeError|ReferenceError|Unable)|QML .*(Error|error)|@flea/[^ ]*: (Error|TypeError|ReferenceError)|Binding loop' | head -5)
    if [ -n "$errors" ]; then
        printf 'FAIL poolpark %s logged QML errors\n%s\n' "$view" "$errors"
        rc=1
    fi
done
exit $rc
