#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# The Trash strip's Empty Trash and a destructive DialogButton draw one ladder in five states, and every ui/ file declaring the Button role and drawing a border.width is the control, a ruled set member, or named here; offscreen, no display or lock.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

verdict=0
fail() { printf 'FAIL %s\n' "$1"; verdict=1; }

# The sweep table (ButtonSystem040 A, DESIGN-040 "buttons"): each file is the one control, a ruled set member, a mark, or deferred by name.
control_files="ConvertDialog MenuActionDialog CollideConfirm TrashConfirm OpenWithDialog NetworkDialog PermissionsDialog TransferCard TrashView ProtocolChip PickerAnswers"
for name in $control_files; do
    grep -q 'Flea\.DialogButton {' "ui/$name.qml" || fail "ui/$name.qml no longer instantiates the one control, Flea.DialogButton"
done
grep -q 'inStrip: true' ui/TrashView.qml || fail 'ui/TrashView.qml: the strip action is not the control hosted in the strip'
# Rule 14: a checkbox is CheckBox.qml, drawn by none of its callers.
for name in OpenWithDialog ConvertDialog PermissionsDialog; do
    grep -q 'Flea\.CheckBox {' "ui/$name.qml" || fail "ui/$name.qml draws its own checkbox, not CheckBox.qml"
done
# A set's current member takes a foreground frame and foreground text and the rest muted ones: SettingsSegment.qml:42 ships it, its keyboard focus is DialogButton's set member focus, and a protocol member is the one control as a set member.
grep -q 'border.color: segment.focusedHere && segment.focusFrame === "accent" ? Theme.color.accent' ui/SettingsSegment.qml || fail 'ui/SettingsSegment.qml: the focused set member recipe moved'
grep -q 'border.width: segment.glyph ? 0 : segment.focusedHere && segment.focusFrame === "thick" ? Buttons.RING : Theme.spacing.hairline' ui/SettingsSegment.qml || fail 'ui/SettingsSegment.qml: the thick set member frame moved'
! grep -q 'anchors.margins: -Buttons.RING' ui/SettingsSegment.qml || fail 'ui/SettingsSegment.qml: a focus ring draws outside the cell'
grep -q ': segment.current ? Theme.color.foreground : Theme.color.muted' ui/SettingsSegment.qml || fail 'ui/SettingsSegment.qml: the set member recipe moved'
grep -q 'readonly property string focusFrame: Buttons.focusFrame(Theme.color.accentHasHue, root.setMember, root.primary && Qt.colorEqual(Theme.color.accentFrame, Theme.color.foreground))' ui/DialogButton.qml || fail 'ui/DialogButton.qml: the focus-frame decision moved'
grep -q 'readonly property int frameWidth: root.focusShown && root.focusFrame === "thick" ? Buttons.RING : Theme.spacing.hairline' ui/DialogButton.qml || fail 'ui/DialogButton.qml: the thick focus frame moved'
grep -q 'readonly property color frame: root.focusShown && root.focusFrame === "accent" ? Theme.color.accent' ui/DialogButton.qml || fail 'ui/DialogButton.qml: the accent focus frame moved'
# Focus is the button's own frame: no item named buttonRing and no accent focus line remains anywhere in ui/.
ring_named=$(grep -rlE 'buttonRing|focusLine' ui --include='*.qml' --include='*.js' || true)
[ -z "$ring_named" ] || fail "a ring item or focus line is still named in: $ring_named"
grep -q 'setMember: true' ui/ProtocolChip.qml || fail 'ui/ProtocolChip.qml is no longer a set member of the one control'
# The picker's answers are the one control and its marks are Tier A chrome marks.
grep -q 'Flea.PickerAnswers {' ui/PickerWindow.qml || fail 'ui/PickerWindow.qml: the answers are not the shared strip'
grep -q 'component Answer: Flea.DialogButton' ui/PickerAnswers.qml || fail 'ui/PickerAnswers.qml: the answers are no longer the one control'
grep -q 'component Mark: Flea.ChromeButton' ui/PickerChrome.qml || fail 'ui/PickerChrome.qml: the marks are no longer chrome marks'
# The QML handback test drives the ipc's own body: a focus scope forced alone returns to its last child, so the button is released first.
grep -q 'view\.emptyItem\.focus = false; view\.forceActiveFocus()' ui/Ipc.qml || fail 'ui/Ipc.qml: trashFocusListing no longer releases the strip button before forcing the view'
# A fresh open() never hands the keyboard to the strip button: open()'s own body releases it before forcing the scope.
open_body=$(sed -n '/function open(action)/,/^    }/p' ui/TrashView.qml)
open_seq=$(grep -o -e 'emptyAction\.focus = false' -e 'forceActiveFocus()' <<< "$open_body")
open_rel=0; open_forces=0; open_ok=1
while IFS= read -r open_tok; do
    case "$open_tok" in
        *focus*) open_rel=$((open_rel + 1)) ;;
        *force*) open_forces=$((open_forces + 1)); [ "$open_rel" -gt 0 ] || open_ok=0; open_rel=$((open_rel - 1)); [ "$open_rel" -ge 0 ] || { open_ok=0; open_rel=0; } ;;
    esac
