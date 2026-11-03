#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# A held j through a real Pane on 10,000 files, offscreen with the real backend: requests by kind, swap holds and rebinds per sweep, counts only.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
command -v qs >/dev/null || { echo 'FAIL columns-held: qs is missing'; exit 1; }
root=$(mktemp -d "$FIXTURE_ROOT/columns-held-XXXXXXXX") || exit 1
sandbox_require "$root" || exit 1
: > "$root/$SANDBOX_MARKER" || exit 1
trap 'sandbox_remove "$root"' EXIT
mkdir -p "$root/config" "$root/home" "$root/state/flea" "$root/cache" "$root/runtime" "$root/fixture" "$root/bin" || exit 1
chmod 700 "$root/runtime" || exit 1
ln -s "$PWD/ui" "$root/config/flea" || exit 1
headless_commons "$root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$root/config/Ui" || exit 1
cp tests/columns-held.qml "$root/config/shell.qml" || exit 1
files=10000
for i in $(seq -w 1 "$files"); do : > "$root/fixture/file-$i.txt"; done
# The backend sits behind tee, so every request line the window writes is kept and the probe counts them by kind.
cat > "$root/bin/flea-shim" <<'SHIM'
#!/bin/bash
tee -a "$FLEA_COLHELD_REQLOG" | exec "$FLEA_COLHELD_REAL" "$@"
SHIM
chmod 755 "$root/bin/flea-shim" || exit 1

# One qs run: the probe sweeps the list first and then switches the same Pane to columns.
log="$root/probe.log"
printf '%s\n' '{"updates":{"autoCheck":false},"view":"list"}' > "$root/state/flea/ui.json" || exit 1
: > "$root/req.log"
env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$root/home" XDG_STATE_HOME="$root/state" XDG_CACHE_HOME="$root/cache" XDG_RUNTIME_DIR="$root/runtime" \
    FLEA_BIN="$root/bin/flea-shim" FLEA_COLHELD_REAL="$PWD/target/debug/flea" FLEA_COLHELD_REQLOG="$root/req.log" \
    FLEA_COLHELD_DIR="$root/fixture" FLEA_COLHELD_FILES="$files" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 150 qs -p "$root/config" > "$log" 2>&1
status=$?
cat "$log"
[ "$status" -eq 0 ] || { printf 'FAIL columns-held: qs exit %s\n' "$status"; exit 1; }
# Sample input, one probe line: " DEBUG qml: COLHELD DONE 11 checks, 0 failed"
[ "$(grep -c 'COLHELD DONE .* checks, 0 failed' "$log")" -eq 1 ] \
    || { echo 'FAIL columns-held: no single "COLHELD DONE ... 0 failed" summary line'; exit 1; }
grep -qE 'COLHELD FAIL|TypeError|ReferenceError' "$log" \
    && { echo 'FAIL columns-held: the probe log holds a COLHELD FAIL, TypeError or ReferenceError line'; exit 1; }
echo 'columns-held: a held j in columns asks the backend and rebinds like the list, holds at its floor and shows no half-built frame'
