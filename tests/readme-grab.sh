#!/usr/bin/env bash
# tests/ui.sh readme_grab against omarchy-drive doubles: a run root with no evidence directory keeps its settled grab and says why when it cannot.
set -u
cd "$(dirname "$0")/.." || exit 1

failed=0
ok() { printf 'ok   %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; failed=1; }

MARKER=.flea-test-sandbox
box=$(mktemp -d) || exit 1
: > "$box/$MARKER"
# A second marked root, outside the first, that a stand-in evidence_dir line points at.
other=$(mktemp -d) || exit 1
: > "$other/$MARKER"
# Removes only an absolute, non-empty root that still carries its marker.
cleanup() {
    local root
    for root in "$box" "$other"; do
        case $root in
            /?*) [ -f "$root/$MARKER" ] && rm -rf -- "$root" ;;
        esac
    done
}
trap cleanup EXIT

# The file whose evidence_dir line run() evaluates; a case swaps in a stand-in.
ui_src=tests/ui.sh

# A marked run root as ui.sh makes it, with no evidence directory, beside a marked stand-in source tree with no docs/images.
fresh_root() {
    mkdir -p "$box/$1/run" "$box/$1/source/src" || exit 1
    : > "$box/$1/run/$MARKER"
    : > "$box/$1/source/$MARKER"
}

# Sample input: run <run root> <hook>; ui.sh's own evidence_dir line runs with run_root set, before the cd into the sibling stand-in source tree, then the hook, and the output is the helper's own.
run() {
    (
        eval "$(sed -n '/^readme_grab()/,/^}/p' tests/ui.sh)"
        sleep() { :; }
        fail() { printf 'FAIL: %s\n' "$*"; exit 1; }
        omarchy-drive() { if [ "$1" = shot ]; then printf 'one settled grab\n' > "$2"; fi; return 0; }
        magick() { printf '2536 1386\n'; }
        run_root=$1 repo=${1%/run}/source readme_park_x=1 readme_park_y=1 readme_grab_tries=5
        eval "$(sed -n '/^evidence_dir=/p' "$ui_src")"
        [ -n "${evidence_dir:-}" ] || fail "$ui_src has no unindented evidence_dir= line, so the grab target is unknown"
        case $(realpath -m -- "$evidence_dir") in
            "$(realpath -- "$box")"/*) ;;
            *) fail "evidence_dir $evidence_dir resolves outside the stand-in root $box" ;;
        esac
        cd "$repo" || exit 1
        shift
        "$@"
        readme_grab grid.png flea
    )
}

fresh_root native
out=$(run "$box/native/run" true)
[ "$out" = 'README grid.png 2536x1386 tries=1' ] \
    && ok "a run root with no evidence directory keeps the settled grab" || bad "a fresh run root must keep the grab, got: $out"
[ -s "$box/native/run/evidence/grid.png" ] && [ ! -e "$box/native/run/readme-a.png" ] \
    && ok "the grab lands in the run root's evidence directory and leaves no scratch behind" || bad "the grab must land in run/evidence/grid.png"
[ ! -e "$box/native/source/docs" ] \
    && ok "the source tree gains no docs directory" || bad "the source tree must stay untouched"

fresh_root refused
out=$(run "$box/refused/run" eval "mv() { printf \"mv: cannot move 'a' to 'b': Permission denied\\nmv: second line\\n\" >&2; return 1; }")
want="FAIL: readme grid.png: could not keep the settled grab at $box/refused/run/evidence/grid.png, mv reported: mv: cannot move 'a' to 'b': Permission denied"
[ "$out" = "$want" ] \
    && ok "a refused move names the target and mv's first stderr line" || bad "a refused move must name its target, got: $out"

fresh_root blocked
: > "$box/blocked/run/evidence"
out=$(run "$box/blocked/run" true)
want="FAIL: readme grid.png: the evidence directory $box/blocked/run/evidence could not be created"
[ "$out" = "$want" ] \
    && ok "an evidence path that cannot be a directory names itself" || bad "an uncreatable evidence directory must name itself, got: $out"

# A hook that writes the evidence directory as a real readme_grab does, so a guard that runs late leaves a trace.
writes_evidence='mkdir -p "${evidence_dir:-$run_root/evidence}" && : > "${evidence_dir:-$run_root/evidence}/written"'

printf '    evidence_dir="$run_root/evidence"\n' > "$box/indented.sh"
fresh_root indented
out=$(ui_src=$box/indented.sh run "$box/indented/run" eval "$writes_evidence")
want="FAIL: $box/indented.sh has no unindented evidence_dir= line, so the grab target is unknown"
[ "$out" = "$want" ] && [ ! -e "$box/indented/run/evidence" ] \
    && ok "a ui.sh without an unindented evidence_dir line fails loud" || bad "a missing evidence_dir line must fail loud, got: $out"

printf 'evidence_dir=%s/evidence\n' "$other" > "$box/outside.sh"
fresh_root outside
out=$(ui_src=$box/outside.sh run "$box/outside/run" eval "$writes_evidence")
want="FAIL: evidence_dir $other/evidence resolves outside the stand-in root $box"
[ "$out" = "$want" ] && [ ! -e "$other/evidence" ] \
    && ok "an evidence_dir outside the stand-in root fails before anything is written" || bad "an outside evidence_dir must fail before a write, got: $out"

[ "$failed" = 0 ] || exit 1
printf 'READMEGRAB DONE\n'
