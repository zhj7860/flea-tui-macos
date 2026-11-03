#!/usr/bin/env bash
# Proves transferlive_teardown stops the run's detached flea --clip-own, spares the operator's, and reports an owner that survives SIGTERM, with stub owners that are scripts named flea and the real flea_process_owned.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
MARKER=.flea-test-sandbox
box=$(mktemp -d) || exit 1
: > "$box/$MARKER"
spawned=()
# Kills only what this suite spawned, then removes only an absolute, non-empty root that still carries its marker.
cleanup() {
    local pid
    for pid in "${spawned[@]}"; do kill "$pid" 2>/dev/null; done
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
# A pid that is running: a zombie has already exited.
# Sample input: /proc/PID/stat "347 (flea) Z 1 347 347 0 -1 4194308 ...", so the state is the field after the ")".
alive() { [ -d "/proc/$1" ] && [ "$(sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | cut -d' ' -f1)" != Z ]; }

# The real predicate from tests/ui.sh, with the two things it reads: flea_process_dir and the run root it matches in the environment.
run_root="$box/run"
drain_wait_s=5
fail() { say "stub fail: $*"; exit 99; }
flea_process_dir() { printf '/proc/%s\n' "$1"; }
eval "$(sed -n '/^flea_process_owned()/,/^}/p' tests/ui.sh)"
kill_flea() { :; }
sandbox_remove() { :; }
# shellcheck source=tests/ui-transfer-live.sh
. tests/ui-transfer-live.sh
transferlive_root="" transferlive_bus_pid="" transferlive_writer_pids=()

# A script named flea has comm flea, and its cmdline ends in the argument given, as the real owner's does.
stub="$box/stub"
mkdir "$stub" || exit 1
printf '#!/bin/bash\ntrap '"'"'kill "$s" 2>/dev/null; exit 0'"'"' TERM\nsleep 300 &\ns=$!\nwait "$s"\n' > "$stub/flea"
chmod +x "$stub/flea"
unset FLEA_TEST_RUN_ROOT
FLEA_TEST_RUN_ROOT="$run_root" "$stub/flea" --clip-own & mine=$!
FLEA_TEST_RUN_ROOT="$run_root" "$stub/flea" --backend & backend=$!
"$stub/flea" --clip-own & foreign=$!
spawned=("$mine" "$backend" "$foreign")
# The kernel names the process after the script once the exec lands, so wait for all three.
for _ in $(seq 1 100); do
    [ "$(pgrep -x flea | grep -cxF -e "$mine" -e "$backend" -e "$foreign")" -eq 3 ] && break
    sleep 0.05
done
alive "$mine" && alive "$backend" && alive "$foreign" && check ok "the three stub processes run" || check bad "the three stub processes run"

transferlive_teardown
alive "$mine" && check bad "teardown stops this run's clipboard owner" || check ok "teardown stops this run's clipboard owner"
alive "$backend" && check ok "teardown leaves this run's backend" || check bad "teardown leaves this run's backend"
alive "$foreign" && check ok "teardown leaves an owner this run did not start" || check bad "teardown leaves an owner this run did not start"

# An owner that traps TERM and keeps running, so the deadline branch is the one under test.
stubhard="$box/stubhard"
mkdir "$stubhard" || exit 1
printf '#!/bin/bash\ntrap : TERM\nwhile :; do sleep 0.2; done\n' > "$stubhard/flea"
chmod +x "$stubhard/flea"
FLEA_TEST_RUN_ROOT="$run_root" "$stubhard/flea" --clip-own & stubborn=$!
spawned+=("$stubborn")
for _ in $(seq 1 100); do
    pgrep -x flea | grep -qxF -e "$stubborn" && break
    sleep 0.05
done
alive "$stubborn" && check ok "the TERM-trapping stub runs" || check bad "the TERM-trapping stub runs"

drain_wait_s=1
stop_out=$( ( transferlive_stop_owners ) 2>&1 ); stop_status=$?
[ "$stop_status" -eq 99 ] && [[ "$stop_out" == *"clipboard owner $stubborn survived for 1 s after SIGTERM"* ]] \
    && check ok "stop_owners fails naming the owner that survived SIGTERM" || check bad "stop_owners fails naming the owner that survived SIGTERM"
alive "$foreign" && check ok "the failed stop still spares an owner this run did not start" || check bad "the failed stop still spares an owner this run did not start"
td_out=$( ( transferlive_teardown ) 2>&1 ); td_status=$?
[ "$td_status" -eq 99 ] && [[ "$td_out" == *"clipboard owner $stubborn survived"* && "$td_out" == *"did not drain at teardown"* ]] \
    && check ok "teardown sets drained to 0 when an owner survives" || check bad "teardown sets drained to 0 when an owner survives"

# SIGKILL cannot be trapped, and wait reaps the child so no zombie outlives the suite.
kill -9 "$stubborn" 2>/dev/null
wait "$stubborn" 2>/dev/null
alive "$stubborn" && check bad "the TERM-trapping stub is killed and reaped" || check ok "the TERM-trapping stub is killed and reaped"

say "transferlive-owners: $checks checks, $bad bad"
[ "$bad" -eq 0 ]
