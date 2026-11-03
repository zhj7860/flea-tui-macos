#!/bin/bash
# Gates tools/flea-field-bench's entrant sweep: a process carrying the bench token is ended wherever it went, and nothing else is touched.
set -u
cd "$(dirname "$0")/.." || exit 1
bench="$PWD/tools/flea-field-bench"

bad=0
check() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" != "$actual" ]; then
    echo "FAIL $label"; echo "  expected: $expected"; echo "  actual:   $actual"; bad=1
  else
    echo "ok   $label"
  fi
}

block=$(sed -n '/^# entrant sweep begin$/,/^# entrant sweep end$/p' "$bench")
[ -n "$block" ] || { echo "FAIL: no entrant sweep block in $bench"; exit 1; }
globals=$(grep -E '^(BENCH_TOKEN|SWEEP_TERM_POLLS|SWEEP_KILL_POLLS)=' "$bench")
check "the bench names the three sweep globals" 3 "$(printf '%s\n' "$globals" | grep -c .)"
eval "$globals"
eval "$block"
# The bench's own fail, so a refusal here reads and exits exactly as it does in a run.
real_fail=$(grep -x 'fail() {.*}' "$bench")
check "the bench defines fail on one line" 1 "$(printf '%s\n' "$real_fail" | grep -c .)"
eval "$real_fail"

# Every process the test starts is ended by its pid on the way out, whatever a case did.
started=()
trap 'kill -9 "${started[@]}" 2>/dev/null' EXIT
# procfs reports every file as size 0, so liveness is a signal check and never test -s.
alive() { kill -0 "$1" 2>/dev/null; }

# The escapes a field entrant makes: a session of its own, SIGTERM ignored, and a child its parent left behind.
FLEA_FIELD_BENCH=$BENCH_TOKEN setsid sleep 300 &
started+=($!); disown
FLEA_FIELD_BENCH=$BENCH_TOKEN setsid bash -c "trap '' TERM; exec sleep 300" &
started+=($!); disown
FLEA_FIELD_BENCH=$BENCH_TOKEN bash -c 'setsid sleep 300 &'
# The controls: no token, and a token one digit longer than this run's, which a prefix match would take.
sleep 300 &
control=$!; started+=($!)
FLEA_FIELD_BENCH=${BENCH_TOKEN}9 sleep 300 &
foreign=$!; started+=($!)
sleep 0.2

# Membership, never a count, for the scan of any token: another field run on the box carries one too.
member() { local want=$1 p; shift; for p in "$@"; do [ "$p" = "$want" ] && { echo yes; return; }; done; echo no; }
token_pids "$BENCH_TOKEN"
mine=("${TOKEN_PIDS[@]}")
started+=("${mine[@]}")
check "the three escapes are found by this run's token, the orphan included" 3 "${#mine[@]}"
token_pids '.*'
check "the start-up scan finds the other invocation's process" yes "$(member "$foreign" "${TOKEN_PIDS[@]}")"
check "the start-up scan finds this run's escapes" "yes yes yes" "$(for p in "${mine[@]}"; do member "$p" "${TOKEN_PIDS[@]}"; done | tr '\n' ' ' | sed 's/ $//')"
check "the start-up scan leaves the process with no token out" no "$(member "$control" "${TOKEN_PIDS[@]}")"

log=$(sweep_token 2>&1)
check "each process the sweep ends is named once" 3 "$(printf '%s\n' "$log" | grep -c '^LEFTOVER: pid [0-9]* (sleep) in ')"
check "the sweep did not refuse" 0 "$(printf '%s\n' "$log" | grep -c '^FAIL: ')"
token_pids "$BENCH_TOKEN"
check "nothing carrying this run's token survives, the SIGTERM ignorer included" 0 "${#TOKEN_PIDS[@]}"
check "the process with no token is untouched" yes "$(alive "$control" && echo yes || echo no)"
check "the other invocation's process is untouched" yes "$(alive "$foreign" && echo yes || echo no)"
check "a sweep with nothing to end says nothing" "" "$(sweep_token 2>&1)"

# A process that outlives SIGKILL, which kill stubbed to do nothing stands in for, is refused by its pid.
FLEA_FIELD_BENCH=$BENCH_TOKEN setsid sleep 300 &
stuck=$!; started+=($!); disown
sleep 0.2
# A sweep that returned past the refusal would print RETURNED, and the run would go on.
log=$(kill() { :; }; SWEEP_TERM_POLLS=1; SWEEP_KILL_POLLS=1; sweep_token 2>&1; echo "RETURNED"); rc=$?
check "a SIGKILL survivor is refused by its pid" 1 "$(printf '%s\n' "$log" | grep -c "^FAIL: pid $stuck carried the bench token and outlived SIGKILL")"
check "the refusal ends the run rather than returning" "1 0" "$rc $(printf '%s\n' "$log" | grep -c '^RETURNED$')"

# The wiring: the timed launch, the preview pass and the warm launch each export the token, and clean_bench sweeps it.
check "three launch sites export the token" 3 "$(grep -v '^ *#' "$bench" | grep -c 'FLEA_FIELD_BENCH=\$BENCH_TOKEN')"
check "clean_bench sweeps after its kill list" "done sweep_token" "$(sed -n '/^clean_bench() {$/,/^}$/p' "$bench" | grep -E '^  (done|sweep_token)$' | sed 's/^ *//' | tr '\n' ' ' | sed 's/ $//')"
check "the start-up refusal scans for any token" 1 "$(sed -n '/^require_bench_idle() {$/,/^}$/p' "$bench" | grep -c "token_pids '\.\*'")"

[ "$bad" = 0 ] && echo "field-entrant-sweep: all passed" || echo "field-entrant-sweep: failures above"
exit "$bad"
