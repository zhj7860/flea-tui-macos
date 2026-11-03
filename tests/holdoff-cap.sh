#!/bin/bash
. "$(dirname "$0")/headless-commons.sh"
# A PDF page render shows its loading state at Swap.CAP_MS and keeps it Swap.MIN_SHOW_MS, as the listing does; offscreen, counts and Timer intervals only.
set -u
cd "$(dirname "$0")/.." || exit 1

pass=0
fail=0
ok()  { printf 'ok   %s\n' "$*"; pass=$((pass+1)); }
bad() { printf 'FAIL %s\n' "$*"; fail=$((fail+1)); }

for tool in qs python3; do
    command -v "$tool" >/dev/null || { echo "holdoff-cap.sh: $tool is not installed"; exit 1; }
done

. "$PWD/tools/flea-sandbox-guard"
sandbox_forbidden /tmp && sandbox_refuse "holdoff-cap: /tmp is inside a forbidden test target"
cap_root=$(mktemp -d /tmp/flea-holdoff-cap.XXXXXXXX) || exit 1
FIXTURE_ROOT=$cap_root
sandbox_root_ok
cap_root=$SANDBOX_ROOT
readonly cap_root
printf 'Flea hold-off cap sandbox\n' > "$cap_root/$SANDBOX_MARKER" || exit 1
cap_work="$cap_root/work"
readonly cap_work
cleanup() {
    local result=$?
    trap - EXIT
    # sandbox_remove verifies an absolute, non-empty path contained in this run's marked root before rm.
    sandbox_remove "$cap_work"
    # A failed run keeps its root, so the log path each FAIL line prints still points at a file.
    [ "$result" -ne 0 ] && exit "$result"
    # The marker goes last, because it is what stands between this directory and rm.
    sandbox_remove "$cap_root/cap.log"
    sandbox_remove "$cap_root/$SANDBOX_MARKER"
    [ -z "$(ls -A "$cap_root")" ] && rmdir "$cap_root"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sandbox_scratch "$cap_work"
mkdir -p "$cap_work"/{config,home,runtime,tmp} || exit 1
chmod 700 "$cap_work/runtime" || exit 1
ln -s "$PWD/tests/holdoff-cap.qml" "$cap_work/config/shell.qml" || exit 1
ln -s "$PWD/ui" "$cap_work/config/flea" || exit 1
headless_commons "$cap_work" || exit 1
ln -s /usr/share/omarchy/shell/Ui "$cap_work/config/Ui" || exit 1

# Four light pages, and a light page followed by one of 600000 filled rectangles, which renders far past the cap.
python3 -I - "$cap_work" <<'PY' || { echo "holdoff-cap.sh: fixture generation failed"; exit 1; }
import random, sys

def pdf(path, counts):
    objs = ["<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [%s] /Count %d >>" % (" ".join("%d 0 R" % (3 + 2 * i) for i in range(len(counts))), len(counts))]
    for i, count in enumerate(counts):
        random.seed(i + 7)
        ops = []
        for _ in range(count):
            x, y = random.uniform(0, 580), random.uniform(0, 760)
            w, h = random.uniform(5, 40), random.uniform(5, 40)
            ops.append("%.2f %.2f %.2f rg %.1f %.1f %.1f %.1f re f" % (random.random(), random.random(), random.random(), x, y, w, h))
        stream = "\n".join(ops)
        objs.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents %d 0 R >>" % (4 + 2 * i))
        objs.append("<< /Length %d >>\nstream\n%s\nendstream" % (len(stream), stream))
    out = "%PDF-1.4\n"
    offsets = []
    for i, body in enumerate(objs):
        offsets.append(len(out))
        out += "%d 0 obj\n%s\nendobj\n" % (i + 1, body)
    table = len(out)
    out += "xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
    for offset in offsets:
        out += "%010d 00000 n \n" % offset
    out += "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, table)
    with open(path, "w") as handle:
        handle.write(out)

pdf(sys.argv[1] + "/light.pdf", [10, 10, 10, 10])
pdf(sys.argv[1] + "/heavy.pdf", [10, 600000])
PY

log="$cap_root/cap.log"
# Software rendering offscreen; the harness ends itself with a kill, so the subshell keeps bash's "Terminated" notice out of the report.
( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$cap_work/home" XDG_RUNTIME_DIR="$cap_work/runtime" TMPDIR="$cap_work/tmp" \
    XDG_CONFIG_HOME="$cap_work/home/.config" XDG_STATE_HOME="$cap_work/home/.local/state" \
    XDG_CACHE_HOME="$cap_work/home/.cache" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 \
    QT_FORCE_STDERR_LOGGING=1 \
    HOLDOFF_LIGHT="$cap_work/light.pdf" HOLDOFF_HEAVY="$cap_work/heavy.pdf" \
    timeout 60 qs -p "$cap_work/config" > "$log" 2>&1; exit $? ) 2>/dev/null
status=$?

# Sample input, one probe line: '  DEBUG qml: HOLDOFF ok the render cap Timer reads Swap.CAP_MS'.
if ! grep -aq 'HOLDOFF DONE' "$log" && ! grep -aq 'HOLDOFF FAIL' "$log"; then
    bad "the harness did not finish (qs exit $status): $(grep -a -m1 -e 'ERROR' -e 'is not installed' "$log") (log $log)"
else
    skipped=0
    while IFS= read -r line; do
        case "$line" in
        *"HOLDOFF ok "*) ok "${line#*HOLDOFF ok }" ;;
        *"HOLDOFF FAIL "*) bad "${line#*HOLDOFF FAIL } (log $log)" ;;
        *"HOLDOFF SKIP "*)
            printf 'skip %s\n' "${line#*HOLDOFF SKIP }"
            # Sample input: 'HOLDOFF SKIP 3 a light page took 80 ms', the checks that skip left out.
            count=${line#*HOLDOFF SKIP }
            count=${count%% *}
            [[ "$count" =~ ^[0-9]+$ ]] && skipped=$((skipped + count)) ;;
        esac
    done < <(grep -a 'HOLDOFF ' "$log")
    # Twelve checks make the suite and only a logged SKIP lowers that, by the checks it left out: a check that did not report did not run.
    if [ "$pass" -lt $((12 - skipped)) ] && ! grep -aq 'HOLDOFF FAIL' "$log"; then
        bad "only $pass check(s) reported, want $((12 - skipped)) (log $log)"
    fi
fi

printf 'holdoff-cap: %s check(s), %s failed\n' "$((pass + fail))" "$fail"
[ "$fail" -eq 0 ]
