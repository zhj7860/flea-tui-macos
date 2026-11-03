#!/usr/bin/env bash
# Compositor-free proof that permissions_point fails closed and permissions_menu_point reveals a clipped menu row before it clicks.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

test_root=$(mktemp -d "$FIXTURE_ROOT/flea-permpoint-XXXXXX") || exit 1
case $test_root in
  /*/*) ;;
  *) echo "FAIL: mktemp -d gave '$test_root', which is not an absolute path two components deep"; exit 1 ;;
esac
sandbox_require "$test_root" || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

clicks="$test_root/clicks.log"
fail() { printf 'PERMPOINT FAILED %s\n' "$*" >&2; exit 1; }
. tests/ui-permissions.sh
assert_focus() { return 0; }
settle() { return 0; }
omarchy-drive() { printf '%s\n' "$*" >> "$clicks"; }
win="0 0 1100 800"
window_box() { printf '%s\n' "$win"; }
# A 9-row file menu: row 4 is a separator, row 5 is a refused (disabled) row, the rest answer the cursor.
fake_model='[{"action":"a"},{"action":"b"},{"action":"c"},{"action":"d"},{"separator":true},{"action":"permissions","disabled":true},{"action":"e"},{"action":"permissions","disabled":false},{"action":"f"}]'
fake_cursor=0
fake_frame="600 50 200 700"
ipc() {
    case "$1" in
        windowSize) printf '1100 800\n' ;;
        contextMenuModel) printf '%s\n' "$fake_model" ;;
        contextMenuCursor) printf '%s\n' "$fake_cursor" ;;
        contextMenuRect) printf '%s\n' "$fake_frame" ;;
        # The body scrolls once the cursor passes row 3, which is what brings a row that sits below the window into the frame.
        contextMenuRowCentre) if (( fake_cursor >= 3 )); then printf '700 %s\n' $((300 + $2 * 10)); else printf '768 %s\n' $((800 + $2 * 3)); fi ;;
        *) return 1 ;;
    esac
}
key() {
    [[ "${STUCK:-0}" == 1 ]] && return 0
    case "$2" in
        Down) fake_cursor=$((fake_cursor + 1)); while [[ "$fake_cursor" == 4 || "$fake_cursor" == 5 ]]; do fake_cursor=$((fake_cursor + 1)); done ;;
        Up) fake_cursor=$((fake_cursor - 1)); while [[ "$fake_cursor" == 4 || "$fake_cursor" == 5 ]]; do fake_cursor=$((fake_cursor - 1)); done ;;
    esac
}
expect_fail() {
    local label="$1" want="$2" out
    shift 2
    out=$("$@" 2>&1) && fail "$label: the call succeeded"
    [[ "$out" == *"$want"* ]] || fail "$label: wrong refusal: $out"
    printf 'PERMPOINT PASS %s\n' "$label"
}

# A window size that is not a number must refuse, never click.
: > "$clicks"
# A name is read as a variable (unset under set -u aborts, else 0), and a malformed number is an arithmetic error that skips an unguarded if.
win="0 0 11x00 800"
expect_fail "a malformed window width refuses" "outside the actual viewport" permissions_point "10 10"
win="0 0 1100 8+"
expect_fail "a malformed window height refuses" "outside the actual viewport" permissions_point "10 10"
win="0 0 wide 800"
expect_fail "a non-numeric window width refuses" "outside the actual viewport" permissions_point "10 10"
win="0 0 1100"
expect_fail "a missing window height refuses" "outside the actual viewport" permissions_point "10 10"
win="0 0 1100 800"
expect_fail "a centre 21 px below the scene refuses" "centre 768,821 is outside the actual viewport 1100x800" permissions_point "768 821"
[[ ! -s "$clicks" ]] || fail "a refused point still clicked: $(cat "$clicks")"
permissions_point "700 400" || fail "a centre inside the window was refused"
[[ "$(cat "$clicks")" == "click 700 400 left" ]] || fail "the click was not delivered: $(cat "$clicks")"
printf 'PERMPOINT PASS an in-window centre clicks once\n'

# The row below the window at the cursor's first row is the Permissions row of the red run.
fake_cursor=0
expect_fail "the unrevealed row refuses, as on the red run" "centre 768,821 is outside" permissions_point "$(ipc contextMenuRowCentre 7)"
: > "$clicks"
fake_cursor=0
permissions_menu_point 7 || fail "an enabled row was not revealed"
[[ "$fake_cursor" == 7 ]] || fail "the cursor ended on $fake_cursor, not on row 7"
[[ "$(cat "$clicks")" == "click 700 370 left" ]] || fail "the revealed row was not clicked: $(cat "$clicks")"
printf 'PERMPOINT PASS an enabled row is revealed by the cursor, then clicked in the frame\n'
# A refused row cannot take the cursor, so the nearest reachable row reveals it.
: > "$clicks"
fake_cursor=0
permissions_menu_point 5 || fail "a refused row was not revealed"
[[ "$fake_cursor" == 6 ]] || fail "the cursor ended on $fake_cursor, not on the nearest reachable row 6"
[[ "$(cat "$clicks")" == "click 700 350 left" ]] || fail "the refused row was not clicked: $(cat "$clicks")"
printf 'PERMPOINT PASS a refused row is revealed through its nearest reachable neighbour\n'
# A cursor that never advances cannot reach its row, so the menu refuses instead of clicking.
: > "$clicks"
fake_cursor=0
STUCK=1
expect_fail "a stuck menu cursor refuses" "menu cursor stalled at" permissions_menu_point 7
STUCK=0
[[ ! -s "$clicks" ]] || fail "a stalled cursor still clicked: $(cat "$clicks")"
# A revealed row that still sits outside the frame is a clipped row, and it refuses.
fake_cursor=0
fake_frame="600 50 200 200"
expect_fail "a row clipped outside the menu frame refuses" "clipped outside the menu frame" permissions_menu_point 7
