#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# Tag slots on real delegates: an untagged row builds none, a tagged row mounts one and reuses it, offscreen with no display or lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "tagrows.sh: qs is not installed, cannot build the row delegates"
    exit 1
fi

test_root="$FIXTURE_ROOT/flea-tagrows-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/tagrows.qml "$test_root/config/shell.qml" || exit 1
cp tests/tagrows-state.qml "$test_root/config/TagStateProbe.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 20 qs -p "$test_root/config" 2>&1)

# Sample input, one probe line: "  INFO qml: TAGROWS PASS grid=96/120"
if printf '%s\n' "$output" | grep -q 'Cannot anchor'; then
    printf 'FAIL a tag slot anchors across its content edge\n'
    printf '%s\n' "$output" | grep -a 'TAGROWS'
    printf '%s\n' "$output" | grep -a 'Cannot anchor' | head -20
    exit 1
fi
if printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|Cannot read|Unable to assign|is not a function|is not defined|Binding loop detected'; then
    printf 'FAIL a tag part read or wrote a property its row does not have, or a width feeds itself\n'
    exit 1
fi
pass_count=$(printf '%s\n' "$output" | grep -c 'TAGROWS PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'TAGROWS FAIL')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL a tag slot built where it must not, or sits where the board says it does not\n'
    printf '%s\n' "$output" | grep -a 'TAGROWS'
    printf '%s\n' "$output" | grep -aiE 'ERROR|error' | head -20
    exit 1
fi
printf '%s\n' "$output" | grep -o 'TAGROWS PASS.*'
# A QML file's code: both comment forms dropped in one left-to-right pass, so a /* inside a // line (or the reverse) is read as the comment it sits in.
# Sample input, a line it strips: "    // createObject(netGap, { sidebar: root })"
qml_code() { perl -0pe 's{//[^\n]*|/\*.*?\*/}{}gs' "$1"; }
# The TAGS section ends the places group by construction, so this pin reads code only and a comment naming the call never satisfies it.
creates_in_gap() { qml_code "$1" | grep -q 'createObject(netGap'; }
if grep -q "stackBefore" ui/Sidebar.qml; then
    printf 'FAIL the rail orders its rows through stackBefore, which QML cannot call\n'
    exit 1
fi
if grep -q '\.data = ' ui/Sidebar.qml; then
    printf 'FAIL the rail replaces its whole data list\n'
    exit 1
fi
creates_in_gap ui/Sidebar.qml || { printf 'FAIL the TAGS section is not created inside the network gap\n'; exit 1; }
# The pin must go red on a file that only mentions the call in a comment, of either form, inside the marked test root.
printf 'Item {\n    /* createObject(netGap, { sidebar: root })\n       is the call this file no longer makes */\n}\n' > "$test_root/block-decoy.qml" || exit 1
printf 'Item {\n    // createObject(netGap, { sidebar: root })\n}\n' > "$test_root/line-decoy.qml" || exit 1
for decoy in block-decoy line-decoy; do
    if creates_in_gap "$test_root/$decoy.qml"; then
        printf 'FAIL the TAGS pin is satisfied by a comment (%s)\n' "$decoy"
        exit 1
    fi
done
