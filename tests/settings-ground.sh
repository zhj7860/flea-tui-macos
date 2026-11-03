#!/usr/bin/env bash
# Settings ground press-move-release over the real pane, offscreen with private state and a private bus.
set -uo pipefail
script_path=$(realpath -- "$0") || exit 1
cd "$(dirname "$script_path")/.." || exit 1
. "$PWD/tests/headless-commons.sh"
. "$PWD/tools/flea-sandbox-guard"
mode=${1:-invocations}
case $mode in invocations|candidate|ground-mutant|card-mutant|ruler-mutant) ;; *) echo 'FAIL settings-ground unknown mode'; exit 1 ;; esac
if [[ "$mode" == invocations ]]; then
    verdict=0
    bash tests/settings-ground.sh candidate
    status=$?
    printf 'SETTINGS_GROUND INVOCATION root exit=%s\n' "$status"
    [[ "$status" == 0 ]] || verdict=1
    (cd tests && bash settings-ground.sh candidate)
    status=$?
    printf 'SETTINGS_GROUND INVOCATION tests exit=%s\n' "$status"
    [[ "$status" == 0 ]] || verdict=1
    exit "$verdict"
fi
python3 -B tests/lib/settings-ground-point.py --self-test || exit 1
command -v qs >/dev/null || { echo 'FAIL settings-ground needs qs'; exit 1; }
command -v dbus-run-session >/dev/null || { echo 'FAIL settings-ground needs private D-Bus'; exit 1; }
bin=${FLEA_BIN:-$PWD/target/debug/flea}
[[ -x "$bin" ]] || { echo 'FAIL settings-ground needs the candidate backend'; exit 1; }
sandbox_root_ok
probe=$(mktemp -d "$SANDBOX_ROOT/flea-settings-ground.XXXXXXXX") || exit 1
: > "$probe/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$probe"; }
trap cleanup EXIT
if [[ "$mode" == candidate ]]; then
    python3 - "$PWD/tests/lib/settings-ground-point.py" "$probe" <<'PY' || exit 1
import pathlib
import subprocess
import sys

root = pathlib.Path(sys.argv[2])
assert root.is_absolute() and (root / ".flea-test-sandbox").is_file()
path = root / "rail-mutant.py"
assert path.resolve().is_relative_to(root.resolve())
text = pathlib.Path(sys.argv[1]).read_text()
anchor = "    exclusions = [(rail_x - margin, rail_x + rail_width + margin)] if rail_width else []"
assert text.count(anchor) == 1
path.write_text(text.replace(anchor, "    exclusions = []", 1))
result = subprocess.run([sys.executable, "-B", str(path), "--self-test"], capture_output=True, text=True)
if result.returncode != 1 or "AssertionError: rail exclusion did not move the candidate off the rail" not in result.stderr:
    sys.exit("FAIL rail mutant did not fail the intended fixture: " + result.stdout + result.stderr)
print("SETTINGS_GROUND_POINT CONTROL rail-mutant exit=1 candidate-covered-only-by-rail")
PY
fi
mkdir -p "$probe"/{home,config,state,data,cache,runtime} "$probe/home/fixture/aaa" || exit 1
chmod 700 "$probe/runtime" || exit 1
printf 'payload\n' > "$probe/home/fixture/s1.txt"
printf 'payload\n' > "$probe/home/fixture/b.txt"
env HOME="$probe/home" XDG_STATE_HOME="$probe/state" "$bin" --ui-state \
    '{"view":"list","keys":"default","menu":{"hidden":[]},"preview":{"column":false,"thumbnails":"off"},"updates":{"autoCheck":false},"display":{"textSize":{"mode":14}}}' >/dev/null || exit 1
if [[ "$mode" == candidate ]]; then
    ln -s "$PWD/ui" "$probe/config/flea" || exit 1
else
    cp -a "$PWD/ui" "$probe/config/flea" || exit 1
    python3 - "$probe" "$mode" <<'PY' || exit 1
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
assert root.is_absolute() and (root / ".flea-test-sandbox").is_file()
path = root / "config/flea" / ("SettingsRuler.qml" if sys.argv[2] == "ruler-mutant" else "SettingsPanel.qml")
assert path.resolve().is_relative_to(root.resolve())
text = path.read_text()
if sys.argv[2] == "ground-mutant":
    anchor = "            onClicked: root.close()"
    assert text.count(anchor) == 1
    text = text.replace(anchor, "            onClicked: {}", 1)
elif sys.argv[2] == "card-mutant":
    anchor = "        MouseArea {\n            anchors.fill: parent\n            acceptedButtons: Qt.LeftButton | Qt.RightButton\n            onClicked: {}\n            onWheel: function (wheel) { wheel.accepted = true }\n        }\n"
    assert text.count(anchor) == 1
    text = text.replace(anchor, "", 1)
else:
    anchor = "TapHandler {\n                enabled: root.active"
    assert text.count(anchor) == 1
    text = text.replace(anchor, "TapHandler {\n                enabled: false", 1)
