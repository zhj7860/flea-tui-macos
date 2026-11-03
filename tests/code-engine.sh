#!/bin/bash
# Drives the real backend's code engine: bat colours only the asked lines inside the jail, and every rule that needs no colour answers before a jail starts.
set -u
set -o pipefail
# Hard rule 9's guard, which owns FIXTURE_ROOT and every create and delete below.
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

BIN=./target/debug/flea
SB="$FIXTURE_ROOT/flea-code-test-$$"
D="$SB/tree"
# The backend ends on its own past this, so a request that never answers cannot hold the run open.
BACKEND_BOUND=120
# A cold jail with bat in it is well under a second; this is the wait for a reply, in seconds.
ANSWER_BOUND=30
# How long a reply that must never come is given to arrive.
SILENCE=3
# How long the backend has to end a superseded jail, in seconds; the held jail outlives it by far.
SUPERSEDE_BOUND=5
TIMEOUT=$(command -v timeout)
REAL_BWRAP=$(command -v bwrap)
BACKEND_PID=""
fail=0

cleanup() {
  exec 3>&-
  [ -s "$SB/held.pid" ] && kill "$(cat "$SB/held.pid")" 2>/dev/null
  end_backend
  sandbox_remove "$SB"
}
trap cleanup EXIT

check() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" != "$actual" ]; then
    echo "FAIL $label"; echo "  expected: $expected"; echo "  actual:   $actual"; fail=1
  else
    echo "ok   $label"
  fi
}

[ -x "$BIN" ] || { echo "code-engine.sh: no binary at $BIN, build it first; refusing to report on nothing" >&2; exit 1; }
for tool in bat jq bwrap prlimit; do
  command -v "$tool" >/dev/null || { echo "code-engine.sh: $tool is not on PATH; this suite runs in the flea-ci image" >&2; exit 1; }
done

# GNU timeout runs the backend in its own process group, so the negative pid reaches both.
end_backend() {
  [ -n "$BACKEND_PID" ] || return 0
  kill -- -"$BACKEND_PID" 2>/dev/null
  wait "$BACKEND_PID" 2>/dev/null
  BACKEND_PID=""
}

# $1 is the PATH the backend sees, which decides whether it finds bwrap, prlimit and bat.
start_backend() {
  rm -f "$SB/out" "$SB/in"; : > "$SB/out"; mkfifo "$SB/in"
  PATH="$1" XDG_CACHE_HOME="$SB/cache" XDG_RUNTIME_DIR="$SB/runtime" "$TIMEOUT" -k 5 "$BACKEND_BOUND" "$BIN" --backend < "$SB/in" > "$SB/out" 2>"$SB/err" &
  BACKEND_PID=$!
  exec 3> "$SB/in"
}

stop_backend() {
  exec 3>&-
  end_backend
}

# Every bwrap goes through this wrapper: jails are counted and their arguments kept, and while $SB/hold exists the jail is a held process whose pid is in $SB/held.pid.
make_shim() {
  mkdir -p "$SB/shim"
  cat > "$SB/shim/bwrap" <<EOF
#!/bin/sh
echo jail >> "$SB/jails"
printf '%s\n' "\$@" >> "$SB/jail-args"
if [ -f "$SB/hold" ]; then echo \$\$ > "$SB/held.pid"; exec sleep 600; fi
exec "$REAL_BWRAP" "\$@"
EOF
  chmod +x "$SB/shim/bwrap"
}

jails() {
  if [ -f "$SB/jails" ]; then wc -l < "$SB/jails" | tr -d ' '; else echo 0; fi
}

# Prints the reply with this token once it has arrived, and fails when none does.
reply() {
  local token=$1 i line
  for i in $(seq 1 $((ANSWER_BOUND * 20))); do
    if line=$(grep -a -m1 "\"token\":$token," "$SB/out"); then printf '%s\n' "$line"; return 0; fi
    sleep 0.05
  done
  return 1
}

# token slot path first count [raw]
file_req() {
  jq -nc --argjson t "$1" --arg s "$2" --arg p "$3" --argjson f "$4" --argjson n "$5" --argjson r "${6:-false}" \
    '{c:"code",token:$t,slot:$s,path:$p,first:$f,count:$n} + (if $r then {raw:true} else {} end)'
}

