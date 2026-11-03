#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# A slow network source draws its loading state on the first frame after the Timer that owns it fires: Enter on a folder whose listing is held, and Space on a file whose content is held or never lands, with the backend proxy reporting the NAS storage class.
set -uo pipefail
. "$(dirname "$0")/../tools/flea-sandbox-guard"
. "$(dirname "$0")/qslog-gate.sh"
cd "$(dirname "$0")/.." || exit 1
for tool in qs dbus-run-session ffmpeg python3 mkfifo strace; do
    command -v "$tool" >/dev/null || { printf 'FAIL slowsource-nas: %s is required\n' "$tool"; exit 1; }
done
test_root="$FIXTURE_ROOT/flea-slowsource-nas-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
mkdir -p "$test_root"/{config,fixture/start/sub,fixture/look} || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -m ui/boot/Ui)" "$test_root/config/Ui" || exit 1
ln -s "$test_root/config/flea/boot/fleatab.qml" "$test_root/config/fleatab.qml" || exit 1
cp -a ui "$test_root/config/flea" || exit 1
cp tests/slowsource-nas.qml "$test_root/config/shell.qml" || exit 1
# Enter: the folder the launch rests on, then the folder Return opens (its listing is the one held).
for n in 1 2 3 4 5 6; do printf 'file %s\n' "$n" > "$test_root/fixture/start/sub/f$n.txt"; done
printf 'a note\n' > "$test_root/fixture/start/z-after.txt"
# Space: one file of each kind Quick Look opens, plus one each of txt, md and jpg whose content never lands: the jpg is a named pipe (the image loader blocks opening it); the txt and md are plain files whose open strace holds (a named pipe row there is refused at once as unpreviewable).
look="$test_root/fixture/look"
seq -f 'line %g of the notes' 40 > "$look/b-notes.txt" || exit 1
printf '# Title\n\nA paragraph of the readme.\n\n- one\n- two\n' > "$look/c-readme.md" || exit 1
ffmpeg -y -f lavfi -i "testsrc=size=320x240" -frames:v 1 "$look/d-pic.jpg" >/dev/null 2>&1 \
    || { printf 'FAIL slowsource-nas: ffmpeg could not make d-pic.jpg\n'; exit 1; }
python3 -I tests/quicklook-hold-pdf.py "$look/d-pic.jpg" "$look/e-doc.pdf" \
    || { printf 'FAIL slowsource-nas: could not make e-doc.pdf\n'; exit 1; }
ffmpeg -y -f lavfi -i "testsrc=size=160x120:rate=10" -t 1 -pix_fmt yuv420p "$look/i-clip.mp4" >/dev/null 2>&1 \
    || { printf 'FAIL slowsource-nas: ffmpeg could not make i-clip.mp4\n'; exit 1; }
mkfifo "$look/h-never.jpg" || exit 1
printf 'never read\n' > "$look/f-never.txt" || exit 1
printf '# Never\n' > "$look/g-never.md" || exit 1
# Sample input, one request line: {"c":"list","path":"/x/start/sub",...} is held when NAS_PROXY_SUB is "/start/sub" and NAS_PROXY_CMD is "list".
cat > "$test_root/flea-proxy" <<'EOS'
#!/usr/bin/env python3
# Forwards a backend session to the real binary, rewrites the fsinfo line's storage class and holds the requests of one command.
import os, subprocess, sys, threading
real = os.environ["NAS_PROXY_REAL"]
if sys.argv[1:] != ["--backend"]:
    os.execv(real, [real] + sys.argv[1:])
