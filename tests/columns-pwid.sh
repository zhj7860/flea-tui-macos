#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# The Columns view's preview column edge on the real ui/ColumnsArea.qml, offscreen: no line at rest, the board's line and mark on hover, a live drag with one save on release, both clamps, a double click back to the default third, a click and a jitter that save nothing, a grab lost or an edge hidden mid-drag, and a relaunch that restores the width on its first frame.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "columns-pwid.sh: qs is not installed, cannot draw the columns"
    exit 1
fi

# A marked sandbox of its own under the fixture root, so cleanup deletes only what this run owns.
test_root=$(mktemp -d "$FIXTURE_ROOT/flea-columns-pwid-XXXXXX") || exit 1
# GNU mktemp -d keeps a relative TMPDIR verbatim, so the path is checked absolute and two components deep.
case $test_root in
  /*/*) ;;
  *) echo "FAIL: mktemp -d gave '$test_root', which is not an absolute path two components deep"; exit 1 ;;
esac
sandbox_require "$test_root" || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state/flea" "$test_root/runtime" "$test_root/bin" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/columns-pwid.qml "$test_root/config/shell.qml" || exit 1
cp tests/columns-pwid-pane.qml "$test_root/config/PwidPane.qml" || exit 1
cp tests/columns-pwid-legs.js "$test_root/config/columns-pwid-legs.js" || exit 1

saves="$test_root/saves.log"
# Stands for flea --ui-state PATCH: it records the patch it was asked to store and stores nothing.
printf '#!/bin/sh\nprintf "%%s\\n" "$2" >> "$PWID_SAVES"\n' > "$test_root/bin/flea-stub" || exit 1
chmod +x "$test_root/bin/flea-stub" || exit 1

verdict=0
# One qs run: $1 is the phase, $2 the stored percent the probe expects. Prints the probe's lines and sets run_status.
run_probe() {
    output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        FLEA_BIN="$test_root/bin/flea-stub" PWID_SAVES="$saves" PWID_PHASE="$1" PWID_STORED="$2" \
        HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
        QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
        timeout 60 qs -p "$test_root/config" 2>&1)
    run_status=$?
    # Sample input: "  INFO qml: PWID PASS 41 checks", then "PWID DONE failures=0", then the probe's own SIGTERM (143).
    pass_count=$(printf '%s\n' "$output" | grep -c 'PWID PASS')
    fail_count=$(printf '%s\n' "$output" | grep -c 'PWID FAIL')
    done_count=$(printf '%s\n' "$output" | grep -c 'PWID DONE')
    if [ "$run_status" -ne 143 ] || [ "$done_count" -ne 1 ]; then
        printf 'FAIL %s run: qs exited %s with %s completion receipts, want the owned self-kill 143 after one DONE\n' "$1" "$run_status" "$done_count"
        verdict=1
    fi
    if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
        printf 'FAIL %s run: the preview column edge missed its contract\n' "$1"
        printf '%s\n' "$output" | grep -aE 'PWID|ERROR|error'
        verdict=1
    fi
    # A stub pane has no signals for a Connections handler to name, so those warnings are the stub's; a script error is never.
    warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|ERROR')
    if [ -n "$warnings" ]; then
        printf 'FAIL %s run: the harness logged a warning\n' "$1"
        printf '%s\n' "$warnings"
        verdict=1
    fi
}

: > "$saves" || exit 1
run_probe drag 0
drag_output=$output
# The relaunch reads what the first run's last save said, as the writer would have stored it.
last_save=$(tail -n 1 "$saves")
# Sample input: '{"preview":{"width":42}}', the one patch line the stub writer logs per save; the sed keeps the digits after "width".
stored=$(printf '%s\n' "$last_save" | sed -n 's/.*"width":\([0-9]*\).*/\1/p')
if [ -z "$stored" ]; then
    printf 'FAIL the drag run saved no width to restore\n'
    verdict=1
else
    printf '%s\n' "$last_save" > "$test_root/state/flea/ui.json" || exit 1
    : > "$saves" || exit 1
    run_probe restore "$stored"
fi
if [ "$verdict" -ne 0 ]; then
    printf '%s\n' "$drag_output"
    exit 1
fi
printf '%s\n' "$drag_output" | grep -o 'PWID PASS.*'
printf '%s\n' "$output" | grep -o 'PWID PASS.*'
printf 'PWID STATUS stored=%s runs=2\n' "$stored"