done <<< "$open_seq"
[ "$open_forces" -gt 0 ] && [ "$open_ok" -eq 1 ] || fail 'ui/TrashView.qml: open() forces the scope without releasing emptyAction first'
# Completeness: a ui/ file declaring the Button or ComboBox accessible role and drawing a border.width (ChromeButton's is its keyboard frame, SidebarRow's the eject mark's focus, TabBar's the New tab mark's keyboard frame, PickerFilter's the filter trigger's) is in this list or it is a new hand-built button.
known="ChromeButton DialogButton DialogField MediaStrip PickerFilter SettingsPanel SettingsSegment SidebarRow TabBar"
found=""
for path in $(grep -rlE 'Accessible\.role[[:space:]]*:[[:space:]]*Accessible\.((Push)?Button|ComboBox)' ui --include='*.qml'); do
    grep -q 'border\.width' "$path" && found="$found $(basename "$path" .qml)"
done
found=$(printf '%s\n' $found | sort | tr '\n' ' ')
want=$(printf '%s\n' $known | sort | tr '\n' ' ')
[ "$found" = "$want" ] || fail "framed buttons in ui/ are [$found], the table names [$want]"
# The retired second recipe is named nowhere in the tree (this suite and the changelog's history excepted).
retired=$(grep -rIl --exclude-dir=.git --exclude-dir=target --exclude-dir=.superpowers --exclude-dir=.flea-local --exclude=CHANGELOG.md \
    'Chrome''Action' . 2>/dev/null | grep -v '^\./tests/button-system\.' || true)
[ -z "$retired" ] || fail "the retired second Empty Trash recipe is still named in: $retired"
[ ! -e ui/Chrome''Action.qml ] || fail 'ui/ChromeAction.qml is back'

if ! command -v qs >/dev/null; then
    echo "button-system.sh: qs is not installed, cannot draw the buttons"
    exit 1
fi

