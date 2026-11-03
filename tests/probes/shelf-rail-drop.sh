#!/bin/bash
# Shelf rail drop probe (issue 255): a file released on the rail after the dwell opened the card must land in the pile.
# Usage: FLEA_BIN=/path/to/flea tests/probes/shelf-rail-drop.sh [--mode=product|full] [--edge=right|left|bottom] (full FAILs by design)
set -u
out() { printf 'SHELFRAIL %s\n' "$*"; }
refuse() { out "FAIL $*"; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || refuse "missing $1"; }
need qs; need hyprctl; need ydotool; need jq
[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || refuse "no Hyprland session"
[ -n "${XDG_RUNTIME_DIR:-}" ] || refuse "no XDG_RUNTIME_DIR, so no ydotool socket"
flea_bin="${FLEA_BIN:-$(command -v flea || true)}"
[ -n "$flea_bin" ] || refuse "no flea binary (set FLEA_BIN)"
[ -x "$flea_bin" ] || refuse "flea binary is not executable: $flea_bin"
repo="$(cd "$(dirname "$0")/../.." && pwd)"
mode=product; edge=right
for arg in "$@"; do
  case "$arg" in
    --mode=product|--mode=full) mode="${arg#--mode=}" ;;
    --edge=right|--edge=left|--edge=bottom) edge="${arg#--edge=}" ;;
    *) refuse "unknown argument $arg" ;;
  esac
done
[ -d /usr/share/omarchy/shell/Commons ] || refuse "no omarchy shell Commons (this probe runs on an Omarchy box)"
[ -f "$repo/tests/lib/hypr-dispatch.sh" ] || refuse "no typed Hyprland helper"
. "$repo/tests/lib/hypr-dispatch.sh"
[ -f "$repo/tests/lib/pointer-glide.sh" ] || refuse "no pointer glide helper"
. "$repo/tests/lib/pointer-glide.sh"
# The helper moves the pointer through this socket, so the press and the release go through it too.
export YDOTOOL_SOCKET="$XDG_RUNTIME_DIR/.ydotool_socket"

