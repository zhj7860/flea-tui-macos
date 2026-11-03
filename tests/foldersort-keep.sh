#!/usr/bin/env bash
# A folder's own sort survives a sort's listed answer: the shipped ui/PaneSwap.qml applyListed, offscreen.
set -u
cd "$(dirname "$0")/.." || exit 1
command -v qml6 >/dev/null || { echo "foldersort-keep.sh: qml6 is not installed, cannot replay the answer"; exit 1; }

log=$(mktemp) || exit 1
trap 'rm -f "$log"' EXIT
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    QML_XHR_ALLOW_FILE_READ=1 timeout 60 qml6 tests/foldersort-keep.qml >"$log" 2>&1
code=$?
if [ "$code" != 0 ]; then echo "foldersort-keep.sh: qml6 exited $code:"; grep -a -E 'FAIL|Error|error' "$log"; exit 1; fi
if grep -a -qE '(^|[: ])FAIL[: ]' "$log"; then grep -a -E '(^|[: ])FAIL[: ]' "$log"; exit 1; fi
grep -a 'FOLDERSORTKEEP DONE' "$log" || { echo "foldersort-keep.sh: no DONE receipt:"; cat "$log"; exit 1; }
if grep -a -iE 'warning|TypeError|ReferenceError' "$log"; then echo "foldersort-keep.sh: warnings above"; exit 1; fi
