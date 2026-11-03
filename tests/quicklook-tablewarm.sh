#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# A rested Markdown document holding a table builds Quick Look's unseen warm table once per prepare, and a held key never does.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$PWD/tools/flea-sandbox-guard"
command -v qs >/dev/null || { printf 'FAIL quicklook-tablewarm: qs is required\n'; exit 1; }
sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-quicklook-tablewarm.XXXXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER"
trap 'sandbox_remove "$test_root"' EXIT
mkdir -p "$test_root"/{config,fixture,home,state,cache,data,runtime,tmp}
chmod 700 "$test_root/runtime"
ln -s "$PWD/ui" "$test_root/config/flea"
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui"
cp tests/quicklook-tablewarm.qml "$test_root/config/shell.qml"
printf '# note\n\nA plain note with **bold** and `code`.\n' > "$test_root/fixture/note.md"
printf '# t1\n\n| Name | Value |\n| :--- | ---: |\n| **rows** | `3` |\n' > "$test_root/fixture/t1.md"
printf '# t2\n\n| A | B |\n| - | - |\n| one | [two](https://example.invalid) |\n' > "$test_root/fixture/t2.md"
printf '> | a | b |\n> | - | - |\n> | 1 | 2 |\n' > "$test_root/fixture/quote.md"
printf -- '- item\n\n  | a | b |\n  | - | - |\n  | 1 | 2 |\n' > "$test_root/fixture/list.md"
limit=60
output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CONFIG_HOME="$test_root/home/.config" \
    XDG_CACHE_HOME="$test_root/cache" XDG_DATA_HOME="$test_root/data" XDG_RUNTIME_DIR="$test_root/runtime" TMPDIR="$test_root/tmp" \
    FLEA_TABLEWARM_DIR="$test_root/fixture" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
    timeout "$limit" qs -p "$test_root/config" 2>&1)
code=$?
# Sample input, one probe line: "  INFO qml: TABLEWARM PASS the warm Markdown is one three column table got=[1,"table",3] expected=[1,"table",3]"
grep -a 'TABLEWARM' <<< "$output"
failures=0
# Sample input, one probe line: "  INFO qml: TABLEWARM DONE 18 checks, 0 failed"
if [ "$code" -ne 0 ] || ! grep -aq 'TABLEWARM DONE .* 0 failed' <<< "$output"; then
    printf 'FAIL quicklook-tablewarm: the probe did not pass (qs exit %s)\n' "$code"
    # Sample input, one probe line: "  INFO qml: TABLEWARM DONE 18 checks, 0 failed"
    grep -a 'TABLEWARM DONE' <<< "$output" >/dev/null || printf '%s\n' "$output" | tail -8
    failures=$((failures + 1))
fi
# The warm table is built and dropped unseen: any warning from its files, or from the prepare, is a failure.
# Sample input, a warning line: "  WARN qml: QuickLookPrepare.qml:42 TypeError: null has no properties"
warnings=$(grep -aE 'TypeError|ReferenceError|Unable to assign|Binding loop detected|not ready|(QuickLookPrepare|MarkdownTable|MarkdownText)\.qml:[0-9]+' <<< "$output" || true)
if [ -n "$warnings" ]; then
    printf 'FAIL quicklook-tablewarm: warnings: %s\n' "$warnings"
    failures=$((failures + 1))
fi
printf 'quicklook-tablewarm: %s failed\n' "$failures"
[ "$failures" -eq 0 ]