work=$(mktemp -d "${TMPDIR:-/tmp}/shelfrail.XXXXXXXX") || refuse "mktemp failed"
touch "$work/.flea-test-sandbox"
qs_pid=""
cleanup() {
  ydotool click 0x80 >/dev/null 2>&1 || true
  [ -n "$qs_pid" ] && kill "$qs_pid" 2>/dev/null || true
  [ -f "$work/.flea-test-sandbox" ] && case "$work" in /*/shelfrail.????????) rm -rf -- "$work" ;; esac
}
trap cleanup EXIT

mkdir -p "$work/src" "$work/state/flea" "$work/cfg"
printf '{"shelf":{"enabled":true,"bar":false,"rail":"%s","screenshots":false,"recordings":false,"recent":0}}' "$edge" > "$work/state/flea/ui.json"
echo "drop me" > "$work/src/dropme.txt"
# Quickshell resolves `import qs.Commons` from the config root, the directory holding harness.qml.
ln -s /usr/share/omarchy/shell/Commons "$work/cfg/Commons" || refuse "cannot link shell Commons"
ln -s "$repo/shelf" "$work/cfg/shelf" || refuse "cannot link shelf tree"

panel_qml="$repo/shelf/Panel.qml"
# Sample input: "  readonly property var railCut: Model.railStrip(rail.edge," continued until its parens close.
# Prints the one Panel.qml item whose first line matches $1, up to where the $2 and $3 characters balance.
shipped_item() {
  local line opens closes depth=0 on=0
  [ "$(grep -c -- "$1" "$panel_qml")" = 1 ] || return 1
  while IFS= read -r line; do
    [[ $on = 0 && $line =~ $1 ]] && on=1
    [ "$on" = 1 ] || continue
    printf '%s\n' "$line"
    opens=${line//[^"$2"]/} closes=${line//[^"$3"]/}
    depth=$((depth + ${#opens} - ${#closes}))
    [ "$depth" = 0 ] && return 0
  done < "$panel_qml"
  return 1
}
cut_qml=''
if [ "$mode" = product ]; then
  mask_qml=$(shipped_item '^ *mask: Region [{]$' '{' '}') || refuse "shelf/Panel.qml has no single mask Region block"
  if [[ "$mask_qml" == *railCut* ]]; then
    cut_qml=$(shipped_item '^ *readonly property var railCut:' '(' ')') || refuse "shelf/Panel.qml mask names railCut but has no single railCut item"
  fi
else
  mask_qml='mask: Region { width: panel.screenW; height: panel.screenH }'
fi

# Real rail and service; the card is a stand-in whose mask and railCut are Panel.qml's own text in product mode.
cat > "$work/cfg/harness.qml" <<EOF
import QtQuick
import Quickshell
import Quickshell.Wayland
import "shelf/" as ShelfFiles
import "shelf/Model.js" as Model
ShellRoot {
  id: root
  property bool carrying: false
  property string work: "$work"
  property string fleaBin: "$flea_bin"
$cut_qml
  ShelfFiles.ShelfService {
    id: service
    settings: ({ fleaCommand: root.fleaBin })
  }
  ShelfFiles.ShelfRail {
    id: rail
    edge: service.railEdge
    dwellMs: service.railDwellMs
    held: 0
    onDropped: function (paths) { service.addAll(paths) }
    onDwelled: {
      panel.open = true
      Quickshell.execDetached(["sh", "-c", "printf 'open\\n' >> '" + root.work + "/card-opened'"])
    }
  }
  // Drag source: a held press carries the sandbox file as a copy offer.
  PanelWindow {
    id: source
    WlrLayershell.namespace: "flea-shelfrail-probe-source"
    WlrLayershell.layer: WlrLayer.Top
    anchors { top: true; left: true }
    width: 900; height: 500
    color: "#202020"
    Rectangle {
      id: handle
      x: 100; y: 100; width: 120; height: 60
      color: "#404040"
      Drag.mimeData: ({ "text/uri-list": "file://$work/src/dropme.txt" })
      Drag.supportedActions: Qt.CopyAction
      // An internal drag never leaves its window, so the offer goes out as a system drag the rail can take.
      Drag.dragType: Drag.Automatic
      MouseArea {
        anchors.fill: parent
        onPressed: handle.Drag.active = true
      }
      Timer { interval: 30000; running: true; onTriggered: handle.Drag.active = false }
    }
  }
  // The card stand-in: full-screen Overlay above the rail, no DropArea by design.
  PanelWindow {
    id: panel
    property bool open: false
    readonly property real screenW: width
    readonly property real screenH: height
    visible: open
    WlrLayershell.namespace: "flea-shelfrail-probe-card"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
$mask_qml
    Rectangle {
      anchors.centerIn: parent
      width: 380; height: 200
      color: "#303030"
      MouseArea { anchors.fill: parent }
    }
  }
}
EOF

export XDG_STATE_HOME="$work/state"
setsid qs -p "$work/cfg/harness.qml" >"$work/qs.log" 2>&1 &
qs_pid=$!
# Layer entry geometry for a namespace: monitor, x, y, w, h (one line, space separated).
layer_geom() {
  hyprctl layers -j 2>/dev/null | jq -er --arg ns "$1" '[to_entries[] | .key as $mon | .value.levels[]?[]? | select(.namespace == $ns) | [$mon, .x, .y, .w, .h]] | if length == 1 then .[0] | join(" ") else empty end'
}
up=""
for _ in $(seq 1 40); do
  layer_geom flea-shelf-rail >/dev/null 2>&1 && up=1 && break
  sleep 0.25
done
[ -n "$up" ] || refuse "probe rail surface never mapped (see $work/qs.log)"
# The rail and the source must share one scale-1 monitor, or the pointer math is unsound.
mon_geom() {
  hyprctl monitors -j 2>/dev/null | jq -er --arg name "$1" '[.[] | select(.name == $name)] | if length == 1 then .[0] | "\(.x) \(.y) \(.scale) \(.width) \(.height)" else empty end'
}
# Hyprland lists a layer before its first arrange, so trust only two equal reads whose centre lies on the monitor.
rail_geom="" prev=""
for _ in $(seq 1 40); do
  cur=$(layer_geom flea-shelf-rail) || refuse "probe rail vanished"
  read -r rail_mon rail_x rail_y rail_w rail_h <<< "$cur"
  mon_line=$(mon_geom "$rail_mon") || refuse "no geometry for monitor $rail_mon"
  read -r mon_x mon_y mon_scale mon_w mon_h <<< "$mon_line"
  cx=$((rail_x + rail_w / 2)); cy=$((rail_y + rail_h / 2))
  if [ "$cur" = "$prev" ] && (( cx >= 0 && cx < mon_w && cy >= 0 && cy < mon_h )); then
    rail_geom=$cur; break
  fi
  prev=$cur
  sleep 0.25
done
[ -n "$rail_geom" ] || refuse "rail geometry never settled on its monitor (last $cur on $mon_line)"
out "rail $rail_geom on monitor $mon_line"
src_geom=$(layer_geom flea-shelfrail-probe-source) || refuse "probe source never mapped"
read -r src_mon src_x src_y _ _ <<< "$src_geom"
[ "$rail_mon" = "$src_mon" ] || refuse "rail on $rail_mon but source on $src_mon, one monitor per run"
[ "$mon_scale" = "1.0" ] || [ "$mon_scale" = "1" ] || refuse "monitor $rail_mon is at scale $mon_scale, this probe needs 1"
# Handle centre and rail strip centre, in global pointer coordinates.
hx=$((mon_x + src_x + 160)); hy=$((mon_y + src_y + 130))
dx=$((mon_x + cx)); dy=$((mon_y + cy))
pointer_glide "$hx" "$hy" || refuse "pointer did not reach the handle at $hx,$hy"
ydotool click 0x40 >/dev/null 2>&1 || refuse "pointer press failed"
sleep 0.3
pointer_glide "$dx" "$dy" || refuse "pointer did not reach the rail at $dx,$dy"
# Past the 120 ms dwell: the card must be open before the release, which is the bug condition.
opened=""
for _ in $(seq 1 50); do
  [ -f "$work/card-opened" ] && opened=1 && break
  sleep 0.1
done
[ -n "$opened" ] || refuse "card never opened past the dwell, so the release proves nothing"
sleep 0.5
ydotool click 0x80 >/dev/null 2>&1 || refuse "pointer release failed"
landed=""
for _ in $(seq 1 30); do
  if jq -e --arg path "$work/src/dropme.txt" 'any(.items[]?; .path == $path)' "$work/state/omarchy/flea-shelf/shelf.json" >/dev/null 2>&1; then
    landed=1; break
  fi
  sleep 0.5
done
if [ "$mode" = "full" ]; then
  [ -z "$landed" ] || refuse "full mask took the drop, so this run does not reproduce the report"
  out "FAIL drop lost after the card opened (v0.3.8 mask reproduced)"
  exit 1
fi
[ -n "$landed" ] || refuse "drop lost after the card opened (see $work/qs.log)"
out "PASS drop landed after the card opened"
