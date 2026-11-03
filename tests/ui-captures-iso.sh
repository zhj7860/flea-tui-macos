#!/usr/bin/env bash
# Sourced by tests/ui.sh; ui:cap_iso captures PR #234 without approving its mounted-image design.

# Polkit accepts Hyprland's graphical session, while an ssh-started udisksctl is an inactive subject.
cap_iso_session_exec() {
    local -r dispatch_timeout_s=5
    local -r completion_timeout_s=30
    local -r poll_interval_s=0.05
    local verb="${1-}" status=125 argument job="" answer deadline device
    if [[ "${iso_session_incomplete:-false}" == true ]]; then
        printf 'cap_iso: previous session command completion is unknown\n' >&2
    elif [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        status=0
        timeout 20 udisksctl "$@" || status=$?
    else
        while :; do
            case "$verb" in
                loop-setup|mount|unmount|loop-delete) ;;
                *) printf 'cap_iso: unknown session command %s\n' "$verb" >&2; break ;;
            esac
            [[ "$iso_root" == /* && -d "$iso_root" && ! -L "$iso_root" \
                && -f "$iso_root/.flea-test-sandbox" && "$iso_file" == "$iso_root/image.iso" \
                && -f "$iso_file" && ! -L "$iso_file" \
                && "$(realpath -e -- "$iso_file")" == "$iso_file" ]] \
                || { printf 'cap_iso: session command needs the marked ISO fixture\n' >&2; break; }
            # Restrict every inserted word, including paths, before building shell and Lua text.
            for argument in "$iso_root" "$@"; do
                [[ -n "$argument" && "$argument" != *[!a-zA-Z0-9_./=-]* ]] || break
            done
            [[ -n "$argument" && "$argument" != *[!a-zA-Z0-9_./=-]* ]] \
                || { printf 'cap_iso: session command refuses whitespace or shell metacharacters\n' >&2; break; }
            [[ "${XDG_RUNTIME_DIR:-}" == /* ]] \
                || { printf 'cap_iso: session command needs XDG_RUNTIME_DIR\n' >&2; break; }
            device="${@: -1}"
            if [[ "$verb" == loop-setup ]]; then
                [[ "$device" == "$iso_file" ]] \
                    || { printf 'cap_iso: loop-setup takes only the fixture ISO, not %s\n' "$device" >&2; break; }
            else
                [[ "$device" =~ ^/dev/loop[0-9]+$ ]] \
                    || { printf 'cap_iso: %s takes a /dev/loopN device, not %s\n' "$verb" "$device" >&2; break; }
            fi
            job=$(mktemp -d "$iso_root/session-$verb.XXXXXXXX") || break
            {
                printf '#!/bin/bash\n'
                printf '{\n'
                if [[ "$verb" != loop-setup ]]; then
                    # Dispatch is asynchronous, so recheck the backing file inside the session too.
                    printf 'iso_file=%q\ndevice=%q\n' "$iso_file" "$device"
                    cat <<'SH'
owned=$(losetup --associated "$iso_file" --noheadings --output NAME) &&
[[ $'\n'"$owned"$'\n' == *$'\n'"$device"$'\n'* ]] &&
SH
                fi
                printf 'timeout 20 udisksctl'
                printf ' %q' "$@"
                printf '\n} > %q 2> %q\n' "$job/stdout" "$job/stderr"
                printf 'rc=$?\nprintf "%%s\\n" "$rc" > %q\n' "$job/rc.tmp"
                printf 'mv -- %q %q\n' "$job/rc.tmp" "$job/rc"
            } > "$job/run.sh" || break
            iso_session_incomplete=true
            status=0
            answer=$(XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" HYPRLAND_INSTANCE_SIGNATURE="$HYPRLAND_INSTANCE_SIGNATURE" \
                timeout "$dispatch_timeout_s" /bin/bash "$repo/tests/lib/hypr-dispatch.sh" session_exec_script "$job/run.sh" 2>&1) || status=$?
            if [[ "$status" != 0 || "$answer" != ok ]]; then
                printf 'cap_iso: session dispatch failed: %s (exit %s)\n' "$answer" "$status" >&2
                [[ "$status" != 0 ]] || status=125
                break
            fi
            deadline=$((SECONDS + completion_timeout_s))
            while [[ ! -f "$job/rc" ]] && (( SECONDS < deadline )); do
                sleep "$poll_interval_s"
            done
            if [[ ! -f "$job/rc" ]]; then
                printf 'cap_iso: session command timed out waiting for %s/rc\n' "$job" >&2
                status=124
                break
            fi
            # Sample input: 0
            if ! read -r status < "$job/rc" || [[ ! "$status" =~ ^[0-9]{1,3}$ ]] || (( 10#$status > 255 )); then
                printf 'cap_iso: session command wrote an invalid exit code\n' >&2
                status=125
            else
                iso_session_incomplete=false
            fi
            break
        done
        if [[ -n "$job" ]]; then
            [[ ! -f "$job/stdout" ]] || cat -- "$job/stdout"
            [[ ! -f "$job/stderr" ]] || cat -- "$job/stderr" >&2
        fi
    fi
    printf 'CAP_ISO session_exec cmd=%s rc=%s\n' "$verb" "$status"
    return "$status"
}

# Only loops still backed by this marked fixture belong to this case, even if a loop number was reused.
cap_iso_loops() {
    [[ -n "$iso_root" && "$iso_root" == /home/flea-sandbox/* && ! -L "$iso_root" \
        && -f "$iso_root/.flea-test-sandbox" && "$iso_file" == "$iso_root/image.iso" ]] \
        || return 1
    [[ "$iso_attach_started" == true ]] || return 0
    [[ -f "$iso_file" && ! -L "$iso_file" && "$(realpath -e -- "$iso_file")" == "$iso_file" ]] || return 1
    losetup --associated "$iso_file" --noheadings --output NAME
}

# Failed teardown keeps the backing file and turns a successful capture into a failed case.
cap_iso_cleanup() {
    local result="$1" loops device mounted left teardown_failed=0
    trap - EXIT INT TERM
    if [[ "$iso_launched" == true ]] && ! ( kill_flea ); then teardown_failed=1; fi
    if [[ "$iso_session_incomplete" == true ]]; then
        printf 'FAIL cap_iso: session command completion unknown; fixture kept at %s\n' "$iso_root" >&2
        exit 1
    fi
    if ! loops=$(cap_iso_loops); then
        printf 'FAIL cap_iso: cannot identify owned loops; fixture kept at %s\n' "$iso_root" >&2
        exit 1
    fi
    for device in $loops; do
        [[ "$device" =~ ^/dev/loop[0-9]+$ ]] || { teardown_failed=1; continue; }
        mounted=$(findmnt --json --source "$device" --output TARGET 2>/dev/null) || mounted='{"filesystems":[]}'
        if jq -e '.filesystems | length > 0' <<< "$mounted" >/dev/null; then
            cap_iso_session_exec unmount --no-user-interaction -b "$device" || teardown_failed=1
        fi
        # Recheck ownership immediately before detach, rather than trusting the earlier loop number.
        left=$(cap_iso_loops) || { teardown_failed=1; continue; }
        if [[ $'\n'"$left"$'\n' == *$'\n'"$device"$'\n'* ]]; then
            cap_iso_session_exec loop-delete --no-user-interaction -b "$device" || teardown_failed=1
        fi
    done
    left=$(cap_iso_loops) || teardown_failed=1
    [[ -z "$left" ]] || teardown_failed=1
    [[ "$iso_session_incomplete" == false ]] || teardown_failed=1
    if (( teardown_failed != 0 )); then
        printf 'FAIL cap_iso: teardown incomplete; fixture kept at %s, loops=[%s]\n' "$iso_root" "$left" >&2
        exit 1
    fi
    [[ -n "$iso_root" && "$iso_root" == /home/flea-sandbox/* && ! -L "$iso_root" \
        && -f "$iso_root/.flea-test-sandbox" ]] || exit 1
    sandbox_remove "$iso_root" || exit 1
    printf 'CAP_ISO cleanup=detached-and-deleted duration_s=%s\n' "$((SECONDS - iso_started))"
    exit "$result"
}

# The native row, its context menu, then the row absent after the menu's Eject, each observed before shooting.
case_cap_iso() (
    local iso_root iso_file iso_loop="" iso_launched=false iso_attach_started=false iso_started=$SECONDS
    local iso_session_incomplete=false
    local iso_label=OMARCHY_202608 builder="" candidate command mounted mountpoint
    local before entries details index deadline chain loops
    (( EUID != 0 )) || fail "cap_iso: run as the desktop session user, never root"
    for command in udisksctl losetup findmnt timeout jq; do
        command -v "$command" >/dev/null || fail "cap_iso: required command is missing: $command"
    done
    for candidate in xorriso genisoimage mkisofs; do
        if command -v "$candidate" >/dev/null; then builder="$candidate"; break; fi
    done
    [[ -n "$builder" ]] || fail "cap_iso: no ISO builder installed; need xorriso, genisoimage or mkisofs"
    sandbox_root_ok
    case "$SANDBOX_ROOT" in
        /home/flea-sandbox|/home/flea-sandbox/*) ;;
        *) fail "cap_iso: fixture root must resolve under /home/flea-sandbox, got $SANDBOX_ROOT" ;;
    esac
    iso_root=$(mktemp -d "$SANDBOX_ROOT/flea-cap-iso.XXXXXXXX") || fail "cap_iso: mktemp failed"
    [[ "$iso_root" == /home/flea-sandbox/* && -d "$iso_root" && ! -L "$iso_root" ]] \
        || fail "cap_iso: invalid temporary root $iso_root"
    : > "$iso_root/.flea-test-sandbox" || fail "cap_iso: cannot mark temporary root"
    iso_file="$iso_root/image.iso"
    trap 'cap_iso_cleanup "$?"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    mkdir -p "$iso_root/source" "$iso_root/browser" || fail "cap_iso: cannot build fixture directories"
    printf 'PR #234 mounted-image capture fixture\n' > "$iso_root/source/README.txt"
    printf 'Native mounted ISO rail capture\n' > "$iso_root/browser/notes.txt"
    local -a iso_command=("$builder")
    [[ "$builder" != xorriso ]] || iso_command+=(-as mkisofs)
    "${iso_command[@]}" -quiet -R -J -V "$iso_label" -o "$iso_file" "$iso_root/source" \
        || fail "cap_iso: $builder could not build the ISO"
    [[ -s "$iso_file" ]] || fail "cap_iso: builder left no ISO bytes"
    printf 'CAP_ISO fixture=%s builder=%s label=%s bytes=%s\n' \
        "$iso_root" "$builder" "$iso_label" "$(stat -c %s "$iso_file")"

    seed_ui_state "$iso_root/state" '{"keys":"default","view":"list","display":{"textSize":{"mode":14}},"places":{"rail":"shown","showDevices":true,"showUnmounted":true}}'
    iso_launched=true
    launch "$iso_root/browser"
    wait_listing 1
    cap_resize 1100 700
    deadline=$((SECONDS + 30))
    before='[]'
    while (( SECONDS < deadline )); do
        before=$(ipc railEntries) || fail "cap_iso: cannot observe existing DEVICES rows"
        jq -e 'any(.[]; .group == "device" and .kind == "disk")' <<< "$before" >/dev/null && break
        sleep 0.1
    done
    jq -e 'any(.[]; .group == "device" and .kind == "disk")' <<< "$before" >/dev/null \
        || fail "cap_iso: no existing system drive row beside which to capture the ISO"
    jq -e --arg label "$iso_label" 'all(.[]; .label != $label)' <<< "$before" >/dev/null \
        || fail "cap_iso: another rail row already carries label $iso_label"
    mkdir -p "$evidence_dir" || fail "cap_iso: cannot create evidence directory"
    printf '%s\n' "$before" > "$evidence_dir/cap-iso-before.json"

    iso_attach_started=true
    cap_iso_session_exec loop-setup --no-user-interaction -r -f "$iso_file" \
        || fail "cap_iso: read-only loop setup denied or failed for the session user"
    loops=$(cap_iso_loops) || fail "cap_iso: cannot identify the ISO's attached loop"
    [[ "$loops" =~ ^/dev/loop[0-9]+$ ]] || fail "cap_iso: expected one owned loop, got [$loops]"
    iso_loop="$loops"
    # udiskie may have mounted the new loop already; only a real mount of our node accepts that race.
    if ! cap_iso_session_exec mount --no-user-interaction -b "$iso_loop"; then
        findmnt --source "$iso_loop" >/dev/null || fail "cap_iso: mounting the ISO denied or failed"
    fi
    mounted=$(findmnt --json --source "$iso_loop" --output TARGET) || fail "cap_iso: mounted loop has no mountpoint"
    mountpoint=$(jq -er '.filesystems | select(length == 1) | .[0].target' <<< "$mounted") \
        || fail "cap_iso: expected one ISO mountpoint, got $mounted"
    [[ "$mountpoint" == /* && -r "$mountpoint/README.txt" ]] || fail "cap_iso: ISO contents are not readable"
    udisksctl info -b "$iso_loop" || fail "cap_iso: UDisks cannot inspect the mounted loop"
    printf 'CAP_ISO loop=%s mountpoint=%s\n' "$iso_loop" "$mountpoint"

    deadline=$((SECONDS + 30))
    entries='[]'
    while (( SECONDS < deadline )); do
        entries=$(ipc railEntries) || fail "cap_iso: cannot observe the ISO rail row"
        jq -e --arg device "$iso_loop" --arg label "$iso_label" --arg path "$mountpoint" \
            '[.[] | select(.device == $device)] | length == 1 and .[0].label == $label
             and .[0].path == $path and .[0].group == "device" and .[0].kind == "volume"
             and .[0].mounted == true and .[0].loop == true and .[0].removable == false
             and .[0].glyph == "drive"' <<< "$entries" >/dev/null && break
        sleep 0.1
    done
    jq -e --arg device "$iso_loop" --arg label "$iso_label" --arg path "$mountpoint" \
        '[.[] | select(.device == $device)] | length == 1 and .[0].label == $label
         and .[0].path == $path and .[0].group == "device" and .[0].kind == "volume"
         and .[0].mounted == true and .[0].loop == true and .[0].removable == false
         and .[0].glyph == "drive"' <<< "$entries" >/dev/null \
        || fail "cap_iso: mounted ISO row absent or wrong: $entries"
    jq -e --argjson before "$before" \
        '[.[] | select(.group == "device") | .device] as $now
         | all($before[] | select(.group == "device"); .device as $device | $now | index($device) != null)' \
        <<< "$entries" >/dev/null || fail "cap_iso: mounting the ISO removed an existing DEVICES row"
    index=$(jq -er --arg device "$iso_loop" 'map(.device) | index($device)' <<< "$entries") \
        || fail "cap_iso: ISO row has no rail index"
    details=$(ipc railDetails) || fail "cap_iso: cannot observe drawn rail geometry"
    ipc railState | jq -e '.hidden == false and .width > 0' >/dev/null \
        || fail "cap_iso: the DEVICES rail is hidden"
    jq -e --argjson index "$index" \
        'any(.headers[]; .text == "DEVICES" and .visible)
         and any(.rows[]; .index == $index and .missing != true and .indicatorVisible
             and .indicatorRect.width == 12 and .indicatorRect.height == 12
             and .rect.x >= 0 and .rect.x + .rect.width <= 1100
             and .rect.y >= 0 and .rect.y + .rect.height <= 700)
         and any(.rows[]; .group == "device" and .kind == "disk" and .missing != true
             and .rect.y >= 0 and .rect.y + .rect.height <= 700)' <<< "$details" >/dev/null \
        || fail "cap_iso: DEVICES header, system row or ISO's 12 px indicator slot is not in the whole window: $details"
    [[ "$(ipc contextMenuVisible)" == false ]] || fail "cap_iso: a menu covers the mounted-row capture"
    printf '%s\n' "$entries" > "$evidence_dir/cap-iso-mounted.json"
    printf '%s\n' "$details" > "$evidence_dir/cap-iso-mounted-geometry.json"
    shot cap-iso-mounted

    click_rail_row "$index" right
    settle
    cap_menu_expect '.opened and .forRail and [.entries[] | if .separator then "-" else .label end] == ["Open","-","Unmount","Eject"]' "ISO context menu"
    [[ "$(ipc contextMenuGlyphs)" == 'folder-open|-|drive|eject' ]] \
        || fail "cap_iso: the ISO menu drew unexpected marks"
    ipc menuState > "$evidence_dir/cap-iso-menu.json" || fail "cap_iso: cannot save menu state"
    shot cap-iso-menu
    menu_seek Eject
    key -k Return >/dev/null || fail "cap_iso: could not activate Eject from the ISO menu"

    deadline=$((SECONDS + 35))
    while (( SECONDS < deadline )); do
        entries=$(ipc railEntries) || fail "cap_iso: cannot observe the post-eject rail"
        chain=$(ipc deviceEjectState) || fail "cap_iso: cannot observe the eject result"
        loops=$(cap_iso_loops) || fail "cap_iso: cannot verify loop detachment"
        if jq -e --arg device "$iso_loop" --arg label "$iso_label" \
            'all(.[]; .device != $device and .label != $label)' <<< "$entries" >/dev/null \
            && [[ -z "$loops" && "$chain" == "|$iso_label||0|Ejected $iso_label.|false|false" ]]; then break; fi
        sleep 0.1
    done
    jq -e --arg device "$iso_loop" --arg label "$iso_label" \
        'all(.[]; .device != $device and .label != $label)' <<< "$entries" >/dev/null \
        || fail "cap_iso: Eject left the ISO row on the rail: $entries"
    [[ -z "$loops" && "$chain" == "|$iso_label||0|Ejected $iso_label.|false|false" ]] \
        || fail "cap_iso: Eject did not finish with an owned loop detached: loops=[$loops] chain=[$chain]"
    [[ "$(ipc contextMenuVisible)" == false && "$(ipc statusError)" == false ]] \
        || fail "cap_iso: Eject left a menu or reported an error"
    printf '%s\n' "$entries" > "$evidence_dir/cap-iso-ejected.json"
    printf 'device=%s\nassociated_loops=%s\neject_state=%s\n' \
        "$iso_loop" "$loops" "$chain" > "$evidence_dir/cap-iso-detached.txt"
    shot cap-iso-ejected
    printf 'CAP_ISO mounted=asserted menu=Open,Unmount,Eject row=gone loop=detached captures=3\n'
)
