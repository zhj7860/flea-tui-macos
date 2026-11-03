#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# The real ui/ChromeButton.qml draws its keyboard frame only for the keyboard, an inset-sized square (20 x 20 at the board's stop 14) centred in the hit box, one foreground hairline on every mark and theme; offscreen.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "chromering.sh: qs is not installed, cannot draw a button"
    exit 1
fi

# Every ChromeButton block sets ruleRows; only the PDF toolbar's five, a Flow under the page frame with no strip rule, may not.
lock_allow="ui/PreviewColumn.qml:5"
# Sample input: "        Flea.ChromeButton {"; braces are counted because ruleRows binds only as a direct child of its block.
lock_check() {
    python3 -I - "$1" <<'PYEOF'
import os, re, sys
root = sys.argv[1]
open_re = re.compile(r'\bChromeButton\s*\{')
rule_re = re.compile(r'\bruleRows\s*:')
paths = []
for dp, dn, fn in os.walk(root):
    for f in fn:
        if f.endswith('.qml'):
            paths.append(os.path.join(dp, f))
paths.sort()
for path in paths:
    depth = 0
    stack = []
    count = 0
    with open(path, encoding='utf-8') as fh:
        for line in fh:
            for m in open_re.finditer(line):
                pre = line[:m.start()]
                stack.append([depth + pre.count('{') - pre.count('}'), False])
            for m in rule_re.finditer(line):
                pre = line[:m.start()]
                if stack and depth + pre.count('{') - pre.count('}') == stack[-1][0] + 1:
                    stack[-1][1] = True
            depth += line.count('{') - line.count('}')
            while stack and depth <= stack[-1][0]:
                if not stack.pop()[1]:
                    count += 1
    count += len(stack)
    if count:
        print(path + ':' + str(count))
PYEOF
}
lock_bare=$(lock_check ui) || exit 1
for lock_loc in $lock_bare; do
    [ "$lock_loc" = "$lock_allow" ] || { printf 'FAIL %s ChromeButton blocks set no ruleRows (allowed: %s)\n' "$lock_loc" "$lock_allow"; exit 1; }
done
lock_box=$(mktemp -d "$FIXTURE_ROOT/flea-chromering-lock.XXXXXX") || exit 1
case "$lock_box" in /*/*) ;; *) printf 'FAIL mktemp gave %s\n' "$lock_box"; exit 1 ;; esac
sandbox_require "$lock_box" || exit 1
: > "$lock_box/$SANDBOX_MARKER" || exit 1
lock_cleanup() { sandbox_remove "$lock_box"; }
trap lock_cleanup EXIT
cp -a ui "$lock_box/base" || exit 1
rm -rf "$lock_box/c1"; cp -a "$lock_box/base" "$lock_box/c1" || exit 1
printf 'import QtQuick\nimport "." as Flea\nItem {\n    ChromeButton {\n        glyph: "x"\n    }\n}\n' > "$lock_box/c1/NegBare.qml" || exit 1
c1_bare=$(lock_check "$lock_box/c1") || exit 1
case "$c1_bare" in *NegBare.qml*) printf 'negative control bare ChromeButton failed as expected: %s\n' "$c1_bare" ;; *) printf 'FAIL negative control bare ChromeButton passed the lock\n'; exit 1 ;; esac
rm -rf "$lock_box/c2"; cp -a "$lock_box/base" "$lock_box/c2" || exit 1
printf 'import QtQuick\nimport "." as Flea\nItem {\n    Flea.ChromeButton {\n        glyph: "x"\n        Item {\n            property int ruleRows: 1\n        }\n    }\n}\n' > "$lock_box/c2/NegNested.qml" || exit 1
c2_bare=$(lock_check "$lock_box/c2") || exit 1
case "$c2_bare" in *NegNested.qml*) printf 'negative control nested ruleRows failed as expected: %s\n' "$c2_bare" ;; *) printf 'FAIL negative control nested ruleRows passed the lock\n'; exit 1 ;; esac
rm -rf "$lock_box/c3"; cp -a "$lock_box/base" "$lock_box/c3" || exit 1
printf 'import QtQuick\nimport "." as Flea\nItem {\n    Flea.ChromeButton {\n        glyph: "x"\n        ruleRows: Theme.spacing.hairline\n' > "$lock_box/c3/AaaNeg.qml" || exit 1
printf 'import QtQuick\nItem {\n    Item {\n        width: 1\n    }\n}\n' > "$lock_box/c3/ZzzNegClean.qml" || exit 1
c3_bare=$(lock_check "$lock_box/c3") || exit 1
case "$c3_bare" in *AaaNeg.qml*) printf 'negative control unbalanced block failed as expected: %s\n' "$c3_bare" ;; *) printf 'FAIL negative control unbalanced block passed the lock\n'; exit 1 ;; esac
sandbox_remove "$lock_box"
trap - EXIT

test_root="$FIXTURE_ROOT/flea-chromering-$$"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/cache" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/chromering.qml "$test_root/config/shell.qml" || exit 1
cp tests/button-probe.js "$test_root/config/button-probe.js" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 20 qs -p "$test_root/config" 2>&1)

# Sample input, one probe line: "  INFO qml: CHROMERING PASS 63 checks"
# At 7 stops the picker answer row adds two row checks and four per answer, and four strip marks two each; the Flash strip adds one setup check and five Back checks at 3 stops: 115 + 70 + 56 + 1 + 15 = 257.
expected_checks=257
pass_count=$(printf '%s\n' "$output" | grep -c 'CHROMERING PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'CHROMERING FAIL')
ran_checks=$(printf '%s\n' "$output" | grep -ao 'CHROMERING PASS [0-9]* checks' | grep -o '[0-9]*')
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ] || [ "${ran_checks:-0}" -ne "$expected_checks" ]; then
    printf 'FAIL the chrome button ring broke, or ran %s checks and not %s\n' "${ran_checks:-0}" "$expected_checks"
    printf '%s\n' "$output" | grep -a 'CHROMERING FAIL'
    printf '%s\n' "$output" | grep -aE 'ERROR|error' | grep -av 'CHROMERING' | head -20
    exit 1
fi
printf '%s\n' "$output" | grep -o 'CHROMERING PASS.*'
