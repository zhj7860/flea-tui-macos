#!/usr/bin/env bash
# The Grid rename editor proof of 0.3.7, driven headless through its node driver.
set -u
cd "$(dirname "$0")/.." || exit 1
. "$PWD/tools/flea-sandbox-guard"
# A private D-Bus session for the offscreen run; the driver execs qml6, never qs.
command -v dbus-run-session >/dev/null || { echo 'FAIL rename-grid-bottom needs a private D-Bus session'; exit 1; }
# The driver itself needs these; each names what is missing.
command -v qml6 >/dev/null || { echo 'FAIL rename-grid-bottom needs qml6'; exit 1; }
command -v node >/dev/null || { echo 'FAIL rename-grid-bottom needs node'; exit 1; }
command -v timeout >/dev/null || { echo 'FAIL rename-grid-bottom needs timeout'; exit 1; }
command -v ffmpeg >/dev/null || { echo 'FAIL rename-grid-bottom needs ffmpeg'; exit 1; }
sandbox_root_ok
probe=$(mktemp -d "$SANDBOX_ROOT/flea-rename-grid-bottom.XXXXXX") || exit 1
: > "$probe/$SANDBOX_MARKER" || exit 1
driver_pid=""
stop_driver() {
    [[ -n "$driver_pid" ]] || return 0
    local tick
    kill -TERM -- "-$driver_pid" 2>/dev/null || true
    for ((tick = 0; tick < 20; tick++)); do
        kill -0 -- "-$driver_pid" 2>/dev/null || break
        sleep 0.1
    done
    if kill -0 -- "-$driver_pid" 2>/dev/null; then
        kill -KILL -- "-$driver_pid" 2>/dev/null || true
        for ((tick = 0; tick < 20; tick++)); do
            kill -0 -- "-$driver_pid" 2>/dev/null || break
            sleep 0.1
        done
    fi
    wait "$driver_pid" 2>/dev/null || true
    if kill -0 -- "-$driver_pid" 2>/dev/null; then
        printf 'FAIL rename-grid-bottom owned process group %s survived teardown\n' "$driver_pid"
        return 1
    fi
    driver_pid=""
}
cleanup() { stop_driver || return 1; sandbox_remove "$probe"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
log="$probe/driver.log"
# Offscreen private session, owned process group, so teardown kills qml6 too.
env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u FLEA_SELECT \
    FLEA_RENAME_GRID_ROOT="$probe" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic \
    QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 setsid dbus-run-session -- node tests/rename-grid-bottom.js >"$log" 2>&1 </dev/null &
driver_pid=$!
# Seven qml6 cases at 15s each, polled every 0.1 s for at most three minutes; the driver exits on its own, so a red run ends at once.
receipt_ticks=1800
for ((tick = 0; tick < receipt_ticks; tick++)); do
    grep -aq 'rename-grid-bottom: .* 0 failed' "$log" && break
    kill -0 "$driver_pid" 2>/dev/null || break
    sleep 0.1
done
stop_driver || exit 1
printf 'rename-grid-bottom: owned process group gone\n'
grep -aE 'rename-grid-bottom|RENAME_GRID_BOTTOM|TypeError|ReferenceError|ERROR|Cannot assign' "$log"
tally=$(grep -ao 'rename-grid-bottom: .* 0 failed' "$log" | tail -1)
[[ -n "$tally" ]] || { printf 'FAIL rename-grid-bottom produced no completion receipt; log tail:\n'; tail -20 "$log"; exit 1; }
[[ "$tally" == *' 0 failed' ]] || exit 1
if grep -aqE 'TypeError|ReferenceError|ERROR|Cannot assign' "$log"; then
    echo 'FAIL rename-grid-bottom logged an engine error beside its receipt'
    exit 1
fi
