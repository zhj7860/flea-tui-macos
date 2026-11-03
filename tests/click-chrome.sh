#!/usr/bin/env bash
# tests/ui.sh click_chrome against ipc doubles: a chrome button that is not visible is refused before any click, a visible one is clicked at its centre.
set -u
cd "$(dirname "$0")/.." || exit 1

failed=0
ok() { printf 'ok   %s\n' "$*"; }
bad() { printf 'FAIL %s\n' "$*"; failed=1; }

# Sample input, ipc chromeButtonState filter in List: {"name":"filter","visible":false,"enabled":true,"focused":false,"hovered":false,"pressed":false,"centre":"1180 14","rect":"1166 0 28 28"}; ipc chromeButtonCentre filter: "1180 14"; window_box: "100 50 1320 820".
# The omarchy-drive double prints the click it receives on stderr, which the caller folds into its output.
run() {
    (
        eval "$(sed -n '/^click_chrome()/,/^}/p' tests/ui.sh)"
        fail() { printf 'FAIL: %s\n' "$*"; exit 1; }
        ipc() {
            case "$1" in
                chromeButtonState)
                    # ui/Ipc.qml controlState: an unknown glyph answers its own name, visible false, enabled false, and "" for centre and rect.
                    if [ -n "$d_reply" ]; then printf '%s\n' "$d_reply"; else
                        jq -nc --arg name "$2" --argjson visible "$d_visible" --arg centre "$d_centre" \
                            '{name: $name, visible: $visible, enabled: ($centre != ""), focused: false, hovered: false, pressed: false, centre: $centre, rect: (if $centre == "" then "" else "1166 0 28 28" end)}'
                    fi
                    return "$d_status" ;;
                chromeButtonCentre) printf '%s\n' "$d_centre" ;;
            esac
        }
        window_box() { printf '100 50 1320 820\n'; }
        omarchy-drive() { printf 'CLICK %s\n' "$*" >&2; }
        d_visible=true d_centre="" d_reply="" d_status=0
        "$@"
        click_chrome "$glyph"
        printf 'returned\n'
    ) 2>&1
}

out=$(run eval 'glyph=filter d_visible=true d_centre="640 14"')
[ "$out" = $'CLICK click 740 64\nreturned' ] \
    && ok "a visible button is clicked at its centre in window coordinates" || bad "a visible button must be clicked once, got: $out"

out=$(run eval 'glyph=filter d_visible=false d_centre="1180 14"')
[ "$out" = 'FAIL: the chrome button filter is not visible in this view, so a click on it would land on another control' ] \
    && ok "a hidden button is refused before any click" || bad "a hidden button must be refused with no click, got: $out"

out=$(run eval 'glyph=search d_visible=false d_centre="640 14"')
[ "$out" = 'FAIL: the chrome button search is not visible in this view, so a click on it would land on another control' ] \
    && ok "the refusal names the glyph it was given" || bad "the refusal must name search, got: $out"

out=$(run eval 'glyph=search d_visible=true d_centre="1180 14"')
[ "$out" = $'CLICK click 1280 64\nreturned' ] \
    && ok "the visible Search button of List is clicked" || bad "the visible Search button must be clicked, got: $out"

out=$(run eval 'glyph=nosuch d_visible=false d_centre=""')
[ "$out" = 'FAIL: the chrome has no button called nosuch' ] \
    && ok "an unknown glyph is still named as missing" || bad "an unknown glyph must be named as missing, got: $out"

out=$(run eval 'glyph=filter d_visible=true d_centre="640 14" d_status=1')
[ "$out" = 'FAIL: the chrome button filter could not be read, ipc answered: '"$(jq -nc '{name: "filter", visible: true, enabled: true, focused: false, hovered: false, pressed: false, centre: "640 14", rect: "1166 0 28 28"}')" ] \
    && ok "an ipc that exits non-zero is a failed read, however well formed its reply" || bad "a failing ipc must be refused before any click, got: $out"

out=$(run eval 'glyph=filter d_reply="Error: no such function"')
[ "$out" = 'FAIL: the chrome button filter could not be read, ipc answered: Error: no such function' ] \
    && ok "an error text printed with exit 0 is a failed read" || bad "an error text with exit 0 must be a failed read, got: $out"

out=$(run eval 'glyph=filter d_reply=null')
[ "$out" = 'FAIL: the chrome button filter could not be read, ipc answered: null' ] \
    && ok "a null reply is a failed read" || bad "a null reply must be a failed read, got: $out"

out=$(run eval 'glyph=nosuch d_reply="{}"')
[ "$out" = 'FAIL: the chrome has no button called nosuch' ] \
    && ok "an object with no centre names the button as missing, never as hidden" || bad "an object with no centre must be named as missing, got: $out"

[ "$failed" = 0 ] || exit 1
printf 'CLICKCHROME DONE\n'
