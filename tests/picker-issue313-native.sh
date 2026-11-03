#!/usr/bin/env bash
# Opt-in minipc proof. FLEA_DISPLAY_LOCK_FD inherits the native runner's existing display lock.
set -euo pipefail
cd "$(dirname "$0")/.."
export FLEA_BIN="${FLEA_BIN:-$PWD/target/release/flea}"
export FLEA_UI="${FLEA_UI:-$PWD/ui}"
: "${FLEA_EXPECTED_SHA:?set the exact committed candidate SHA}"
proof=$(mktemp -d /tmp/flea-ui-run.issue313.XXXXXXXX)
: > "$proof/.flea-test-sandbox"
mkdir -m700 "$proof/evidence" "$proof/cache" "$proof/runtime"
printf 'NATIVE_EVIDENCE_ROOT=%s\n' "$proof"
qt_status=not-run
native_status=not-run
version=unknown
finish() {
    local status=$? native_root
    set +e
    # Sample log entry: PICKER_EVIDENCE /tmp/flea-picker-native-AbCd1234
    native_root=$(sed -n 's/^PICKER_EVIDENCE //p' "$proof/evidence/native.log" 2>/dev/null | head -1)
    if [[ "$native_root" == /tmp/flea-picker-native-?* && -d "$native_root" && ! -L "$native_root" && -f "$native_root/.flea-test-sandbox" ]]; then
        mkdir -p "$proof/evidence/native"
        cp -a "$native_root/." "$proof/evidence/native/" || status=1
    else
        printf 'FAIL picker native evidence directory %q missing or invalid (source %q)\n' "$native_root" "$proof/evidence/native.log" >&2
        [[ "$status" != 0 ]] || status=1
    fi
    python3 - "$proof/evidence/result.json" "$status" "$qt_status" "$native_status" "$version" "$FLEA_EXPECTED_SHA" "$native_root" <<'PY'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps(dict(exit=int(sys.argv[2]), qtPickerExit=sys.argv[3], nativeExit=sys.argv[4],
    qtVersion=sys.argv[5], expectedSourceSHA=sys.argv[6], nativeEvidence=sys.argv[7]), indent=2))
PY
    [[ "$?" == 0 ]] || status=1
    printf 'ISSUE313 exit=%s qt-picker=%s native=%s evidence=%s/evidence\n' "$status" "$qt_status" "$native_status" "$proof"
    exit "$status"
}
trap finish EXIT
version=$(QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic qml6 --version)
printf '%s\n' "$version" | tee "$proof/evidence/qt-version.txt"
[[ "$version" =~ 6\.12\.[0-9]+$ ]] || { echo 'FAIL issue313 requires actual Qt 6.12'; exit 1; }
git --no-optional-locks rev-parse HEAD > "$proof/evidence/source-sha.txt"
sha256sum "$FLEA_BIN" ui/js/Picker.js ui/PickerWindow.qml tools/flea-portal > "$proof/evidence/candidate-sha256.txt"
set +e
XDG_CACHE_HOME="$proof/cache" XDG_RUNTIME_DIR="$proof/runtime" QML_DISABLE_DISK_CACHE=1 \
    timeout --signal=INT --kill-after=15s 150s bash tests/js.sh picker > "$proof/evidence/qt612-picker.log" 2>&1
qt_status=$?
set -e
cat "$proof/evidence/qt612-picker.log"
[[ "$qt_status" == 0 ]] || exit "$qt_status"
set +e
timeout --signal=INT --kill-after=35s 6m python3 -B tests/picker-native.py issue313 > "$proof/evidence/native.log" 2>&1
native_status=$?
set -e
cat "$proof/evidence/native.log"
[[ "$native_status" == 0 ]] || exit "$native_status"
grep -q 'picker-native: .* checks, 0 failed' "$proof/evidence/native.log"