# token slot text name lang
text_req() {
  jq -nc --argjson t "$1" --arg s "$2" --arg x "$3" --arg m "$4" --arg l "$5" '{c:"code",token:$t,slot:$s,text:$x,name:$m,lang:$l}'
}

# Sends one request alone and prints its reply; the jails it started are left in $SB/delta.
ask() {
  local before after
  before=$(jails)
  printf '%s\n' "$1" >&3
  reply "$2" || return 1
  after=$(jails)
  echo $((after - before)) > "$SB/delta"
}

field() {
  jq -r "$1" <<< "$2"
}

sandbox_make "$SB"
mkdir -p "$D" "$SB/cache" "$SB/runtime" "$SB/nobat"
chmod 700 "$SB/runtime"
make_shim

# Fixtures: a 132-line Rust file, minified and broken JSON, and one file for each rule that ends before a jail.
for n in $(seq 1 132); do printf 'fn f%d() { let s = "x"; }\n' "$n"; done > "$D/a.rs"
jq -cn '[range(0;400) | {id: ., name: "item \(.)"}]' > "$D/data.json"
printf '{"a":' > "$D/bad.json"
printf 'a,b\n1,2\n' > "$D/t.csv"
printf 'text\0text\n' > "$D/nul.txt"
head -c 1048577 /dev/zero | tr '\0' a > "$D/over.txt"
head -c 1048576 /dev/zero | tr '\0' a > "$D/at.txt"
{ printf 'fn a() {}\n'; head -c 5001 /dev/zero | tr '\0' x; printf '\n'; } > "$D/long.rs"
printf '<img src="http://127.0.0.1:9/x">\n' > "$D/img.html"
printf 'fn a() {}\n' > "$D/small.rs"

start_backend "$SB/shim:$PATH"

r=$(ask "$(file_req 1 look "$D/a.rs" 40 20)" 1) || r=""
check "a Rust file is answered styled" "styled" "$(field .state "$r")"
check "lines 40 to 59 come back as first 40" "40" "$(field .first "$r")"
check "twenty lines of the 132" "20 132" "$(field '[(.lines|length), .total]|join(" ")' "$r")"
check "the fn run is magenta" "5 fn" "$(field '.lines[0][0:2]|join(" ")' "$r")"
check "a string run is green" "2" "$(field '[.lines[0] as $l | range(0; $l|length; 2) | select($l[.+1] | contains("\"x\"")) | $l[.]] | first' "$r")"
check "no escape byte reaches the wire" "0" "$(printf '%s' "$r" | grep -c -a -e '\\u001b' -e "$(printf '\033')")"
check "exactly one jail answered it" "1" "$(cat "$SB/delta")"
check "the jail is given the file on stdin and never its path" "0" "$(grep -a -c -x -F -e "$D/a.rs" "$SB/jail-args")"

r=$(ask "$(file_req 2 look "$D/data.json" 1 400)" 2) || r=""
check "minified JSON is answered styled" "styled" "$(field .state "$r")"
check "and comes back formatted over many lines" "true" "$(field '.total > 1 and (.lines|length) > 1' "$r")"
check "its keys are blue" "true" "$(field '.lines[2] as $l | [range(0; $l|length; 2) | $l[.]] | contains([4])' "$r")"
check "one jail did the jq and the colour" "1" "$(cat "$SB/delta")"

r=$(ask "$(file_req 3 look "$D/bad.json" 1 400)" 3) || r=""
check "JSON jq refuses is coloured as it is" "styled 1" "$(field '[.state, .total]|join(" ")' "$r")"
check "still one jail" "1" "$(cat "$SB/delta")"

r=$(ask "$(file_req 4 look "$D/nul.txt" 1 400)" 4) || r=""
check "a NUL in the first KiB is binary" "binary" "$(field .state "$r")"
check "binary starts no jail" "0" "$(cat "$SB/delta")"

r=$(ask "$(file_req 5 look "$D/over.txt" 1 400)" 5) || r=""
check "1 MiB and one byte is large" "large" "$(field .state "$r")"
check "large starts no jail" "0" "$(cat "$SB/delta")"

