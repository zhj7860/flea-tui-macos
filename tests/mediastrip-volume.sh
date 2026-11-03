#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# The Quick Look media strip's volume track on the real ui/MediaStrip.qml, offscreen: Media040's geometry, the live drag and the one save on release, mute apart from the level, and no track in the framed strip.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "mediastrip-volume.sh: qs is not installed, cannot draw the strip"
    exit 1
fi

verdict=0
# What an attached property or another file's binding keeps out of the harness's reach, read from the source.
# Sample input: the track's `Accessible.role: Accessible.Slider` and `Accessible.name: "Volume"` lines in ui/MediaVolume.qml.
for line in 'Accessible.role: Accessible.Slider' 'Accessible.name: "Volume"'; do
    grep -qF "$line" ui/MediaVolume.qml || { printf 'FAIL ui/MediaVolume.qml no longer holds %s\n' "$line"; verdict=1; }
done
# Both tracks fill and draw their handle in the accent frame ink, never the raw accent, which a low-chroma theme leaves under 3:1 on the strip.
[ "$(grep -c 'color: Theme.color.accentFrame' ui/MediaTrack.qml)" -eq 2 ] && ! grep -qE 'Theme\.color\.accent([^F]|$)' ui/MediaTrack.qml ui/MediaStrip.qml ui/MediaVolume.qml \
    || { printf 'FAIL the media tracks do not draw their fill and handle in Theme.color.accentFrame alone\n'; verdict=1; }
# One AudioOutput serves the column and Quick Look, so the converted level reaches every player through it.
players=$(grep -rl 'AudioOutput {' ui --include='*.qml' | tr '\n' ' ')
[ "$players" = 'ui/PreviewMedia.qml ' ] || { printf 'FAIL the players are [%s], want ui/PreviewMedia.qml alone\n' "$players"; verdict=1; }
grep -qF 'volume: Flea.MediaSound.gain' ui/PreviewMedia.qml || { printf 'FAIL ui/PreviewMedia.qml does not play at MediaSound.gain\n'; verdict=1; }

# A marked sandbox of its own under the fixture root, so cleanup deletes only what this run owns.
test_root=$(mktemp -d "$FIXTURE_ROOT/flea-mediastrip-volume-XXXXXX") || exit 1
# GNU mktemp -d keeps a relative TMPDIR verbatim, so the path is checked absolute and two components deep.
case $test_root in
  /*/*) ;;
  *) echo "FAIL: mktemp -d gave '$test_root', which is not an absolute path two components deep"; exit 1 ;;
esac
sandbox_require "$test_root" || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state/flea" "$test_root/runtime" "$test_root/bin" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/mediastrip-volume.qml "$test_root/config/shell.qml" || exit 1

# The level ui.json holds before the strip is built; the first frame has to draw it.
stored=60
printf '{"preview":{"volume":%s}}\n' "$stored" > "$test_root/state/flea/ui.json" || exit 1
saves="$test_root/saves.log"
: > "$saves" || exit 1
# Stands for flea --ui-state PATCH: it records the patch it was asked to store and stores nothing.
printf '#!/bin/sh\nprintf "%%s\\n" "$2" >> "$MEDIASTRIPVOL_SAVES"\n' > "$test_root/bin/flea-stub" || exit 1
chmod +x "$test_root/bin/flea-stub" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    FLEA_BIN="$test_root/bin/flea-stub" MEDIASTRIPVOL_SAVES="$saves" MEDIASTRIPVOL_STORED="$stored" \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 60 qs -p "$test_root/config" 2>&1)
qs_status=$?

# Sample input: "  INFO qml: MEDIASTRIPVOL PASS 52 checks", then "MEDIASTRIPVOL DONE failures=0", then the probe's own SIGTERM (143).
pass_count=$(printf '%s\n' "$output" | grep -c 'MEDIASTRIPVOL PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'MEDIASTRIPVOL FAIL')
done_count=$(printf '%s\n' "$output" | grep -c 'MEDIASTRIPVOL DONE')
if [ "$qs_status" -ne 143 ]; then
    printf 'FAIL qs exited %s, want the owned self-kill 143 after DONE\n' "$qs_status"
    verdict=1
fi
if [ "$done_count" -ne 1 ]; then
    printf 'FAIL completion receipts %s, want exactly 1 DONE beside the PASS\n' "$done_count"
    verdict=1
fi
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL the media strip missed its volume contract\n'
    printf '%s\n' "$output" | grep -aE 'MEDIASTRIPVOL|ERROR|error'
    verdict=1
fi
# The offscreen platform itself says it cannot mask a FloatingWindow; that one line is the platform's, never the strip's.
platform_warning='This plugin does not support setting window masks'
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN|ERROR' | grep -vF "$platform_warning")
if [ -n "$warnings" ]; then
    printf 'FAIL the strip harness logged a warning\n'
    printf '%s\n' "$warnings"
    verdict=1
fi
if [ "$verdict" -ne 0 ]; then
    printf '%s\n' "$output"
    exit 1
fi
printf '%s\n' "$output" | grep -o 'MEDIASTRIPVOL PASS.*'
printf 'MEDIASTRIPVOL STATUS qs_exit=%s done=1\n' "$qs_status"
