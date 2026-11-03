#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# Quick Look's font page over a stub backend: the page whole in one turn, one ask per theme change, a stale answer dropped, a refusal shown as the unsupported state.
set -uo pipefail
. "$(dirname "$0")/../tools/flea-sandbox-guard"
. "$(dirname "$0")/qslog-gate.sh"
cd "$(dirname "$0")/.." || exit 1
for tool in qs python3; do
    command -v "$tool" >/dev/null || { printf 'FAIL fontpane: %s is required\n' "$tool"; exit 1; }
done
test_root="$FIXTURE_ROOT/flea-fontpane-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
mkdir -p "$test_root"/{fixture,runtime,state,cache} || exit 1
chmod 700 "$test_root/runtime" || exit 1
# Three sample sets of three PNGs, one colour each, at the pixel sizes of the board's three samples; and files whose names the stub backend answers for.
python3 -I - "$test_root/fixture" <<'PY' || { printf 'FAIL fontpane: could not make the sample images\n'; exit 1; }
import struct, sys, zlib
def png(w, h, rgb):
    raw = b"".join(b"\x00" + bytes(rgb) * w for _ in range(h))
    def chunk(t, b):
        return struct.pack(">I", len(b)) + t + b + struct.pack(">I", zlib.crc32(t + b) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
for name, rgb in (("r0", (200, 60, 60)), ("r1", (60, 60, 200)), ("hack", (60, 200, 60))):
    for i, (w, h) in enumerate(((412, 34), (286, 24), (231, 20))):
        open("%s/%s-%d.png" % (sys.argv[1], name, i), "wb").write(png(w, h, rgb))
PY
for name in Inter-Bold.ttf Hack-Regular.otf Slow-Light.ttf Broken.ttf; do
    printf 'not read: the stub backend answers for this name\n' > "$test_root/fixture/$name" || exit 1
done
printf 'a line of notes\n' > "$test_root/fixture/notes.txt" || exit 1
# The palette Theme reads, and the one a theme switch writes; theme.name is the file Theme watches for a switch.
palette="$test_root/home/.local/state/omarchy/current"
mkdir -p "$palette/theme" || exit 1
printf 'background = "#101315"\nforeground = "#c0caf5"\ndark_background = "#181825"\n' > "$palette/theme/colors.toml" || exit 1
printf 'background = "#ffffff"\nforeground = "#202020"\ndark_background = "#eeeeee"\n' > "$test_root/alt-colors.toml" || exit 1
printf 'dark\n' > "$palette/theme.name" || exit 1
# One qs run of the probe over a ui/ tree: sets $status and writes $test_root/NAME.log.
probe() {
    local name=$1 ui=$2 config="$test_root/config-$1"
    mkdir -p "$config" || return 1
    ln -s "$ui" "$config/flea" || return 1
    headless_commons "$test_root" "$config/Commons" || exit 1
    ln -s "$(readlink -f ui/boot/Ui)" "$config/Ui" || return 1
    cp tests/fontpane.qml "$config/shell.qml" || return 1
    cp "$test_root/colors-dark.toml" "$palette/theme/colors.toml" || return 1
    ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" XDG_RUNTIME_DIR="$test_root/runtime" \
        FLEA_REDUCED_MOTION=1 FONTPANE_DIR="$test_root/fixture" FONTPANE_ALT="$test_root/alt-colors.toml" \
        FONTPANE_DARK="$test_root/colors-dark.toml" FONTPANE_COLORS="$palette/theme/colors.toml" FONTPANE_NAME="$palette/theme.name" \
        QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
        QT_LOGGING_RULES="$(qslog_rules)" \
        timeout 90 qs -p "$config" > "$test_root/$name.log" 2>&1; exit $? ) 2>/dev/null
    status=$?
}
# The same ui/ with one exact line changed; refuses when the line is absent or not alone, so a control never runs on an unchanged tree.
mutate() {
    local name=$1 file=$2 from=$3 to=$4
    cp -a ui "$test_root/ui-$name" || return 1
    python3 -I - "$test_root/ui-$name/$file" "$from" "$to" <<'PY'
import sys
path, old, new = sys.argv[1:4]
text = open(path).read()
if text.count(old) != 1:
    sys.exit(1)
open(path, "w").write(text.replace(old, new))
PY
}
cp "$palette/theme/colors.toml" "$test_root/colors-dark.toml" || exit 1

probe run "$PWD/ui" || exit 1
log="$test_root/run.log"
[ -z "${FLEA_CI_SUITE_LOGS:-}" ] || cp "$log" "$FLEA_CI_SUITE_LOGS/fontpane-engine.log" 2>/dev/null
# Sample input, one probe line: "  INFO qml: FONTPANE STEP 4 the theme change asked once, with both colours of the new palette"
grep -a 'FONTPANE \(STEP\|FAIL\|DONE\)' "$log"
failures=0
qslog_crash fontpane "$log" || failures=$((failures + 1))
if { [ "$status" -ne 0 ] && [ "$status" -ne 143 ]; } || [ "$(grep -ac 'FONTPANE DONE' "$log")" -ne 1 ] \
    || grep -aqE 'FONTPANE FAIL|TypeError|ReferenceError|Binding loop detected' "$log"; then
    printf 'FAIL fontpane: the font page did not hold (qs exit %s)\n' "$status"
    grep -aE 'TypeError|ReferenceError|Binding loop detected' "$log" | head -3
    failures=$((failures + 1))
fi
# Controls: each undoes one fix on a copy of ui/ and the probe has to name it, so a green run above is not a probe that cannot fail.
control() {
    local name=$1 file=$2 from=$3 to=$4 want=$5
    if ! mutate "$name" "$file" "$from" "$to"; then
        printf 'FAIL fontpane: control %s could not change %s\n' "$name" "$file"
        failures=$((failures + 1))
        return
    fi
    probe "$name" "$test_root/ui-$name" || { failures=$((failures + 1)); return; }
    [ -z "${FLEA_CI_SUITE_LOGS:-}" ] || cp "$test_root/$name.log" "$FLEA_CI_SUITE_LOGS/fontpane-engine-$name.log" 2>/dev/null
    if grep -aq "FONTPANE FAIL $want" "$test_root/$name.log"; then
        printf 'fontpane: control %s is red as it must be (%s)\n' "$name" "$want"
    else
        printf 'FAIL fontpane: control %s stayed green or failed elsewhere, want "%s"\n' "$name" "$want"
        grep -a 'FONTPANE \(FAIL\|DONE\)' "$test_root/$name.log" | head -2
        failures=$((failures + 1))
    fi
}
control immediate-ask FontPane.qml 'onAskKeyChanged: askTimer.restart()' 'onAskKeyChanged: root.ask()' 'the theme change'
control any-answer FontPane.qml 'if (message.id !== root.pending) return' '' 'a stale answer'
control restarting-id FontPane.qml 'root.pending = Kinds.nextLookId()' 'root.pending += 1' "an earlier pane's late answer"
control kept-page-on-refusal FontPane.qml 'root.look = null' 'root.look = root.look' 'a refusal after a drawn page'
control bar-always-visible FontPane.qml 'visible: root.drawn' 'visible: true' 'the bar shows before the answer'
control no-refusal Preview.qml 'root.archiveFailed || root.fontFailed' 'root.archiveFailed' 'the unsupported sentence'
printf 'fontpane: %s failed\n' "$failures"
[ "$failures" -eq 0 ]
