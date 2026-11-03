#!/bin/bash
# Asserts tools/flea-file-budget rejects an oversized file and accepts a normal tree.
set -u
# The cd comes first: a trap installed above it fires against the caller's working directory when
# the cd fails, which is a relative-path rm -rf in somebody else's tree.
cd "$(dirname "$0")/.." || exit 1
repo=$PWD

# The oversized fixture lives in a mktemp -d of its own, which is what hard rule 9 allows outright.
# The tool finds its files with a relative find, so a scratch tree it is run inside is a whole tree
# to it, and nothing is ever written into the checkout under ~/Work.
scratch=$(mktemp -d) || exit 1
# GNU mktemp -d honours a relative TMPDIR verbatim, so the one delete this suite makes is checked
# absolute and non-empty here, before the trap that runs it is installed.
case $scratch in
  /*/*) ;;
  *) echo "FAIL: mktemp -d gave '$scratch', which is not an absolute path two components deep"; exit 1 ;;
esac
trap 'rm -rf "$scratch"' EXIT

fail=0
check() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" != "$actual" ]; then
    echo "FAIL $label: expected exit $expected, got $actual"
    fail=1
  else
    echo "ok   $label"
  fi
}

# Read-only against the real tree, which is the gate this suite exists to keep.
"$repo/tools/flea-file-budget" >/dev/null 2>&1
check "clean tree passes" 0 $?

mkdir -p "$scratch/src" "$scratch/ui" "$scratch/tests"
( cd "$scratch" && "$repo/tools/flea-file-budget" >/dev/null 2>&1 )
check "an empty tree passes too" 0 $?

# A literal one past the Rust hard cap of 400, so the test stays independent.
oversized_lines=401
seq 1 $oversized_lines | sed 's/^/\/\/ line /' > "$scratch/src/oversized.rs"
( cd "$scratch" && "$repo/tools/flea-file-budget" >/dev/null 2>&1 )
check "oversized file fails" 1 $?

# The duplicate-ceiling gate reads a hardcoded list, so a scratch-root copy of the tool names one file twice and runs there.
rm -f "$scratch/src/oversized.rs"
sed 's|^known_over_cap="shelf/Model.js 701$|&\nshelf/Model.js 701|' "$repo/tools/flea-file-budget" > "$scratch/dup-budget"
if cmp -s "$repo/tools/flea-file-budget" "$scratch/dup-budget"; then
  echo "FAIL duplicate fixture: the sed did not duplicate a known_over_cap entry"
  fail=1
fi
chmod +x "$scratch/dup-budget"
dup_out=$(cd "$scratch" && "$scratch/dup-budget" 2>&1)
check "a duplicated ceiling fails" 1 $?
case $dup_out in
  *"DUPLICATE ceiling: shelf/Model.js"*) echo "ok   duplicate is named" ;;
  *) echo "FAIL duplicate is named: got '$dup_out'"; fail=1 ;;
esac

exit $fail
