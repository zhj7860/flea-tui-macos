#!/usr/bin/env bash
# tests/ui-captures-filter.sh resizes every column limit to a window whose pane draws that many columns, driven with the native steps stubbed.
set -u
cd "$(dirname "$0")/.." || exit 1

failed=0
ok() { printf 'ok   %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; failed=1; }

# Sample input, ui/js/Columns.js: var COUNT_4_AT = 1700
narrow_at=$(sed -n 's/^var COUNT_NARROW_AT = \([0-9][0-9]*\)$/\1/p' ui/js/Columns.js)
four_at=$(sed -n 's/^var COUNT_4_AT = \([0-9][0-9]*\)$/\1/p' ui/js/Columns.js)
five_at=$(sed -n 's/^var COUNT_5_AT = \([0-9][0-9]*\)$/\1/p' ui/js/Columns.js)
# Sample input, ui/js/Places.js: var WIDTH_STOPS = [160, 192, 224, 256]
sidebar_max=$(sed -n 's/^var WIDTH_STOPS = \[.*, \([0-9][0-9]*\)\]$/\1/p' ui/js/Places.js)
[ -n "$narrow_at" ] && [ -n "$four_at" ] && [ -n "$five_at" ] && [ -n "$sidebar_max" ] \
    || { bad "the column thresholds or the widest sidebar could not be read"; exit 1; }

fixture_root=/nonexistent
. tests/ui-captures-filter.sh
widths=() counts=()
for stub in cap_filter_pin cap_filter_slash_ap cap_filter_slash_nomatch cap_filter_search_ap cap_filter_search_nomatch cap_filter_escape cap_filter_empty seed_ui_state launch wait_listing kill_flea; do
    eval "$stub() { :; }"
done
cap_resize() { widths+=("$1"); }
sweep_wait() { [ "$1" = columnCount ] && counts+=("$2"); return 0; }
for n in 2 3 4 5; do cap_filter_columns /nonexistent "$n"; done
cap_filter_empties /nonexistent

[ "${#widths[@]}" = 8 ] && [ "${#counts[@]}" = 8 ] \
    && ok "four column limits and four empty-folder limits each resized once" || bad "expected 8 resizes and 8 column counts, got ${#widths[@]} and ${#counts[@]}"

for i in "${!counts[@]}"; do
    n=${counts[$i]}
    case "$n" in 2) need=0 ;; 3) need=$narrow_at ;; 4) need=$four_at ;; 5) need=$five_at ;; esac
    pane=$((${widths[$i]} - sidebar_max))
    (( pane >= need )) \
        && ok "limit $n resizes to ${widths[$i]} px, a pane of at least $pane px against $need" \
        || bad "limit $n resizes to ${widths[$i]} px, a pane of $pane px at the widest sidebar, short of the $need px that draws $n columns"
done

[ "$failed" = 0 ] || exit 1
printf 'CAPFILTERWIDTH DONE\n'
