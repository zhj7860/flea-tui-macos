#!/usr/bin/env bash
# Execute the shipped preview state callbacks and the list geometry probe under qml6.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$PWD/tools/flea-sandbox-guard"
command -v qml6 >/dev/null || { echo "FAIL markdown-preview-state: qml6 is required"; exit 1; }
test_root=$(mktemp -d "$FIXTURE_ROOT/flea-markdown-state.XXXXXXXX") || exit 1
[ -n "$test_root" ] && [[ "$test_root" = /* ]] || exit 1
: > "$test_root/$SANDBOX_MARKER"
trap 'sandbox_remove "$test_root"' EXIT
text_module="$test_root/text"
mkdir -p "$text_module/js" || exit 1
cp ui/MarkdownText.qml ui/MarkdownList.qml "$text_module/" || exit 1
cp ui/js/MarkdownLists.js "$text_module/js/" || exit 1
printf 'MarkdownText 1.0 MarkdownText.qml\nMarkdownList 1.0 MarkdownList.qml\nsingleton Theme 1.0 Theme.qml\n' > "$text_module/qmldir"
cat > "$text_module/Theme.qml" <<'THEME'
pragma Singleton
import QtQuick
QtObject {
    property var color: ({ foreground: "#ffffff" })
    property var font: ({ family: "sans-serif", body: 16 })
    property var spacing: ({ gap: 8 })
}
THEME
out=$(TZ=UTC QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 30 qml6 tests/markdown-preview-state.qml -- "$text_module" 2>&1)
status=$?
printf '%s\n' "$out"
[ "$status" -eq 0 ] && grep -qE 'MARKDOWN_PREVIEW_STATE [0-9]+ checks, 0 failed' <<< "$out" \
    && ! grep -qE 'FAIL |TypeError|ReferenceError|Cannot assign|Unable to assign' <<< "$out" || exit 1
