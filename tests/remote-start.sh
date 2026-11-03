#!/usr/bin/env bash

# A remote start enumerates the share once: an adopted prefetch costs zero backend gio spawns, a missing or stale one costs exactly one.
set -u
# Hard rule 9's guard, which owns FIXTURE_ROOT and every create and delete below.
. "$(dirname "$0")/../tools/flea-sandbox-guard"

cd "$(dirname "$0")/.." || exit 1

BIN=${BIN:-./target/debug/flea}
# A clean git archive export carries no target/, so without this guard every case reports a missing binary as product failures.
if [ ! -x "$BIN" ]; then
    printf 'remote-start.sh: no binary at %s\n' "$BIN" >&2
    printf 'remote-start.sh: build it (cargo build) or set BIN to one; refusing to report on nothing\n' >&2
    exit 1
fi
if ! command -v timeout >/dev/null 2>&1; then
    echo 'remote-start.sh: timeout is required so a hung adopt fails instead of hanging the suite' >&2
    exit 1
fi
SB="$FIXTURE_ROOT/flea-remote-start-$$"
# The hermetic runtime dir: adopt_in only trusts a dest inside it.
export XDG_RUNTIME_DIR="$SB/runtime"
export XDG_CACHE_HOME="$SB/cache"
# A hung backend fails the case after 120 s instead of hanging the suite.
BACK_TIMEOUT=120
# The reader's bounds: GRACE_SECS in src/gvfsprefetch.rs and GIO_TIMEOUT in src/backend/gvfslist.rs.
GRACE_MS=2000
GIO_TIMEOUT_MS=15000
fail=0
passed=0

check() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" != "$actual" ]; then
    echo "FAIL $label"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    fail=$((fail + 1))
  else
    echo "ok   $label"
    passed=$((passed + 1))
  fi
}

sandbox_make "$SB"
SHARE="$XDG_RUNTIME_DIR/gvfs/smb-share:server=t,share=u/dir"
RUNTIMEDIR="$XDG_RUNTIME_DIR/flea"
mkdir -p "$RUNTIMEDIR"
chmod 700 "$RUNTIMEDIR"

# Names are arguments, so a stale adoption shows up in the rows and not only in the count.
stage_dest() {
  local dest="$1" name1="$2" name2="$3"
  printf 'smb://h/share/%s\t3\t(regular)\ttime::modified=100\nsmb://h/share/%s\t4\t(regular)\ttime::modified=200\n' "$name1" "$name2" > "$dest"
  chmod 600 "$dest"
}

# Sample rows line: {"t":"rows",...,"rows":[{"n":"a.txt",...},{"n":"b.txt",...}]}.
rows_names() {
  grep -o '"n":"[a-z.]*"' | sort | tr '\n' ' '
}

# A fake gio that must never run: any call records itself and refuses, so the rows assertion fails alongside the count.
failing_gio() {
  local fake="$1" calls="$2"
  printf '#!/bin/sh\necho called >> "%s"\nexit 1\n' "$calls" > "$fake"
  chmod +x "$fake"
}

# A fake gio answering two rows: single quotes keep the tabs and newlines for the fake's own printf to interpret.
printing_gio() {
  local fake="$1" calls="$2"
  {
    printf '#!/bin/sh\necho called >> "%s"\n' "$calls"
    printf '%s\n' 'printf "smb://h/share/a.txt\t3\t(regular)\ttime::modified=100\nsmb://h/share/b.txt\t4\t(regular)\ttime::modified=200\n"'
  } > "$fake"
  chmod +x "$fake"
}

gio_calls() {
  local calls="$1"
  if [ -f "$calls" ]; then wc -l < "$calls" | tr -d ' '; else printf '0'; fi
}

# Millisecond clock without a helper, so the suite needs date alone.
now_ms() {
  date +%s%3N
}

