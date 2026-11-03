#!/usr/bin/env bash
# slowsource-load.sh removes its sandbox root after a clean run, and a root holding a stray entry keeps its marker so the guard can still remove it, names the root and fails the run.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. tools/flea-sandbox-guard
box=$(mktemp -d) || exit 1
: > "$box/$SANDBOX_MARKER"
# Removes only an absolute, non-empty root that still carries its marker.
cleanup() {
    case $box in
        /?*) [ -f "$box/$SANDBOX_MARKER" ] && rm -rf -- "$box" ;;
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
# The script under test makes its own root in /tmp, so a root it leaves behind is marked here and removed through the guard.
reap() {
    case $1 in /tmp/flea-slowsource-load.????????) ;; *) return 0 ;; esac
    [ -d "$1" ] && [ ! -L "$1" ] || return 0
    : > "$1/$SANDBOX_MARKER"
    FIXTURE_ROOT=$1
    sandbox_root_ok
    local e
    for e in "$1"/* "$1"/.[!.]*; do [ -e "$e" ] && sandbox_remove "$e"; done
    rmdir "$1"
}

mkdir -p "$box/bin" || exit 1
# The stub qs answers each leg's DONE line, tells the test which root the script made, and drops a stray entry beside the logs when STUB_STRAY is set.
cat > "$box/bin/qs" <<'STUB'
#!/bin/sh
root=$(dirname "$(dirname "$2")")
printf '%s\n' "$root" > "$STUB_SEEN"
[ -z "${STUB_STRAY:-}" ] || : > "$root/stray"
case $SLOWSOURCE_LEG in slow) n=1 ;; *) n=0 ;; esac
echo "  DEBUG qml: SLOWSOURCE DONE leg=$SLOWSOURCE_LEG fallbacks=$n shownMs=1"
STUB
chmod +x "$box/bin/qs"
slowsource() { env PATH="$box/bin:$PATH" STUB_SEEN="$box/seen" "$@" bash tests/slowsource-load.sh 2>&1; }

out=$(slowsource); rc=$?
root=$(cat "$box/seen" 2>/dev/null)
[ "$rc" -eq 0 ] && [ -n "$root" ] && [ ! -e "$root" ] \
    && check ok "a clean run removes its root" || check bad "a clean run removes its root (rc $rc, root ${root:-unseen})"
reap "$root"

out2=$(slowsource STUB_STRAY=1); rc=$?
root=$(cat "$box/seen" 2>/dev/null)
[ "$rc" -ne 0 ] && [ -n "$root" ] && [ -e "$root/stray" ] && [ -f "$root/$SANDBOX_MARKER" ] && [[ $out2 == *"the load root $root holds more than its marker"* ]] \
    && check ok "a clean run with a stray entry keeps the root's marker, names the root and fails" || check bad "a clean run with a stray entry keeps the root's marker, names the root and fails (rc $rc, root ${root:-unseen})"
reap "$root"

# The cleanup function is cut out of the script and driven on a marked scratch root holding one extra file, after a passing run (result 0).
mkdir -p "$box/direct" || exit 1
: > "$box/direct/$SANDBOX_MARKER"
: > "$box/direct/extra"
sed -n '/^cleanup() {$/,/^}$/p' tests/slowsource-load.sh > "$box/cleanup.sh"
out3=$(bash -c '. tools/flea-sandbox-guard; FIXTURE_ROOT=$2; sandbox_root_ok; load_root=$SANDBOX_ROOT; load_work=$load_root/work; . "$1"; true; cleanup' _ "$box/cleanup.sh" "$box/direct" 2>&1); rc=$?
[ "$rc" -ne 0 ] && [ -f "$box/direct/extra" ] && [ -f "$box/direct/$SANDBOX_MARKER" ] && [[ $out3 == *"the load root $box/direct holds more than its marker"* ]] \
    && check ok "the cleanup alone names a root holding an extra file and exits non-zero" || check bad "the cleanup alone names a root holding an extra file and exits non-zero (rc $rc)"

say "slowsource-load-cleanup: $checks check(s), $bad failed"
if [ "$bad" -ne 0 ]; then say "$out"; say "$out2"; say "$out3"; fi
[ "$bad" -eq 0 ]
