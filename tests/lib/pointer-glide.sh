# Sourced by native captures: moves the pointer through ydotool's uinput device, because a compositor move gives Qt no pointer frame.
# Sample input: pointer_glide 640 360 (absolute layout pixels, negative left of or above the origin); answers 1, with the cause on stderr, when it cannot get within 2 px.
pointer_glide() {
    [[ $# -eq 2 && "$1" =~ ^-?[0-9]+$ && "$2" =~ ^-?[0-9]+$ ]] || { echo "pointer_glide: target '$*' is not two integers" >&2; return 1; }
    local moves=0 x y inside shaken=0
    # Up to 32 moves toward the target; the read after the last one decides, so a glide that lands on its last move still counts.
    while :; do
        # Sample input: hyprctl cursorpos prints "640, 360"; the comma goes before the split.
        read -r x y < <(hyprctl cursorpos | tr -d ',')
        [[ "$x" =~ ^-?[0-9]+$ && "$y" =~ ^-?[0-9]+$ ]] || { echo "pointer_glide: hyprctl cursorpos gave '$x $y', no pointer row" >&2; return 1; }
        inside=0
        (( x >= $1 - 2 && x <= $1 + 2 && y >= $2 - 2 && y <= $2 + 2 )) && inside=1
        # Only a read inside the target after the out-and-back ends the glide; a back leg that drifted out glides again.
        (( inside && shaken )) && return 0
        if (( inside )); then
            # One pixel out and back gives Qt a real motion and frame at this point; the pause keeps libinput from accelerating the back leg.
            YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket" ydotool mousemove -x 1 -y 0 >/dev/null 2>&1 || { echo "pointer_glide: ydotool refused the motion at $x,$y" >&2; return 1; }
            sleep 0.05
            YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket" ydotool mousemove -x -1 -y 0 >/dev/null 2>&1 || { echo "pointer_glide: ydotool refused the motion at $x,$y" >&2; return 1; }
            shaken=1
        else
            (( moves < 32 )) || break
            # Half the gap per step, so libinput's acceleration cannot carry the pointer past the target.
            YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket" ydotool mousemove -x "$((($1 - x) / 2))" -y "$((($2 - y) / 2))" >/dev/null 2>&1 \
                || { echo "pointer_glide: ydotool refused the motion at $x,$y" >&2; return 1; }
            moves=$((moves + 1)) shaken=0
        fi
        sleep 0.05
    done
    echo "pointer_glide: the pointer stopped at $x,$y after 32 steps, short of $1,$2" >&2
    return 1
}
