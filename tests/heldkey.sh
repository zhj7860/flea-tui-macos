#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# heldkey: a held j steps once per repeat in each view under load and never after the release.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "heldkey.sh: qs is not installed, cannot build the views"
    exit 1
fi

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-heldkey.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/heldkey.qml "$test_root/config/shell.qml" || exit 1

rc=0
for view in list grid columns; do
    for load in 0 10 30; do
        output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
            HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
            QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
            HELDKEY_VIEW="$view" HELDKEY_LOAD="$load" timeout 60 qs -p "$test_root/config" 2>&1)
        # Sample input, one table line: "  INFO qml: HELDKEY grid load=10 sent=71 steps=71 after=0 worstgap=12"
        printf '%s\n' "$output" | grep -a 'HELDKEY list\|HELDKEY grid\|HELDKEY columns' | grep -av 'HELDKEY DONE\|HELDKEY FAIL' | head -1
        if ! printf '%s\n' "$output" | grep -q "HELDKEY DONE $view load=$load"; then
            printf 'FAIL heldkey %s load=%s did not finish clean\n' "$view" "$load"
            printf '%s\n' "$output" | grep -a 'HELDKEY FAIL' | head -3
            printf '%s\n' "$output" | tail -8
            rc=1
            continue
        fi
        errors=$(printf '%s\n' "$output" | grep -aE 'qml: .*(Error|TypeError|ReferenceError|Unable)|QML .*(Error|error)|@flea/[^ ]*: (Error|TypeError|ReferenceError)|Binding loop' | head -5)
        if [ -n "$errors" ]; then
            printf 'FAIL heldkey %s load=%s logged QML errors\n%s\n' "$view" "$load" "$errors"
            rc=1
        fi
    done
done
exit $rc