# Case 1: the stage is stamped a second past the launch because a reader refuses an older dest and a coarse mount clock can report a just-written file as older than the start clock.
START1=$(now_ms)
DEST="$RUNTIMEDIR/gvfs-adopt.list"
stage_dest "$DEST" a.txt b.txt
touch -d "@$((START1 / 1000 + 1))" "$DEST"
FAKE1="$SB/fake1-gio"
CALLS1="$SB/fake1-calls"
failing_gio "$FAKE1" "$CALLS1"
out1=$(printf '{"c":"list","path":"%s","first":10}\n{"c":"quit"}\n' "$SHARE" | FLEA_GIO_BIN="$FAKE1" FLEA_GVFS_PREFETCH="$DEST" FLEA_GVFS_PATH="$SHARE" FLEA_GVFS_START="$START1" timeout "$BACK_TIMEOUT" "$BIN" --backend 2>/dev/null)
got1="$(printf '%s\n' "$out1" | sed -n 2p | rows_names)"
check "adopted listing answers its rows" '"n":"a.txt" "n":"b.txt" ' "$got1"
if [ "$got1" != '"n":"a.txt" "n":"b.txt" ' ]; then printf '%s\n' "$out1" | head -3 | cut -c1-200; fi
check "adopted listing spawns gio zero times" "0" "$(gio_calls "$CALLS1")"

# Case 2: with no prefetch the backend lists the share itself, the one enumeration the launch costs.
FAKE2="$SB/fake2-gio"
CALLS2="$SB/fake2-calls"
printing_gio "$FAKE2" "$CALLS2"
out2=$(printf '{"c":"list","path":"%s","first":10}\n{"c":"quit"}\n' "$SHARE" | FLEA_GIO_BIN="$FAKE2" timeout "$BACK_TIMEOUT" "$BIN" --backend 2>/dev/null)
got2="$(printf '%s\n' "$out2" | sed -n 2p | rows_names)"
check "unadopted listing answers its rows" '"n":"a.txt" "n":"b.txt" ' "$got2"
if [ "$got2" != '"n":"a.txt" "n":"b.txt" ' ]; then printf '%s\n' "$out2" | head -3 | cut -c1-200; fi
check "unadopted listing spawns gio exactly once" "1" "$(gio_calls "$CALLS2")"

# Case 3a: a dest older than the launch is a leftover, still fresh by the clock.
DEST3A="$RUNTIMEDIR/gvfs-stale-mtime.list"
stage_dest "$DEST3A" old.txt older.txt
START3A=$(now_ms)
touch -d "@$((START3A / 1000 - 2))" "$DEST3A"
FAKE3A="$SB/fake3a-gio"
CALLS3A="$SB/fake3a-calls"
printing_gio "$FAKE3A" "$CALLS3A"
out3a=$(printf '{"c":"list","path":"%s","first":10}\n{"c":"quit"}\n' "$SHARE" | FLEA_GIO_BIN="$FAKE3A" FLEA_GVFS_PREFETCH="$DEST3A" FLEA_GVFS_PATH="$SHARE" FLEA_GVFS_START="$START3A" timeout "$BACK_TIMEOUT" "$BIN" --backend 2>/dev/null)
got3a="$(printf '%s\n' "$out3a" | sed -n 2p | rows_names)"
check "mtime-stale prefetch answers the live rows" '"n":"a.txt" "n":"b.txt" ' "$got3a"
if [ "$got3a" != '"n":"a.txt" "n":"b.txt" ' ]; then printf '%s\n' "$out3a" | head -3 | cut -c1-200; fi
check "mtime-stale prefetch spawns gio exactly once" "1" "$(gio_calls "$CALLS3A")"

# Case 3b: a dest newer than the launch but older than the 10 s freshness bound in src/gvfsprefetch.rs.
START3B=$(( $(now_ms) - 30000 ))
DEST3B="$RUNTIMEDIR/gvfs-stale-age.list"
stage_dest "$DEST3B" old.txt older.txt
touch -d "@$((START3B / 1000 + 10))" "$DEST3B"
FAKE3B="$SB/fake3b-gio"
CALLS3B="$SB/fake3b-calls"
printing_gio "$FAKE3B" "$CALLS3B"
out3b=$(printf '{"c":"list","path":"%s","first":10}\n{"c":"quit"}\n' "$SHARE" | FLEA_GIO_BIN="$FAKE3B" FLEA_GVFS_PREFETCH="$DEST3B" FLEA_GVFS_PATH="$SHARE" FLEA_GVFS_START="$START3B" timeout "$BACK_TIMEOUT" "$BIN" --backend 2>/dev/null)
got3b="$(printf '%s\n' "$out3b" | sed -n 2p | rows_names)"
check "age-stale prefetch answers the live rows" '"n":"a.txt" "n":"b.txt" ' "$got3b"
if [ "$got3b" != '"n":"a.txt" "n":"b.txt" ' ]; then printf '%s\n' "$out3b" | head -3 | cut -c1-200; fi
check "age-stale prefetch spawns gio exactly once" "1" "$(gio_calls "$CALLS3B")"

