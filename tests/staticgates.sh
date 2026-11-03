#!/usr/bin/env bash
# Thirteen gates share one scanner (worker-report judges paths, the rest read source); controls run first.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -B tests/staticgates_tests.py
exec python3 -B tests/staticgates.py "$@"