r=$(ask "$(file_req 6 look "$D/at.txt" 1 400)" 6) || r=""
check "1 MiB exactly is not large; its one long line is plain" "plain" "$(field .state "$r")"

r=$(ask "$(file_req 7 look "$D/long.rs" 1 400)" 7) || r=""
check "a line over 5000 bytes is plain with every line" "plain 2" "$(field '[.state, (.lines|length)]|join(" ")' "$r")"
check "a long line starts no jail" "0" "$(cat "$SB/delta")"

r=$(ask "$(file_req 8 look "$D/t.csv" 1 400 true)" 8) || r=""
check "raw answers plain lines" "plain 2" "$(field '[.state, (.lines|length)]|join(" ")' "$r")"
check "raw starts no jail" "0" "$(cat "$SB/delta")"

r=$(ask "$(file_req 9 look "$D/img.html" 1 400)" 9) || r=""
check "markup is literal text runs" '<img src="http://127.0.0.1:9/x">' "$(field '[.lines[0][] | select(type == "string")] | join("")' "$r")"

r=$(ask "$(text_req 10 fence:1 $'fn main() {}\n' x.rs '')" 10) || r=""
check "a text named x.rs colours fn magenta" "styled 5 fn" "$(field '[.state, .lines[0][0], .lines[0][1]]|join(" ")' "$r")"
check "the text form is one jail" "1" "$(cat "$SB/delta")"

r=$(ask "$(text_req 11 fence:2 $'[package]\nname = "x"\n' '' toml)" 11) || r=""
check "a toml table header is yellow" "3 package" "$(field '[.lines[0][] ] | [.[2], .[3]] | join(" ")' "$r")"

r=$(ask "$(text_req 12 fence:3 $'hello\n' '' nosuchlang)" 12) || r=""
check "an unknown language is plain" "plain" "$(field .state "$r")"

# Two requests on one slot: the second is answered, the first never is, and the second ends the first jail, which the shim holds far longer than the check waits.
touch "$SB/hold"
before=$(jails)
printf '%s\n' "$(file_req 20 column "$D/a.rs" 1 5)" >&3
for _ in $(seq 1 $((ANSWER_BOUND * 20))); do [ -s "$SB/held.pid" ] && break; sleep 0.05; done
rm -f "$SB/hold"
check "the first request's jail started before the second was sent" "1" "$(( $(jails) - before ))"
# The job attaches its jail right after the spawn; this is long beside that.
sleep 0.3
printf '%s\n' "$(file_req 21 column "$D/small.rs" 1 400)" >&3
r=$(reply 21) || r=""
check "the second request on a slot is answered" "styled" "$(field .state "$r")"
sleep "$SILENCE"
check "the first request on that slot is never answered" "0" "$(grep -a -c '"token":20,' "$SB/out")"
check "the second is answered once" "1" "$(grep -a -c '"token":21,' "$SB/out")"
held=$(cat "$SB/held.pid" 2>/dev/null)
for _ in $(seq 1 $((SUPERSEDE_BOUND * 10))); do [ -n "$held" ] && kill -0 "$held" 2>/dev/null || break; sleep 0.1; done
alive=gone; [ -n "$held" ] && kill -0 "$held" 2>/dev/null && alive=alive
check "the superseded jail is ended" "gone" "$alive"
stop_backend

# A path without bat answers plain from a direct read and starts no jail.
# Its bwrap is the counting shim, so a jail it started would move the count.
ln -sf "$(command -v prlimit)" "$SB/nobat/prlimit"
ln -sf "$SB/shim/bwrap" "$SB/nobat/bwrap"
before=$(jails)
start_backend "$SB/nobat"
r=$(ask "$(file_req 30 look "$D/a.rs" 1 5)" 30) || r=""
check "with no bat the answer is plain" "plain 5 132" "$(field '[.state, (.lines|length), .total]|join(" ")' "$r")"
check "the plain lines are the file's own" "fn f1() { let s = \"x\"; }" "$(field '.lines[0][1]' "$r")"
check "with no bat no jail starts" "$before" "$(jails)"
stop_backend

[ "$fail" -eq 0 ] && echo "code-engine: all checks passed"
exit "$fail"
