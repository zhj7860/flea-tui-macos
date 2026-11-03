# Whole-window shots of the states the button look items (L1 to L10) are judged from; sourced by ui.sh after the cohesion kit, whose openers and pointer helpers it reuses.

# Keyboard stops a walk takes at most before it counts the state missed.
b72_walk_limit=16
# The control index ipc pdfState reports while the Close mark holds the keyboard.
b72_pdf_close_control=5
# The Settings close mark sits this far in from the card's right edge (the header's rowPaddingX) and is twice this wide.
b72_row_pad_px=14
b72_mark_half_px=12
# Tab stops shot after the TLS row, polls and pause waiting for the video to load.
b72_tabs_after_tls=3
b72_video_polls=50
b72_video_settle_s=1

# A state the walk or the pointer never reached is counted, not shot; the surface fails at its end.
b72_miss() { b72_missed=$((b72_missed + 1)); printf 'B72_MISS %s %s\n' "$coh_theme" "$1"; }

# Sample manifest line: "b72-L4-permissions-close-rest-live<TAB>live<TAB>L4<TAB>permissions<TAB>close-rest", the sidecar being NAME.json.
b72_shot() {
    local item="$1" surface="$2" state="$3" name="b72-$1-$2-$3-$coh_theme" sidecar
    sidecar=$(ipc cohesionControls) && [[ -n "$sidecar" ]] || fail "b72: the reader gave no sidecar for $name"
    shot "$name"
    printf '%s\n' "$sidecar" > "$evidence_dir/$name.json"
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$coh_theme" "$item" "$surface" "$state" >> "$evidence_dir/b72-manifest.tsv"
}

# Sample input: {"controls":[{"kind":"ChromeButton","name":"Close permissions","x":1050,"y":10,"w":28,"h":28}]}
# The centre of the first reported control named NAME, "x y" in window pixels, or nothing.
b72_control_centre() {
    ipc cohesionControls | jq -r --arg name "$1" '[.controls[] | select(.name == $name)][0]
        | if . == null then "" else "\(.x + (.w / 2 | floor)) \(.y + (.h / 2 | floor))" end'
}

# Tab until the command answers WANT; a walk that never gets there stops at the limit and returns 1.
b72_tab_until() {
    local want="$1" k
    shift
    for ((k = 0; k < b72_walk_limit; k++)); do
        [[ "$("$@")" == "$want" ]] && { settle; return 0; }
        key -k Tab >/dev/null
        settle
    done
    printf 'B72_SOFT %s %s never answered %s\n' "$coh_theme" "$*" "$want"
    return 1
}

# Sample input: {"page":1,"control":5,"controls":[{"name":"Close","centre":"1040 20","hovered":false}]}, so this prints 5.
b72_pdf_control() { ipc pdfState true | jq -r .control; }

# Sample input: {"focus":{"kind":"ChromeButton","name":"Close permissions","via":"owner"},"controls":[...]}
# Tab until the cohesion reader's focused control is NAME.
b72_tab_to() {
    local name="$1" k
    for ((k = 0; k < b72_walk_limit; k++)); do
        ipc cohesionControls | jq -e --arg name "$name" '.focus.name == $name' >/dev/null 2>&1 && return 0
        key -k Tab >/dev/null
        settle
    done
    printf 'B72_SOFT %s Tab never reached %s\n' "$coh_theme" "$name"
    return 1
}

# Sample input: {"controls":[{"kind":"ChromeButton","x":1050,"y":10,"w":28,"h":28,"hoverable":true,"hovered":true,"pressable":true,"pressed":false}]}
# MediaStrip's play Item has a TapHandler but no hover effect; its hover shot requires the real exposed hit target after pointer_glide verified the pointer.
b72_flag_at() {
    local x="$1" y="$2" flag="$3" surface="$4" able=hoverable end=$((SECONDS + coh_wait_s))
    [[ "$flag" == pressed ]] && able=pressable
    while (( SECONDS < end )); do
        ipc cohesionControls | jq -e --argjson x "$x" --argjson y "$y" --arg flag "$flag" --arg able "$able" \
            '[.controls[] | select((.[$able] or ($flag == "hovered" and .kind == "MediaPlay" and .exposed))
                and .x <= $x and $x < .x + .w and .y <= $y and $y < .y + .h)]
                | length > 0 and any(.[]; .[$flag] or ($flag == "hovered" and .kind == "MediaPlay" and .exposed and (.hoverable | not)))' >/dev/null 2>&1 && return 0
        sleep "$coh_poll_s"
    done
    printf 'B72_SOFT %s %s: no %s control at %s,%s ever reported %s\n' "$coh_theme" "$surface" "$able" "$x" "$y" "$flag"
    return 1
}

