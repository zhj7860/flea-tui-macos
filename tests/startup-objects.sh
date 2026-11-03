#!/usr/bin/env bash
# Census the real window after a small listing settles, with no display or operator state.
set -uo pipefail
. "$(dirname "$0")/../tools/flea-sandbox-guard"
. "$(dirname "$0")/headless-commons.sh"
cd "$(dirname "$0")/.." || exit 1
command -v qs >/dev/null || { printf 'FAIL startup-objects: qs is required\n'; exit 1; }
command -v dbus-run-session >/dev/null || { printf 'FAIL startup-objects: dbus-run-session is required\n'; exit 1; }
test_root="$FIXTURE_ROOT/flea-startup-objects-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
mkdir -p "$test_root"/{config,home,state/flea,cache,runtime,fixture,bin} || exit 1
chmod 700 "$test_root/runtime" || exit 1
headless_commons "$test_root" || exit 1
printf '{}\n' > "$test_root/state/flea/ui.json"
touch "$test_root/fixture/a.rs" "$test_root/fixture/b.py" "$test_root/fixture/c.go"
ln -s "$(readlink -m ui/boot/Ui)" "$test_root/config/Ui" || exit 1
# The window loads its tab catcher from the shell directory at startup, so the probe ships it as the product does.
ln -s "$PWD/ui/boot/fleatab.qml" "$test_root/config/fleatab.qml" || exit 1
cp tests/startup-objects.qml "$test_root/config/shell.qml" || exit 1
power_disk=""
for stat_file in /sys/block/*/stat; do
    [ -r "$stat_file" ] || continue
    power_disk=${stat_file%/stat}
    power_disk="/dev/${power_disk##*/}"
    break
done
[ -n "$power_disk" ] || { printf 'FAIL startup-objects: no readable disk stat\n'; exit 1; }
probe_timeout_seconds=20
leg_timeout_seconds=$((probe_timeout_seconds + 1))
cat > "$test_root/bin/gio" <<'SH'
#!/usr/bin/env bash
# Sample input: gio mount -t /dev/sda, held without touching the device.
case "${1-} ${2-}" in
    'mount -t'|'mount -u') exec sleep "$STARTUP_OBJECTS_LEG_TIMEOUT_SECONDS" ;;
    *) exec /usr/bin/gio "$@" ;;
esac
SH
chmod +x "$test_root/bin/gio" || exit 1
# One probe run: run_probe LOG BACKEND HANG EARLY, where EARLY exercises cold or in-flight menu demand.
run_probe() {
    if [[ "${5:-}" == off ]]; then printf '{"langMarks":false}\n' > "$test_root/state/flea/ui.json";
    else printf '{}\n' > "$test_root/state/flea/ui.json"; fi
    # The shell starts the GVfs trash daemon, so it runs on its own bus, whose daemons log to bus.log and stay out of the engine-warning scan.
    ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u QML_DISABLE_DISK_CACHE \
        HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
        XDG_RUNTIME_DIR="$test_root/runtime" FLEA_BIN="$2" STARTUP_OBJECTS_HANG="$3" \
        STARTUP_OBJECTS_MENU_EARLY="${4:-}" \
        STARTUP_OBJECTS_MARKS_OFF="$([[ "${5:-}" == off ]] && printf 1 || printf 0)" \
        FLEA_PATH="$test_root/fixture" STARTUP_OBJECTS_UI="$PWD/ui" STARTUP_OBJECTS_DISK="$power_disk" \
        PATH="$test_root/bin:$PATH" STARTUP_OBJECTS_LEG_TIMEOUT_SECONDS="$leg_timeout_seconds" \
        QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 QML_IMPORT_TRACE=1 \
        QT_LOGGING_RULES='qt.qml.diskcache*=true' \
        dbus-run-session -- bash -c 'timeout "$1" qs -p "$2" > "$3" 2>&1' _ "$probe_timeout_seconds" "$test_root/config" "$1" 2> "$test_root/bus.log" ) 2>/dev/null
}
log="$test_root/startup.log"
run_probe "$log" "$PWD/target/debug/flea" 0
status=$?
grep -a 'STARTUP_OBJECTS' "$log" || true
# Measurements survive a red pin so the next value comes from the actual execution path.
if grep -aq 'STARTUP_OBJECTS TOTAL' "$log"; then
    # Sample input: Error loading "file:///fixture/ui/Row.qml" from disk cache: <reason> yields Row.qml before TOTAL.
    measured=$(sed -n '1,/STARTUP_OBJECTS TOTAL/p' "$log" | grep -aoE 'Error loading "file://[^"]*/ui/[^"]+" from disk cache' | sed -E 's|.*/ui/([^"]+)".*|\1|' | sort -u)
    measured_bytes=0
    while IFS= read -r unit; do measured_bytes=$((measured_bytes + $(wc -c < "ui/$unit"))); done <<< "$measured"
    printf 'STARTUP_OBJECTS MEASURE units=%s bytes=%s\n' "$(printf '%s\n' "$measured" | grep -c .)" "$measured_bytes"
    printf '%s\n' "$measured" | sed 's/^/STARTUP_OBJECTS UNIT /'
