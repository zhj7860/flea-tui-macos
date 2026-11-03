#!/usr/bin/env bash
# Compositor-free proof of tests/lib/pointer-glide.sh against a fake hyprctl and an accelerating fake ydotool.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

# A marked sandbox of its own under the fixture root, so cleanup deletes only what this run owns.
test_root=$(mktemp -d "$FIXTURE_ROOT/flea-pointer-glide-XXXXXX") || exit 1
case $test_root in
  /*/*) ;;
  *) echo "FAIL: mktemp -d gave '$test_root', which is not an absolute path two components deep"; exit 1 ;;
esac
sandbox_require "$test_root" || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/bin" || exit 1
# The fake compositor answers cursorpos from a state file in hyprctl's "640, 360" form, or a refusal when told to.
cat > "$test_root/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == cursorpos ]] || exit 2
[[ -f "$GLIDE_STATE.broken" ]] && { echo "error: no pointer"; exit 0; }
read -r x y < "$GLIDE_STATE"; printf '%s, %s\n' "$x" "$y"
EOF
# The fake uinput device logs each move and accelerates past 4 px by 5/2, so a full-gap step overshoots and diverges; it can also refuse, stay stuck, ignore moves until a set count and then land on a set point, or add a drift to one numbered move.
cat > "$test_root/bin/ydotool" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == mousemove && "$2" == -x && "$4" == -y ]] || exit 2
echo "$3 $5" >> "$GLIDE_STATE.log"
[[ -f "$GLIDE_STATE.refuse" ]] && exit 1
[[ -f "$GLIDE_STATE.stuck" ]] && exit 0
if [[ -f "$GLIDE_STATE.late" ]]; then
    read -r count x y < "$GLIDE_STATE.late"
    (( $(wc -l < "$GLIDE_STATE.log") >= count )) && echo "$x $y" > "$GLIDE_STATE"
    exit 0
fi
read -r x y < "$GLIDE_STATE"
drift=0
[[ -f "$GLIDE_STATE.drift" ]] && { read -r at dx < "$GLIDE_STATE.drift"; (( $(wc -l < "$GLIDE_STATE.log") == at )) && drift=$dx; }
accel() { local d=$1; (( d > 4 || d < -4 )) && d=$((d * 5 / 2)); echo "$d"; }
echo "$((x + $(accel "$3") + drift)) $((y + $(accel "$5")))" > "$GLIDE_STATE"
EOF
chmod +x "$test_root/bin/hyprctl" "$test_root/bin/ydotool" || exit 1

export PATH="$test_root/bin:$PATH" GLIDE_STATE="$test_root/pos" XDG_RUNTIME_DIR="$test_root"
. tests/lib/pointer-glide.sh
failed=0
check() {
    if [[ "$2" == "$3" ]]; then printf 'POINTERGLIDE PASS %s\n' "$1"; else printf 'POINTERGLIDE FAIL %s: got %s, want %s\n' "$1" "$2" "$3"; failed=$((failed + 1)); fi
}
start() { [[ "$GLIDE_STATE" == "$test_root/pos" && -n "$test_root" ]] || exit 1; rm -f -- "$GLIDE_STATE.log" "$GLIDE_STATE.stuck" "$GLIDE_STATE.broken" "$GLIDE_STATE.refuse" "$GLIDE_STATE.late" "$GLIDE_STATE.drift"; echo "$1 $2" > "$GLIDE_STATE"; : > "$GLIDE_STATE.log"; }
near() { read -r x y < "$GLIDE_STATE"; (( x >= $1 - 2 && x <= $1 + 2 && y >= $2 - 2 && y <= $2 + 2 )) && echo yes || echo "no at $x,$y"; }

start 10 10; pointer_glide 900 -300; check "a far target past the origin is reached through acceleration" "$? $(near 900 -300)" "0 yes"
start 640 361; pointer_glide 640 360; check "a pointer already there still sends one motion out and back" "$? $(tr '\n' '|' < "$GLIDE_STATE.log")" "0 1 0|-1 0|"
start 0 0; touch "$GLIDE_STATE.broken"; why=$(pointer_glide 50 50 2>&1); check "an unreadable cursorpos refuses before any motion, naming cursorpos" "$? $(wc -l < "$GLIDE_STATE.log") ${why%%,*}" "1 0 pointer_glide: hyprctl cursorpos gave 'error: no pointer'"
start 0 0; touch "$GLIDE_STATE.stuck"; why=$(pointer_glide 500 500 2>&1); check "a pointer that never moves gives up after 32 steps, saying where it stopped" "$? $(wc -l < "$GLIDE_STATE.log") $why" "1 32 pointer_glide: the pointer stopped at 0,0 after 32 steps, short of 500,500"
start 0 0; why=$(pointer_glide x 5 2>&1); check "a malformed target is refused by name" "$? $(wc -l < "$GLIDE_STATE.log") $why" "1 0 pointer_glide: target 'x 5' is not two integers"
start 0 0; touch "$GLIDE_STATE.refuse"; why=$(pointer_glide 50 50 2>&1); check "a refused ydotool motion is named" "$? $why" "1 pointer_glide: ydotool refused the motion at 0,0"
start 0 0; echo "32 500 500" > "$GLIDE_STATE.late"; pointer_glide 500 500; check "a pointer that lands on the 32nd move is reached, then goes out and back" "$? $(wc -l < "$GLIDE_STATE.log") $(near 500 500)" "0 34 yes"
start 0 0; echo "32 7 7" > "$GLIDE_STATE.late"; why=$(pointer_glide 500 500 2>&1); check "the give-up names the position read after the last move" "$? $why" "1 pointer_glide: the pointer stopped at 7,7 after 32 steps, short of 500,500"
start 640 360; echo "2 -3" > "$GLIDE_STATE.drift"; pointer_glide 640 360; check "a back leg that drifts off the target glides back and goes out and back again" "$? $(tr '\n' '|' < "$GLIDE_STATE.log")" "0 1 0|-1 0|1 0|1 0|-1 0|"
printf 'POINTERGLIDE DONE checks=9 failed=%d\n' "$failed"
[[ "$failed" == 0 ]]
