#!/bin/bash
. "$(dirname "$0")/headless-commons.sh"
# Column moves under the preview hold, offscreen on the threaded and basic loops: frames per key and a whole release frame.
set -u
cd "$(dirname "$0")/.." || exit 1

pass=0
fail=0
ok()  { printf 'ok   %s\n' "$*"; pass=$((pass+1)); }
bad() { printf 'FAIL %s\n' "$*"; fail=$((fail+1)); }

command -v qs >/dev/null || { echo "preview-holdframes.sh: qs is not installed"; exit 1; }

. "$PWD/tools/flea-sandbox-guard"
sandbox_forbidden /tmp && sandbox_refuse "preview-holdframes: /tmp is inside a forbidden test target"
hf_root=$(mktemp -d /tmp/flea-preview-holdframes.XXXXXXXX) || exit 1
FIXTURE_ROOT=$hf_root
sandbox_root_ok
hf_root=$SANDBOX_ROOT
readonly hf_root
printf 'Flea preview holdframes sandbox\n' > "$hf_root/$SANDBOX_MARKER" || exit 1
hf_work="$hf_root/work"
readonly hf_work
cleanup() {
    local result=$?
    trap - EXIT
    sandbox_remove "$hf_work"
    # The fixture root is never a sandbox_remove target, so its marker and logs go by name.
    case $hf_root in /tmp/flea-preview-holdframes.?*) rm -f -- "$hf_root/$SANDBOX_MARKER" "$hf_root"/holdframes-*.log; rmdir -- "$hf_root" ;; esac
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sandbox_scratch "$hf_work"
mkdir -p "$hf_work"/{config,home,runtime,tmp} "$hf_work"/out-{threaded,basic} || exit 1
chmod 700 "$hf_work/runtime" || exit 1
ln -s "$PWD/tests/preview-holdframes.qml" "$hf_work/config/shell.qml" || exit 1
headless_commons "$hf_work" || exit 1
ln -s /usr/share/omarchy/shell/Ui "$hf_work/config/Ui" || exit 1

ui=${PREVIEW_HOLDFRAMES_UI:-$PWD/ui}
# Zero idle time starts a queued repaint at once, as vsync does; the subshell hides the harness kill's notice.
run_leg() {
    local loop=$1
    log="$hf_root/holdframes-$loop.log"
    out="$hf_work/out-$loop"
    ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$hf_work/home" XDG_RUNTIME_DIR="$hf_work/runtime" TMPDIR="$hf_work/tmp" \
        XDG_CONFIG_HOME="$hf_work/home/.config" XDG_STATE_HOME="$hf_work/home/.local/state" \
        XDG_CACHE_HOME="$hf_work/home/.cache" \
        QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QSG_RENDER_LOOP="$loop" \
        QT_QPA_UPDATE_IDLE_TIME=0 QT_FORCE_STDERR_LOGGING=1 \
        PREVIEW_HOLDFRAMES_UI="$ui" PREVIEW_HOLDFRAMES_OUT="$out" \
        timeout 90 qs -p "$hf_work/config" > "$log" 2>&1; exit $? ) 2>/dev/null
    status=$?
    warnings=$(grep -aE 'TypeError|ReferenceError|Cannot|is not a type|failed to load|crashed' "$log" || true)
    done=$(grep -a 'HOLDFRAMES DONE' "$log" | tail -1)
    if grep -q 'HOLDFRAMES FAIL' "$log" || [ -z "$done" ] || ! grep -q 'HOLDFRAMES GRAB' "$log" || [ -n "$warnings" ]; then
        bad "the $loop leg did not finish cleanly (qs exit $status)"
        cat "$log"
        return 1
    fi
    printf '  %s: %s\n' "$loop" "${done#*HOLDFRAMES }"
}
field() { printf '%s' "$done" | sed -n "s/.* $1=\([0-9]*\).*/\1/p"; }

# Sample input: '... KEY 5 capture=1 held=3 free=1 whole=1'; keys 1 and 2 warm up and are not judged.
judge_keys() {
    local line k v n=0
    while IFS= read -r line; do
        k=${line#*KEY }; k=${k%% *}
        [[ $line =~ (^|\ )$1=([0-9]+) ]] && v=${BASH_REMATCH[2]} || v=
        [ "$k" -gt 2 ] && [ "$v" != 1 ] && n=$((n + 1))
    done < <(grep -a 'HOLDFRAMES KEY' "$log")
    echo "$n"
}

# Both legs: every release frame whole, every hold landed, and the settled window shows the last preview.
judge_common() {
    local loop=$1
    if [ "$(field broken)" = 0 ]; then ok "$loop: every release frame drew the new preview whole";
    else bad "$loop: $(field broken) release frame(s) were not whole"; fi
    if [ "$(field holds)" = 14 ] && [ "$(field fallbacks)" = 0 ] && [ "$(field mid)" = 0 ]; then
        ok "$loop: 14 holds, none fell back, no half-built frame"
    else bad "$loop: holds=$(field holds) fallbacks=$(field fallbacks) mid=$(field mid), want 14, 0 and 0"; fi
    if [ "$(field letgo)" = 14 ] && [ "$(field kept)" = 0 ]; then ok "$loop: every release let go of the layer's source";
    else bad "$loop: letgo=$(field letgo) kept=$(field kept), want 14 and 0"; fi
    # The settled window: a P6 PPM; the bottom-left of the preview is the last preview's ground, #2a3a4a.
    px=$(python3 -c '
import sys
d = open(sys.argv[1], "rb").read()
parts = d.split(maxsplit=4)
w = int(parts[1]); body = parts[4]
o = (875 * w + 325) * 3
print("%02x%02x%02x" % tuple(body[o:o + 3]))' "$out/settled.ppm" 2>/dev/null)
    if [ "$px" = 2a3a4a ]; then ok "$loop: the settled window shows the last preview";
    else bad "$loop: the settled window shows #${px:-nothing} where the last preview's ground #2a3a4a belongs"; fi
}

if run_leg threaded; then
    grep -a 'HOLDFRAMES KEY' "$log" | sed 's/.*HOLDFRAMES /    /'
    late=$(judge_keys capture)
    if [ "$late" -eq 0 ]; then ok "threaded: every judged key changed the preview in the first frame after the key frame";
    else bad "threaded: $late judged key(s) drew a frame with only the picture's repaint before the change"; fi
    extra=$(judge_keys free)
    if [ "$extra" -eq 0 ]; then ok "threaded: every judged key drew one frame after the release and no more";
    else bad "threaded: $extra judged key(s) drew a frame after the release frame"; fi
    judge_common threaded
fi

if run_leg basic; then
    if [ "$(field inframe)" = 0 ]; then ok "basic: no change ran between a frame's sync and its render";
    else bad "basic: $(field inframe) change(s) ran between a frame's sync and its render"; fi
    judge_common basic
fi

printf 'preview-holdframes: %s check(s), %s failed\n' "$((pass + fail))" "$fail"
[ "$fail" -eq 0 ]
