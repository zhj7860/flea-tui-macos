#!/usr/bin/env bash
# Native capture of Grid hover on one tile's icon, caption and bare cell margin; sourced by ui.sh.
# shellcheck disable=SC2154 # ui.sh supplies the fixture root, the native driver and the shared helpers.

# Parks the pointer off the grid, then moves to a window point with the pointer-frame nudge the scroll case uses, and settles.
gridhover_move() {
    local label="$1" wx="$2" wy="$3" px="$4" py="$5" x="$6" y="$7"
    hypr_cursor_move "$((wx + px - hypr_pointer_frame_offset))" "$((wy + py))" || fail "gridhover: $label: parking the pointer failed"
    YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket" ydotool mousemove -x 1 -y 0 >/dev/null 2>&1
    settle
    hypr_cursor_move "$((wx + x - hypr_pointer_frame_offset))" "$((wy + y))" || fail "gridhover: $label: pointer motion failed"
    YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket" ydotool mousemove -x 1 -y 0 >/dev/null 2>&1
    settle
}

# One tile of the second row, hovered on its icon, its caption and its bare margin, a whole-window shot at each; the hover values differ by build and are only printed.
case_cap_gridhover() {
    local dir state wx wy ww wh index first tile row_x row_y row_w row_h
    local icon_x icon_y icon_w icon_h lines text_h slot_h bottom caption_y
    local icon_at_x icon_at_y caption_at_x caption_at_y margin_at_x margin_at_y
    local icon_hover caption_hover margin_hover name
    dir="$fixture_root/cap-gridhover"
    sandbox_scratch "$dir"
    for ((index = 1; index <= 12; index++)); do
        printf -v name '%s/file%02d.txt' "$dir" "$index"
        : > "$name"
    done
    seed_ui_state "$fixture_root/cap-gridhover-state" '{"view":"grid"}'
    launch "$dir"
    wait_listing 12
    cap_resize 1100 700
    settle
    [[ "$(ipc viewMode)" == "grid" ]] || fail "gridhover: opened in $(ipc viewMode), not grid"
    [[ "$(ipc cursor)" == "0" ]] || fail "gridhover: the cursor is on tile $(ipc cursor), not the first"
    read -r wx wy ww wh < <(window_box) || fail "gridhover: native window coordinates unavailable"
    # Sample input, rowRect 0 prints "14 100 118 128": the window x, y, width and height of tile 0.
    read -r _ first _ _ <<< "$(ipc rowRect 0)"
    [[ "$first" =~ ^[0-9]+$ ]] || fail "gridhover: tile 0 has no row rectangle: '$first'"
    tile=-1
    for ((index = 1; index < 12; index++)); do
        read -r _ row_y _ _ <<< "$(ipc rowRect "$index")"
        if [[ "$row_y" =~ ^[0-9]+$ ]] && (( row_y > first )); then tile=$index; break; fi
    done
    (( tile > 0 )) || fail "gridhover: no tile of the second row among 12 files"
    read -r row_x row_y row_w row_h <<< "$(ipc rowRect "$tile")"
    # Sample input, rowThumbRect 5 prints "30 250 64 64": the window x, y, width and height of tile 5's icon box.
    read -r icon_x icon_y icon_w icon_h <<< "$(ipc rowThumbRect "$tile")"
    [[ "$icon_x $icon_y $icon_w $icon_h" =~ ^[0-9]+\ [0-9]+\ [0-9]+\ [0-9]+$ ]] || fail "gridhover: tile $tile has no icon box: '$icon_x $icon_y $icon_w $icon_h'"
    # Sample input, gridCaptionState: {"name":"file05.txt","lines":1,"truncated":false,"textHeight":17,"slotHeight":34,"bottom":116,"tileHeight":128}.
    read -r lines text_h slot_h bottom < <(ipc gridCaptionState "$tile" | jq -er '[.lines, .textHeight, .slotHeight, .bottom] | map(floor) | @tsv') \
        || fail "gridhover: tile $tile has no caption state"
    (( lines >= 1 && text_h > 0 )) || fail "gridhover: tile $tile caption paints no line"
    caption_y=$((row_y + bottom - slot_h))
    icon_at_x=$((icon_x + icon_w / 2))
    icon_at_y=$((icon_y + icon_h / 2))
    caption_at_x=$((row_x + row_w / 2))
    caption_at_y=$((caption_y + text_h / lines / 2))
    margin_at_x=$(((row_x + icon_x) / 2))
    margin_at_y=$icon_at_y
    (( icon_x - row_x >= 4 )) || fail "gridhover: tile $tile has no margin left of the icon box"
    (( margin_at_x > row_x && margin_at_x < icon_x && margin_at_y >= icon_y && margin_at_y < icon_y + icon_h )) \
        || fail "gridhover: the margin point is not inside the cell and outside the icon box"
    (( caption_at_y >= icon_y + icon_h && caption_at_y < caption_y + text_h && caption_at_y < row_y + row_h )) \
        || fail "gridhover: the caption point is not on the first caption line"
    (( margin_at_y < caption_y )) || fail "gridhover: the margin point reaches the caption"

    gridhover_move icon "$wx" "$wy" "$((ww / 2))" 4 "$icon_at_x" "$icon_at_y"
    icon_hover=$(ipc rowHovered "$tile")
    printf 'ipc rowHovered %s %s\n' "$tile" "$icon_hover"
    shot gridhover-icon
    gridhover_move caption "$wx" "$wy" "$((ww / 2))" 4 "$caption_at_x" "$caption_at_y"
    caption_hover=$(ipc rowHovered "$tile")
    printf 'ipc rowHovered %s %s\n' "$tile" "$caption_hover"
    shot gridhover-caption
    gridhover_move margin "$wx" "$wy" "$((ww / 2))" 4 "$margin_at_x" "$margin_at_y"
    margin_hover=$(ipc rowHovered "$tile")
    printf 'ipc rowHovered %s %s\n' "$tile" "$margin_hover"
    shot gridhover-margin
    printf 'CAP_GRIDHOVER tile=%s icon=%s caption=%s margin=%s\n' "$tile" "$icon_hover" "$caption_hover" "$margin_hover"
    kill_flea
}
