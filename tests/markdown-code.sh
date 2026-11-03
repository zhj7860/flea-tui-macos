#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# Markdown Source and fenced blocks over the real backend and bat: the Source gutter and inks from line 1, a 3,000-line Source asking only for its window, fences coloured in Quick Look and the column, a one-screen sweep with no fence still owed its colours, and markup drawn as text. Offscreen, in the flea-ci image.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
. "$(dirname "$0")/qslog-gate.sh"
cd "$(dirname "$0")/.." || exit 1

for tool in qs bat bwrap prlimit python3 qjs; do
    command -v "$tool" >/dev/null || { echo "markdown-code.sh: $tool is not on PATH; this suite runs in the flea-ci image"; exit 1; }
done
bin=${FLEA_BIN:-$PWD/target/debug/flea}
[ -x "$bin" ] || { echo "markdown-code.sh: build the backend first: $bin"; exit 1; }
qs_bin=$(command -v qs)
timeout_bin=$(command -v timeout)
# The deadline for the harness, in seconds.
RUN_BOUND=300

# The image supplies the Quickshell imports this checkout's qmllint gate needs.
tools/flea-qmllint-gate
lint_status=$?
printf 'MARKDOWN_CODE_QMLLINT_EXIT %s\n' "$lint_status"

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-markdown-code-XXXXXX") || exit 1
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
mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" "$fixture" || exit 1
chmod 700 "$test_root/runtime" || exit 1
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/markdown-code.qml "$test_root/config/shell.qml" || exit 1

# The board's notes: 48 lines, a toml fence with 240, a mermaid figure, a fence with no info string, then a list.
notes=("# Field notes" "" 'A note on the 0.4.0 Previews, with `inline code`.' "" '```toml' '[preview]' 'thumbCap = 240' '```' ""
    '```mermaid' 'graph TD' 'A-->B' '```' "" '```' 'plain fence' '```' "" "## What shipped in 0.4.0" "")
