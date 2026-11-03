#!/bin/bash
# A folder copied onto a vfat model lands every entry the drive can hold, names each it cannot, and undoes whole.
set -u
# Hard rule 9's guard, which owns FIXTURE_ROOT and every create and delete below.
. "$(dirname "$0")/../tools/flea-sandbox-guard"

cd "$(dirname "$0")/.." || exit 1
BIN=./target/debug/flea
[ -x "$BIN" ] || { echo "fatcopy.sh: $BIN is missing, run cargo build" >&2; exit 1; }
command -v cc >/dev/null || { echo "fatcopy.sh: cc is required to build the vfat model" >&2; exit 1; }
command -v jq >/dev/null || { echo "fatcopy.sh: jq is required to read the wire" >&2; exit 1; }
D="$FIXTURE_ROOT/flea-fatcopy-$$"
FAT="$D/fat"
fail=0

cleanup() {
  exec 3>&-
  [ -n "${BACKEND_PID:-}" ] && kill "$BACKEND_PID" 2>/dev/null
  sandbox_remove "$D"
}
trap cleanup EXIT

check() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" != "$actual" ]; then
    echo "FAIL $label"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    fail=1
  else
    echo "ok   $label"
  fi
}

# The binary runs with the model preloaded, so every path under $FAT answers the way a vfat stick does.
start_backend() {
  rm -f "$D/out" "$D/in"; : > "$D/out"
  mkfifo "$D/in"
  mkdir -p "$D/rt"
  LD_PRELOAD="$D/fat.so" FLEA_TEST_FAT_ROOT="$FAT" XDG_RUNTIME_DIR="$D/rt" FLEA_UNDO_DIR="$D/undo" \
    $BIN --backend < "$D/in" > "$D/out" 2>/dev/null &
  BACKEND_PID=$!
  exec 3> "$D/in"
}

stop_backend() {
  send '{"c":"quit"}'
  exec 3>&-
  wait "$BACKEND_PID" 2>/dev/null
  BACKEND_PID=""
}

send() { printf '%s\n' "$1" >&3; }

# A bounded poll that reads the file directly, never a background watcher.
await() {
  local pattern="$1" i
  for i in $(seq 1 300); do
    grep -q -- "$pattern" "$D/out" && return 0
    sleep 0.05
  done
  echo "  TIMEOUT waiting for: $pattern"
  return 1
}

# The paste a client sends: the collision question first, then the transfer carrying its answer.
paste() {
  local op="$1" src="$2" id="$3"
  send "{\"c\":\"collisions\",\"id\":$id,\"dest\":\"$FAT\",\"paths\":[\"$src\"]}"
  await "\"t\":\"collisions\"" || fail=1
  send "{\"c\":\"transfer\",\"op\":\"$op\",\"paths\":[\"$src\"],\"dest\":\"$FAT\",\"collide\":\"refuse\",\"collideId\":$id}"
  await '"t":"transferdone"' || fail=1
}

line() { grep -- "\"t\":\"$1\"" "$D/out" | tail -1; }
refused_names() { line transferdone | jq -r '[.refused[]?.name] | sort | join(" ")'; }
landed() { (cd "$1" && find . -mindepth 1 -printf '%y %P\n' | LC_ALL=C sort | tr '\n' ';'); }

sandbox_make "$D"
mkdir -p "$FAT" "$D/src" "$D/undo" || exit 1
cc -shared -fPIC -o "$D/fat.so" tests/fatcopy-shim.c -ldl || { echo "FAIL the vfat model did not build"; exit 1; }

# Sample tree: three files, a nested folder, a link to a file, a link to a folder and a broken link.
T="$D/src/thesis"
mkdir -p "$T/notes/deep"
printf 'a' > "$T/a.txt"; printf 'b' > "$T/notes/b.txt"; printf 'c' > "$T/notes/deep/c.txt"; printf 'z' > "$T/z.txt"
ln -s a.txt "$T/link-file"; ln -s notes "$T/link-dir"; ln -s missing "$T/notes/broken"

echo "--- a copy onto vfat lands every file, names every link, and undo takes back what landed ---"
start_backend
paste copy "$T" 1
item=$(line transferitem)
check "the folder is a failed item, never a silent success" "false" "$(printf '%s' "$item" | jq -r '.ok')"
check "its sentence counts the links and names the first" "yes" \
  "$(printf '%s' "$item" | jq -r '.err' | grep -qE '^3 items inside could not be copied; the first is (link-file|link-dir|notes/broken): this drive cannot hold links$' && echo yes || echo no)"
check "the done line counts the failed item" '0 1' "$(line transferdone | jq -r '"\(.ok) \(.failed)"')"
check "the done line names each link under dest" "thesis/link-dir thesis/link-file thesis/notes/broken" "$(refused_names)"
check "every file landed and no link did" "d notes;d notes/deep;f a.txt;f notes/b.txt;f notes/deep/c.txt;f z.txt;" "$(landed "$FAT/thesis")"
send '{"c":"undo"}'
await '"t":"undone"' || fail=1
check "undo reverses the copy" "1" "$(grep -c '"t":"undone","op":"copy","ok":true' "$D/out")"
check "and leaves nothing of it on the drive" "no" "$([ -e "$FAT/thesis" ] && echo yes || echo no)"
check "the source keeps its links" "link" "$(stat -c %F "$T/link-dir" | sed 's/symbolic //')"
stop_backend

echo "--- a move onto vfat copies the rest and keeps its source whole ---"
start_backend
cp -a "$T" "$D/src/moving"
paste move "$D/src/moving" 2
check "the move fails and names the links it could not move" "yes" \
  "$(line transferitem | jq -r '.err' | grep -q '^3 items inside could not be moved; the first is ' && echo yes || echo no)"
check "every file landed past the links" "d notes;d notes/deep;f a.txt;f notes/b.txt;f notes/deep/c.txt;f z.txt;" "$(landed "$FAT/moving")"
check "the source is whole, links included" "$(landed "$T")" "$(landed "$D/src/moving")"
stop_backend

echo "--- every other item vfat cannot hold is skipped and named, and the rest lands ---"
start_backend
C="$D/src/class"
mkdir -p "$C"
printf 'k' > "$C/keep.txt"; printf 'c' > "$C/a:b.txt"; printf 'u' > "$C/README"; printf 'l' > "$C/readme"; mkfifo "$C/pipe"
paste copy "$C" 3
check "the refused name, the fifo and one of the folded pair are named" "3" "$(line transferdone | jq -r '.refused | length')"
check "the colon name gives vfat's own reason" "':' is not allowed in a name on this vfat drive" \
  "$(line transferdone | jq -r '.refused[] | select(.name == "class/a:b.txt") | .err')"
check "the fifo gives the special file reason" "this drive cannot hold special files" \
  "$(line transferdone | jq -r '.refused[] | select(.name == "class/pipe") | .err')"
check "the plain file and one of the folded pair landed" "2" "$(find "$FAT/class" -type f | wc -l | tr -d ' ')"
stop_backend

[ "$fail" = 0 ] && echo "fatcopy.sh: all checks passed" || echo "fatcopy.sh: FAIL"
exit "$fail"