fi
if [ "$status" -ne 0 ] && [ "$status" -ne 143 ]; then
    printf 'FAIL startup-objects: qs exit %s\n' "$status"
    cat "$log"
    exit 1
fi
trace_control=ui/js/Startup.js
# A silent trace cannot prove that the picker library stayed cold.
if ! grep -aFq "$trace_control" "$log"; then
    printf 'FAIL startup-objects: log %s has no loaded JS control %s\n' "$log" "$trace_control"
    exit 1
fi
if grep -aFq 'ui/js/Picker.js' "$log"; then
    printf 'FAIL startup-objects: the unused picker library loaded at startup\n'
    exit 1
fi
for static_input in ui/RailPlaces.qml ui/TrashHost.qml; do
    if [ ! -f "$static_input" ] || [ ! -r "$static_input" ]; then
        printf 'FAIL startup-objects: cannot read %s\n' "$static_input"
        exit 1
    fi
done
if grep -qE '^[[:space:]]*(readonly[[:space:]]+)?property .* entries:' ui/RailPlaces.qml; then
    printf 'FAIL startup-objects: the keymap-only places aggregate is eager\n'
    exit 1
fi
if grep -qE '^[[:space:]]*(readonly[[:space:]]+)?property var sheetPane:' ui/TrashHost.qml; then
    printf 'FAIL startup-objects: the keymap-only Trash pane uses a binding\n'
    exit 1
fi
if [ "$(grep -ac 'STARTUP_OBJECTS PASS' "$log")" -ne 1 ] \
    || [ "$(grep -ac 'STARTUP_OBJECTS DONE' "$log")" -ne 1 ] \
    || grep -aq 'STARTUP_OBJECTS FAIL' "$log"; then
    printf 'FAIL startup-objects: no clean completion receipt\n'
    cat "$log"
    exit 1
fi
# Every unit loaded before the first rows costs each launch; the probe's empty cache logs each one, pinned by name and bytes.
pinned=tests/startup-units.txt
grep -aq 'STARTUP_OBJECTS TOTAL' "$log" || { printf 'FAIL startup-objects: log %s has no STARTUP_OBJECTS TOTAL line to cut the units at\n' "$log"; exit 1; }
# Sample line: Error loading "file:///home/gm/flea/ui/Row.qml" from disk cache: <reason>, kept only before the TOTAL line since the probe's Quick Look and power-off legs follow it.
seen=$(sed -n '1,/STARTUP_OBJECTS TOTAL/p' "$log" | grep -aoE 'Error loading "file://[^"]*/ui/[^"]+" from disk cache' | sed -E 's|.*/ui/([^"]+)".*|\1|' | sort -u)
for cold in CardScroll.qml ContextMenu.qml IpcControls.qml LocalSendMark.qml MenuEdgeFade.qml MenuRow.qml TailscaleMark.qml js/ControlReader.js js/LockedMenu.js js/MenuFit.js js/MenuRefresh.js; do
    if printf '%s\n' "$seen" | grep -Fxq "$cold"; then
        printf 'FAIL startup-objects: demand-only unit %s loaded before the startup cut\n' "$cold"
        exit 1
    fi
done
for enabled in LangMark.qml LangMarkLoader.qml js/LangMarkPaths.js; do
    printf '%s\n' "$seen" | grep -Fxq "$enabled" || { printf 'FAIL startup-objects: default ON missed %s\n' "$enabled"; exit 1; }
done
bytes=0
while IFS= read -r unit; do bytes=$((bytes + $(wc -c < "ui/$unit"))); done <<< "$seen"
printf 'startup-objects: %s first-frame units, %s bytes\n' "$(printf '%s\n' "$seen" | grep -c .)" "$bytes"
listed=$(grep -vE '^(#|bytes )' "$pinned" | sort -u)
if [ "$seen" != "$listed" ]; then
    printf 'FAIL startup-objects: the first-frame units moved; added then dropped against %s:\n' "$pinned"
    comm -13 <(printf '%s\n' "$listed") <(printf '%s\n' "$seen") | sed 's/^/+ /'
    comm -23 <(printf '%s\n' "$listed") <(printf '%s\n' "$seen") | sed 's/^/- /'
    printf '%s\n' "$seen" | sed 's/^/startup-objects UNIT /'
    exit 1
fi
ceiling=$(sed -n 's/^bytes //p' "$pinned")
[[ "$ceiling" =~ ^[0-9]+$ ]] || { printf 'FAIL startup-objects: %s has no single numeric bytes line, got [%s]\n' "$pinned" "$ceiling"; exit 1; }
if [ "$bytes" -gt "$ceiling" ]; then
    printf 'FAIL startup-objects: the first-frame units hold %s bytes, over the %s pinned in %s\n' "$bytes" "$ceiling" "$pinned"
    exit 1
