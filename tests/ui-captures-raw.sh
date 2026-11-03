# Raw.html and Properties040 captures, sourced by ui.sh and run only by name on the native display.

readonly cap_raw_name=L1000921.DNG
readonly cap_raw_photo='{"make":"Canon","model":"Canon EOS R6","lens":"RF35mm F1.8 MACRO IS STM","exp":[1,250],"fnum":[28,10],"iso":400,"focal":[35,1],"taken":"2026:09:12 18:31:00","w":6000,"h":4000}'
readonly cap_raw_photo_rows='Camera=Canon EOS R6|Lens=RF35mm F1.8 MACRO IS STM|Exposure=1/250 s · f/2.8 · ISO 400|Focal=35 mm|Pixels=6000 × 4000|Taken=2026-09-12 18:31'
# Match Raw.html's caption band, whose height is Theme.chromeHeight.
readonly cap_raw_caption_height=27
# Cache misses can start the native thumbnail worker, so every readiness wait has a 30-second bound.
readonly cap_raw_wait_s=30

cap_raw_cleanup() {
    kill_flea || return 1
    [[ -n "$cap_raw_root" && "$cap_raw_root" == /* && -f "$cap_raw_root/$SANDBOX_MARKER" ]] \
        || fail "raw: the fixture cleanup lost its marked absolute root"
    sandbox_remove "$cap_raw_root"
}

cap_raw_fixture() {
    local mode="$1" name
    sandbox_require "$fixture_root/cap-raw"
    cap_raw_root=$(mktemp -d "$fixture_root/cap-raw.XXXXXXXX") || fail "raw: cannot create fixture sandbox"
    [[ -n "$cap_raw_root" && "$cap_raw_root" == /* ]] || fail "raw: fixture root is not absolute"
    : > "$cap_raw_root/$SANDBOX_MARKER"
    trap cap_raw_cleanup EXIT
    mkdir -p "$cap_raw_root"/{raw,cache,state}
    : > "$cap_raw_root/raw/$SANDBOX_MARKER"
    python3 -B "$repo/tests/fixtures/raw/generate.py" "$cap_raw_root/raw" || fail "raw: DNG generation failed"
    (cd "$cap_raw_root/raw" && sha256sum --check "$repo/tests/fixtures/raw/SHA256SUMS") \
        || fail "raw: generated DNG hash differs"
    if [[ "$mode" == grid ]]; then
        for name in _DSF4471.DNG DSC_2210.DNG IMG_0412.DNG P1030044.DNG; do
            cp --reflink=auto --no-clobber "$cap_raw_root/raw/$cap_raw_name" "$cap_raw_root/raw/$name" \
                || fail "raw: cannot populate $name"
        done
    fi
    # UTC is local to the launched case, so Modified has the board's exact text in every session timezone.
    TZ=UTC touch -d '2026-09-18 20:10:00' "$cap_raw_root/raw/"*.DNG || fail "raw: cannot stamp the fixture"
    export TZ=UTC LC_ALL=C.UTF-8 XDG_CACHE_HOME="$cap_raw_root/cache"
}

cap_raw_launch() {
    local mode="$1" total=1 view=columns wx wy ww wh
    [[ "$mode" != grid ]] || { view=grid; total=5; }
    cap_raw_fixture "$mode"
    seed_ui_state "$cap_raw_root/state" '{"keys":"default","view":"'"$view"'","columnsLimit":2,"display":{"textSize":{"mode":14}},"previewFacts":"full","preview":{"column":true,"loadOn":"automatic","thumbSize":"medium"},"menu":{"hidden":[]}}'
    launch "$cap_raw_root/raw"
    wait_listing "$total"
    if [[ "$mode" == grid ]]; then cap_resize 1000 514
    else cap_resize 1100 700; fi
    cap_raw_still
    read -r wx wy ww wh < <(window_box) || fail "raw: cannot park the pointer off the native window"
    pointer_glide "$((wx + ww / 2))" "$((wy - 1))" || fail "raw: cannot clear the native hover"
    settle
    menus_expect bodyPx '. == 14' "RAW capture uses the board's body text size"
    [[ "$(ipc viewMode)" == "$view" ]] || fail "raw: the requested view did not land"
    [[ "$mode" == grid ]] || seek_row_named "$cap_raw_name"
}

# The centring move can finish after cap_resize has established the size.
cap_raw_still() {
    local previous="" box="" deadline=$((SECONDS + cap_raw_wait_s))
    while (( SECONDS < deadline )); do
        box=$(window_box) || fail "raw: cannot observe the native window"
        [[ -n "$previous" && "$box" == "$previous" ]] && return
        previous="$box"
        sleep 0.2
    done
    fail "raw: the native window did not settle: $box"
}

cap_raw_wait() {
    local observer="$1" want="$2" label="$3" observed="" deadline=$((SECONDS + cap_raw_wait_s))
    shift 3
    while (( SECONDS < deadline )); do
        observed=$(ipc "$observer" "$@") || fail "raw: cannot read $observer"
        [[ "$observed" == "$want" ]] && return
        sleep 0.05
    done
    fail "raw: $label: expected [$want], observed [$observed]"
}

# Geometry comes from the drawn item and scales to the whole-window screenshot's actual pixels.
cap_raw_crop() {
    local shot_name="$1" crop_name="$2" rect="$3" x y w h wx wy ww wh pw ph destination
    read -r x y w h <<< "$rect"
    [[ "$rect" =~ ^[0-9]+\ [0-9]+\ [0-9]+\ [0-9]+$ && "$w" -gt 0 && "$h" -gt 0 ]] \
        || fail "raw: $crop_name has no positive rectangle: [$rect]"
    read -r wx wy ww wh < <(window_box) || fail "raw: native window rectangle is unavailable"
    (( x + w <= ww && y + h <= wh )) || fail "raw: $crop_name lies outside the owned window"
    read -r pw ph < <(magick identify -format '%w %h\n' "$evidence_dir/$shot_name.png")
    [[ "$pw $ph" =~ ^[0-9]+\ [0-9]+$ ]] || fail "raw: cannot read the whole-window shot's size"
    x=$((x * pw / ww)); y=$((y * ph / wh))
    w=$((w * pw / ww)); h=$((h * ph / wh))
    (( w > 0 && h > 0 )) || fail "raw: $crop_name scales to an empty crop"
    destination="$evidence_dir/$crop_name.png"
    [[ ! -e "$destination" && ! -L "$destination" ]] || fail "raw: refusing existing crop $destination"
    magick "$evidence_dir/$shot_name.png" -crop "${w}x${h}+${x}+${y}" +repage "$destination" \
        || fail "raw: $crop_name could not be cropped"
    [[ -s "$destination" ]] || fail "raw: $crop_name is empty"
    printf 'CROP %s\n' "$destination"
}

cap_raw_columns_ready() {
    local size expected
    cap_raw_wait columnThumbShown true "the DNG's embedded preview thumbnail is drawn"
    cap_raw_wait columnFrameReady true "the DNG's preview frame is decoded"
    cap_raw_wait previewColumnState image "the DNG is shown as an image"
    menus_expect previewSelectionState ".inlineVisible and (.path | endswith(\"/$cap_raw_name\"))" "the preview belongs to the selected DNG"
    size=$(cap_propcount_size "$(stat -c %s "$cap_raw_root/raw/$cap_raw_name")")
    size="${size% (*}"
    expected="Kind=Adobe DNG negative|Size=$size|Modified=2026-09-18 20:10|$cap_raw_photo_rows"
    cap_raw_wait previewFacts "$expected" "the nine displayed facts have the board's order and photo strings"
    printf 'RAW_FACTS %s\n' "$expected"
}

case_cap_raw_grid() {
    local menus_checks=0 index name caption
    command -v magick >/dev/null || fail "raw: magick is required for board crops"
    cap_raw_launch grid
    for name in _DSF4471.DNG DSC_2210.DNG IMG_0412.DNG L1000921.DNG P1030044.DNG; do
        index=$(row_index_of "$name")
        [[ "$index" =~ ^[0-9]+$ ]] || fail "raw: no listing row for $name"
        cap_raw_wait rowThumbReady true "$name has a decoded thumbnail" "$index"
        caption=$(ipc gridCaptionState "$index")
        [[ "$(jq -er '.name | gsub("\n"; "")' <<< "$caption")" == "$name" ]] || fail "raw: $name has a different grid caption"
        jq -e '.truncated == false and .lines > 0' <<< "$caption" >/dev/null || fail "raw: $name is clipped"
    done
    [[ "$(ipc cursor)" == 0 ]] || fail "raw: the grid cursor is not on the first tile"
    shot raw-grid
    for name in _DSF4471.DNG DSC_2210.DNG IMG_0412.DNG L1000921.DNG P1030044.DNG; do
        index=$(row_index_of "$name")
        cap_raw_crop raw-grid "raw-grid-$name" "$(ipc rowRect "$index")"
    done
    cap_raw_cleanup
    trap - EXIT
}

case_cap_raw_columns() {
    local menus_checks=0 x y w h wx wy ww wh left top right bottom
    command -v magick >/dev/null || fail "raw: magick is required for board crops"
    cap_raw_launch columns
    cap_raw_columns_ready
    shot raw-columns
    cap_raw_crop raw-columns raw-columns-frame "$(ipc columnFrameRect)"
    read -r x y w h <<< "$(ipc columnFrameRect)"
    read -r wx wy ww wh < <(window_box)
    left=$((x > 14 ? x - 14 : 0)); top=$((y > 14 ? y - 14 : 0))
    right=$((x + w + 14 < ww ? x + w + 14 : ww)); bottom=$((wh - cap_raw_caption_height))
    cap_raw_crop raw-columns raw-columns-facts "$left $top $((right - left)) $((bottom - top))"
    cap_raw_cleanup
    trap - EXIT
}

case_cap_raw_quicklook() {
    local menus_checks=0 x y w h
    command -v magick >/dev/null || fail "raw: magick is required for board crops"
    cap_raw_launch quicklook
    cap_raw_columns_ready
    key -k space >/dev/null
    cap_raw_wait previewOpen true "Space opens Quick Look on the DNG"
    cap_raw_wait previewKind image "Quick Look shows the embedded RAW image"
    cap_raw_wait previewState image "Quick Look's image decode lands"
    menus_expect previewSwapState '.lookVisible and .lookOpen.revealed and .lookOpen.landed' "Quick Look's image is revealed"
    menus_expect chromeHeight ". == $cap_raw_caption_height" "the board's caption band height is set"
    shot raw-quicklook
    cap_raw_crop raw-quicklook raw-quicklook-surface "$(ipc previewSurfaceRect)"
    read -r x y w h <<< "$(ipc previewSurfaceRect)"
    cap_raw_crop raw-quicklook raw-quicklook-caption "$x $((y + h - cap_raw_caption_height)) $w $cap_raw_caption_height"
    # No caption IPC reader exists; the crop is native evidence for this exact board string.
    printf 'RAW_CAPTION_REVIEW Embedded preview · 1620 × 1080\n'
    key -k Escape >/dev/null
    cap_raw_wait previewOpen false "Escape closes Quick Look"
    cap_raw_cleanup
    trap - EXIT
}

case_cap_raw_properties() {
    local menus_checks=0 state size
    command -v magick >/dev/null || fail "raw: magick is required for board crops"
    cap_raw_launch properties
    cap_raw_columns_ready
    key m >/dev/null
    menus_expect menuState '.opened' "the DNG's file menu opens"
    menu_seek Properties
    key -k Return >/dev/null
    size=$(cap_propcount_size "$(stat -c %s "$cap_raw_root/raw/$cap_raw_name")")
    menus_expect menuDialogState ".opened and .action == \"properties\" and .facts.ok and .facts.kind == \"File\" and .facts.directory == false and .facts.path == \"$cap_raw_root/raw/$cap_raw_name\" and .facts.photo == $cap_raw_photo and .liveLines.size.value == \"$size\"" "Properties carries the DNG's exact size and every board photo fact"
    state=$(ipc menuDialogState)
    printf 'RAW_PROPERTIES %s\n' "$(jq -c '{photo: .facts.photo, size: .liveLines.size.value}' <<< "$state")"
    settle
    shot raw-properties
    cap_raw_crop raw-properties raw-properties-card "$(jq -er .rect <<< "$state")"
    key -k Escape >/dev/null
    menus_expect menuDialogState '.opened | not' "Escape closes Properties"
    cap_raw_cleanup
    trap - EXIT
}
