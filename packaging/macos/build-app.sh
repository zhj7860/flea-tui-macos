#!/bin/sh
# Builds Flea.app: the release binary inside a macOS bundle whose Finder entry opens the TUI in
# Terminal. Usage: packaging/macos/build-app.sh [output directory]   (default: ./dist)
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
if [ -n "${FLEA_BIN:-}" ]; then
    bin=$FLEA_BIN
else
    (cd "$root" && cargo build --release --locked)
    bin=$root/target/release/flea
fi
[ -x "$bin" ] || { echo "flea-macos-app: no release binary at $bin" >&2; exit 1; }
version=$(sed -n 's/^version = "\(.*\)"$/\1/p' "$root/Cargo.toml" | head -1)
[ -n "$version" ] || { echo "flea-macos-app: no version in $root/Cargo.toml" >&2; exit 1; }
exec "$root/packaging/macos/build-tui-app.sh" \
    --name Flea --id com.thisisgm.flea --binary "$bin" --version "$version" \
    --icon "$root/packaging/com.thisisgm.flea.svg" --args "--tui" "${1:-$root/dist}"