# Hover and a held press on the window point X Y, released off the control so nothing acts; READS unread marks a control the reader never reports.
b72_hover_press() {
    local item="$1" surface="$2" x="$3" y="$4" press="${5:-press}" reads="${6:-read}"
    [[ "$x" =~ ^-?[0-9]+$ && "$y" =~ ^-?[0-9]+$ ]] || fail "b72: $item $surface has no pointer target, got [$x] [$y]"
    coh_pointer_to "$x" "$y"
    if [[ "$reads" == unread ]]; then
        printf 'B72_UNREAD %s %s %s hover at %s,%s is shot with no reader state to confirm it\n' "$coh_theme" "$item" "$surface" "$x" "$y"
    elif ! b72_flag_at "$x" "$y" hovered "$surface"; then
        b72_miss "$item $surface hover"; coh_park; return 0
    fi
    settle
    b72_shot "$item" "$surface" hover
    [[ "$press" == press ]] || { coh_park; return 0; }
    coh_held=1
    coh_ydotool click 0x40 || fail "b72: pointer press failed"
    if b72_flag_at "$x" "$y" pressed "$surface"; then
        settle
        b72_shot "$item" "$surface" press
    else
        b72_miss "$item $surface press"
    fi
    local moved=1
    coh_pointer_to "$coh_approach_px" "$((coh_win_h - coh_approach_px))" || moved=0
    coh_ydotool click 0x80 || fail "b72: pointer release failed"
    coh_held=0
    [ "$moved" = 1 ] || fail "b72: pointer move off the control failed, so the release landed on it"
    coh_park
}

# L1 and L8: the TLS row on WebDAV at rest, focused, unticked, then the Tab stops after it.
b72_network() {
    coh_launch "$list"
    coh_open_network
    click_chip WebDAV
    coh_park
    b72_shot L1 network tls-on-rest
    b72_tab_until TLS ipc networkFocus || { b72_miss "L1 network tls-on-focus"; return 0; }
    b72_shot L1 network tls-on-focus
    key -k space >/dev/null
    settle
    b72_shot L1 network tls-off-focus
    key -k space >/dev/null
    settle
    local k
    for ((k = 1; k <= b72_tabs_after_tls; k++)); do
        key -k Tab >/dev/null
        settle
        b72_shot L8 network "tab$k-after-tls"
    done
}

# L4: the Settings close mark at rest, under the pointer and after one Tab from the pane.
b72_settings() {
    local centre x y w h cy reads=read
    coh_launch "$list"
    coh_open_settings
    coh_park
    b72_shot L4 settings close-rest
    centre=$(b72_control_centre "Close settings")
    if [[ -z "$centre" ]]; then
        # The hand-built mark reports nothing, so it is found where it sits: the header's right edge, rowPaddingX in.
        # Sample input: ipc settingsCardRect answers "210 90 680 520" (x y w h) and settingsTitleCentre "550 118" (x y).
        read -r x y w h <<< "$(ipc settingsCardRect)"
        read -r _ cy <<< "$(ipc settingsTitleCentre)"
        [[ -n "$x" && -n "$w" && -n "$cy" ]] || fail "b72: the Settings card or its title reported no box"
        centre="$((x + w - b72_row_pad_px - b72_mark_half_px)) $cy"
        reads=unread
    fi
    b72_hover_press L4 settings-close $centre nopress "$reads"
    key -k Tab >/dev/null
    settle
    b72_shot L4 settings close-tab1
    key -k Tab >/dev/null
    settle
    b72_shot L4 settings close-tab2
}

