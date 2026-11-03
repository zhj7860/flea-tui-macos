# Sourced by drag.sh look235 after its owned launcher, IPC observers and pointer driver are ready.
look235_evidence="$capture_root/evidence"
mkdir "$look235_evidence" || die "look235: cannot create fresh evidence directory"
look235_files=(r1a.txt r1b.txt r2.txt)
look235_selected=""

look235_rail_point() {
  local label="$1" group="$2" index point x y entries
  entries=$(ipc railEntries) || die "look235: rail entries observer failed"
  index=$(jq -er --arg label "$label" --arg group "$group" \
    'to_entries | map(select(.value.label == $label and .value.group == $group))
     | if length == 1 then .[0].key else error("rail target missing or ambiguous") end' <<< "$entries") \
    || die "look235: no unique $group row named $label"
  point=$(ipc railRowCentre "$index") || die "look235: $label centre observer failed"
  [[ "$point" =~ ^[0-9]+\ [0-9]+$ ]] || die "look235: $label has no native geometry"
  read -r x y <<< "$point"
  (( x > 0 && x < WW && y > 0 && y < WH )) || die "look235: $label is outside the owned window"
  printf '%s %s\n' "$((WX + x))" "$((WY + y))"
}

look235_hover() {
  local label="$1" group="$2" line="$3" point x y
  point=$(look235_rail_point "$label" "$group") || die "look235: cannot address $label"
  read -r x y <<< "$point"
  glide_to "$x" "$y"
  expect_ipc stickyMessage "$line"
  expect_ipc selectedIndices "$look235_selected"
  expect_ipc selectionCount 3
  [[ "$button_down" == true ]] || die "look235: hover has no held drag"
}

look235_shot() {
  local name="$1" total="$2" selected="$3" primary="$4" sticky="$5" notice="$6" undo="$7" target="${8:-}"
  local png="$look235_evidence/$name.png" footer activity rail window reader value pointer point x y px py
  [[ "$(myid)" == "$MYID $MYPID" ]] || die "look235: capture lost its owned instance"
  expect_ipc path "$HOMEDIR"
  expect_ipc viewMode list
  expect_ipc listInFlight false
  expect_ipc total "$total"
  expect_ipc selectionCount "$selected"
  expect_ipc statusError false
  expect_ipc stickyMessage "$sticky"
  expect_ipc lastMessage "$notice"
  expect_ipc statusPrimary "$primary"
  footer=$(ipc statusFooterState) || die "look235: footer observer failed"
  activity=$(ipc statusActivityState) || die "look235: activity observer failed"
  rail=$(ipc railDetails) || die "look235: rail observer failed"
  jq -e --arg target "$target" \
    '[.rows[] | select(.kind == "trash")] | length == 1 and
     (.[0] | if $target == "Trash" then .detail == "move here" and
       .labelRect.x + .labelRect.width < .detailRect.x and .detailRect.width > 0
       else .detail != "move here" end)' <<< "$rail" >/dev/null \
    || die "look235: Trash drop cue does not describe $name: $rail"
  jq -e --arg path "$HOMEDIR" --arg primary "$primary" --argjson total "$total" \
    --argjson selected "$selected" --argjson undo "$undo" \
    '.path == $path and .total == $total and .selected == $selected and .listingState == "ready"
     and .centre.text == $primary and .centre.visible and .undo.visible == $undo
     and .undo.text == (if $undo then "z undoes" else "" end)' <<< "$footer" >/dev/null \
    || die "look235: footer does not describe $name: $footer"
  jq -e --arg line "$sticky" --arg path "$HOMEDIR" --argjson undo "$undo" \
    '.undoAvailable == $undo and .errors == 0
     and [.activities[] | {text,ownerPath,running}] ==
       (if $line == "" then [] else [{text:$line,ownerPath:$path,running:false}] end)' \
    <<< "$activity" >/dev/null || die "look235: activity does not describe $name: $activity"
  window=$(hyprctl clients -j | jq -ce --argjson pid "$MYPID" \
    '[.[] | select(.pid == $pid)] | if length == 1 then .[0] else error("owned window missing or ambiguous") end') \
    || die "look235: owned capture window missing"
  jq -e --argjson x "$WX" --argjson y "$WY" --argjson w "$WW" --argjson h "$WH" \
    '.at == [$x,$y] and .size == [$w,$h]' <<< "$window" >/dev/null \
    || die "look235: window geometry changed during the drag"
  if [[ -n "$target" ]]; then
    [[ "$button_down" == true ]] || die "look235: $name has no held pointer"
    expect_ipc selectedIndices "$look235_selected"
    point=$(look235_rail_point "$target" "$([[ "$target" == Trash ]] && echo trash || echo favourite)") \
      || die "look235: target disappeared before capture"
    read -r x y <<< "$point"
    pointer=$(hyprctl cursorpos | tr -d ',') || die "look235: pointer observer failed"
    read -r px py <<< "$pointer"
    [[ "$px $py" =~ ^[0-9]+\ [0-9]+$ ]] || die "look235: invalid pointer coordinates"
    (( px >= x - pointer_tolerance && px <= x + pointer_tolerance
       && py >= y - pointer_tolerance && py <= y + pointer_tolerance )) \
      || die "look235: pointer left $target before capture"
  fi
  for reader in railState railEntries statusFooterState statusActivityState keyDeliveryState; do
    value=$(ipc "$reader") || die "look235: $reader snapshot failed"
    printf '%s\n' "$value" > "$look235_evidence/$name.$reader.json" || die "look235: $reader evidence write failed"
  done
  printf '%s\n' "$rail" > "$look235_evidence/$name.railDetails.json" || die "look235: rail evidence write failed"
  printf '%s\n' "$window" > "$look235_evidence/$name.window.json" || die "look235: window evidence write failed"
  [[ ! -e "$png" && ! -L "$png" ]] || die "look235: refusing existing evidence $png"
  omarchy-drive shot "$png" flea >/dev/null || die "look235: whole-window capture failed for $name"
  [[ -s "$png" ]] || die "look235: whole-window capture is missing or empty"
  printf 'SHOT %s\n' "$png"
}

echo "== look235: one three-row drag, Trash, FAVORITES, drop, undo =="
expect_ipc listInFlight false
expect_ipc total 8
expect_ipc viewMode list
expect_ipc keymapPreset default
expect_ipc lastMessage ""
for name in "${look235_files[@]}"; do
  index=$(rowidx "$name") || die "look235: source $name is not listed"
  point=$(screen_centre "$name") || die "look235: source $name is not visible"
  read -r x y <<< "$point"
  if [[ -z "$look235_selected" ]]; then
    omarchy-drive click "$x" "$y" left >/dev/null || die "look235: first selection failed"
    look235_selected="$index"
  else
    omarchy-drive click "$x" "$y" left --mods ctrl >/dev/null || die "look235: additive selection failed"
    look235_selected="$look235_selected,$index"
  fi
  expect_ipc selectedIndices "$look235_selected"
done
point=$(screen_centre r2.txt) || die "look235: last selected row is not visible"
read -r x y <<< "$point"
glide_to "$x" "$y"
press
look235_hover Trash trash "Move 3 items to Trash"
look235_shot 01-trash-hover 8 3 "Move 3 items to Trash" "Move 3 items to Trash" "" false Trash
look235_hover omarchy favourite "Move 3 items to a folder · Ctrl copies, Shift moves"
look235_shot 02-favorite-hover 8 3 "Move 3 items to a folder · Ctrl copies, Shift moves" \
  "Move 3 items to a folder · Ctrl copies, Shift moves" "" false omarchy
look235_hover Trash trash "Move 3 items to Trash"
for name in "${look235_files[@]}"; do
  owned_path "$HOMEDIR/$name"
  owned_path "$XDG_DATA_HOME/Trash/files/$name"
  owned_path "$XDG_DATA_HOME/Trash/info/$name.trashinfo"
done
owned_path "$XDG_DATA_HOME/Trash"
release
expect_ipc lastMessage "Moved 3 items to Trash · z undoes"
expect_ipc total 5
expect_ipc listInFlight false
for name in "${look235_files[@]}"; do
  [[ ! -e "$HOMEDIR/$name" && -f "$XDG_DATA_HOME/Trash/files/$name" ]] \
    || die "look235: $name did not reach only the fixture Trash"
  if rowidx "$name" >/dev/null; then die "look235: $name remains in the IPC listing"; fi
done
look235_shot 03-dropped 5 1 "Moved 3 items to Trash" "" "Moved 3 items to Trash · z undoes" true
for name in "${look235_files[@]}"; do
  owned_path "$HOMEDIR/$name"
  owned_path "$XDG_DATA_HOME/Trash/files/$name"
  owned_path "$XDG_DATA_HOME/Trash/info/$name.trashinfo"
done
native_key z
expect_ipc lastMessage "Put it back from Trash."
expect_ipc total 8
expect_ipc listInFlight false
for name in "${look235_files[@]}"; do
  owned_path "$HOMEDIR/$name"
  [[ -f "$HOMEDIR/$name" && ! -e "$XDG_DATA_HOME/Trash/files/$name" ]] \
    || die "look235: undo did not restore $name from fixture Trash"
  printf '%s payload\n' "${name%.txt}" | cmp -s - "$HOMEDIR/$name" || die "look235: undo changed $name bytes"
  rowidx "$name" >/dev/null || die "look235: restored $name is absent from the IPC listing"
done
look235_shot 04-undone 8 0 "Put it back from Trash." "" "Put it back from Trash." false
cp -- "$SB/flea.log" "$look235_evidence/native.log" || die "look235: native log was not preserved"
printf 'LOOK235 duration_s=%s captures=4 same_drag=true\n' "$((SECONDS - look235_started))"
echo "$((pass + fail)) checks, $fail failed"
