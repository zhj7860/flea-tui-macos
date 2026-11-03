#!/bin/bash
. "$(dirname "$0")/headless-commons.sh"
# The slow-source counter gate on the real PreviewSwap, offscreen with no CPU limit so it runs in every lane.
set -u
cd "$(dirname "$0")/.." || exit 1

for tool in qs; do
    command -v "$tool" >/dev/null || { echo "slowsource-load.sh: $tool is not installed"; exit 1; }
done

. "$PWD/tools/flea-sandbox-guard"
sandbox_forbidden /tmp && sandbox_refuse "slowsource-load: /tmp is inside a forbidden test target"
load_root=$(mktemp -d /tmp/flea-slowsource-load.XXXXXXXX) || exit 1
FIXTURE_ROOT=$load_root
sandbox_root_ok
load_root=$SANDBOX_ROOT
readonly load_root
printf 'Flea slow-source load sandbox\n' > "$load_root/$SANDBOX_MARKER" || exit 1
load_work="$load_root/work"
readonly load_work
cleanup() {
    local result=$? leg
    trap - EXIT
    sandbox_remove "$load_work"
    # A failed run keeps its root, so the log path each FAIL line prints still points at a file.
    [ "$result" -ne 0 ] && exit "$result"
    for leg in fast slow starve; do sandbox_remove "$load_root/$leg.log"; done
    # The marker goes last, and only when nothing else is left: it is what stands between this directory and rm, so a root holding a stray entry keeps it.
    [ "$(ls -A "$load_root")" = "$SANDBOX_MARKER" ] || { printf 'slowsource-load: the load root %s holds more than its marker, so it was kept and the run fails.\n' "$load_root" >&2; exit 1; }
    sandbox_remove "$load_root/$SANDBOX_MARKER"
    rmdir "$load_root"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sandbox_scratch "$load_work"
mkdir -p "$load_work"/{config,home,runtime,tmp} || exit 1
chmod 700 "$load_work/runtime" || exit 1
ln -s "$PWD/tests/slowsource-load.qml" "$load_work/config/shell.qml" || exit 1
headless_commons "$load_work" || exit 1
ln -s /usr/share/omarchy/shell/Ui "$load_work/config/Ui" || exit 1

pass=0
fail=0
ok()  { printf 'ok   %s\n' "$*"; pass=$((pass+1)); }
bad() { printf 'FAIL %s\n' "$*"; fail=$((fail+1)); }

# Sample input, one probe line: '  DEBUG qml: SLOWSOURCE DONE leg=slow fallbacks=1 shownMs=116'.
run_leg() {
    local leg="$1" out log status done why
    out="$load_work/out-$leg"
    log="$load_root/$leg.log"
    mkdir -p "$out" || exit 1
    ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$load_work/home" XDG_RUNTIME_DIR="$load_work/runtime" TMPDIR="$load_work/tmp" \
        XDG_CONFIG_HOME="$load_work/home/.config" XDG_STATE_HOME="$load_work/home/.local/state" \
        XDG_CACHE_HOME="$load_work/home/.cache" \
        QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=16 \
        QT_FORCE_STDERR_LOGGING=1 \
        SLOWSOURCE_UI="${SLOWSOURCE_UI:-$PWD/ui}" SLOWSOURCE_LEG="$leg" \
        timeout 90 qs -p "$load_work/config" > "$log" 2>&1; exit $? ) 2>/dev/null
    status=$?
    if grep -q 'SLOWSOURCE FAIL' "$log" || ! grep -q "SLOWSOURCE DONE leg=$leg" "$log"; then
        why=$(grep -a 'SLOWSOURCE FAIL' "$log" | head -1)
        bad "$leg: ${why:-the harness did not finish (qs exit $status)} (log $log)"
        return
    fi
    done=$(grep -a "SLOWSOURCE DONE leg=$leg" "$log" | tail -1)
    printf '  %s: %s\n' "$leg" "$done"
    if [ "$leg" = slow ]; then
        [[ "$done" =~ fallbacks=1 ]] || { bad "$leg: the slow source did not fall back exactly once (log $log)"; return; }
    else
        [[ "$done" =~ fallbacks=0 ]] || { bad "$leg: a fast decode fell back (log $log)"; return; }
    fi
    ok "$leg: counters as asserted"
}

run_leg fast
run_leg slow
run_leg starve

printf 'slowsource-load: %s check(s), %s failed\n' "$((pass + fail))" "$fail"
[ "$fail" -eq 0 ]
