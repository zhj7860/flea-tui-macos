#!/usr/bin/env bash
# A real DNG through the live backend's RAW extraction, meta and Properties requests.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
. "$repo/tools/flea-sandbox-guard"
sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-raw-fixture.XXXXXXXX")
[[ -n "$test_root" && "$test_root" == /* ]] || exit 1
: > "$test_root/$SANDBOX_MARKER"
trap 'sandbox_remove "$test_root"' EXIT
mkdir -p "$test_root"/{raw,cache,state,home,undo}
: > "$test_root/raw/$SANDBOX_MARKER"
python3 -B "$repo/tests/fixtures/raw/generate.py" "$test_root/raw"
(cd "$test_root/raw" && sha256sum --check "$repo/tests/fixtures/raw/SHA256SUMS")
python3 -B "$repo/tests/fixtures/raw/check_tests.py" "$test_root"
timeout 90 python3 -B "$repo/tests/fixtures/raw/check.py" "${FLEA_BIN:-$repo/target/debug/flea}" "$test_root"
printf 'raw-fixture: real DNG, preview decode and photo facts passed\n'
