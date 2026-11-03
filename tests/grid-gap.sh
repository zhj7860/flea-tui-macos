#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# The first grid tile's frame stands a gap plus a hairline off the rail and the chrome.
# Offscreen and with no compositor, so this needs neither the display nor the display lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "grid-gap.sh: qs is not installed, cannot draw a grid tile"
    exit 1
fi

test_root="$FIXTURE_ROOT/flea-grid-gap-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/grid-gap.qml "$test_root/config/shell.qml" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 20 qs -p "$test_root/config" 2>&1)

# Sample input, one probe line: "  INFO qml: GRID_GAP PASS widths=500,800,1200 gap=8 lane=12 columns=3,5,7"
pass_count=$(printf '%s\n' "$output" | grep -c 'GRID_GAP PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'GRID_GAP FAIL')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL a grid tile frame left the gap or the tile maths drifted\n'
    printf '%s\n' "$output" | grep -aE 'GRID_GAP|ERROR|error' | head -20
    exit 1
fi
printf '%s\n' "$output" | grep -o 'GRID_GAP PASS.*'
printf '%s\n' "$output" | grep -aE 'GRID_GAP (ROWS|LIFT)' | head -12

# Mutant control in a scratch copy: with the lift off the bottom check must fail.
mutant_ui="$test_root/mutant-ui"
cp -r "$PWD/ui" "$mutant_ui" || exit 1
sed -i 's#if (root.contentHeight + root.topMargin + root.bottomMargin <= root.height || root.columns < 1 || view < 0) return#return // mutant-nolift: the lift stays off#' "$mutant_ui/GridArea.qml" || exit 1
[ "$(grep -c 'mutant-nolift' "$mutant_ui/GridArea.qml")" = 1 ] || { printf 'FAIL the nolift mutant patch missed\n'; exit 1; }
mkdir -p "$test_root/mutant-config" || exit 1
ln -s "$mutant_ui" "$test_root/mutant-config/flea" || exit 1
headless_commons "$test_root" "$test_root/mutant-config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/mutant-config/Ui" || exit 1
cp tests/grid-gap.qml "$test_root/mutant-config/shell.qml" || exit 1

mutant_output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 30 qs -p "$test_root/mutant-config" 2>&1)

printf 'MUTANT-NOLIFT BEGIN\n'
printf '%s\n' "$mutant_output" | grep -aE 'GRID_GAP (LIFT|FAIL)' | sed 's/GRID_GAP FAIL/MUTANT-NOLIFT expected-failure:/' | head -30
printf 'MUTANT-NOLIFT END\n'
if ! printf '%s\n' "$mutant_output" | grep -aq 'GRID_GAP FAIL last tile bottom'; then
    printf 'FAIL the nolift mutant kept the bottom gap, so the suite cannot feel the lift\n'
    exit 1
fi

# Second mutant leg in a scratch copy: with only the restore lift off the restore check must fail.
restore_ui="$test_root/restore-mutant-ui"
cp -r "$PWD/ui" "$restore_ui" || exit 1
sed -i 's#root.keepLastRowClear(view)#// mutant-norestore-lift: the restore lift stays off#' "$restore_ui/GridArea.qml" || exit 1
[ "$(grep -c 'mutant-norestore-lift' "$restore_ui/GridArea.qml")" = 1 ] || { printf 'FAIL the norestore-lift mutant patch missed\n'; exit 1; }
mkdir -p "$test_root/restore-mutant-config" || exit 1
ln -s "$restore_ui" "$test_root/restore-mutant-config/flea" || exit 1
headless_commons "$test_root" "$test_root/restore-mutant-config/Commons" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/restore-mutant-config/Ui" || exit 1
cp tests/grid-gap.qml "$test_root/restore-mutant-config/shell.qml" || exit 1

restore_output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 30 qs -p "$test_root/restore-mutant-config" 2>&1)

printf 'MUTANT-NORESTORE-LIFT BEGIN\n'
printf '%s\n' "$restore_output" | grep -aE 'GRID_GAP (LIFT|FAIL)' | sed 's/GRID_GAP FAIL/MUTANT-NORESTORE-LIFT expected-failure:/' | head -30
printf 'MUTANT-NORESTORE-LIFT END\n'
if ! printf '%s\n' "$restore_output" | grep -aq 'GRID_GAP FAIL.*restored last tile bottom'; then
    printf 'FAIL the norestore-lift mutant kept the restored bottom gap, so the suite cannot feel the restore lift\n'
    exit 1
fi
