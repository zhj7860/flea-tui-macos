#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# The Trash view keeps the order the backend gives its rows, opens with the cursor on the first row, and m opens the cursor row's menu under that row; offscreen, no display or lock. The backend's own order is tested in src/backend/trashbrowse.rs, and nothing here reads a Trash.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "trash-view.sh: qs is not installed, cannot build the Trash view"
    exit 1
fi

# A marked sandbox of its own under the fixture root, so cleanup deletes only what this run owns.
test_root=$(mktemp -d "$FIXTURE_ROOT/flea-trash-view-XXXXXX") || exit 1
# GNU mktemp -d keeps a relative TMPDIR verbatim, so the path is checked absolute and two components deep.
case $test_root in
  /*/*) ;;
  *) echo "FAIL: mktemp -d gave '$test_root', which is not an absolute path two components deep"; exit 1 ;;
esac
sandbox_require "$test_root" || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/cache" "$test_root/runtime" || exit 1
chmod 700 "$test_root/runtime" || exit 1

# The rows as the backend answers them, newest deleted first: name, deleted, directory flag, icon. No Trash is read here; the harness fakes every reply.
data="$test_root/data"
mkdir -p "$data" || exit 1
rows=""
while IFS=$'\t' read -r name date dir icon; do
    row=$(printf '{"uri":"trash:///%s","original":"%s","size":1,"deleted":"%s","directory":%s,"icon":"%s","identity":"id-%s","bulkSelected":false}' \
        "$name" "$test_root/orig/$name" "$date" "$dir" "$icon" "$name")
    rows="${rows:+$rows,}$row"
done <<TABLE
photo.png	2026-10-05T09:00:00	false	image-png
notes.txt	2026-10-03T09:00:00	false	text-x-generic
old-folder	2026-10-01T09:00:00	true	folder
TABLE

# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
ln -s "$PWD/ui/boot/fleatab.qml" "$test_root/config/fleatab.qml" || exit 1
cp tests/qml-probe.js "$test_root/config/qml-probe.js" || exit 1
cp tests/trash-view.qml "$test_root/config/shell.qml" || exit 1

# The harness ends itself with a kill, so the subshell keeps bash's "Terminated" notice out of the report.
output=$( ( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_DATA_HOME="$data" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" TRASHVIEW_ROWS="[$rows]" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 QT_FORCE_STDERR_LOGGING=1 \
    timeout 30 qs -p "$test_root/config" 2>&1 ) 2>/dev/null )

# Sample input, the verdict lines: "  INFO qml: TRASHVIEW PASS 24 checks" and "  INFO qml: TRASHVIEW DONE checks=24 failed=0".
done_count=$(printf '%s\n' "$output" | grep -c 'TRASHVIEW DONE checks=[0-9]* failed=0$')
pass_count=$(printf '%s\n' "$output" | grep -c 'TRASHVIEW PASS ')
if [ "$done_count" -ne 1 ] || [ "$pass_count" -ne 1 ] || printf '%s\n' "$output" | grep -q 'TRASHVIEW FAIL'; then
    printf 'FAIL the Trash view order, landing or m target is not as drawn\n'
    printf '%s\n' "$output" | head -40
    exit 1
fi
# The offscreen platform itself says it cannot mask a FloatingWindow; that one line is the platform's, never the view's.
platform_warning='This plugin does not support setting window masks'
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN' | grep -vF "$platform_warning")
if [ -n "$warnings" ]; then
    printf 'FAIL the Trash view logged a warning\n'
    printf '%s\n' "$warnings"
    exit 1
fi
printf '%s\n' "$output" | grep -o 'TRASHVIEW PASS.*'
