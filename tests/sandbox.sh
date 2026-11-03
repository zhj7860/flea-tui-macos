#!/bin/bash
# Proves hard rule 9's guard refuses what it must. Every refusal below is a path that has either
# already destroyed something on this project or is one unset variable away from doing so.
set -u
set -o pipefail
cd "$(dirname "$0")/.." || exit 1
. ./tools/flea-sandbox-guard

fail=0

# Every sandbox this suite makes is named with its pid, and a failing check does not stop the script,
# so a run that leaves one behind is a leak. The trap removes them by name and never by pattern.
cleanup() {
  local d
  for d in "$FIXTURE_ROOT"/flea-guard-*-$$; do
    [ -d "$d" ] || continue
    # No marker is planted here: planting one before deleting makes the ownership check unable to
    # refuse anything this glob matches, which is the one thing it exists to do. A directory this
    # suite made carries its marker already; one that does not is left for a human to look at.
    sandbox_remove "$d" 2>/dev/null || true
  done
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

# Every refusal exits, so each one is asked in its own subshell and reported by its status.
refuses() {
  ( sandbox_require "$1" ) >/dev/null 2>&1 && echo no || echo yes
}
removal_refuses() {
  ( sandbox_remove "$1" ) >/dev/null 2>&1 && echo no || echo yes
}

echo "--- the empty and the shallow, which is what an unset variable produces ---"
check "an empty path is refused" "yes" "$(refuses "")"
check "the root directory is refused" "yes" "$(refuses "/")"
check "a one-component path is refused" "yes" "$(refuses "/home")"
check "a relative path is refused" "yes" "$(refuses "flea-sandbox/x")"
check "a path with a parent traversal is refused" "yes" "$(refuses "$FIXTURE_ROOT/../../etc")"

# A path outside the fixture root is refused by containment alone, so the roots hard rule 9 names
# are proven where the rule actually lives: on the root itself, which the environment can replace.
root_refuses() {
  ( FLEA_FIXTURE_ROOT="$1"; . ./tools/flea-sandbox-guard; sandbox_root_ok ) >/dev/null 2>&1 \
    && echo no || echo yes
}

echo "--- the roots hard rule 9 names, each one asked as a replacement fixture root ---"
check "\$HOME itself is refused as a root" "yes" "$(root_refuses "$HOME")"
check "~/Work is refused as a root" "yes" "$(root_refuses "$HOME/Work")"
check "~/Work/claude/flea is refused as a root" "yes" "$(root_refuses "$HOME/Work/claude/flea")"
check "~/.config is refused as a root" "yes" "$(root_refuses "$HOME/.config")"
check "~/.local is refused as a root" "yes" "$(root_refuses "$HOME/.local/share")"
check "~/.cache is refused as a root" "yes" "$(root_refuses "$HOME/.cache")"
check "~/tmp is refused, it is one unset variable from \$HOME" "yes" "$(root_refuses "$HOME/tmp")"
check "/etc is refused as a root" "yes" "$(root_refuses "/etc")"
check "/usr/share is refused as a root" "yes" "$(root_refuses "/usr/share")"
# :- substitutes the default when the variable is empty as well as when it is unset, so an empty
# override lands on the safe root rather than on "": that is the behaviour, and it is the right one.
check "an empty root falls back to the safe default" "no" "$(root_refuses "")"
check "/ is refused as a root" "yes" "$(root_refuses "/")"
check "and the real fixture root is accepted" "no" "$(root_refuses "/home/flea-sandbox")"

echo "--- component-aware, so a sibling that shares a prefix is not mistaken for a child ---"
check "a sibling of \$HOME sharing its prefix is judged on its own" "no" "$(root_refuses "${HOME}other")"
check "and a path outside the fixture root is still refused" "yes" "$(refuses "${HOME}other/x")"

echo "--- the fixture root, which is overridable and therefore checked ---"
check "the fixture root itself is refused as a target" "yes" "$(refuses "$FIXTURE_ROOT")"
check "a path outside the fixture root is refused" "yes" "$(refuses "/srv/flea-sandbox/x")"
check "a real sandbox under the fixture root is allowed" "no" "$(refuses "$FIXTURE_ROOT/flea-guard-test-$$")"

echo "--- the marker, which is what stands between a directory and rm -rf ---"
D="$FIXTURE_ROOT/flea-guard-test-$$"
UNMARKED="$FIXTURE_ROOT/flea-guard-unmarked-$$"
sandbox_require "$UNMARKED"; rm -rf "$UNMARKED"
mkdir -p "$UNMARKED/keepme"; printf 'do not lose me' > "$UNMARKED/keepme/file"
check "a directory with no marker is refused, not deleted" "yes" "$(removal_refuses "$UNMARKED")"
check "and its contents are still there" "do not lose me" "$(cat "$UNMARKED/keepme/file" 2>/dev/null)"
: > "$UNMARKED/$SANDBOX_MARKER"; sandbox_remove "$UNMARKED"

sandbox_make "$D"
check "a made sandbox carries its own marker" "yes" "$([ -f "$D/$SANDBOX_MARKER" ] && echo yes || echo no)"
printf 'scratch' > "$D/scratch"
sandbox_remove "$D"
check "a marked sandbox is removed" "no" "$([ -e "$D" ] && echo yes || echo no)"
check "removing a path that was never there is not an error" "0" "$(sandbox_remove "$D" >/dev/null 2>&1; echo $?)"

echo "--- a scratch directory inside a marked sandbox leaves no marker of its own ---"
SBROOT="$FIXTURE_ROOT/flea-guard-root-$$"
sandbox_make "$SBROOT"
sandbox_scratch "$SBROOT/case"
check "the scratch directory exists" "yes" "$([ -d "$SBROOT/case" ] && echo yes || echo no)"
check "and carries no marker, so a listing of it is exactly what the test put there" "0" \
  "$(ls -A "$SBROOT/case" | wc -l | tr -d ' ')"
printf 'x' > "$SBROOT/case/file"
sandbox_scratch "$SBROOT/case"
check "a second scratch empties it" "0" "$(ls -A "$SBROOT/case" | wc -l | tr -d ' ')"
sandbox_remove "$SBROOT/case"
check "and a scratch is removable, because its sandbox owns it" "no" "$([ -e "$SBROOT/case" ] && echo yes || echo no)"
scratch_refuses() { ( sandbox_scratch "$1" ) >/dev/null 2>&1 && echo no || echo yes; }
check "a scratch outside any marked sandbox is refused" "yes" "$(scratch_refuses "$FIXTURE_ROOT/flea-guard-orphan-$$")"
sandbox_remove "$SBROOT"

cache_refuses_early() { ( sandbox_cache_require "$1" ) >/dev/null 2>&1 && echo no || echo yes; }

# set -u catches an unset HOME, not an empty one, and every forbidden root is written from it.
echo "--- an empty or unset HOME is refused before any path is judged ---"
# With HOME empty the guard used to accept /.cache/thumbnails, which is what an unset variable
# turns every "$HOME/.cache/..." into.
empty_home_refuses() {
  ( export HOME=""; . ./tools/flea-sandbox-guard; sandbox_cache_require "/.cache/thumbnails" ) \
    >/dev/null 2>&1 && echo no || echo yes
}
check "an empty HOME is refused, not treated as no forbidden root" "yes" "$(empty_home_refuses)"
check "an unset HOME is refused too" "yes" \
  "$( ( unset HOME; . ./tools/flea-sandbox-guard; sandbox_cache_require "/.cache/thumbnails" ) >/dev/null 2>&1 && echo no || echo yes)"
check "and a real HOME still passes its own cache path" "no" "$(cache_refuses_early "$HOME/.cache/thumbnails")"

# A trailing slash made a path compare unequal to itself and made a parent match nothing. $HOME is
# the single entry covering ~/Work, ~/.config, ~/.local, ~/.cache and ~/tmp, and it is the one entry
# an environment can set, so a slash on it emptied the whole forbidden list.
echo "--- a trailing slash, on either side of any comparison ---"
check "a slashed parent still contains its child" "yes" \
  "$( ( . ./tools/flea-sandbox-guard; sandbox_under "/home/gm/Work" "/home/gm/" ) && echo yes || echo no)"
check "a slashed HOME is still refused as a fixture root" "yes" \
  "$( ( export HOME="/home/gm/"; export FLEA_FIXTURE_ROOT="/home/gm/Work"; . ./tools/flea-sandbox-guard; sandbox_root_ok ) >/dev/null 2>&1 && echo no || echo yes)"
check "the fixture root with a trailing slash is still the fixture root" "yes" \
  "$(refuses "$FIXTURE_ROOT/")"
check "and a real sandbox with a trailing slash is still allowed" "no" \
  "$(refuses "$FIXTURE_ROOT/flea-guard-slash-$$/")"

# HOME can be emptied after the guard is sourced, so the refusal cannot be source-time only.
echo "--- an empty HOME emptied at call time, not only at source time ---"
check "a require after HOME is emptied is refused" "yes" \
  "$( ( . ./tools/flea-sandbox-guard; HOME=""; sandbox_require "$FIXTURE_ROOT/x" ) >/dev/null 2>&1 && echo no || echo yes)"
check "a cache require after HOME is emptied is refused" "yes" \
  "$( ( . ./tools/flea-sandbox-guard; HOME=""; sandbox_cache_require "/.cache/thumbnails" ) >/dev/null 2>&1 && echo no || echo yes)"

# The marker check dereferences, so a sandbox reached through a symlink deletes somewhere else.
echo "--- a path that resolves through a symlink out of the root ---"
LINKROOT="$FIXTURE_ROOT/flea-guard-link-$$"
OUTSIDE="$FIXTURE_ROOT/flea-guard-outside-$$"
sandbox_make "$LINKROOT"
sandbox_make "$OUTSIDE"
ln -s "$OUTSIDE" "$LINKROOT/escape"
check "a sandbox inside the root is allowed" "no" "$(refuses "$LINKROOT/plain")"
# FIXTURE_ROOT is what the guard reads; FLEA_FIXTURE_ROOT only feeds it at source time.
check "but one reached through a symlink out of the root is refused" "yes" \
  "$( ( . ./tools/flea-sandbox-guard; FIXTURE_ROOT="$LINKROOT"; sandbox_require "$LINKROOT/escape/x" ) >/dev/null 2>&1 && echo no || echo yes)"
sandbox_remove "$LINKROOT"
sandbox_remove "$OUTSIDE"

# realpath -m collapses these too, which trailing-slash stripping never did: an interior // in HOME
# emptied the forbidden list exactly the way a trailing one did.
echo "--- an interior doubled slash, and a root that is validated before it is canonicalised ---"
check "an interior // in the parent still contains its child" "yes" \
  "$( ( . ./tools/flea-sandbox-guard; sandbox_under "/home/gm/Work" "/home//gm" ) && echo yes || echo no)"
check "and in the cache root too" "yes" \
  "$( ( . ./tools/flea-sandbox-guard; sandbox_under "/home/gm/.cache" "/home//gm" ) && echo yes || echo no)"
check "an interior // in HOME is still refused as a fixture root" "yes" \
  "$( ( export HOME="/home//gm"; export FLEA_FIXTURE_ROOT="/home/gm/Work"; . ./tools/flea-sandbox-guard; sandbox_root_ok ) >/dev/null 2>&1 && echo no || echo yes)"
# /home/ satisfies the depth test's second * with the empty string, so a raw check reads it as two
# components deep and passes a root the canonical form refuses.
check "a slashed top-level root is refused, not read as two components deep" "yes" \
  "$(root_refuses "/home/")"
check "and a path under it is refused with it" "yes" \
  "$( ( export FLEA_FIXTURE_ROOT="/home/"; . ./tools/flea-sandbox-guard; sandbox_require "/home/gm" ) >/dev/null 2>&1 && echo no || echo yes)"

# A check on the canonical form and an action on the raw one is not the same check.
echo "--- every action runs on the canonical path, not on what the caller typed ---"
SLASHROOT="$FIXTURE_ROOT/flea-guard-act-$$"
sandbox_make "$SLASHROOT"
printf 'keep' > "$SLASHROOT/keepme"
scratch_slash_refuses() { ( sandbox_scratch "$1" ) >/dev/null 2>&1 && echo no || echo yes; }
check "a scratch of the sandbox itself with a trailing slash is refused" "yes" "$(scratch_slash_refuses "$SLASHROOT/")"
check "and the sandbox still holds what it held" "keep" "$(cat "$SLASHROOT/keepme" 2>/dev/null)"
check "a scratch inside it with a trailing slash still works" "no" "$(scratch_slash_refuses "$SLASHROOT/case/")"
sandbox_remove "$SLASHROOT"

# An action must act on the path its own check cleared, not on whatever a later call left in a global.
# Through the ACTION, not through the helper. The previous version of this check called the helper
# directly, so it went red for the right reason while every real caller reached the refusal inside a
# command substitution, where an exit ends only the subshell and the caller carries on. A control
# that lands can still exercise the wrong path.
echo "--- an empty checked path stops the script, at the site an action reaches it from ---"
empty_path_stops_the_script() {
  ( . ./tools/flea-sandbox-guard
    sandbox_require "$FIXTURE_ROOT/flea-guard-empty-$$"
    # Emptied after the check, which is the shape a nested call would produce.
    SANDBOX_PATH=""
    sandbox_take
    echo REACHED-PAST-THE-REFUSAL ) 2>/dev/null
}
check "the script does not run on past it" "" "$(empty_path_stops_the_script)"
# The behaviour above is only reachable because the action takes the path by assignment. A refusal
# inside a command substitution prints and exits the SUBSHELL, so the caller runs on with an empty
# path, and no script sourcing this guard sets -e to stop it. Demonstrated, then asserted
# structurally, because the behavioural check above cannot see which form an action used.
refusing_in_a_substitution_does_not_stop_the_caller() {
  ( refuse_here() { echo "REFUSED: demo" >&2; exit 1; }
    taker() { refuse_here; printf 'never'; }
    p=$(taker 2>/dev/null)
    echo "CALLER-ALIVE-WITH-[$p]" )
}
check "a refusal inside a substitution does not stop its caller" "CALLER-ALIVE-WITH-[]" \
  "$(refusing_in_a_substitution_does_not_stop_the_caller)"
# Zero of the bad shape, rather than a count of the good one: a new action added later must fail
# this if it uses a substitution, and must not fail it merely for existing.
check "so no action takes the checked path through one" "0" \
  "$(grep -c 'sandbox_take)' tools/flea-sandbox-guard)"
check "and at least one action takes it by assignment" "yes" \
  "$([ "$(grep -c 'p=\$SANDBOX_TAKEN' tools/flea-sandbox-guard)" -ge 1 ] && echo yes || echo no)"
check "and a real path is taken unchanged" "$FIXTURE_ROOT/x" \
  "$( . ./tools/flea-sandbox-guard; SANDBOX_PATH="$FIXTURE_ROOT/x"; sandbox_take; printf '%s' "$SANDBOX_TAKEN" )"

# realpath resolves a .. away, so checking only the canonical form leaves the raw path's own
# defects unable to fire: the check has to see what the caller actually wrote.
echo "--- a path written with a parent traversal is refused on its raw form ---"
check "a sandbox reached through .. is refused" "yes" "$(refuses "$FIXTURE_ROOT/sb/../other")"
check "and one written plainly is not" "no" "$(refuses "$FIXTURE_ROOT/other")"
check "a relative path is still refused" "yes" "$(refuses "sb/../other")"

echo "--- the cache helper, which asserts a real path and never claims the cache is a sandbox ---"
cache_refuses() { ( sandbox_cache_require "$1" ) >/dev/null 2>&1 && echo no || echo yes; }
check "the cache root itself is refused" "yes" "$(cache_refuses "$HOME/.cache")"
check "and a cache path written with a parent traversal is refused on its raw form" "yes" \
  "$(cache_refuses "$HOME/.cache/thumbnails/../../.ssh")"
check "an empty cache path is refused" "yes" "$(cache_refuses "")"
check "a path outside the cache is refused" "yes" "$(cache_refuses "/etc/thumbnails")"
check "the real thumbnail cache is allowed" "no" "$(cache_refuses "$HOME/.cache/thumbnails")"

echo
if [ "$fail" = 0 ]; then echo "sandbox.sh: all checks passed"; else echo "sandbox.sh: FAILURES above"; fi
exit "$fail"
