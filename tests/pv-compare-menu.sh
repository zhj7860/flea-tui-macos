#!/usr/bin/env bash
# Runs the real menu harness with pv-compare's existing marked fixture and teardown checks.
export PVCMP_MENU_ONLY=1
exec /bin/bash "$(dirname "$0")/pv-compare.sh"