# L4: the Permissions close mark at rest, under the pointer and focused by the Tab walk.
b72_permissions() {
    local centre
    coh_launch "$list"
    coh_open_permissions
    coh_park
    b72_shot L4 permissions close-rest
    centre=$(b72_control_centre "Close permissions")
    [[ -n "$centre" ]] || fail "b72: Permissions reports no close mark"
    b72_hover_press L4 permissions-close $centre nopress
    if b72_tab_to "Close permissions"; then b72_shot L4 permissions close-focus; else b72_miss "L4 permissions close-focus"; fi
}

# L4 and L6: Quick Look's PDF strip, the close mark at rest, hovered and focused, then Expand off and on.
b72_qlpdf() {
    local centre x y wx wy
    coh_launch "$list"
    coh_open_qlpdf
    coh_park
    b72_shot L4 ql-pdf close-rest
    centre=$(ipc pdfState true | jq -r '.controls[] | select(.name == "Close") | .centre')
    b72_hover_press L4 ql-pdf-close $centre nopress
    if b72_tab_until "$b72_pdf_close_control" b72_pdf_control; then b72_shot L4 ql-pdf close-focus; else b72_miss "L4 ql-pdf close-focus"; fi
    centre=$(ipc pdfState true | jq -r '.controls[] | select(.name == "Expand") | .centre')
    b72_shot L6 ql-pdf collapsed
    read -r x y <<< "$centre"
    read -r wx wy _ _ < <(window_box) || fail "b72: native window coordinates unavailable"
    omarchy-drive click "$((wx + x))" "$((wy + y))" left >/dev/null || fail "b72: Expand click failed"
    coh_park
    [[ "$(ipc previewExpanded)" == true ]] || printf 'B72_SOFT %s Quick Look did not expand\n' "$coh_theme"
    b72_shot L6 ql-pdf expanded
    centre=$(ipc pdfState true | jq -r '.controls[] | select(.name == "Expand") | .centre')
    b72_hover_press L6 ql-pdf-expand $centre nopress
}

# L5: the column preview's media strip on a video, at rest, play hovered and play held.
b72_media() {
    local centre k
    coh_launch "$cols"
    seek_row_named clip.mp4 || fail "b72: no clip.mp4 row"
    for ((k = 0; k < b72_video_polls; k++)); do
        [[ "$(ipc previewColumnState)" == video ]] && break
        sleep "$coh_poll_s"
    done
    [[ "$(ipc previewColumnState)" == video ]] || fail "b72: the column never showed the video"
    sleep "$b72_video_settle_s"
    coh_park
    b72_shot L5 cols-video strip-rest
    centre=$(ipc columnPlayCentre)
    [[ -n "$centre" ]] || fail "b72: the column shows no media strip"
    b72_hover_press L5 cols-video-play $centre
}

# Holds the owned backend so a commit stays in flight; b72_held is the surface subshell's own, read by its EXIT trap.
b72_hold_backend() {
    local -a pids
    mapfile -t pids < <(backend_pids)
    [[ "${#pids[@]}" == 1 ]] || fail "b72: a held commit needs one owned backend"
    b72_held="${pids[0]}"
    permissions_listing="$coh_dir"
    convert_pause_backend "$b72_held"
}

b72_release_backend() {
    [[ -n "${b72_held:-}" ]] || return 0
    # A held request never runs: the owned backend dies stopped, so no conversion or launch reaches the box.
    permissions_backend_owned "$b72_held" && kill -KILL "$b72_held"
    b72_held=""
    kill_flea
}

# L7: Convert at rest, then mid-commit with its backend held.
b72_convert() {
    b72_held=""
    trap 'b72_release_backend; coh_release_held' EXIT
    coh_launch "$list"
    coh_open_convert
    menus_expect convertState '.canConvert' "b72: Convert is ready to commit"
    coh_park
    b72_shot L7 convert rest
    b72_hold_backend
    menus_control convertState Convert
    menus_expect convertState '.busy' "b72: the held conversion is in flight"
    coh_park
    b72_shot L7 convert busy
}