path.write_text(text)
PY
fi
headless_commons "$probe" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$probe/config/Ui" || exit 1
ln -s "$PWD/ui/boot/fleatab.qml" "$probe/config/fleatab.qml" || exit 1
cp tests/settings-ground.qml "$probe/config/shell.qml" || exit 1
printf 'SETTINGS_GROUND PANEL mode=%s sha256=%s\n' "$mode" "$(sha256sum "$probe/config/flea/SettingsPanel.qml" | cut -d' ' -f1)"
printf 'SETTINGS_GROUND RULER mode=%s sha256=%s\n' "$mode" "$(sha256sum "$probe/config/flea/SettingsRuler.qml" | cut -d' ' -f1)"
log="$probe/qs.log"
env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u FLEA_SELECT \
    HOME="$probe/home" XDG_STATE_HOME="$probe/state" XDG_CONFIG_HOME="$probe/config" \
    XDG_DATA_HOME="$probe/data" XDG_CACHE_HOME="$probe/cache" XDG_RUNTIME_DIR="$probe/runtime" \
    FLEA_PATH="$probe/home/fixture" FLEA_BIN="$bin" GIO_USE_VOLUME_MONITOR=unix \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
    timeout 60 dbus-run-session -- qs -p "$probe/config" > "$log" 2>&1
qs_status=$?
cat "$log"
verdict=0
[[ "$qs_status" == 143 ]] || { printf 'FAIL qs exit %s, expected 143 after backend drain\n' "$qs_status"; verdict=1; }
[[ "$(rg -c 'SETTINGS_GROUND DONE' "$log")" == 1 ]] || { echo 'FAIL expected one completion receipt'; verdict=1; }
rg -q 'SETTINGS_GROUND DONE checks=126 failed=0' "$log" || { echo 'FAIL settings-ground tally'; verdict=1; }
[[ "$(rg -c 'SETTINGS_GROUND ok ' "$log")" == 126 ]] || { echo 'FAIL settings-ground passed tally'; verdict=1; }
# Offscreen cannot mask the window or connect the real WindowBody's Hyprland import to a compositor.
if rg 'SETTINGS_GROUND FAIL|TypeError|ReferenceError|ERROR|Cannot assign|WARN' "$log" \
    | rg -vF -e 'This plugin does not support setting window masks' -e '$HYPRLAND_INSTANCE_SIGNATURE is unset. Cannot connect to hyprland.' >/dev/null; then
    echo 'FAIL settings-ground logged a failed check or engine warning'
    verdict=1
fi
[[ -f "$probe/home/fixture/s1.txt" && ! -e "$probe/home/fixture/aaa/s1.txt" ]] || { echo 'FAIL the file moved under Settings'; verdict=1; }
printf 'SETTINGS_GROUND STATUS qs_exit=%s\n' "$qs_status"
if [[ "$mode" == candidate && "$verdict" == 0 ]]; then
    for control in ground-mutant card-mutant ruler-mutant; do
        output=$(bash "$script_path" "$control" 2>&1)
        control_status=$?
        failures=$(printf '%s\n' "$output" | rg 'SETTINGS_GROUND FAIL')
        warnings=$(printf '%s\n' "$output" | rg 'TypeError|ReferenceError|ERROR|Cannot assign|WARN' \
            | rg -vF -e 'This plugin does not support setting window masks' -e '$HYPRLAND_INSTANCE_SIGNATURE is unset. Cannot connect to hyprland.')
        if [[ "$control" == ground-mutant ]]; then
            expected=5
            pattern='SETTINGS_GROUND FAIL ((left|right) (drag|click)|ground-owned release over card) release preserves the gesture.s dismissal:'
        elif [[ "$control" == card-mutant ]]; then
            expected=4
            pattern='SETTINGS_GROUND FAIL (card (left|right) click|(card|contents) to ground right) release preserves the gesture.s dismissal:'
        else
            expected=1
            pattern='SETTINGS_GROUND FAIL ruler to ground the real ruler handler owns the press:'
        fi
        if [[ "$control_status" != 1 || -n "$warnings" ]] || ! rg -q "SETTINGS_GROUND DONE checks=126 failed=$expected" <<< "$output" \
            || [[ "$(rg -c 'SETTINGS_GROUND FAIL' <<< "$failures")" != "$expected" ]] \
            || rg -qv "$pattern" <<< "$failures" \
            || rg -q 'FAIL qs exit|FAIL expected one|harness error|FAIL the file moved|TypeError|ReferenceError|ERROR|Cannot assign' <<< "$output"; then
            printf 'FAIL settings-ground %s control did not fail only its intended checks, exit=%s\n%s\n' "$control" "$control_status" "$output"
            verdict=1
        else
            printf '%s\n' "$output" | rg '^SETTINGS_GROUND (PANEL|RULER) '
            printf '%s\n' "$failures" | sed 's/SETTINGS_GROUND FAIL/SETTINGS_GROUND expected-red/'
            printf 'SETTINGS_GROUND CONTROL %s exit=%s checks=126 failed=%s\n' "$control" "$control_status" "$expected"
        fi
    done
fi
exit "$verdict"
