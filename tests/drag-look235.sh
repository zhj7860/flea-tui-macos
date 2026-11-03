#!/usr/bin/env bash
# Capture only PR 235's four native states with the existing relative-input drag driver.
exec bash "$(dirname "$0")/drag.sh" look235
