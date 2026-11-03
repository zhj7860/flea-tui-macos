#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# The opener's own contract, on the real ui/Opener.qml against a stub flea, offscreen.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1

if ! command -v qs >/dev/null; then
    echo "opener-ask.sh: qs is not installed, cannot measure the opener"
    exit 1
fi

# A marked sandbox of its own under the fixture root, so cleanup deletes only what this run owns.
test_root=$(mktemp -d "$FIXTURE_ROOT/flea-opener-ask-XXXXXX") || exit 1
# GNU mktemp -d keeps a relative TMPDIR verbatim, so the path is checked absolute and two components deep.
case $test_root in
  /*/*) ;;
  *) echo "FAIL: mktemp -d gave '$test_root', which is not an absolute path two components deep"; exit 1 ;;
esac
sandbox_require "$test_root" || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

mkdir -p "$test_root/config" "$test_root/home" "$test_root/state" "$test_root/runtime" "$test_root/bin" || exit 1
chmod 700 "$test_root/runtime" || exit 1
# The probe imports ui/ as Flea, and ui/'s qs.Commons resolves against this root, as it does from ui/boot.
ln -s "$PWD/ui" "$test_root/config/flea" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp tests/opener-ask.qml "$test_root/config/shell.qml" || exit 1

# The stub flea answers by path: an ask line with 4, a bare 4 with no line, Open with with 5, a directory with 3, silence with 0, refusal otherwise, and one slow lane held until the probe releases it.
cat > "$test_root/bin/flea" <<'EOF'
#!/bin/sh
# Sample argv: flea --open /ask/tool.sh answers the run card's own ask line.
ask='{"ask":"run","kind":"script","size":8,"handlerId":"","handlerName":"","dev":"8","ino":"9","mtimeS":11,"mtimeNs":12,"target":"/real/tool.sh"}'
case "$2" in
  /noline/*) exit 4;;
  /ask/*) printf '%s' "$ask"; exit 4;;
  /with/*) exit 5;;
  /dir/*) exit 3;;
  /slow/*) while [ ! -e "$FLEA_TEST_RELEASE" ] && [ -d "${FLEA_TEST_RELEASE%/*}" ]; do sleep 0.05; done; exit 0;;
  /ok/*) exit 0;;
  *) exit 1;;
esac
EOF
chmod +x "$test_root/bin/flea" || exit 1

output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    FLEA_BIN="$test_root/bin/flea" FLEA_TEST_RELEASE="$test_root/release" \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_RUNTIME_DIR="$test_root/runtime" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_FORCE_STDERR_LOGGING=1 \
    timeout 60 qs -p "$test_root/config" 2>&1)
qs_status=$?

# Sample input: "  INFO qml: OPENER PASS 8 checks", then "OPENER DONE failures=0", then the probe's own SIGTERM (143).
pass_count=$(printf '%s\n' "$output" | grep -c 'OPENER PASS')
fail_count=$(printf '%s\n' "$output" | grep -c 'OPENER FAIL')
done_count=$(printf '%s\n' "$output" | grep -c 'OPENER DONE')
verdict=0
if [ "$qs_status" -ne 143 ]; then
    printf 'FAIL qs exited %s, want the owned self-kill 143 after DONE\n' "$qs_status"
    verdict=1
fi
if [ "$done_count" -ne 1 ]; then
    printf 'FAIL completion receipts %s, want exactly 1 DONE beside the PASS\n' "$done_count"
    verdict=1
fi
if [ "$pass_count" -ne 1 ] || [ "$fail_count" -ne 0 ]; then
    printf 'FAIL the opener missed its contract\n'
    printf '%s\n' "$output" | grep -aE 'OPENER|ERROR|error'
    verdict=1
fi
# The offscreen platform itself says it cannot mask a FloatingWindow; that one line is the platform's, never the opener's.
platform_warning='This plugin does not support setting window masks'
# The nostart scene's own launch, which Quickshell reports once as a warning and never as an exit.
nostart_warning='Process failed to start'
nostart_count=$(printf '%s\n' "$output" | grep -acF "$nostart_warning")
if [ "$nostart_count" -ne 1 ]; then
    printf 'FAIL failed-start warnings %s, want exactly 1 from the nostart scene\n' "$nostart_count"
    verdict=1
fi
warnings=$(printf '%s\n' "$output" | grep -aE 'TypeError|ReferenceError|WARN|ERROR' | grep -vF -e "$platform_warning" -e "$nostart_warning")
if [ -n "$warnings" ]; then
    printf 'FAIL the opener harness logged a warning\n'
    printf '%s\n' "$warnings"
    verdict=1
fi
if [ "$verdict" -ne 0 ]; then
    printf '%s\n' "$output"
    exit 1
fi
printf '%s\n' "$output" | grep -o 'OPENER PASS.*'
printf 'OPENER STATUS qs_exit=%s done=1\n' "$qs_status"
