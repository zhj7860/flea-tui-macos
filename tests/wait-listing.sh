#!/usr/bin/env bash
# tests/ui.sh wait_listing against ipc doubles: a view scrolled past row 0 draws the cursor's row, and an undrawn listing never lands.
set -u
cd "$(dirname "$0")/.." || exit 1

failed=0
ok() { printf 'ok   %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; failed=1; }

# Sample input, ipc visibleRowName 101: "north-01.txt"; ipc rowAt 0: "loading", the list delegate columns and grid never build.
run() {
    (
        eval "$(sed -n '/^wait_listing()/,/^}/p' tests/ui.sh)"
        declare -F wait_listing > /dev/null || { printf 'FAIL: wait_listing is not defined by tests/ui.sh\n'; exit 1; }
        sleep() { :; }
        fail() { printf 'FAIL: %s\n' "$*"; exit 1; }
        ipc() {
            case "$1" in
                total) printf '%s\n' "$d_total" ;;
                rowAt) printf '%s\n' loading ;;
                cursor) printf '%s\n' "$d_cursor" ;;
                listInFlight) printf '%s\n' "$d_flight" ;;
                visibleRowName) if [ "$2" = 0 ]; then printf '%s\n' "$d_row0"; elif [ "$2" = "$d_cursor" ]; then printf '%s\n' "$d_rowc"; fi ;;
            esac
        }
        d_total=281 d_cursor=0 d_flight=false d_row0="" d_rowc=""
        "$@"
        wait_listing 281
        printf 'landed\n'
    )
}

out=$(run eval 'd_row0=sub')
[ "$out" = landed ] && ok "row 0 drawn at the top of the folder lands" || bad "row 0 drawn must land, got: $out"

out=$(run eval 'd_cursor=101 d_row0="" d_rowc=north-01.txt')
[ "$out" = landed ] && ok "a view scrolled past row 0 lands on the cursor's drawn row" || bad "the cursor's row drawn must land, got: $out"

out=$(run eval 'd_cursor=101 d_row0="" d_rowc=""')
[ "$out" = 'FAIL: listing did not reach total 281, got total=281 row=loading' ] \
    && ok "no row drawn at row 0 or the cursor never lands" || bad "an undrawn listing must fail, got: $out"

out=$(run eval 'd_row0=sub d_flight=true')
[ "$out" = 'FAIL: listing did not reach total 281, got total=281 row=sub|' ] \
    && ok "a drawn row with a listing still out never lands" || bad "a listing still out must fail, got: $out"

out=$(run eval 'd_total=70 d_row0=north-01.txt')
[ "$out" = 'FAIL: listing did not reach total 281, got total=70 row=north-01.txt|' ] \
    && ok "a drawn row under the wrong count never lands" || bad "a wrong count must fail, got: $out"

[ "$failed" = 0 ] || exit 1
printf 'WAITLISTING DONE\n'
