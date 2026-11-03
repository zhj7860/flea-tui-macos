# Unlock board captures (outside the default wanted list); tests/ui.sh supplies fixture, helpers and shots.
. "$repo/tests/lib/pointer-glide.sh"

# Poll unlockState until its jq filter holds, so every card state is asserted, never assumed.
cap_unlock_expect() {
    local filter="$1" what="$2" state=""
    local end=$((SECONDS + 30))
    while (( SECONDS < end )); do
        state=$(ipc unlockState 2>/dev/null || printf unavailable)
        jq -e "$filter" <<< "$state" >/dev/null 2>&1 && return 0
        sleep 0.05
    done
    fail "cap_unlock: $what, last state $state"
}

# The rail label of the locked row for this device, waited on the lsblk poll, never counted.
cap_unlock_locked_label() {
    local dev="$1" label=""
    local end=$((SECONDS + 30))
    while (( SECONDS < end )); do
        label=$(ipc railEntries 2>/dev/null | jq -r --arg dev "$dev" \
            '[.[] | select(.device == $dev and .locked == true)][0].label // ""' 2>/dev/null || printf "")
        [[ -n "$label" ]] && { printf '%s' "$label"; return 0; }
        sleep 0.2
    done
    fail "cap_unlock: no locked rail row for $dev, entries $(ipc railEntries | jq -c 'map({label,device,locked})')"
}

# cap_resize returns on size alone while the centring move may still run, so no shot follows one until the whole box holds still (the cap_sidebar idiom, ui-captures.sh).
cap_unlock_still() {
    local box="" previous="" end=$((SECONDS + 20))
    while (( SECONDS < end )); do
        box=$(window_box) || fail "cap_unlock: native window coordinates unavailable"
        [[ "$box" == "$previous" ]] && break
        previous="$box"
        sleep 0.2
    done
    [[ "$box" == "$previous" && "$box" == *" 1100 700" ]] || fail "cap_unlock: the window never held still at 1100x700, last box [$box]"
}

# ydotool's left button down and up codes, and the Tab and Return key codes (":1" presses, ":0" releases).
cap_unlock_left_down=0x40
cap_unlock_left_up=0x80
cap_unlock_key_tab=15
cap_unlock_key_return=28

# Pointer onto one card button through ydotool, since Hyprland's cursor move sends Qt no pointer frame.
cap_unlock_point() {
    local button="$1" centre cx cy wx wy _ww _wh
    centre=$(ipc unlockState | jq -er --arg b "$button" '.controls[] | select(.name == $b and .visible) | .centre') \
        || fail "cap_unlock: no visible $button button to point at"
    read -r cx cy <<< "$centre"
    read -r wx wy _ww _wh < <(window_box) || fail "cap_unlock: native window coordinates unavailable"
    pointer_glide "$((wx + cx))" "$((wy + cy))" || fail "cap_unlock: pointer move to $button failed"
    settle
}

# Pointer onto the card's own title, off every button, so a release there activates nothing.
cap_unlock_point_title() {
    local wx wy _ww _wh rx ry rw _rh
    read -r wx wy _ww _wh < <(window_box) || fail "cap_unlock: native window coordinates unavailable"
    read -r rx ry rw _rh <<< "$(ipc unlockState | jq -r '.rect')"
    [[ "$rx" =~ ^[0-9]+$ && "$ry" =~ ^[0-9]+$ && "$rw" =~ ^[0-9]+$ ]] || fail "cap_unlock: the card reported no rect"
    pointer_glide "$((wx + rx + rw / 2))" "$((wy + ry + 12))" || fail "cap_unlock: pointer move to the card title failed"
    settle
}

# Hover, then a held press let go off the button, each asserted from unlockState before its shot.
cap_unlock_pointer() {
    local button="$1" name="$2"
    cap_unlock_point "$button"
    cap_unlock_expect "[.controls[] | select(.name == \"$button\") | .hovered] == [true]" "$button reports the hover"
    settle
    shot "$name-hover-$button"
    YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket" ydotool click "$cap_unlock_left_down" >/dev/null 2>&1 || fail "cap_unlock: press on $button failed"
    cap_unlock_expect "[.controls[] | select(.name == \"$button\") | .pressed] == [true]" "$button reports the press"
    settle
    shot "$name-pressed-$button"
    cap_unlock_point_title
    YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket" ydotool click "$cap_unlock_left_up" >/dev/null 2>&1 || fail "cap_unlock: release off $button failed"
    cap_unlock_expect "[.controls[] | select(.name == \"$button\") | .pressed] == [false]" "the release off $button lets go"
    cap_unlock_expect '.opened == true' "a press let go off $button keeps the card"
}

# Pointer onto the eye through ydotool, the same way as the buttons.
cap_unlock_point_eye() {
    local ex ey wx wy _ww _wh
    read -r ex ey <<< "$(ipc unlockState | jq -r '.eye')"
    [[ "$ex" =~ ^[0-9]+$ && "$ey" =~ ^[0-9]+$ ]] || fail "cap_unlock: the card reported no eye centre"
    read -r wx wy _ww _wh < <(window_box) || fail "cap_unlock: native window coordinates unavailable"
    pointer_glide "$((wx + ex))" "$((wy + ey))" || fail "cap_unlock: pointer move onto the eye failed"
    settle
}

