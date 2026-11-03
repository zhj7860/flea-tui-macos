#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# cursormark: a cursor move lights only the cursor row in the same turn, and no delegate binds cursor to the pane's cursor.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "cursormark.sh: qs is not installed, cannot build the views"
    exit 1
fi

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-cursormark.XXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/cursormark.qml "$test_root/config/shell.qml" || exit 1

rc=0
for view in list grid columns; do
    # Qt logs each binding a script write replaces, which is how a delegate still bound to the pane's cursor shows.
    output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
        QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
        QT_LOGGING_RULES="qt.qml.binding.removal.info=true" \
        CURSORMARK_VIEW="$view" timeout 60 qs -p "$test_root/config" 2>&1)
    # Sample input, one probe line: "  INFO qml: CURSORMARK DONE grid"
    if ! printf '%s\n' "$output" | grep -q "CURSORMARK DONE $view"; then
        printf 'FAIL cursormark %s did not finish clean\n' "$view"
        printf '%s\n' "$output" | grep -a 'CURSORMARK FAIL' | head -3
        printf '%s\n' "$output" | tail -20
        rc=1
        continue
    fi
    probe=$(printf '%s\n' "$output" | sed -n '/CURSORMARK PROBE begin/,/CURSORMARK PROBE end/p')
    # Sample input, one removal line: "  INFO qt.qml.binding.removal: Overwriting binding on Row_QMLTYPE_12::selected at ..."
    if ! printf '%s\n' "$probe" | grep -qE 'Overwriting binding on [^ ]*::selected'; then
        printf 'FAIL cursormark %s: the binding probe saw no removal of the selected binding, so it cannot see cursor\n' "$view"
        printf '%s\n' "$probe"
        rc=1
    elif printf '%s\n' "$probe" | grep -qE 'Overwriting binding on [^ ]*::cursor([^A-Za-z]|$)'; then
        printf 'FAIL cursormark %s: a delegate binds cursor, so every cursor move re-runs it in every live delegate\n' "$view"
        rc=1
    fi
    printf '%s\n' "$probe" | grep -aoE 'Overwriting binding on [^ ]*::[a-zA-Z]+' | sed "s/^/cursormark $view probe: /"
    printf '%s\n' "$output" | grep -aoE 'CURSORMARK [a-z]+ (enter|step 8|end|home revealed|filter cleared|rename open|resize grow|back|stale entry dropped) .*|CURSORMARK DONE .*' | head -13
    errors=$(printf '%s\n' "$output" | grep -aE 'qml: .*(Error|TypeError|ReferenceError|Unable)|QML .*(Error|error)|@flea/[^ ]*: (Error|TypeError|ReferenceError)|Binding loop' | head -5)
    if [ -n "$errors" ]; then
        printf 'FAIL cursormark %s logged QML errors\n%s\n' "$view" "$errors"
        rc=1
    fi
done
exit $rc