fi
# Keep the actual inventory visible on both Qt lanes even when an engine warning then rejects the run.
warnings=$(grep -aE 'TypeError|ReferenceError|ERROR|WARN' "$log" | grep -vF 'This plugin does not support setting window masks' || true)
if [ -n "$warnings" ]; then
    printf 'FAIL startup-objects: engine warnings\n%s\n' "$warnings"
    exit 1
fi
# Saved OFF keeps its measured object and unit budget independently of the new fresh default.
off_log="$test_root/off.log"
sandbox_scratch "$test_root/cache"
run_probe "$off_log" "$PWD/target/debug/flea" 0 "" off
status=$?
grep -a 'STARTUP_OBJECTS' "$off_log" || true
if { [ "$status" -ne 0 ] && [ "$status" -ne 143 ]; } \
    || ! grep -aq 'STARTUP_OBJECTS PASS' "$off_log" \
    || grep -aE 'STARTUP_OBJECTS FAIL|TypeError|ReferenceError|ERROR|WARN' "$off_log" | grep -vF 'This plugin does not support setting window masks'; then
    printf 'FAIL startup-objects: saved-OFF leg\n'; exit 1
fi
# Sample input: Error loading "file:///fixture/ui/Row.qml" from disk cache: <reason> yields Row.qml before TOTAL.
off_seen=$(sed -n '1,/STARTUP_OBJECTS TOTAL/p' "$off_log" | grep -aoE 'Error loading "file://[^"]*/ui/[^"]+" from disk cache' | sed -E 's|.*/ui/([^"]+)".*|\1|' | sort -u)
off_listed=$(grep -vE '^(#|bytes )' tests/startup-units-off.txt | sort -u)
[[ "$off_seen" == "$off_listed" ]] || { printf 'FAIL startup-objects: saved-OFF first-frame units moved\n'; exit 1; }
off_bytes=0
while IFS= read -r unit; do off_bytes=$((off_bytes + $(wc -c < "ui/$unit"))); done <<< "$off_seen"
off_ceiling=$(sed -n 's/^bytes //p' tests/startup-units-off.txt)
[[ "$off_ceiling" =~ ^[0-9]+$ && "$off_bytes" -le "$off_ceiling" ]] || { printf 'FAIL startup-objects: saved-OFF source bytes moved\n'; exit 1; }
# Sample input: DEBUG qml: STARTUP_OBJECTS TOTAL 590 yields 590 from the first receipt.
off_objects=$(awk '/STARTUP_OBJECTS TOTAL/ {print $NF; exit}' "$off_log")
printf 'STARTUP_OBJECTS OFF units=%s bytes=%s objects=%s language=0\n' "$(printf '%s\n' "$off_seen" | grep -c .)" "$off_bytes" "$off_objects"
if [[ -n "${FLEA_CI_SUITE_LOGS:-}" ]]; then cp "$off_log" "$FLEA_CI_SUITE_LOGS/startup-objects-off.log" || exit 1; fi
# A listing that never answers must still build the IPC seam once the pane turns "waiting".
printf '#!/bin/sh\nexec cat > /dev/null\n' > "$test_root/bin/flea-silent" && chmod +x "$test_root/bin/flea-silent" || exit 1
hang_log="$test_root/hang.log"
run_probe "$hang_log" "$test_root/bin/flea-silent" 1
status=$?
grep -a 'STARTUP_OBJECTS' "$hang_log" || true
if [ "$status" -ne 0 ] && [ "$status" -ne 143 ]; then
    printf 'FAIL startup-objects: hang leg qs exit %s\n' "$status"
    cat "$hang_log"
    exit 1
fi
if [ "$(grep -ac 'STARTUP_OBJECTS PASS' "$hang_log")" -ne 1 ] || grep -aq 'STARTUP_OBJECTS FAIL' "$hang_log"; then
    printf 'FAIL startup-objects: a listing that never answered built no IPC seam\n'
    cat "$hang_log"
    exit 1
fi
for early in cold warming; do
    early_log="$test_root/early-$early.log"
    run_probe "$early_log" "$PWD/target/debug/flea" 0 "$early"
    status=$?
    if { [ "$status" -ne 0 ] && [ "$status" -ne 143 ]; } \
        || ! grep -aq "STARTUP_OBJECTS PASS early-menu=$early ready=1 retained=1" "$early_log" \
        || grep -aqE 'STARTUP_OBJECTS FAIL|TypeError|ReferenceError|ERROR' "$early_log"; then
        printf 'FAIL startup-objects: early menu %s leg (qs exit %s)\n' "$early" "$status"
        grep -aE 'STARTUP_OBJECTS|TypeError|ReferenceError|ERROR' "$early_log"
        exit 1
    fi
    grep -aE 'STARTUP_OBJECTS (PASS|PARENT)' "$early_log"
done
printf 'startup-objects: 1 passed, 0 failed\n'
