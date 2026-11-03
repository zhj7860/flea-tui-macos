#!/usr/bin/env bash
# Runs tests/portal-startup.sh against a frontend that never owns the portal name, to pin that a TERM ends it with its sandbox gone and a failing gdbus fails it by name.
set -u
set -o pipefail

# Hard rule 9's guard, which owns FIXTURE_ROOT and every create and delete below.
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

for tool in dbus-run-session setsid; do
    command -v "$tool" >/dev/null 2>&1 || { printf 'portal-startup-abort.sh: %s is missing, and the suite under test needs it\n' "$tool" >&2; exit 1; }
done

root="$FIXTURE_ROOT/flea-portal-abort-$$"
runner=0
cleanup() {
    # The two pids come from this suite's own spawns: the run it started and the frontend stub that run started.
    if [ "$runner" != 0 ] && kill -0 "$runner" 2>/dev/null; then
        kill -KILL "$runner" 2>/dev/null
    fi
    if [ -s "$root/frontend.pid" ] && kill -0 "$(cat "$root/frontend.pid")" 2>/dev/null; then
        kill "$(cat "$root/frontend.pid")" 2>/dev/null
    fi
    sandbox_remove "$root"
}
trap cleanup EXIT
sandbox_make "$root"

fail=0
check() {
    if [ "$2" != "$3" ]; then
        echo "FAIL $1"
        echo "  expected: $2"
        echo "  actual:   $3"
        fail=1
    else
        echo "ok   $1"
    fi
}

# The frontend stub notes its pid and never owns the portal name, so the run under test sits in its first wait.
cat > "$root/frontend" <<'STUB'
#!/bin/sh
echo $$ > "$FLEA_PORTAL_ABORT_PIDFILE"
exec sleep 60
STUB
chmod +x "$root/frontend"
export FLEA_FIXTURE_ROOT="$root" FLEA_PORTAL_FRONTEND="$root/frontend" FLEA_PORTAL_ABORT_PIDFILE="$root/frontend.pid"

bash tests/portal-startup.sh > "$root/term.out" 2>&1 &
runner=$!
waited=0
while [ ! -s "$root/frontend.pid" ] && [ "$waited" -lt 100 ]; do
    sleep 0.1
    waited=$((waited + 1))
done
check "term: the run reached its frontend" "1" "$([ -s "$root/frontend.pid" ] && echo 1 || echo 0)"
check "term: the run's sandbox is present before the TERM" "present" "$([ -e "$root/flea-portal-startup-$runner" ] && echo present || echo gone)"
kill -TERM "$runner"
waited=0
while kill -0 "$runner" 2>/dev/null && [ "$waited" -lt 100 ]; do
    sleep 0.1
    waited=$((waited + 1))
done
state=gone
if kill -0 "$runner" 2>/dev/null; then
    state=running
    kill -KILL "$runner"
fi
check "term: the run stops within 10 s of a TERM" "gone" "$state"
wait "$runner"
check "term: the run exits with the signal's code" "143" "$?"
check "term: the run's sandbox is gone" "gone" "$([ -e "$root/flea-portal-startup-$runner" ] && echo present || echo gone)"
runner=0
check "term: the frontend it started is gone" "gone" "$(kill -0 "$(cat "$root/frontend.pid")" 2>/dev/null && echo running || echo gone)"
check "term: the run did not resume on the removed sandbox" "0" "$(grep -c 'No such file' "$root/term.out")"

# The gdbus double fails the way a lost bus does, so the first name check can only pass by reading that failure as "no owner".
mkdir "$root/bin"
printf '#!/bin/sh\necho "gdbus-double: simulated bus failure" >&2\nexit 1\n' > "$root/bin/gdbus"
chmod +x "$root/bin/gdbus"
PATH="$root/bin:$PATH" timeout 120 bash tests/portal-startup.sh > "$root/gdbus.out" 2>&1
status=$?
check "gdbus: a failing gdbus fails the run" "1" "$status"
check "gdbus: the failure names the gdbus error" "1" "$(grep -c 'gdbus NameHasOwner .* failed: gdbus-double: simulated bus failure' "$root/gdbus.out")"
check "gdbus: the first name check did not pass on the failure" "0" "$(grep -c '^ok   the private bus starts with no frontend on it' "$root/gdbus.out")"

if [ "$fail" = 0 ]; then
    echo "portal-startup-abort.sh: all checks passed"
else
    echo "portal-startup-abort.sh: FAILED"
    for file in term.out gdbus.out; do
        echo "--- $file ---"
        cat "$root/$file" 2>/dev/null
    done
fi
exit "$fail"
