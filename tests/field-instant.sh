#!/bin/bash
# Gates the instant census harness's targeting with no display: its selftest, then a dry run of every part against a synthetic marked root, reading the pointer target of the dual wheel and fling, the row an Enter lands on, and the --only filter.
set -u
cd "$(dirname "$0")/.." || exit 1
repo=$PWD
tool="$repo/tools/flea-field-instant"

# The fixture root is a mktemp -d of its own, and its one delete is checked absolute and two deep before the trap exists.
scratch=$(mktemp -d) || exit 1
case $scratch in
  /*/*) ;;
  *) echo "FAIL: mktemp -d gave '$scratch', which is not an absolute path two components deep"; exit 1 ;;
esac
trap 'rm -rf "$scratch"' EXIT

fail=0
check() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" != "$actual" ]; then
    echo "FAIL $label"; echo "  expected: $expected"; echo "  actual:   $actual"; fail=1
  else
    echo "ok   $label"
  fi
}

# json FILE EXPR: a Python expression over the dry run's JSON, d.
json() { python3 -I -c 'import json, sys; d = json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2"; }

selftest_out=$("$tool" selftest 2>&1)
check "the tool's selftest exits 0" 0 "$?"
last=$(printf '%s\n' "$selftest_out" | grep -v '^[[:space:]]*$' | tail -1)
case $last in
  "SELFTEST ok ("*) echo "ok   selftest: $last" ;;
  *) echo "FAIL selftest last line: $last"; printf '%s\n' "$selftest_out" | grep -a 'FAIL' | head -20; fail=1 ;;
esac

# A synthetic root as tools/flea-field-instant fixtures lays it out, empty files only: the load folder L holds a_dir first.
root="$scratch/root"; usb="$scratch/usb/flea-instant-1"; nas="$scratch/nas/flea-instant-2"
mkdir -p "$root/nav/nav500" "$root/nav/nav10k" "$root/nav/enter/big" "$root/nav/preview" "$root/ops" \
  "$root/load/L/a_dir" "$root/load/cold-src" "$usb/enter/big" "$usb/dst" "$nas/enter/big" "$nas/stream"
for r in "$root" "$usb" "$nas"; do : > "$r/.flea-test-sandbox"; done
for f in b_text.txt f_0000.txt f_0001.txt zzz_big.bin; do : > "$root/load/L/$f"; done
printf '{"root": "%s", "nav": {"nav500": 500}, "usb": "%s", "nas": "%s"}\n' "$root" "$usb" "$nas" > "$root/fixtures.json"

dry() { # dry PART [ARGS...]: the JSON goes to $scratch/dry-PART.json, the exit status is the function's
  local part=$1; shift
  "$tool" run "$part" --root "$root" --flea /nonexistent --out "$scratch/out" --dry "$@" > "$scratch/dry-$part.json" 2> "$scratch/dry-$part.err"
}

# Sample input: PARTS = ["smoke", "p1-cursor", "p2-held", "p3-navigate", "p4-open", "p5-heavy", "p6-ops", "p7-load"]
parts=$(sed -n 's/^PARTS = \[\(.*\)\]$/\1/p' "$tool" | tr -d '"' | tr ',' ' ')
[ -n "$parts" ] || { echo "FAIL: no PARTS line in $tool"; exit 1; }
for part in $parts; do
  dry "$part"; rc=$?
  check "dry run of $part exits 0" 0 "$rc"
  check "and lists a journey with no unmapped row" "True" "$(json "$scratch/dry-$part.json" 'len(d["journeys"]) > 0 and d["unmapped"] == []' 2>&1)"
done
check "a dry run writes nothing under --out" "no" "$([ -e "$scratch/out" ] && echo yes || echo no)"

# The dual wheel and fling go to the left pane; every other view keeps the watched region's centre.
f="$scratch/dry-p1-cursor.json"
check "p1-cursor: dual wheel and fling aim at the left pane" "['centre of the left pane', 'centre of the left pane']" \
  "$(json "$f" '[t["aim"] for t in d["targets"] if t["view"] == "dual" and t["series"] in ("wheel", "fling")]')"
check "p1-cursor: list, columns and grid aim at the watched region" "6" \
  "$(json "$f" 'len([t for t in d["targets"] if t["view"] != "dual" and t["aim"] == "centre of the watched region"])')"
check "p1-cursor: the dual pointer is left of the content centre by more than a pane edge strip" "True" \
  "$(json "$f" '(lambda dual, lst: lst[0] - dual[0] > 100 and dual[1] == lst[1])([t["pointer"] for t in d["targets"] if t["view"] == "dual" and t["series"] == "wheel"][0], [t["pointer"] for t in d["targets"] if t["view"] == "list" and t["series"] == "wheel"][0])')"

# Enter goes to the first folder of the fixture: Home and no Down on both nav/enter and L.
f="$scratch/dry-p7-load.json"
check "p7-load: Enter and Back resolve to Home and no Down under all three loads" "[('a', 0, ['home']), ('b', 0, ['home']), ('c', 0, ['home'])]" \
  "$(json "$f" '[(t["load"], t["enter_index"], t["setup"]) for t in d["targets"] if t["series"] == "cycle"]')"
f="$scratch/dry-p3-navigate.json"
check "p3-navigate: nav/enter resolves to index 0 in all four views" "[('list', 0), ('columns', 0), ('grid', 0), ('dual', 0)]" \
  "$(json "$f" '[(t["view"], t["enter_index"]) for t in d["targets"] if t["series"] == "cycle"]')"

# A first folder that is the fourth name still resolves to Home alone (folders first); a listing with no folder is a failed dry run.
mv "$root/load/L/a_dir" "$root/load/L/g_dir"
dry p7-load; rc=$?
check "L with its first folder fourth: dry run exits 0" 0 "$rc"
check "and Enter resolves to index 0 with Home alone, because folders come first" "[(0, 'home', True)]" \
  "$(json "$scratch/dry-p7-load.json" 'sorted({(t["enter_index"], " ".join(t["setup"]), "folders first" in t["aim"]) for t in d["targets"] if t["series"] == "cycle"})')"
rmdir "$root/load/L/g_dir"
dry p7-load; rc=$?
check "L with no folder: dry run exits 1" 1 "$rc"
check "and names the listing" "True" "$(json "$scratch/dry-p7-load.json" 'all("no folder in" in t["error"] for t in d["targets"] if t["series"] == "cycle")')"
mkdir "$root/load/L/a_dir"

# The journey filter: only the matching series stay, and a filter that matches nothing is a usage error.
dry p1-cursor --only 'nav\.dual\.(wheel|fling)'; rc=$?
check "p1-cursor --only dual wheel and fling exits 0" 0 "$rc"
check "and holds exactly those two journeys in one session" "(['nav.dual.fling', 'nav.dual.wheel'], 1)" \
  "$(json "$scratch/dry-p1-cursor.json" '(d["journeys"], d["sessions"])')"
dry p7-load --only 'nav\.dual\.(enter|back)'; rc=$?
check "p7-load --only dual enter and back exits 0" 0 "$rc"
check "and holds exactly those two journeys in three sessions" "(['nav.dual.back', 'nav.dual.enter'], 3)" \
  "$(json "$scratch/dry-p7-load.json" '(d["journeys"], d["sessions"])')"
dry p1-cursor --only 'no such journey'; rc=$?
check "an --only that matches no journey exits 2" 2 "$rc"
: > "$scratch/x.jsonl"
"$tool" gate "$scratch/x.jsonl" --only '(' > /dev/null 2> "$scratch/gate.err"; rc=$?
check "a gate --only that is not a regular expression exits 2 and says so" "2 yes" \
  "$rc $(grep -q 'is not a regular expression' "$scratch/gate.err" && echo yes || echo no)"

if [ "$fail" = 0 ]; then echo "field-instant: all passed"; else echo "field-instant: FAILED"; fi
exit "$fail"