klass = os.environ.get("NAS_PROXY_CLASS")
hold = float(os.environ.get("NAS_PROXY_HOLD_MS", "0")) / 1000.0
cmd = os.environ.get("NAS_PROXY_CMD", "")
sub = os.environ.get("NAS_PROXY_SUB", "")
child = subprocess.Popen([real, "--backend"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=sys.stderr, text=True, bufsize=1)
send = threading.Lock()
def pump():
    for line in child.stdout:
        if klass is not None and '"t":"fsinfo"' in line:
            head, _, tail = line.partition('"class":"')
            if tail:
                _, _, rest = tail.partition('"')
                line = head + '"class":"' + klass + '"' + rest
        sys.stdout.write(line)
        sys.stdout.flush()
threading.Thread(target=pump, daemon=True).start()
def forward(line):
    with send:
        try:
            child.stdin.write(line)
            child.stdin.flush()
        except (BrokenPipeError, ValueError):
            pass
for line in sys.stdin:
    if hold > 0 and cmd and ('"c":"%s"' % cmd) in line and sub in line:
        timer = threading.Timer(hold, forward, [line])
        timer.daemon = True
        timer.start()
        continue
    forward(line)
child.stdin.close()
EOS
chmod +x "$test_root/flea-proxy" || exit 1
# The GUI thread's file calls (no -f: the main thread is the GUI thread and the only one traced), so the audit reads what the Enter and Space turns touch on the browsed folder rather than what the code suggests.
strace_prefix="strace -ttt -y -qq -s 96 -o @@LOG@@ -e trace=%file,read,pread64,readv,getdents64"
failures=0
legs=0
# run_leg LEG DIR TOTAL TARGET CLASS HOLDMS PROXYCMD PROXYSUB [OPENHOLD]: one fresh qs process (a leg named enter-net-nohold audits every call on the fixture, not only reads); the proxy holds PROXYCMD requests naming PROXYSUB for HOLDMS and reports CLASS (empty reports local); OPENHOLD "open" holds every open of the target file instead (a slow mount's first read), HOLDMS capped at 8000, and takes the place of the GUI-thread audit.
run_leg() {
    local leg=$1 dir=$2 total=$3 target=$4 class=$5 hold=$6 cmd=$7 sub=$8 openhold=${9:-}
    local leg_root="$test_root/$leg" log="$test_root/$leg/run.log" status fifo="$test_root/fixture/$2/$4" releaser=''
    local tracer="$strace_prefix" file="$test_root/fixture/$dir/$target"
    if [ "$openhold" = open ]; then
        tracer="strace -f --seccomp-bpf -qq -o @@LOG@@ -P $file -P $(readlink -f "$file") -e trace=openat -e inject=openat:delay_enter=$((hold > 8000 ? 8000 : hold))ms"
    fi
    mkdir -p "$leg_root"/{home,state/flea,cache,runtime} || exit 1
    chmod 700 "$leg_root/runtime" || exit 1
    printf '{}\n' > "$leg_root/state/flea/ui.json"
    # A named pipe the image loader is blocked on keeps qs from exiting: once the probe is done, open and close its write end so the reader sees an empty file.
    if [ -p "$fifo" ]; then
        ( until grep -aq 'NASPROBE DONE' "$log" 2>/dev/null; do sleep 0.3; done; timeout 10 bash -c ': > "$0"' "$fifo" ) &
        releaser=$!
    fi
    ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u QML_DISABLE_DISK_CACHE \
        HOME="$leg_root/home" XDG_STATE_HOME="$leg_root/state" XDG_CACHE_HOME="$leg_root/cache" \
        XDG_RUNTIME_DIR="$leg_root/runtime" FLEA_BIN="$test_root/flea-proxy" NAS_PROXY_REAL="${NAS_BIN:-$PWD/target/debug/flea}" FLEA_PATH="$test_root/fixture/$dir" \
        NAS_PROXY_CLASS="$class" NAS_PROXY_HOLD_MS="$hold" NAS_PROXY_CMD="$cmd" NAS_PROXY_SUB="$sub" \
        NAS_UI="$test_root/config/flea" NAS_LEG="$leg" NAS_TOTAL="$total" NAS_TARGET="$target" NAS_HOLD_MS="$hold" NAS_CLASS="$class" \
        QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
        dbus-run-session -- bash -c 'timeout 120 ${3/@@LOG@@/$4} qs -p "$1" > "$2" 2>&1' _ "$test_root/config" "$log" "$tracer" "$leg_root/strace.log" 2> "$leg_root/bus.log" ) 2>/dev/null
    status=$?
    [ -z "$releaser" ] || kill "$releaser" 2>/dev/null
    legs=$((legs + 1))
    [ -z "${FLEA_CI_SUITE_LOGS:-}" ] || cp "$log" "$FLEA_CI_SUITE_LOGS/slowsource-nas-$leg.log" 2>/dev/null
    # Sample input, one probe line: "  INFO qml: NASPROBE ENTER hold=400 cap=1 capFrame=4 markFrame=5 markDelta=1 timer=swap-cap keyToCapMs=70 keyToMarkMs=82 landMs=401 shownMs=332".
    grep -a 'NASPROBE \(STORAGE\|ENTER\|LOOK\|WINDOW\|FAIL\|DONE\)' "$log" | sed 's/\x1b\[[0-9;]*m//g; s/^.*NASPROBE /NASPROBE /' | sed "s/^/$leg: /"
    [ "$openhold" = open ] || AUDIT_ALL=$([ "$leg" = enter-net-nohold ] && echo 1) audit_leg "$leg" "$log" "$leg_root/strace.log" "$test_root/fixture"
    if ! qslog_crash "slowsource-nas $leg" "$log"; then
        failures=$((failures + 1))
    fi
    if [ "$status" -ne 0 ] || [ "$(grep -ac 'NASPROBE DONE' "$log")" -ne 1 ] || grep -aqE 'NASPROBE FAIL|TypeError|ReferenceError|Binding loop detected' "$log"; then
        printf 'FAIL slowsource-nas: %s leg did not hold (qs exit %s)\n' "$leg" "$status"
        grep -aE 'TypeError|ReferenceError|Binding loop detected' "$log" | head -3
        failures=$((failures + 1))
    fi
}
# audit_leg LEG LOG STRACE FIXTURE: the GUI thread (the qs process itself, the only one traced) makes no read of the browsed folder between the key and the end of the leg; its path calls are listed.
# Sample input, one strace line: "1760000000.123456 read(21</x/fixture/look/b-notes.txt>, ..., 4096) = 4096" inside the window is a FAIL; with AUDIT_ALL set so is every other traced call on the fixture (statx, openat, access, readlink, ...).
audit_leg() {
    local leg=$1 log=$2 trace=$3 fixture=$4 window out
    window=$(sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -a 'NASPROBE WINDOW' | tail -1 | sed 's/.*from=\([0-9]*\) to=\([0-9]*\).*/\1 \2/')
    [ -n "$window" ] || { printf 'FAIL slowsource-nas: %s leg printed no NASPROBE WINDOW line, so its audit checked nothing\n' "$leg"; failures=$((failures + 1)); return; }
    [ -s "$trace" ] || { printf 'FAIL slowsource-nas: %s leg has no strace record, so a silent audit proves nothing\n' "$leg"; failures=$((failures + 1)); return; }
    out=$(python3 -I - "$trace" "$fixture" $window <<'EOP'
import os, re, sys
trace, fixture, t0, t1 = sys.argv[1], sys.argv[2], int(sys.argv[3]) / 1000.0, int(sys.argv[4]) / 1000.0
line = re.compile(r"^(\d+\.\d+)\s+(\w+)\((.*)$")
reads, paths, window = [], {}, []
for raw in open(trace, errors="replace"):
    m = line.match(raw)
    if not m:
        continue
    ts, call, rest = float(m.group(1)), m.group(2), m.group(3)
    if not (t0 <= ts <= t1):
        continue
    window.append("%.1f %s(%s" % ((ts - t0) * 1000, call, rest.rstrip()[:200]))
    if fixture not in rest:
        continue
    where = re.search(re.escape(fixture) + r"[^\s>,\"]*", rest)
    key = call + " " + (where.group(0).replace(fixture, "") if where else "")
    paths[key] = paths.get(key, 0) + 1
    if call in ("read", "pread64", "readv", "getdents64") or os.environ.get("AUDIT_ALL"):
        reads.append(key)
dest = os.environ.get("FLEA_CI_SUITE_LOGS")
if dest:
    open(os.path.join(dest, "slowsource-nas-" + os.path.basename(os.path.dirname(trace)) + ".strace"), "w").write("\n".join(window[:400]) + "\n")
print("reads=%d all=%d" % (len(reads), len(window)))
for key in sorted(paths):
    print("  %s x%d" % (key, paths[key]))
EOP
)
    printf '%s: AUDIT GUI-thread calls on the browsed folder: %s\n' "$leg" "$(printf '%s\n' "$out" | tr '\n' ';')"
    if ! printf '%s\n' "$out" | head -1 | grep -q '^reads=0 '; then
        printf 'FAIL slowsource-nas: %s leg read the browsed folder on the GUI thread between the key and the end\n' "$leg"
        failures=$((failures + 1))
    fi
}
here="$test_root/fixture"
run_leg enter-net start 2 "$here/start/sub" network 400 list /start/sub
run_leg enter-local start 2 "$here/start/sub" "" 400 list /start/sub
run_leg enter-net-100 start 2 "$here/start/sub" network 100 list /start/sub
run_leg enter-net-40 start 2 "$here/start/sub" network 40 list /start/sub
run_leg enter-net-nohold start 2 "$here/start/sub" network 0 "" ""
run_leg look-txt look 8 b-notes.txt network 0 "" ""
run_leg look-md look 8 c-readme.md network 0 "" ""
run_leg look-jpg look 8 d-pic.jpg network 0 "" ""
run_leg look-video look 8 i-clip.mp4 network 0 "" ""
run_leg look-pdf look 8 e-doc.pdf network 0 "" ""
run_leg look-pdf-slow look 8 e-doc.pdf network 400 pdfcopy ""
run_leg look-pdf-never look 8 e-doc.pdf network 600000 pdfcopy ""
run_leg look-txt-slow look 8 b-notes.txt network 400 "" "" open
run_leg look-md-slow look 8 c-readme.md network 400 "" "" open
run_leg look-txt-never look 8 f-never.txt network 600000 "" "" open
run_leg look-md-never look 8 g-never.md network 600000 "" "" open
run_leg look-jpg-never look 8 h-never.jpg network 600000 "" ""
printf 'slowsource-nas: %s legs, %s failed\n' "$legs" "$failures"
[ "$failures" -eq 0 ]
