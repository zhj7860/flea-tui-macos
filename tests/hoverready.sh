#!/bin/bash
# The grid's hover comes from one shared probe: no tile builds its own HoverHandler and every tile reads one index.
set -u
cd "$(dirname "$0")/.." || exit 1
# One shared probe on the view; the delegate and the tile hold no HoverHandler of their own.
[ "$(sed -e 's://.*::' ui/GridArea.qml | grep -c 'HoverHandler')" = 1 ] || { echo "hoverready: FAIL GridArea holds no single shared handler"; exit 1; }
grep -q 'HoverHandler' ui/GridTile.qml && { echo "hoverready: FAIL GridTile builds its own handler"; exit 1; }
grep -q 'hoveredIndex === cell.index' ui/GridArea.qml || { echo "hoverready: FAIL delegate reads no shared index"; exit 1; }
out=$(QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 timeout 60 qml6 tests/hoverready.qml 2>&1)
code=$?
printf '%s\n' "$out" | grep -a -v '^$' | tail -n 5
[ "$code" = 0 ] || { echo "hoverready: FAIL qml6 ended $code"; exit 1; }
printf '%s' "$out" | grep -q 'hoverready: [0-9]* checks, 0 failed' || exit 1
