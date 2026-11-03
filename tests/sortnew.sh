#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# Real browser views, column peeks and picker lists over localized XDG folders, then a fresh process reads an explicit Name choice.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. tools/flea-sandbox-guard
command -v qs >/dev/null || { echo 'FAIL sortnew: qs is required'; exit 1; }
bin=${FLEA_BIN:-$PWD/target/debug/flea}
[ -x "$bin" ] || { echo "FAIL sortnew: no backend at $bin"; exit 1; }
sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-sortnew.XXXXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
mkdir -p "$test_root"/{config,xdg,state/flea,cache,data,runtime,tmp,home/.config} || exit 1
chmod 700 "$test_root/runtime" || exit 1
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/sortnew.qml "$test_root/config/shell.qml" || exit 1
for dir in Inbox 'Photo Library' Clips Documents; do
    folder="$test_root/home/$dir"
    mkdir -p "$folder/folder" || exit 1
    printf 'old\n' > "$folder/a-old.txt"
    printf 'new\n' > "$folder/z-new.txt"
    printf 'hidden\n' > "$folder/.hidden.txt"
    touch -d '2020-01-01 UTC' "$folder/folder" "$folder/a-old.txt" || exit 1
    touch -d '2025-01-01 UTC' "$folder/z-new.txt" || exit 1
    touch -d '2026-01-01 UTC' "$folder/.hidden.txt" || exit 1
done
printf '%s\n' 'XDG_DOWNLOAD_DIR="$HOME/Old Inbox"' 'XDG_PICTURES_DIR="relative"' \
    'XDG_VIDEOS_DIR="$HOME"' 'XDG_DOWNLOAD_DIR="$HOME/Inbox"' 'XDG_PICTURES_DIR="$HOME/Photo Library"' \
    'XDG_VIDEOS_DIR="$HOME/Clips"' 'XDG_DOCUMENTS_DIR="$HOME/Documents"' \
    'XDG_DOWNLOAD_DIR="relative"' 'XDG_PICTURES_DIR="$HOME/Unterminated' > "$test_root/xdg/user-dirs.dirs"
request=$(printf '{"mode":"open","folder":"%s","title":"Newest first"}' "$test_root/home/Inbox")
for phase in fresh restart; do
    log="$test_root/$phase.log"
    env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
        HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/xdg" XDG_STATE_HOME="$test_root/state" \
        XDG_CACHE_HOME="$test_root/cache" XDG_DATA_HOME="$test_root/data" XDG_RUNTIME_DIR="$test_root/runtime" TMPDIR="$test_root/tmp" \
        QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
        FLEA_BIN="$bin" FLEA_PICKER="$request" FLEA_PICKER_REPLY="$test_root/reply.json" SORTNEW_PHASE="$phase" \
        timeout 90 qs -p "$test_root/config" > "$log" 2>&1
    code=$?
    sed -n '/SORTNEW/p' "$log"
    if [ "$code" -ne 0 ] || ! grep -q 'SORTNEW DONE .* 0 failed' "$log"; then
        echo "FAIL sortnew $phase: exit=$code"
        tail -12 "$log"
        exit 1
    fi
    if grep -aE 'TypeError|ReferenceError|Binding loop|Unable to assign|Cannot assign' "$log"; then
        echo "FAIL sortnew $phase: engine warning"
        exit 1
    fi
    if [ "$phase" = fresh ]; then
        python3 - "$test_root/state/flea/ui.json" "$test_root/home/Inbox" <<'PY'
import json, sys
state = json.load(open(sys.argv[1]))
assert state['folderSorts'] == {sys.argv[2]: {'key': 'name', 'reverse': False}}, state['folderSorts']
print('SORTNEW PASS only explicit Name ascending occupies the persisted map')
PY
        [ "$?" -eq 0 ] || exit 1
    fi
done
