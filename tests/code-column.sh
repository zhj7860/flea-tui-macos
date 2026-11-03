#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# The Columns preview column over the real backend and bat: code in the theme's inks, the binary, too large and long-line frames, no plain frame before the coloured one, plain lines without bat, markup drawn as text. Offscreen, in the flea-ci image.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

for tool in qs bat bwrap prlimit python3; do
    command -v "$tool" >/dev/null || { echo "code-column.sh: $tool is not on PATH; this suite runs in the flea-ci image"; exit 1; }
done
bin=${FLEA_BIN:-$PWD/target/debug/flea}
[ -x "$bin" ] || { echo "code-column.sh: build the backend first: $bin"; exit 1; }
qs_bin=$(command -v qs)
# Both are resolved here: the second run's PATH holds only the jail tools, and env looks timeout up on it.
timeout_bin=$(command -v timeout)
# The deadline for one run of the harness, in seconds.
RUN_BOUND=120

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-code-column-XXXXXX") || exit 1
case $test_root in
  /*/*) ;;
  *) echo "FAIL: mktemp -d gave '$test_root', which is not an absolute path two components deep"; exit 1 ;;
esac
: > "$test_root/$SANDBOX_MARKER" || exit 1
listener=""
cleanup() {
    [ -n "$listener" ] && kill "$listener" 2>/dev/null
    sandbox_remove "$test_root"
}
trap cleanup EXIT

fixture="$test_root/fixture"
mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" "$test_root/nobat" "$fixture" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/code-column.qml "$test_root/config/shell.qml" || exit 1
# The jail tools and nothing else: bat is not on this PATH, so the backend answers plain.
ln -s "$(command -v bwrap)" "$test_root/nobat/bwrap" || exit 1
ln -s "$(command -v prlimit)" "$test_root/nobat/prlimit" || exit 1

# Sorted by name the files are: a Markdown note (text that is not code), two Rust files, a binary, a file over 1 MiB, long lines, markup.
printf '# Notes\n\nplain words, no code\n' > "$fixture/00-notes.md"
for i in $(seq 1 132); do printf 'fn f%d() { let s = "x"; }\n' "$i"; done > "$fixture/01-icons.rs"
for i in $(seq 1 132); do printf 'fn g%d() { let s = "y"; }\n' "$i"; done > "$fixture/02-more.rs"
printf 'text\0text\n' > "$fixture/03-nul.txt"
yes 'a log line' | head -c 1048577 > "$fixture/04-over.log"
for i in 1 2 3 4; do printf 'fn long() { let s = "'; head -c 6000 /dev/zero | tr '\0' x; printf '\n'; done > "$fixture/05-long.rs"

# Anything that connects to the listener is logged, and a connection made here at the end proves it could have seen one. The lane may not bind port 9, so the listener takes a free port and the markup names it.
python3 -I -c '
import socket, sys
s = socket.socket()
s.bind(("127.0.0.1", 0))
s.listen(8)
s.settimeout(0.2)
log = open(sys.argv[1], "a", buffering=1)
log.write("listening %d\n" % s.getsockname()[1])
while True:
    try:
        c, _ = s.accept()
        log.write("connection\n")
        c.close()
    except socket.timeout:
        pass
' "$test_root/listener.log" 2>"$test_root/listener.err" &
listener=$!
for _ in $(seq 1 50); do grep -q listening "$test_root/listener.log" 2>/dev/null && break; sleep 0.1; done
verdict=0
# Sample input: "listening 41233".
port=$(sed -n 's/^listening //p' "$test_root/listener.log" 2>/dev/null)
if [ -z "$port" ]; then
    printf 'FAIL the listener did not start, so a markup fetch could not be seen\n'
    cat "$test_root/listener.err"
    exit 1
fi
img="<img src=\"http://127.0.0.1:$port/x\">"
# XML keeps this literal-markup test on CodeLines now that HTML renders a page.
printf '%s\n' "$img" > "$fixture/06-img.xml"

# $1 is the run's name, $2 its PATH, $3 whether bat is withheld.
run_harness() {
    local name=$1 path=$2 nobat=$3 log="$test_root/$1.log" status
    env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        PATH="$path" HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
        XDG_CONFIG_HOME="$test_root/home/.config" XDG_CACHE_HOME="$test_root/home/.cache" \
        QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=16 QT_FORCE_STDERR_LOGGING=1 \
        FLEA_BIN="$bin" CODECOL_DIR="$fixture" CODECOL_NOBAT="$nobat" CODECOL_IMG="$img" \
        "$timeout_bin" "$RUN_BOUND" "$qs_bin" -p "$test_root/config" > "$log" 2>&1
    status=$?
    # Sample input, the receipt: "  INFO qml: CODECOL DONE 41 checks, 0 failed".
    local done_count noisy
    done_count=$(grep -ac 'CODECOL DONE' "$log")
    noisy=$(grep -aiE 'WARN|ERROR|TypeError|ReferenceError|is not a function|is not defined|Binding loop|Unable to assign|Cannot assign' "$log" \
        | grep -av 'does not support setting window masks' | grep -av 'Process failed to start, likely because the binary could not be found' | grep -avF '$HYPRLAND_INSTANCE_SIGNATURE is unset. Cannot connect to hyprland.')
    if [ "$done_count" -ne 1 ] || grep -aq 'CODECOL FAIL' "$log" || [ "$status" -ne 0 ] || [ -n "$noisy" ]; then
        printf 'FAIL %s: qs exit %s, receipts %s\n' "$name" "$status" "$done_count"
        grep -a 'CODECOL' "$log"
        [ -n "$noisy" ] && printf '%s\n' "$noisy"
        verdict=1
        return
    fi
    grep -a 'CODECOL' "$log"
}

run_harness coloured "$PATH" 0
run_harness nobat "$test_root/nobat" 1

seen=$(grep -c connection "$test_root/listener.log")
if [ "$seen" -ne 0 ]; then
    printf 'FAIL the markup line opened %s connection(s) to the listener\n' "$seen"
    verdict=1
else
    printf 'CODECOL PASS the markup line opened no connection to the listener\n'
fi
python3 -I -c 'import socket, sys; socket.create_connection(("127.0.0.1", int(sys.argv[1])), 2).close()' "$port"
for _ in $(seq 1 30); do [ "$(grep -c connection "$test_root/listener.log")" -eq 1 ] && break; sleep 0.1; done
if [ "$(grep -c connection "$test_root/listener.log")" -ne 1 ]; then
    printf 'FAIL the listener missed a connection made to it, so its silence proves nothing\n'
    verdict=1
else
    printf 'CODECOL PASS the listener sees a connection made to it\n'
fi

exit "$verdict"