# L7: Open with at rest, then mid-launch with its backend held.
b72_openwith() {
    b72_held=""
    trap 'b72_release_backend; coh_release_held' EXIT
    coh_launch "$list"
    coh_open_openwith
    menus_expect openWithState 'any(.controls[]; .name == "Open" and .enabled)' "b72: Open with has an application"
    coh_park
    b72_shot L7 openwith rest
    b72_hold_backend
    menus_control openWithState Open
    menus_expect openWithState '.committing' "b72: the held launch is in flight"
    coh_park
    b72_shot L7 openwith busy
}

# L10: the main window at rest and after one and two Tabs from the list.
b72_main() {
    coh_launch "$list"
    coh_park
    b72_shot L10 main rest
    key -k Tab >/dev/null
    settle
    b72_shot L10 main tab1
    key -k Tab >/dev/null
    settle
    b72_shot L10 main tab2
}

# A surface fails when a step fails or a state was missed; the subshell keeps errexit on, which an if-condition subshell would mask.
b72_run_surface() {
    b72_missed=0
    "$@"
    (( b72_missed == 0 )) || fail "b72: $1 never reached $b72_missed states"
}

b72_surface() {
    local status=0 errexit=0
    [[ $- == *e* ]] && errexit=1
    set +e
    ( set -e; coh_held=0; trap coh_release_held EXIT; b72_run_surface "$@" ) < /dev/null
    status=$?
    if (( errexit )); then set -e; fi
    (( status == 0 )) && return 0
    printf 'B72_FAILED %s %s\n' "$coh_theme" "$1"
    b72_failed+=" $coh_theme/$1"
}

# The picker is the portal's own process, so its states run in Python against the picker's IPC. Each run takes a fresh root, so no picker state carries over.
b72_picker() {
    local home status=0
    home=$(coh_home "$coh_theme")
    FLEA_BIN="$flea_bin" FLEA_UI="$flea_ui" timeout 240 python3 "$repo/tests/ui-captures-b72-picker.py" \
        "$fixture_root/coh-$coh_theme/b72-picker-$RANDOM$RANDOM" "$home" "$evidence_dir" "$coh_theme" < /dev/null || status=$?
    (( status == 0 )) && return 0
    printf 'B72_FAILED %s picker status %s\n' "$coh_theme" "$status"
    b72_failed+=" $coh_theme/picker"
}

# B72_THEMES and B72_SURFACES narrow a run to fit a minipc slot; both default to everything.
case_cap_b72() {
    local coh_dir="$fixture_root/b72" coh_theme b72_failed="" live_foreground="$real_foreground" menus_checks=0 s
    local list='{"keys":"default","view":"list","menu":{"hidden":[]}}'
    local cols='{"keys":"default","view":"columns","columnsLimit":3,"preview":{"column":true,"loadOn":"automatic"},"menu":{"hidden":[]}}'
    local themes="${B72_THEMES:-live gruvbox kanagawa}" want="${B72_SURFACES:-all}"
    local flea_ui
    flea_ui=$(coh_capture_ui) || fail "b72: the UI fixture could not be prepared"
    coh_fixture "$coh_dir"
    ffmpeg -y -f lavfi -i "testsrc=duration=15:size=320x180:rate=10" "$coh_dir/clip.mp4" >/dev/null 2>&1
    [[ -s "$coh_dir/clip.mp4" ]] || fail "b72: ffmpeg produced no clip.mp4"
    mkdir -p "$evidence_dir" || fail "b72: the evidence directory could not be created"
    : > "$evidence_dir/b72-manifest.tsv"
    for coh_theme in $themes; do
        for s in network settings permissions qlpdf media convert openwith main picker; do
            [[ "$want" == all || " $want " == *" $s "* ]] || continue
            kill_flea
            if [[ "$s" == picker ]]; then b72_picker; else b72_surface "b72_$s"; fi
        done
        kill_flea
        real_foreground="$live_foreground"
    done
    printf 'CAP_B72 shots=%s failed=%s\n' "$(wc -l < "$evidence_dir/b72-manifest.tsv")" "${b72_failed:-none}"
    [[ -z "$b72_failed" ]] || fail "b72: surfaces failed:$b72_failed"
}

case_cap_b72_live() { B72_THEMES=live case_cap_b72; }
case_cap_b72_gruvbox() { B72_THEMES=gruvbox case_cap_b72; }
case_cap_b72_kanagawa() { B72_THEMES=kanagawa case_cap_b72; }