# A marked sandbox of its own under the fixture root, so cleanup deletes only what this run owns.
test_root=$(mktemp -d "$FIXTURE_ROOT/flea-button-system-XXXXXX") || exit 1
# GNU mktemp -d honours a relative TMPDIR verbatim, so the path is checked absolute and two components deep.
case $test_root in
  /*/*) ;;
  *) echo "FAIL: mktemp -d gave '$test_root', which is not an absolute path two components deep"; exit 1 ;;
esac
sandbox_require "$test_root" || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/home/.config" "$test_root/state" "$test_root/data" "$test_root/cache" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1

# The outer cap, passed to the harness as BUTTONSYS_TIMEOUT_S so its own cap, half of it, lands first.
run_timeout_s=60
# Each harness runs in its own config dir with the same pinned roots: "<qml file>:<report tag>:<checks a full green run makes>".
harnesses="button-system.qml:BUTTONSYS:101 button-members.qml:MEMBERS:161 button-hueless.qml:HUELESS:20 button-keys.qml:KEYS:21 button-heldmask.qml:HELDMASK:4 button-press.qml:PRESSSNAP:102 button-press.qml:PRESS:102 button-press.qml:PRESSMUTANT:102"
total=0
verdict_output=""
for spec in $harnesses; do
    qml=${spec%%:*}; rest=${spec#*:}; tag=${rest%%:*}; expected_checks=${rest#*:}
    config="$test_root/config-$tag"
    mkdir -p "$config" || exit 1
    negative=0
    # The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
    if [ "$tag" = PRESSMUTANT ] || [ "$tag" = PRESSSNAP ]; then
        negative=1
        [ "$tag" = PRESSSNAP ] && negative=2
        tag=PRESS
        cp -a ui "$config/flea" || exit 1
        # Mutate only this run's marked copy, restoring root scaling or removing both inset Behaviors.
        if [ "$negative" -eq 2 ]; then
            for axis in X Y; do
                [ "$(grep -cxF "            Behavior on inset$axis {" "$config/flea/DialogButton.qml")" -eq 1 ] || exit 1
                sed -i "/^            Behavior on inset$axis {$/,/^            }$/d" "$config/flea/DialogButton.qml" || exit 1
            done
        else
            [ "$(grep -cxF '    id: root' "$config/flea/DialogButton.qml")" -eq 1 ] || exit 1
            sed -i '/^    id: root$/a\
    scale: tap.pressed && root.available && !Theme.reducedMotion ? Buttons.PRESS_SCALE : 1\
    Behavior on scale { NumberAnimation { duration: Buttons.PRESS_MS; easing.type: Easing.OutCubic } }
' "$config/flea/DialogButton.qml" || exit 1
        fi
    else
        ln -s "$PWD/ui" "$config/flea" || exit 1
    fi
    headless_commons "$test_root" "$config/Commons" || exit 1
    ln -s "$(readlink -f ui/boot/Ui)" "$config/Ui" || exit 1
    cp "tests/$qml" "$config/shell.qml" || exit 1
    cp tests/button-probe.js "$config/button-probe.js" || exit 1
    cp tests/qml-probe.js "$config/qml-probe.js" || exit 1
    # Every XDG root is pinned under the marked root and no backend answers; the subshell keeps bash's "Terminated" notice out of the report.
    output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
        XDG_DATA_HOME="$test_root/data" XDG_CONFIG_HOME="$test_root/home/.config" \
        XDG_RUNTIME_DIR="$test_root/runtime" BUTTONSYS_ROOT="$test_root" BUTTONSYS_TIMEOUT_S="$run_timeout_s" \
        QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
        timeout "$run_timeout_s" qs -p "$config" 2>&1 ) 2>/dev/null )
    # Sample input: "  INFO qml: BUTTONSYS ok rest: ..." once per check, and "  INFO qml: BUTTONSYS DONE checks=101 failed=0" once.
    passed=$(printf '%s\n' "$output" | grep -c "$tag ok ")
    failed=$(printf '%s\n' "$output" | grep -c "$tag FAIL")
    if [ "$negative" -eq 2 ]; then
        if [ "$failed" -eq 4 ] \
            && [ "$(printf '%s\n' "$output" | grep -c 'PRESS FAIL case [0-3] press inset transitions before settling')" -eq 4 ] \
            && [ "$(printf '%s\n' "$output" | grep -c 'PRESS ok case [45] reduced motion snaps without inset transition')" -eq 2 ] \
            && printf '%s\n' "$output" | grep -q "PRESS DONE checks=$expected_checks failed=4$"; then
            printf 'button-system: no-Behavior mutant rejected by all four normal-motion cases; both reduced-motion cases snap (%s failed of %s)\n' "$failed" "$expected_checks"
        else
            fail 'button-press.qml: the no-Behavior mutant escaped its inset-transition gate'
        fi
        verdict_output="$verdict_output
$output"
        continue
    elif [ "$negative" -eq 1 ]; then
        if printf '%s\n' "$output" | grep -q 'PRESS FAIL .*held label never transforms' \
            && printf '%s\n' "$output" | grep -q "PRESS DONE checks=$expected_checks failed=[1-9][0-9]*"; then
            printf 'button-system: root-scale mutant rejected by mapped-label checks (%s failed of %s)\n' "$failed" "$expected_checks"
        else
            fail 'button-press.qml: the root-scale mutant escaped its mapped-label gate'
        fi
        verdict_output="$verdict_output
$output"
        continue
    fi
    if [ "$failed" -ne 0 ]; then
        fail "$qml: the controls draw different ladders: $failed checks failed"
        printf '%s\n' "$output" | grep -a "$tag FAIL"
    fi
    if ! printf '%s\n' "$output" | grep -q "$tag DONE checks=$expected_checks failed=0"; then
        fail "$qml: the run did not report $expected_checks checks and 0 failed"
        printf '%s\n' "$output" | grep -aE "$tag DONE|ERROR|error" | head -10
    fi
    [ "$passed" -eq "$expected_checks" ] || fail "$qml: the run passed $passed checks by name, not $expected_checks"
    total=$((total + passed))
    verdict_output="$verdict_output
$output"
done
output=$verdict_output
# The offscreen platform itself says it cannot mask a FloatingWindow; that one line is the platform's, never the button's.
platform_warning='This plugin does not support setting window masks'
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN' | grep -vF "$platform_warning")
if [ -n "$warnings" ]; then
    fail 'the button harness logged a warning'
    printf '%s\n' "$warnings" | head -10
fi
if [ "$verdict" -ne 0 ]; then
    exit 1
fi
printf 'BUTTONSYS PASS %s checks, strip, dialog, set members, picker and field draw one ladder\n' "$total"
