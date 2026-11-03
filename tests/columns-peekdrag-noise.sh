#!/usr/bin/env bash
# columns-peekdrag.sh prints the QML warning that failed it: a Binding loop line beside a passing DONE line reaches the FAIL output, capped at 20 lines.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
MARKER=.flea-test-sandbox
box=$(mktemp -d) || exit 1
: > "$box/$MARKER"
# Removes only an absolute, non-empty root that still carries its marker.
cleanup() {
    case $box in
        /?*) [ -f "$box/$MARKER" ] && rm -rf -- "$box" ;;
    esac
}
trap cleanup EXIT
checks=0
bad=0
# The verdict word is reworded in every line this suite prints, so only a real failure reads as one to flea-ci.
say() { local s=$*; printf '%s\n' "${s//FAIL/failed}"; }
check() {
    checks=$((checks + 1))
    if [ "$1" = ok ]; then say "ok   $2"; else bad=$((bad + 1)); say "BAD  $2"; fi
}

mkdir -p "$box/bin" "$box/fixtures" || exit 1
# Sample input, STUB_NOISE='QML ListView: Binding loop detected for property "x"': the stub logs that line STUB_COUNT times, then the probe's passing DONE line.
cat > "$box/bin/qs" <<'STUB'
#!/bin/sh
i=0
while [ -n "${STUB_NOISE:-}" ] && [ "$i" -lt "${STUB_COUNT:-1}" ]; do printf '%s\n' "$STUB_NOISE"; i=$((i + 1)); done
echo "  INFO qml: COLUMNSPEEKDRAG DONE checks=39 failed=0"
STUB
chmod +x "$box/bin/qs"
peekdrag() { env PATH="$box/bin:$PATH" FLEA_FIXTURE_ROOT="$box/fixtures" "$@" bash tests/columns-peekdrag.sh 2>&1; }

loop='QML ListView: Binding loop detected for property "x"'
out=$(peekdrag STUB_NOISE="$loop"); rc=$?
[ "$rc" -ne 0 ] && grep -qF -- "$loop" <<< "$out" \
    && check ok "a Binding loop line fails the run and is printed" || check bad "a Binding loop line fails the run and is printed"

bare='file:///x.qml:12: foo is not a function'
out=$(peekdrag STUB_NOISE="$bare"); rc=$?
[ "$rc" -ne 0 ] && grep -qF -- "$bare" <<< "$out" \
    && check ok "a bare 'is not a function' line fails the run and is printed" || check bad "a bare 'is not a function' line fails the run and is printed"

out=$(peekdrag STUB_NOISE="$loop" STUB_COUNT=30); rc=$?
shown=$(grep -cF -- "$loop" <<< "$out")
[ "$rc" -ne 0 ] && [ "$shown" -eq 20 ] \
    && check ok "thirty Binding loop lines print twenty" || check bad "thirty Binding loop lines print $shown (rc $rc)"

out=$(peekdrag); rc=$?
[ "$rc" -eq 0 ] && grep -q 'COLUMNSPEEKDRAG DONE checks=39 failed=0' <<< "$out" \
    && check ok "a quiet passing log passes" || check bad "a quiet passing log passes (rc $rc)"

say "columns-peekdrag-noise: $checks check(s), $bad failed"
if [ "$bad" -ne 0 ]; then say "$out"; fi
[ "$bad" -eq 0 ]