# Case 4: an armed dest that never arrives returns at once past the 2 s grace bound in src/gvfsprefetch.rs.
DEST4="$RUNTIMEDIR/gvfs-missing.list"
START4=$(( $(now_ms) - 3000 ))
FAKE4="$SB/fake4-gio"
CALLS4="$SB/fake4-calls"
printing_gio "$FAKE4" "$CALLS4"
T4=$(now_ms)
out4=$(printf '{"c":"list","path":"%s","first":10}\n{"c":"quit"}\n' "$SHARE" | FLEA_GIO_BIN="$FAKE4" FLEA_GVFS_PREFETCH="$DEST4" FLEA_GVFS_PATH="$SHARE" FLEA_GVFS_START="$START4" timeout "$BACK_TIMEOUT" "$BIN" --backend 2>/dev/null)
T4=$(( $(now_ms) - T4 ))
got4="$(printf '%s\n' "$out4" | sed -n 2p | rows_names)"
check "missing prefetch answers the live rows" '"n":"a.txt" "n":"b.txt" ' "$got4"
if [ "$got4" != '"n":"a.txt" "n":"b.txt" ' ]; then printf '%s\n' "$out4" | head -3 | cut -c1-200; fi
check "missing prefetch spawns gio exactly once" "1" "$(gio_calls "$CALLS4")"
check "missing prefetch past the grace answers inside it" "yes" "$(if [ "$T4" -lt "$GRACE_MS" ]; then echo yes; else echo "no, $T4 ms"; fi)"

# Case 5: inside the grace an armed dest that never arrives is waited for until the deadline, then gio answers.
DEST5="$RUNTIMEDIR/gvfs-late.list"
START5=$(( $(now_ms) - 1000 ))
FAKE5="$SB/fake5-gio"
CALLS5="$SB/fake5-calls"
printing_gio "$FAKE5" "$CALLS5"
T5=$(now_ms)
out5=$(printf '{"c":"list","path":"%s","first":10}\n{"c":"quit"}\n' "$SHARE" | FLEA_GIO_BIN="$FAKE5" FLEA_GVFS_PREFETCH="$DEST5" FLEA_GVFS_PATH="$SHARE" FLEA_GVFS_START="$START5" timeout "$BACK_TIMEOUT" "$BIN" --backend 2>/dev/null)
T5=$(( $(now_ms) - T5 ))
got5="$(printf '%s\n' "$out5" | sed -n 2p | rows_names)"
check "late prefetch answers the live rows" '"n":"a.txt" "n":"b.txt" ' "$got5"
if [ "$got5" != '"n":"a.txt" "n":"b.txt" ' ]; then printf '%s\n' "$out5" | head -3 | cut -c1-200; fi
check "late prefetch spawns gio exactly once" "1" "$(gio_calls "$CALLS5")"
check "late prefetch waits for the deadline" "yes" "$(if [ "$T5" -ge $(( GIO_TIMEOUT_MS - GRACE_MS )) ]; then echo yes; else echo "no, $T5 ms"; fi)"
# START5 is 1 s back, so a deadline counted from the launch ends before GIO_TIMEOUT_MS of test time.
check "late prefetch gives up at the launch's deadline" "yes" "$(if [ "$T5" -lt "$GIO_TIMEOUT_MS" ]; then echo yes; else echo "no, $T5 ms"; fi)"

echo "remote-start: $passed passed, $fail failed"
sandbox_remove "$SB"
exit $fail
