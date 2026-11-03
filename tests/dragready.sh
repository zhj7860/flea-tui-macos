#!/bin/bash
# The grid's first press-move after a cold landing starts the drag: the lift handler builds with the tile, and the shared drop area leaves the tile's own DropArea disabled.
set -u
cd "$(dirname "$0")/.." || exit 1
# The grid delegate opts out of the per-row area; the list and columns rows keep it.
grep -q 'dropsLocal: false' ui/GridArea.qml || { echo "dragready: FAIL grid delegate builds a per-row drop area"; exit 1; }
grep -q 'dropsLocal' ui/List.qml ui/ColumnPane.qml && { echo "dragready: FAIL list or columns left the shared drop area"; exit 1; }
out=$(QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 timeout 60 qml6 tests/dragready.qml 2>&1)
code=$?
printf '%s\n' "$out" | grep -a -v '^$' | tail -n 5
[ "$code" = 0 ] || { echo "dragready: FAIL qml6 ended $code"; exit 1; }
printf '%s' "$out" | grep -q 'dragready: [0-9]* checks, 0 failed' || exit 1