# Holds the pointer on the card's eye through ydotool, shoots the revealed field, then lets go.
cap_unlock_hold_eye() {
    local shot_name="$1"
    cap_unlock_point_eye
    cap_unlock_expect '.revealed | not' "the eye at rest masks the typed passphrase"
    shot unlock-eye-hover
    YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket" ydotool click "$cap_unlock_left_down" >/dev/null 2>&1 || fail "cap_unlock: pointer press on the eye failed"
    cap_unlock_expect '.revealed == true' "the held eye reveals the typed passphrase"
    settle
    shot "$shot_name"
    YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket" ydotool click "$cap_unlock_left_up" >/dev/null 2>&1 || fail "cap_unlock: pointer release off the eye failed"
    cap_unlock_expect '.revealed | not' "letting go of the eye masks the field again"
}

# Flea's own window keeps the keyboard: a foreign passphrase prompt (udiskie) must never be typed into.
cap_unlock_own_focus() {
    local seen
    seen=$(focused_class || true)
    [[ "$seen" == "$flea_window_class" ]] \
        || fail "cap_unlock: focus is on class '$seen', not $flea_window_class, so nothing is typed"
}

# The passphrase file is created owner-only: an absolute path only, any leftover file removed first, umask 077 in a subshell, so no byte of it is ever readable by another user.
cap_unlock_write_key() {
    local keyfile="$1" key="$2"
    case $keyfile in /?*) ;; *) fail "cap_unlock: the key file path '$keyfile' is not absolute" ;; esac
    ( umask 077; rm -f -- "$keyfile" && printf '%s' "$key" > "$keyfile" ) || fail "cap_unlock: the key file could not be written"
}

# The test-only passphrase typed with no argv carrying it; the file holds exactly its bytes.
cap_unlock_type_key() {
    local keyfile="$1" via="${2:-field}" stop=""
    cap_unlock_own_focus
    YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket" ydotool type -f "$keyfile" >/dev/null 2>&1 \
        || fail "cap_unlock: ydotool could not type the key file"
    # Each Tab rides the key's queue and must land on its stop, so Return submits from the Unlock button and nowhere else.
    if [[ "$via" == unlock ]]; then
        for stop in cancel unlock; do
            YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket" ydotool key "$cap_unlock_key_tab:1" "$cap_unlock_key_tab:0" >/dev/null 2>&1 \
                || fail "cap_unlock: ydotool could not press Tab"
            cap_unlock_expect ".focus == \"$stop\"" "Tab never reached $stop before the right passphrase"
        done
    fi
    # Return rides the same uinput queue as the key, since a virtual-keyboard Return can overtake the typing.
    YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket" ydotool key "$cap_unlock_key_return:1" "$cap_unlock_key_return:0" >/dev/null 2>&1 \
        || fail "cap_unlock: ydotool could not press Return"
}