for i in $(seq 1 $((48 - ${#notes[@]}))); do notes+=("- item $i"); done
printf '%s\n' "${notes[@]}" > "$fixture/notes.md"
{ printf '# Big\n'; for i in $(seq 1 2999); do printf 'line %d of the long note\n' "$i"; done; } > "$fixture/big.md"
for i in $(seq 1 40); do printf '```rust\nfn f%d() {}\n```\n\n' "$i"; done > "$fixture/fences.md"
for i in $(seq 1 100); do printf 'line %s ' "$i"; printf 'long Markdown text %.0s' $(seq 1 40); printf '\n'; done > "$fixture/long.md"
# Stale listing sizes in the harness force the code engine itself to refuse these Source files.
CODE_WINDOW_MAX_BYTES=1048576
oversized_bytes=$((CODE_WINDOW_MAX_BYTES + 1))
python3 -I -c 'import sys; open(sys.argv[1], "w").write("x" * int(sys.argv[2]))' "$fixture/over.md" "$oversized_bytes" || exit 1
printf '# Unreadable\n' > "$fixture/unreadable.md"
chmod 000 "$fixture/unreadable.md" || exit 1
printf '# Binary\ntext\0text\n' > "$fixture/binary.md"
printf '```rust\nfn rebound() { let n = 240; }\n```\n' > "$fixture/rebind.md"

# Anything that connects to the listener is logged, and a connection made here at the end proves it could have seen one. The lane may not bind port 9, so the listener takes a free port and the markup names it.
python3 -I -c '
import socket, sys
s = socket.socket()
try:
    s.bind(("127.0.0.1", 9))
except OSError:
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
verdict=$lint_status
# Sample input: "listening 41233".
port=$(sed -n 's/^listening //p' "$test_root/listener.log" 2>/dev/null)
if [ -z "$port" ]; then
    printf 'FAIL the listener did not start, so a markup fetch could not be seen\n'
    cat "$test_root/listener.err"
    exit 1
fi
# The markup a Source line and a fence hold: a tag, an entity and an img that would fetch the listener.
{
    printf '%s\n' '```html' '<b>x</b> <img src=x> &amp;' "<img src=\"http://127.0.0.1:$port/x\">" '```' ''
    for i in $(seq 1 36); do printf 'Spacer paragraph %s.\n\n' "$i"; done
    printf '%s\n' '```flea-unknown-language' 'plain unknown fence' '```'
} > "$fixture/markup.md"

run_harness() {
env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    PATH="$PATH" HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    XDG_CONFIG_HOME="$test_root/home/.config" XDG_CACHE_HOME="$test_root/home/.cache" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QSG_RENDER_LOOP=basic QT_QPA_UPDATE_IDLE_TIME=16 QT_FORCE_STDERR_LOGGING=1 QT_LOGGING_RULES="$(qslog_rules "${QT_LOGGING_RULES:-}")" \
    FLEA_BIN="$bin" FLEA_UI="$PWD/ui" MDCODE_DIR="$fixture" \
    "$timeout_bin" "$RUN_BOUND" "$qs_bin" -p "$test_root/config" > "$1" 2>&1
}
log="$test_root/markdown-code.log"
run_harness "$log"
status=$?
# The harness ends by its own SIGTERM, so a clean run exits 143; a receipt line alone proves the checks ran.
# Sample input, the receipt: "  INFO qml: MARKDOWN_CODE DONE 14 checks, 0 failed".
done_count=$(grep -ac 'MARKDOWN_CODE DONE' "$log")
qslog_nullptr markdown-code < "$log" || verdict=1
noisy=$(qslog_filter markdown-code < "$log" | grep -aiE 'WARN|ERROR|TypeError|ReferenceError|is not a function|is not defined|Binding loop|Unable to assign|Cannot assign' \
    | grep -av 'does not support setting window masks' | grep -av 'Process failed to start, likely because the binary could not be found' | grep -avF '$HYPRLAND_INSTANCE_SIGNATURE is unset. Cannot connect to hyprland.' \
    | grep -avF "inotify_add_watch($fixture/unreadable.md) failed: (Permission denied)")
if [ "$done_count" -ne 1 ] || grep -aq 'MARKDOWN_CODE FAIL' "$log" || [ "$status" -ne 143 ] || [ -n "$noisy" ]; then
    printf 'FAIL markdown-code: qs exit %s, receipts %s\n' "$status" "$done_count"
    grep -a 'MARKDOWN_CODE' "$log"
    [ -n "$noisy" ] && printf '%s\n' "$noisy"
    verdict=1
else
    grep -a 'MARKDOWN_CODE' "$log"
fi

cp tests/markdown-code-rebind.qml "$test_root/config/shell.qml" || exit 1
rebind_log="$test_root/markdown-code-rebind.log"
run_harness "$rebind_log"
rebind_status=$?
grep -a 'MARKDOWN_REBIND' "$rebind_log"
# Sample input: " DEBUG qml: MARKDOWN_REBIND DONE 0 failed".
if [ "$rebind_status" -ne 143 ] || [ "$(grep -ac 'MARKDOWN_REBIND DONE' "$rebind_log")" -ne 1 ] || grep -aqE 'MARKDOWN_REBIND FAIL|TypeError|ReferenceError|Unable to assign|Cannot assign' "$rebind_log"; then
    printf 'FAIL markdown-code backend handoff: qs exit %s\n' "$rebind_status"
    verdict=1
fi
if [ -n "${FLEA_CI_SUITE_LOGS:-}" ]; then
    cp "$rebind_log" "$FLEA_CI_SUITE_LOGS/markdown-code-rebind.log" || exit 1
fi

seen=$(grep -c connection "$test_root/listener.log")
if [ "$seen" -ne 0 ]; then
    printf 'FAIL the markup opened %s connection(s) to the listener\n' "$seen"
    verdict=1
else
    printf 'MARKDOWN_CODE PASS the markup opened no connection to the listener on port %s\n' "$port"
fi
python3 -I -c 'import socket, sys; socket.create_connection(("127.0.0.1", int(sys.argv[1])), 2).close()' "$port"
for _ in $(seq 1 30); do [ "$(grep -c connection "$test_root/listener.log")" -eq 1 ] && break; sleep 0.1; done
if [ "$(grep -c connection "$test_root/listener.log")" -ne 1 ]; then
    printf 'FAIL the listener missed a connection made to it, so its silence proves nothing\n'
    verdict=1
else
    printf 'MARKDOWN_CODE PASS the listener sees a connection made to it\n'
fi

exit "$verdict"
