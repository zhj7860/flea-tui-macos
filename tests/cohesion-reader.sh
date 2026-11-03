#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# ipc cohesionControls answers sane boxes and states in the real WindowBody, offscreen.
set -u
cd "$(dirname "$0")/.." || exit 1
. "$PWD/tools/flea-sandbox-guard"
command -v qs >/dev/null || { echo 'FAIL cohesion-reader needs qs'; exit 1; }
command -v dbus-run-session >/dev/null || { echo 'FAIL cohesion-reader needs a private D-Bus session'; exit 1; }
bin=${FLEA_BIN:-$PWD/target/debug/flea}
[[ -x "$bin" ]] || { echo 'FAIL cohesion-reader needs the built backend'; exit 1; }
sandbox_root_ok
probe=$(mktemp -d "$SANDBOX_ROOT/flea-cohesion-reader.XXXXXX") || exit 1
: > "$probe/$SANDBOX_MARKER" || exit 1
qs_pid=""
# The run and each teardown wait are polled ten times a second (poll_s is one over polls_per_s) up to these bounds.
poll_s=0.1
polls_per_s=10
run_budget_s=60
stop_grace_s=2
run_polls=$(( run_budget_s * polls_per_s ))
stop_polls=$(( stop_grace_s * polls_per_s ))
stop_qs() {
    [[ -n "$qs_pid" ]] || return 0
    local tick
    kill -TERM -- "-$qs_pid" 2>/dev/null || true
    for ((tick = 0; tick < stop_polls; tick++)); do
        kill -0 -- "-$qs_pid" 2>/dev/null || break
        sleep "$poll_s"
    done
    if kill -0 -- "-$qs_pid" 2>/dev/null; then
        kill -KILL -- "-$qs_pid" 2>/dev/null || true
        for ((tick = 0; tick < stop_polls; tick++)); do
            kill -0 -- "-$qs_pid" 2>/dev/null || break
            sleep "$poll_s"
        done
    fi
    wait "$qs_pid" 2>/dev/null || true
    if kill -0 -- "-$qs_pid" 2>/dev/null; then
        printf 'FAIL cohesion-reader owned process group %s survived teardown\n' "$qs_pid"
        return 1
    fi
    qs_pid=""
}
cleanup() { stop_qs || return 1; chmod u+w "$probe/home/readonly" 2>/dev/null; sandbox_remove "$probe"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$probe"/{home,config,state,data,cache,runtime} "$probe/home"/{fixture,readonly,Downloads} || exit 1
mkdir -p "$probe/data/Trash"/{files,info}
printf 'discarded\n' > "$probe/data/Trash/files/discarded.txt"
printf '[Trash Info]\nPath=%s\nDeletionDate=2026-09-23T10:00:00\n' "$probe/home/discarded.txt" > "$probe/data/Trash/info/discarded.txt.trashinfo"
chmod 700 "$probe/runtime"
printf 'a\n' > "$probe/home/fixture/a.txt"
printf 'b\n' > "$probe/home/fixture/b.txt"
python3 - "$probe/home/fixture/manual.pdf" <<'PY' || exit 1
import pathlib, sys
objects = ['<< /Type /Catalog /Pages 2 0 R >>', '<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>']
for page in range(2):
    stream = '0.1 0.1 0.1 rg 30 500 100 24 re f'
    objects.append(f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 560] /Contents {4 + page * 2} 0 R >>')
    objects.append(f'<< /Length {len(stream)} >>\nstream\n{stream}\nendstream')
data = b'%PDF-1.4\n'
offsets = []
for number, body in enumerate(objects, 1):
    offsets.append(len(data))
    data += f'{number} 0 obj\n{body}\nendobj\n'.encode()
xref = len(data)
data += f'xref\n0 {len(objects) + 1}\n0000000000 65535 f \n'.encode()
for offset in offsets:
    data += f'{offset:010d} 00000 n \n'.encode()
data += f'trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode()
pathlib.Path(sys.argv[1]).write_bytes(data)
PY
ln -s a.txt "$probe/home/fixture/link.txt"
mkdir "$probe/home/fixture/sub"
printf 'read only\n' > "$probe/home/readonly/ro.txt"
touch -d '2000-01-01 00:00:00 UTC' "$probe/home/fixture/a.txt"
chmod 555 "$probe/home/readonly"
cat > "$probe/data/recently-used.xbel" <<XML
<?xml version="1.0"?><xbel version="1.0">
<bookmark href="file://$probe/home/fixture/a.txt" visited="2026-09-23T10:47:00Z"/>
<bookmark href="file://$probe/home/fixture/b.txt" visited="2026-09-22T09:12:00Z"/>
</xbel>
XML
env HOME="$probe/home" XDG_STATE_HOME="$probe/state" "$bin" --ui-state \
    '{"preview":{"column":false,"thumbnails":"off"},"updates":{"autoCheck":false}}' >/dev/null || exit 1
# One qs run per leg, each with its own shell directory: LEG RECEIPT SHELL_QML UI [ENV=VALUE...].
leg() {
    local name="$1" receipt="$2" shell="$3" ui="$4" config="$probe/config-$1" log="$probe/$1.log" tick tally
    shift 4
    mkdir -p "$config" || return 1
    ln -s "$ui" "$config/flea"
    headless_commons "$probe" "$config/Commons" || exit 1
    ln -s "$(readlink -f ui/boot/Ui)" "$config/Ui"
    # The window loads its tab catcher from the shell directory, so the probe ships it as the product does.
    ln -s "$PWD/ui/boot/fleatab.qml" "$config/fleatab.qml"
    cp "$shell" "$config/shell.qml"
    cp tests/button-probe.js "$config/button-probe.js" || return 1
    env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u FLEA_SELECT \
        HOME="$probe/home" XDG_STATE_HOME="$probe/state" XDG_CONFIG_HOME="$config" \
        XDG_DATA_HOME="$probe/data" XDG_CACHE_HOME="$probe/cache" XDG_RUNTIME_DIR="$probe/runtime" \
        FLEA_BIN="$bin" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic \
        QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 "$@" setsid dbus-run-session -- qs -p "$config" >"$log" 2>&1 </dev/null &
    qs_pid=$!
    for ((tick = 0; tick < run_polls; tick++)); do
        grep -aq "$receipt DONE checks=[0-9]* failed=[0-9]*" "$log" && break
        sleep "$poll_s"
    done
    stop_qs || return 1
    printf 'cohesion-reader %s: owned process group gone\n' "$name"
    grep -aE "$receipt|TypeError|ReferenceError|ERROR|Cannot assign|Insufficient arguments" "$log"
    tally=$(grep -ao "$receipt DONE checks=[0-9]* failed=[0-9]*" "$log" | tail -1)
    [[ -n "$tally" ]] || { printf 'FAIL cohesion-reader %s produced no completion receipt inside %ss; log tail:\n' "$name" "$run_budget_s"; tail -20 "$log"; return 1; }
    [[ "$tally" == *' failed=0' ]] || return 1
    if grep -aqE 'TypeError|ReferenceError|ERROR|Cannot assign|Insufficient arguments' "$log"; then
        printf 'FAIL cohesion-reader %s logged an engine error beside its receipt\n' "$name"
        return 1
    fi
}
leg window COHREADER tests/cohesion-reader.qml "$PWD/ui" FLEA_PATH="$probe/home/fixture" || exit 1
# The picker leg opens the portal's window on the same fixture, as a file request would.
request=$(printf '{"mode":"open","multiple":true,"folder":"%s","name":"a.txt","title":"Cohesion picker","filters":[{"label":"Text","globs":["*.txt"],"mimes":[]}]}' "$probe/home/fixture")
leg picker COHPICKER tests/cohesion-picker-reader.qml "$PWD/ui" FLEA_PICKER="$request" FLEA_PICKER_REPLY="$probe/reply.json" || exit 1
mkdir -p "$probe/capture-ui" || exit 1
cp -a ui/. "$probe/capture-ui/" || exit 1
cp tests/ui-captures-reader.qml "$probe/capture-ui/IpcControls.qml" || exit 1
leg capture-window COHREADER tests/cohesion-reader.qml "$probe/capture-ui" FLEA_PATH="$probe/home/fixture" FLEA_COH_CAPTURE=true || exit 1
leg capture-picker COHPICKER tests/cohesion-picker-reader.qml "$probe/capture-ui" FLEA_PICKER="$request" FLEA_PICKER_REPLY="$probe/capture-reply.json" FLEA_COH_CAPTURE=true || exit 1
leg capture COHCAPTURE tests/cohesion-capture-reader.qml "$probe/capture-ui" || exit 1
# Without the wheel, the same derived PDF stays asleep and must fail before any held press.
if leg capture-no-wheel COHCAPTURE tests/cohesion-capture-reader.qml "$probe/capture-ui" FLEA_COH_SKIP_WHEEL=true > "$probe/no-wheel.log" 2>&1; then
    printf 'FAIL cohesion-reader: the sleeping PDF passed without its wake wheel\n'
    exit 1
fi
grep -q 'COHCAPTURE FAIL an asleep PDF bar cannot expose without a wheel' "$probe/no-wheel.log" \
    || { cat "$probe/no-wheel.log"; printf 'FAIL cohesion-reader: the no-wheel control failed for another reason\n'; exit 1; }
printf 'cohesion-reader capture-no-wheel: the asleep PDF was refused before any press\n'
for mutant in root-scale no-inset; do
    cp -a "$probe/capture-ui" "$probe/$mutant-ui" || exit 1
    python3 - "$probe" "$mutant" <<'PY' || exit 1
from pathlib import Path
import sys
root = Path(sys.argv[1])
assert root.is_absolute() and (root / '.flea-test-sandbox').is_file()
mutant = sys.argv[2]
assert mutant in ('root-scale', 'no-inset')
path = root / f'{mutant}-ui/DialogButton.qml'
assert path.resolve().is_relative_to(root.resolve())
source = path.read_text()
if mutant == 'root-scale':
    anchor = '    id: root\n'
    assert source.count(anchor) == 1
    source = source.replace(anchor, anchor + '    scale: tap.pressed && root.available && !Theme.reducedMotion ? Buttons.PRESS_SCALE : 1\n', 1)
else:
    for axis, span in (('X', 'width'), ('Y', 'height')):
        anchor = f'property int inset{axis}: root.pressShown && !Theme.reducedMotion ? Math.round(box.{span} * (1 - Buttons.PRESS_SCALE) / 2) : 0'
        assert source.count(anchor) == 1
        source = source.replace(anchor, f'property int inset{axis}: 0', 1)
path.write_text(source)
PY
    control_log="$probe/$mutant.control.log"
    control_status=0
    leg "capture-$mutant" COHCAPTURE tests/cohesion-capture-reader.qml "$probe/$mutant-ui" > "$control_log" 2>&1 || control_status=$?
    if [ -n "${FLEA_CI_SUITE_LOGS:-}" ]; then
        cp "$control_log" "$FLEA_CI_SUITE_LOGS/cohesion-reader-$mutant.control.log" || exit 1
    fi
    root_failed=$(grep -cF 'COHCAPTURE FAIL press keeps the root unscaled and coordinate signature stable' "$control_log" || true)
    fixed_failed=$(grep -cF 'COHCAPTURE FAIL a press keeps the hit box and coordinate signature fixed' "$control_log" || true)
    caption_failed=$(grep -cF 'COHCAPTURE FAIL a press keeps the caption geometry fixed' "$control_log" || true)
    local_failed=$(grep -cF 'COHCAPTURE FAIL only the frame takes the exact whole-pixel press inset' "$control_log" || true)
    # Keep exact assertions and count any local-coordinate failure from inverse-transform rounding.
    expected_failed=3; expected_root=0; expected_fixed=0; expected_caption=0; expected_local=1
    if [ "$mutant" = root-scale ]; then
        expected_failed=$((5 + local_failed)); expected_root=1; expected_fixed=1; expected_caption=1
        expected_local=$local_failed
    fi
    if [ "$control_status" -ne 1 ] || ! grep -qF "COHCAPTURE DONE checks=23 failed=$expected_failed" "$control_log" \
        || [ "$root_failed" -ne "$expected_root" ] \
        || [ "$fixed_failed" -ne "$expected_fixed" ] \
        || [ "$caption_failed" -ne "$expected_caption" ] \
        || [ "$local_failed" -ne "$expected_local" ] \
        || [ "$local_failed" -gt 1 ] \
        || ! grep -qF 'COHCAPTURE FAIL press insets only the frame on whole pixels' "$control_log" \
        || ! grep -qF 'COHCAPTURE FAIL press insets only the wash on whole pixels' "$control_log" \
        || grep -qE 'TypeError|ReferenceError|ERROR|Cannot assign|Insufficient arguments' "$control_log"; then
        cat "$control_log"
        printf 'FAIL cohesion-reader %s mutant did not fail only its geometry checks\n' "$mutant"
        exit 1
    fi
    printf 'COHCAPTURE CONTROL %s rejected checks=23 failed=%s exit=%s\n' "$mutant" "$expected_failed" "$control_status"
done