# Writes DIR/lsblk: a loop container lists as a stick (rm, and a name past Devices.js isPseudo); other calls are the real lsblk.
cap_unlock_lsblk_shim() {
    local dir="$1" dev="$2" real="$3" dev2="${4:-}"
    [[ "$dev" =~ ^/dev/loop[0-9]+$ && "$real" == /* && -x "$real" ]] || return 1
    [[ -z "$dev2" || ( "$dev2" =~ ^/dev/loop[0-9]+$ && "$dev2" != "$dev" ) ]] || return 1
    mkdir -p -- "$dir" || return 1
    {
        printf '#!/bin/bash\n# Test-only lsblk written by tests/ui-captures-unlock.sh; it dies with its sandbox root.\n'
        printf 'real=%q dev=%q dev2=%q\n' "$real" "$dev" "$dev2"
        cat <<'SHIM'
# Sample input (Flea's argv, ui/DeviceMounts.qml): "--bytes --json -o NAME,PATH,...,UUID"; the real lsblk's reply: {"blockdevices":[{"name":"loop0","path":"/dev/loop0","rm":false,"children":[{"name":"luks-6f1c2a7e","rm":false}]}]}
case " $* " in *" --json "*|*" -J "*) ;; *) exec "$real" "$@" ;; esac
body=$("$real" "$@"; rc=$?; printf x; exit "$rc"); rc=$?; body=${body%x}
pick='(.path // ("/dev/" + (.name // ""))) == $dev'
if (( rc != 0 )) || ! jq -e --arg dev "$dev" "any(.blockdevices[]?; $pick)" <<< "$body" >/dev/null 2>&1; then
    printf '%s' "$body"
    exit "$rc"
fi
mark='def mark: .rm = true | if .children then .children |= map(mark) else . end;'
if [[ -z "$dev2" ]]; then
jq --arg dev "$dev" "$mark .blockdevices |= map(if $pick then (mark | .name = \"cap-\" + .name) else . end)" <<< "$body"
else
jq --arg dev "$dev" --arg dev2 "$dev2" "$mark .blockdevices |= map(if $pick then (mark | .name = \"cap-\" + .name) elif ((.path // (\"/dev/\" + (.name // \"\"))) == \$dev2) then (.name = \"cap-\" + .name) else . end)" <<< "$body"
fi
SHIM
    } > "$dir/lsblk" || return 1
    chmod 700 "$dir/lsblk"
}

# Launch Flea the supported way for one device: flea --unlock names it (FLEA_UNLOCK reaches only its card).
cap_unlock_launch() {
    local dev="$1" shim="${2:-}"
    kill_flea
    cat "$flea_log" >> "$run_log" 2>/dev/null || true
    : > "$flea_log"
    rm -f "$FLEA_UNDO_DIR/undo-journal" "$FLEA_UNDO_DIR/undo-journal.lock"
    PATH="${shim:+$shim:}$PATH" FLEA_UI="$flea_ui" FLEA_BIN="$flea_bin" ${flea_launch_wrap[@]+"${flea_launch_wrap[@]}"} \
        setsid nohup "$flea_bin" --unlock "$dev" >"$flea_log" 2>&1 </dev/null &
    omarchy-drive wait window flea --timeout 15 >/dev/null
    omarchy-drive focus flea >/dev/null
    assert_window
    printf 'LAUNCH unlock dev=%q pid=%s\n' "$dev" "$(flea_pid)"
}

# The previous open-file leg may have unmounted, so a cwd holder needs both the unlocked row and the live mount.
cap_unlock_unmount_in_use() {
    local mount="$1" unmount_label="$2" row rail_idx mounted_label busy_status status end _attempt
    row=$(ipc railEntries | jq -c --arg mount "$mount" '[to_entries[] | select(.value.path == $mount and .value.locked != true and (.value.device // "") != "")][0] // null')
    if [[ "$row" == null ]] || ! mountpoint -q -- "$mount"; then
        printf 'CAP SKIP unlock-unmount-in-use: the open-file leg left no mounted unlocked S1LUKS row at %s\n' "$mount"
        inuse_receipt=skipped
        return 0
    fi
    rail_idx=$(jq -r .key <<< "$row")
    mounted_label=$(jq -er '.value.label | select(length > 0)' <<< "$row") || fail "cap_unlock: the mounted S1LUKS row has no name"
    # DeviceMounts.qml:231,500 passes the mounted row's label to Devices.js:344, not the locked container's label.
    busy_status="$mounted_label is busy; close what is using it and try again."
    # The open-file leg can leave this same sentence standing, so Escape clears it and only a new one counts.
    for _attempt in 1 2 3 4; do
        [[ "$(ipc statusPrimary 2>/dev/null)" == "$busy_status" ]] || break
        key -k Escape >/dev/null
        settle
    done
    [[ "$(ipc statusPrimary 2>/dev/null)" != "$busy_status" ]] || fail "cap_unlock: the earlier busy sentence never cleared"
    ( cd -- "$mount" && exec sleep 60 ) &
    holder=$!
    for _attempt in $(seq 1 40); do
        [[ "$(readlink "/proc/$holder/cwd" 2>/dev/null)" == "$mount" ]] && break
        sleep 0.05
    done
    [[ "$(readlink "/proc/$holder/cwd" 2>/dev/null)" == "$mount" ]] || { kill "$holder" 2>/dev/null || true; fail "cap_unlock: nothing holds $mount, so Unmount could not be refused"; }
    click_rail_row "$rail_idx" right
    settle
    menu_seek "$unmount_label"
    key -k Return >/dev/null
    end=$((SECONDS + 25))
    while (( SECONDS < end )); do
        status=$(ipc statusPrimary 2>/dev/null || printf "")
        [[ "$status" == "$busy_status" ]] && break
        sleep 0.1
    done
    [[ "$status" == "$busy_status" ]] || { kill "$holder" 2>/dev/null || true; fail "cap_unlock: Unmount of a volume in use did not say it was busy, status [$status]"; }
    settle
    shot unlock-unmount-in-use
    kill "$holder" 2>/dev/null || true
    wait "$holder" 2>/dev/null || true
    holder=""
}

# Unlock: the locked row, the card wrong-then-right, the unlocked row and the Eject that relocks it.
case_cap_unlock() {
    # The container is FLEA_CAP_LUKS_DEV (LUKS2 over a vfat labelled S1LUKS); its test-only passphrase is FLEA_CAP_LUKS_KEY.
    local dir="$fixture_root/cap-unlock" dev="${FLEA_CAP_LUKS_DEV:-}" key="${FLEA_CAP_LUKS_KEY:-}"
    local label="" keyfile="" state="" status="" wrong="no-such-passphrase"
    local end crypt="" shot_done=false shim="" rail_poll_ms="" listing_ms="" unlocking="" stop=""
    local busy_status="" mount="" first="" cancel_seen=false entries="" unmount_label="" rail_idx="" holder="" ilabel="" idev=""
    # The receipt names only the states actually shot, so each SKIP below downgrades its part.
    local cancel_receipt=rail openfile_receipt=skipped inuse_receipt=in-use unmounted_receipt=rail eject_receipt=locked,ejected
    # An ssh-started Flea is an inactive polkit subject that udisks refuses, so it starts in the graphical slice.
    local -a flea_launch_wrap=(systemd-run --user --scope --quiet --slice=app-graphical.slice)
    sandbox_scratch "$dir"
    if [[ -z "$dev" ]]; then
        # needs a real LUKS container, driven by the controller
        printf 'CAP SKIP unlock-locked-row: no FLEA_CAP_LUKS_DEV in this environment\n'
        printf 'CAP SKIP unlock-card-typing: no FLEA_CAP_LUKS_DEV in this environment\n'
        printf 'CAP SKIP unlock-card-typing-text: no FLEA_CAP_LUKS_DEV in this environment\n'
        printf 'CAP SKIP unlock-card-wrong: no FLEA_CAP_LUKS_DEV in this environment\n'
        printf 'CAP SKIP unlock-card-unlocking: no FLEA_CAP_LUKS_DEV in this environment\n'
        printf 'CAP SKIP unlock-card-unlock: no FLEA_CAP_LUKS_DEV in this environment\n'
        printf 'CAP SKIP unlock-unlocked-row: no FLEA_CAP_LUKS_DEV in this environment\n'
        printf 'CAP SKIP unlock-unlocked-nonempty: no FLEA_CAP_LUKS_DEV in this environment\n'
        printf 'CAP SKIP unlock-ejected-rail: no FLEA_CAP_LUKS_DEV in this environment\n'
        printf 'CAP SKIP unlock-cancel-rail: no FLEA_CAP_LUKS_DEV in this environment\n'
        printf 'CAP SKIP unlock-lock-open-file: no FLEA_CAP_LUKS_DEV in this environment\n'
        printf 'CAP SKIP unlock-unmounted-rail: no FLEA_CAP_LUKS_DEV in this environment\n'
        printf 'CAP SKIP unlock-internal-locked-row: no FLEA_CAP_LUKS_DEV in this environment\n'
        printf 'CAP SKIP unlock-card-hover-cancel: no FLEA_CAP_LUKS_DEV in this environment\n'
        printf 'CAP SKIP unlock-card-hover-unlock: no FLEA_CAP_LUKS_DEV in this environment\n'
        printf 'CAP SKIP unlock-card-pressed-cancel: no FLEA_CAP_LUKS_DEV in this environment\n'
        printf 'CAP SKIP unlock-card-pressed-unlock: no FLEA_CAP_LUKS_DEV in this environment\n'
        printf 'CAP SKIP unlock-eye-rest: no FLEA_CAP_LUKS_DEV in this environment\n'
        printf 'CAP SKIP unlock-eye-hover: no FLEA_CAP_LUKS_DEV in this environment\n'
        printf 'CAP SKIP unlock-eye-on: no FLEA_CAP_LUKS_DEV in this environment\n'
        printf 'CAP SKIP unlock-card-focus-unlock: no FLEA_CAP_LUKS_DEV in this environment\n'
        printf 'CAP SKIP unlock-card-focus-cancel: no FLEA_CAP_LUKS_DEV in this environment\n'
        printf 'CAP SKIP unlock-unmount-in-use: no FLEA_CAP_LUKS_DEV in this environment\n'
        return 0
    fi
    [[ "$dev" == /dev/* ]] || fail "cap_unlock: FLEA_CAP_LUKS_DEV names [$dev], not a device path"
    [[ -n "$key" ]] || fail "cap_unlock: FLEA_CAP_LUKS_DEV is set but FLEA_CAP_LUKS_KEY is empty"
    [[ "$wrong" != "$key" ]] || wrong="wrong-passphrase-2"
    command -v udisksctl >/dev/null || fail "cap_unlock: udisksctl is not on PATH, so relock cannot be asserted"
    # A loop device has no rm or tran, so the rail lists it only through the shim; the real stick never takes it.
    if [[ "$dev" =~ ^/dev/loop[0-9]+$ ]]; then
        shim="$fixture_root/cap-unlock-shim"
        sandbox_scratch "$shim"
        idev="${FLEA_CAP_INTERNAL_LUKS_DEV:-}"
        [[ "$idev" =~ ^/dev/loop[0-9]+$ ]] || idev=""
        cap_unlock_lsblk_shim "$shim" "$dev" "$(command -v lsblk)" "$idev" || fail "cap_unlock: the lsblk shim for $dev could not be written"
        printf 'CAP NOTE unlock: lsblk shim marks %s removable, listed as cap-%s\n' "$dev" "${dev#/dev/}"
    fi
    printf 'one\n' > "$dir/a.txt"
    printf 'two\n' > "$dir/b.txt"
    seed_ui_state "$fixture_root/cap-unlock-state" '{"keys":"default","view":"list"}'
    PATH="${shim:+$shim:}$PATH" launch "$dir"
    wait_listing 2
    cap_resize 1100 700
    cap_unlock_still
    label=$(cap_unlock_locked_label "$dev")
    key -k Tab >/dev/null
    settle
    [[ "$(ipc focusView)" == "rail" ]] || fail "cap_unlock: Tab did not reach the rail"
    rail_seek "$label"
    settle
    shot unlock-locked-row
    key -k Return >/dev/null
    cap_unlock_expect '.opened == true' "the Unlock card never opened on $label"
    cap_resize 1100 700
    cap_unlock_still
    shot unlock-card-typing
    key "$wrong" >/dev/null
    settle
    shot unlock-card-typing-text
    # Tab walks the card's own order, field then Cancel then Unlock, and comes back to the field.
    for stop in cancel unlock field cancel unlock; do
        key -k Tab >/dev/null
        cap_unlock_expect ".focus == \"$stop\"" "Tab never reached $stop on the card"
    done
    # The walk ends on Unlock, so the keyboard ring there is shot before Return submits it.
    settle
    shot unlock-card-focus-unlock
    # Return on the focused Unlock submits. A refusal can end inside one poll, so the Unlocking stop list is pinned on the right attempt below.
    key -k Return >/dev/null
    cap_unlock_expect '.phase == "wrong"' "a wrong passphrase never ended in the wrong state"
    state=$(ipc unlockState)
    [[ "$(jq -r .note <<< "$state")" == "That passphrase did not unlock $label." ]] \
        || fail "cap_unlock: the wrong note reads $(jq -r .note <<< "$state")"
    jq -e '.masked == false and .focus == "field"' <<< "$state" >/dev/null \
        || fail "cap_unlock: the wrong state kept the passphrase or lost the field, state $state"
    shot unlock-card-wrong
    keyfile="$dir/.cap-key"
    # The path is expanded here because the trap runs after this function's locals are gone.
    trap "rm -f -- ${keyfile@Q}" EXIT
    cap_unlock_write_key "$keyfile" "$key"
    cap_unlock_type_key "$keyfile" unlock
    rm -f "$keyfile"
    trap - EXIT
    keyfile=""
    end=$((SECONDS + 15))
    while (( SECONDS < end )); do
        state=$(ipc unlockState 2>/dev/null || printf unavailable)
        [[ "$(jq -r .phase <<< "$state" 2>/dev/null)" == "unlocking" ]] && { shot unlock-card-unlocking; shot_done=true; unlocking=$state; break; }
        [[ "$(jq -r .opened <<< "$state" 2>/dev/null)" == "false" ]] && break
        sleep 0.05
    done
    [[ "$shot_done" == true ]] || fail "cap_unlock: unlocking never showed before the dialog closed, last $state"
    # Submit empties the field, so no property holds the passphrase while it unlocks (tests/unlock-stdin.qml).
    jq -e '.masked == false' <<< "$unlocking" >/dev/null \
        || fail "cap_unlock: Unlocking kept the passphrase in the field, state $unlocking"
    # Submitted from the Unlock button, the keyboard drops to the card and only Cancel's forced ring shows.
    jq -e '.focus == ""' <<< "$unlocking" >/dev/null || fail "cap_unlock: a stop kept the keyboard while unlocking, state $unlocking"
    cap_unlock_expect '.opened == false' "the dialog never closed after the right passphrase"
    status=$(ipc statusPrimary)
    [[ "$status" == "Unlocked and mounted $label." ]] \
        || fail "cap_unlock: the unlocked footer reads [$status]"
    [[ "$(ipc path)" == */S1LUKS ]] || fail "cap_unlock: the pane is at $(ipc path), not the unlocked volume"
    end=$((SECONDS + 10))
    while (( SECONDS < end )); do
        [[ "$(ipc listInFlight 2>/dev/null)" == "false" ]] && break
        sleep 0.05
    done
    end=$((SECONDS + 3))
    while (( SECONDS < end )); do
        ipc railEntries 2>/dev/null | jq -e '[.[] | select((.path | endswith("/S1LUKS")) and .locked == false)] | length == 1' >/dev/null 2>&1 && break
        sleep 0.05
    done
    ipc railEntries | jq -e '[.[] | select((.path | endswith("/S1LUKS")) and .locked == false)] | length == 1' >/dev/null \
        || fail "cap_unlock: the rail never drew the unlocked row, entries $(ipc railEntries | jq -c 'map({label,device,locked})')"
    jq -e --argjson at "$(ipc railCursor)" '.[$at].path | endswith("/S1LUKS")' <<< "$(ipc railEntries)" >/dev/null \
        || fail "cap_unlock: the rail cursor is at $(ipc railCursor), not on the unlocked row"
    # The fixture's container is named apart from its filesystem, so one name on the row and the footer is the container's.
    ipc railEntries | jq -e --arg label "$label" '[.[] | select((.path | endswith("/S1LUKS")) and .label == $label)] | length == 1' >/dev/null \
        || fail "cap_unlock: the unlocked row is not named $label, entries $(ipc railEntries | jq -c 'map({label,device,locked})')"
    shot unlock-unlocked-row
    [[ "$(ipc focusView)" == "list" ]] || fail "cap_unlock: focus is on $(ipc focusView), not the unlocked listing"
    # The board's non-empty unlocked volume: three small vfat-safe files go into the mount, the cursor goes to the first row, and they are removed again so the container stays bare.
    mount=$(ipc path)
    printf 'fixture photo\n' > "$dir/photo.jpg"
    printf 'fixture key\n' > "$dir/backup.key"
    printf 'fixture archive\n' > "$dir/bundle.tar.zst"
    cp "$dir/photo.jpg" "$dir/backup.key" "$dir/bundle.tar.zst" "$mount/" || fail "cap_unlock: fixture files could not be staged on $mount"
    wait_listing 3
    key g >/dev/null
    settle
    first=$(ipc rowAt "$(ipc cursor)")
    [[ "$first" != loading && "$first" == *"|"* ]] || fail "cap_unlock: the cursor is not on a first row, got [$first]"
    shot unlock-unlocked-nonempty
    rm -f "$mount/photo.jpg" "$mount/backup.key" "$mount/bundle.tar.zst"
    end=$((SECONDS + 5))
    while (( $(ipc total 2>/dev/null || printf -1) != 0 && SECONDS < end )); do sleep 0.05; done
    [[ "$(ipc total)" == "0" ]] || printf 'CAP NOTE unlock-unlocked-nonempty: the listing still shows %s rows after cleanup\n' "$(ipc total)"
    crypt=$(ipc railEntries | jq -r '[.[] | select(.path | endswith("/S1LUKS")) | .device][0] // ""')
    [[ "$crypt" == /dev/* ]] || fail "cap_unlock: the unlocked row names no cleartext device"
    # Eject on a stick unmounts, locks and powers it off, so the cleartext device going away is the lock.
    if [[ -n "$shim" ]]; then
        # A loop container has no drive for gio to eject, so the loop lane locks it the way udisks does and shoots the rail.
        printf 'CAP SKIP unlock eject: %s is a loop container with no drive to eject; locked through udisksctl\n' "$dev"
        eject_receipt=skipped
        "${flea_launch_wrap[@]}" udisksctl unmount --no-user-interaction -b "$crypt" >/dev/null 2>&1 \
            || fail "cap_unlock: udisksctl could not unmount $crypt on the loop lane"
        "${flea_launch_wrap[@]}" udisksctl lock --no-user-interaction -b "$dev" >/dev/null 2>&1 \
            || fail "cap_unlock: udisksctl could not lock $dev on the loop lane"
    else
        key -M ctrl -k E -m ctrl >/dev/null
    fi
    end=$((SECONDS + 60))
    while (( SECONDS < end )); do
        status=$(ipc statusPrimary 2>/dev/null || printf "")
        [[ "$status" == *"could not be locked"* ]] && fail "cap_unlock: Eject left the container unlocked: [$status]"
        [[ -e "$crypt" ]] || break
        sleep 0.5
    done
    [[ -e "$crypt" ]] && fail "cap_unlock: $crypt is still open after Eject, status [$(ipc statusPrimary)]"
    # Sample input: "    readonly property int pollMs: 5000", the rail's device poll in ui/DeviceMounts.qml.
    rail_poll_ms=$(sed -n 's/^ *readonly property int pollMs: \([0-9]*\)$/\1/p' "$repo/ui/DeviceMounts.qml")
    [[ "$rail_poll_ms" =~ ^[0-9]+$ ]] || fail "cap_unlock: ui/DeviceMounts.qml names no pollMs"
    # Flea's Eject re-lists the rail as its unmount exits; the loop lane locks outside Flea, so it waits one device poll (ms clock).
    listing_ms=1000
    end=$(( $(date +%s%3N) + listing_ms ))
    [[ -n "$shim" ]] && end=$(( end + rail_poll_ms ))
    while (( $(date +%s%3N) < end )); do
        ipc railEntries 2>/dev/null | jq -e --arg crypt "$crypt" '[.[] | select(.device == $crypt)] | length == 0' >/dev/null 2>&1 && break
        sleep 0.05
    done
    ipc railEntries | jq -e --arg crypt "$crypt" '[.[] | select(.device == $crypt)] | length == 0' >/dev/null \
        || fail "cap_unlock: the rail still lists $crypt after Eject"
    status=$(ipc statusPrimary)
    [[ "$status" == *"could not be locked"* ]] && fail "cap_unlock: the status reports a lock failure: [$status]"
    settle
    shot unlock-ejected-rail
    kill_flea
    cap_unlock_launch "$dev" "$shim"
    cap_unlock_expect '.opened == true' "flea --unlock never opened the card on $dev"
    cap_unlock_expect ".label == $(jq -cn --arg l "$label" '$l') and (.subtitle | startswith($(jq -cn --arg l "$label · " '$l')) and test(\" · [0-9][0-9.]* [kKMGT]?B · \"))" \
        "flea --unlock never named the card after the rail row $label with its size"
    cap_resize 1100 700
    cap_unlock_still
    shot unlock-card-unlock
    # Hover and pressed on each button through the card's own geometry, then the eye over a sandbox-only passphrase.
    cap_unlock_pointer cancel unlock-card
    cap_unlock_pointer unlock unlock-card
    key "sandbox-eye-only" >/dev/null
    settle
    cap_unlock_expect '.masked == true' "the typed sandbox passphrase never masked"
    shot unlock-eye-rest
    cap_unlock_hold_eye unlock-eye-on
    key -k Escape >/dev/null
    cap_unlock_expect '.opened == false' "Escape never closed the card flea --unlock opened"
    # Second pass for the states round one leaves out: Cancel during Unlocking, then the rail-menu unmount with a file held open and clean, each shot the same way as above.
    PATH="${shim:+$shim:}$PATH" launch "$dir"
    wait_listing 2
    cap_resize 1100 700
    cap_unlock_still
    key -k Tab >/dev/null
    settle
    [[ "$(ipc focusView)" == "rail" ]] || fail "cap_unlock: Tab did not reach the rail on the second pass"
    rail_seek "$label"
    settle
    key -k Return >/dev/null
    cap_unlock_expect '.opened == true' "the Unlock card never reopened on $label"
    # Reopened empty one Tab puts the keyboard ring on Cancel, so it is shot before typing.
    key -k Tab >/dev/null
    cap_unlock_expect '.focus == "cancel"' "Tab never put the keyboard on Cancel"
    settle
    shot unlock-card-focus-cancel
    for stop in unlock field; do
        key -k Tab >/dev/null
        cap_unlock_expect ".focus == \"$stop\"" "Tab never came back through $stop to the field"
    done
    keyfile="$dir/.cap-key2"
    trap "rm -f -- ${keyfile@Q}" EXIT
    cap_unlock_write_key "$keyfile" "$key"
    cap_unlock_type_key "$keyfile" unlock
    rm -f "$keyfile"
    trap - EXIT
    keyfile=""
    end=$((SECONDS + 15))
    while (( SECONDS < end )); do
        state=$(ipc unlockState 2>/dev/null || printf unavailable)
        [[ "$(jq -r .phase <<< "$state" 2>/dev/null)" == "unlocking" ]] && {
            key -k Escape >/dev/null
            cap_unlock_expect '.opened == false' "Escape never cancelled the in-flight unlock"
            settle
            shot unlock-cancel-rail
            cancel_seen=true
            break
        }
        [[ "$(jq -r .opened <<< "$state" 2>/dev/null)" == "false" ]] && break
        sleep 0.05
    done
    [[ "$cancel_seen" == true ]] || printf 'CAP SKIP unlock-cancel-rail: unlocking never showed on the second pass, last %s\n' "$state"
    [[ "$cancel_seen" == true ]] || cancel_receipt=skipped
    status=$(ipc statusPrimary)
    if [[ "$status" != "Unlocked and mounted $label." ]]; then
        # Cancel held, so the rail kept its locked row: reopen the card and unlock for real.
        for _attempt in 1 2 3 4; do
            [[ "$(ipc focusView)" == "rail" ]] && break
            key -k Tab >/dev/null
            settle
        done
        [[ "$(ipc focusView)" == "rail" ]] || fail "cap_unlock: Tab never returned to the rail after Cancel"
        rail_seek "$label"
        settle
        key -k Return >/dev/null
        cap_unlock_expect '.opened == true' "the Unlock card never reopened on $label after Cancel"
        keyfile="$dir/.cap-key3"
        trap "rm -f -- ${keyfile@Q}" EXIT
        cap_unlock_write_key "$keyfile" "$key"
        cap_unlock_type_key "$keyfile" unlock
        rm -f "$keyfile"
        trap - EXIT
        keyfile=""
        cap_unlock_expect '.opened == false' "the dialog never closed after the right passphrase on the second pass"
        status=$(ipc statusPrimary)
        [[ "$status" == "Unlocked and mounted $label." ]] \
            || fail "cap_unlock: the unlocked footer reads [$status] on the second pass"
    else
        printf 'CAP NOTE unlock-cancel-rail: the cancelled attempt still unlocked, menu states continue\n'
    fi
    [[ "$(ipc path)" == */S1LUKS ]] || fail "cap_unlock: the pane is at $(ipc path), not the unlocked volume"
    # The rail-menu unmount: first with a shell holding a file open for the lock sentence.
    mount=$(ipc path)
    printf 'held open\n' > "$mount/hold.txt" || fail "cap_unlock: the held file could not be staged on $mount"
    sleep 45 < "$mount/hold.txt" &
    holder=$!
    rail_idx=$(ipc railEntries | jq -r '[to_entries[] | select(.value.path | endswith("/S1LUKS")) | .key][0] // -1')
    [[ "$rail_idx" != "-1" ]] || { kill "$holder" 2>/dev/null || true; fail "cap_unlock: the rail has no unlocked S1LUKS row"; }
    click_rail_row "$rail_idx" right
    settle
    entries=$(ipc contextMenuEntries)
    unmount_label=""
    [[ "|$entries|" == *"|Unmount|"* ]] && unmount_label="Unmount"
    [[ -z "$unmount_label" && "|$entries|" == *"|Eject|"* ]] && unmount_label="Eject"
    if [[ -z "$unmount_label" ]]; then
        key -k Escape >/dev/null
        settle
        kill "$holder" 2>/dev/null || true
        wait "$holder" 2>/dev/null || true
        holder=""
        printf 'CAP SKIP unlock-lock-open-file: no Unmount or Eject on the unlocked rail menu (%s)\n' "$entries"
        printf 'CAP SKIP unlock-unmount-in-use: no Unmount or Eject on the unlocked rail menu (%s)\n' "$entries"
        printf 'CAP SKIP unlock-unmounted-rail: no Unmount or Eject on the unlocked rail menu (%s)\n' "$entries"
        inuse_receipt=skipped
        unmounted_receipt=skipped
    else
        menu_seek "$unmount_label"
        key -k Return >/dev/null
        end=$((SECONDS + 60))
        while (( SECONDS < end )); do
            status=$(ipc statusPrimary 2>/dev/null || printf "")
            [[ "$status" == *"could not be locked"* ]] && break
            crypt=$(ipc railEntries 2>/dev/null | jq -r '[.[] | select(.path | endswith("/S1LUKS")) | .device][0] // ""')
            [[ -z "$crypt" ]] && break
            sleep 0.5
        done
        status=$(ipc statusPrimary)
        if [[ "$status" == *"could not be locked"* ]]; then
            settle
            shot unlock-lock-open-file
            openfile_receipt=sentence
        else
            printf 'CAP SKIP unlock-lock-open-file: the busy unmount left no lock sentence, status [%s]\n' "$status"
        fi
        kill "$holder" 2>/dev/null || true
        wait "$holder" 2>/dev/null || true
        holder=""
        rm -f "$mount/hold.txt"
        cap_unlock_unmount_in_use "$mount" "$unmount_label"
        # Clean unmount through the same menu for the locked row it leaves behind.
        crypt=$(ipc railEntries | jq -r '[.[] | select(.path | endswith("/S1LUKS")) | .device][0] // ""')
        if [[ -z "$crypt" ]]; then
            printf 'CAP NOTE unlock-unmounted-rail: the busy unmount already relocked, shot as left\n'
            settle
            shot unlock-unmounted-rail
        else
            rail_idx=$(ipc railEntries | jq -r '[to_entries[] | select(.value.path | endswith("/S1LUKS")) | .key][0] // -1')
            [[ "$rail_idx" != "-1" ]] || fail "cap_unlock: the unlocked S1LUKS row is gone before the clean unmount"
            click_rail_row "$rail_idx" right
            settle
            if [[ "$(ipc contextMenuVisible)" == "true" ]]; then
                menu_seek "$unmount_label"
                key -k Return >/dev/null
            else
                printf 'CAP NOTE unlock-unmounted-rail: the menu never reopened, locking through udisksctl\n'
                crypt=$(ipc railEntries | jq -r '[.[] | select(.path | endswith("/S1LUKS")) | .device][0] // ""')
                "${flea_launch_wrap[@]}" udisksctl unmount --no-user-interaction -b "$crypt" >/dev/null 2>&1 \
                    || fail "cap_unlock: udisksctl could not unmount $crypt for the clean relock"
                "${flea_launch_wrap[@]}" udisksctl lock --no-user-interaction -b "$dev" >/dev/null 2>&1 \
                    || fail "cap_unlock: udisksctl could not lock $dev for the clean relock"
            fi
            end=$((SECONDS + 60))
            while (( SECONDS < end )); do
                crypt=$(ipc railEntries 2>/dev/null | jq -r '[.[] | select(.path | endswith("/S1LUKS")) | .device][0] // ""')
                [[ -z "$crypt" ]] && break
                sleep 0.5
            done
            [[ -z "$crypt" ]] || fail "cap_unlock: the volume is still unlocked after the clean unmount"
            listing_ms=1000
            end=$(( $(date +%s%3N) + listing_ms + rail_poll_ms ))
            while (( $(date +%s%3N) < end )); do
                ipc railEntries 2>/dev/null | jq -e '[.[] | select(.path | endswith("/S1LUKS"))] | length == 0' >/dev/null 2>&1 && break
                sleep 0.05
            done
            settle
            shot unlock-unmounted-rail
        fi
    fi
    # An internal LUKS partition lists a locked row of its own; without one there is nothing to shoot.
    idev="${FLEA_CAP_INTERNAL_LUKS_DEV:-}"
    if [[ "$idev" == /dev/* ]]; then
        ilabel=$(cap_unlock_locked_label "$idev")
        for _attempt in 1 2 3 4; do
            [[ "$(ipc focusView)" == "rail" ]] && break
            key -k Tab >/dev/null
            settle
        done
        [[ "$(ipc focusView)" == "rail" ]] || fail "cap_unlock: Tab never returned to the rail for the internal row"
        rail_seek "$ilabel"
        settle
        shot unlock-internal-locked-row
    else
        printf 'CAP SKIP unlock-internal-locked-row: no FLEA_CAP_INTERNAL_LUKS_DEV in this environment\n'
    fi
    # Cancel and Unlock hovered and pressed, and the eye at rest, hovered and on, are shot in the flea --unlock lane above.
    printf 'CAP_UNLOCK locked=row card=typing,text,focus-unlock,wrong,unlocking,unlock,focus-cancel,hover-cancel,hover-unlock,pressed-cancel,pressed-unlock eye=rest,hover,on unlocked=row,nonempty eject=%s cancel=%s openfile=%s inuse=%s unmounted=%s internal=env-gated\n' "$eject_receipt" "$cancel_receipt" "$openfile_receipt" "$inuse_receipt" "$unmounted_receipt"
    kill_flea
}
