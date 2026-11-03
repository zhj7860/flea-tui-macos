#!/bin/bash
# The committed charts in docs/images/ must be exactly what the generator makes from the bench CSVs,
# so a re-run that moves a number cannot leave a chart quietly claiming the old one.
set -u
cd "$(dirname "$0")/.." || exit 1

bench=${FLEA_BENCH_DIR:-docs/bench}
for csv in scale-rc-2026.csv media-rc-2044.csv; do
  # These ship in the repo. A missing one used to skip and still print ok, which is green on
  # every machine that is not the box the bench was run on.
  if [ ! -f "$bench/$csv" ]; then
    echo "FAIL $bench/$csv is missing, so the charts cannot be checked"
    exit 1
  fi
done

art="bench-scale.svg bench-scale-social.svg bench-scale-social.png
     bench-media.svg bench-media-social.svg bench-media-social.png"

out_dir=$(mktemp -d)
# Same check keymap-gen.sh and budget.sh carry: GNU mktemp honours a relative TMPDIR verbatim, so
# the path is confirmed absolute and two components deep before the trap that deletes it.
case $out_dir in
  /*/*) ;;
  *) echo "FAIL: mktemp gave '$out_dir', which is not an absolute path two components deep"; exit 1 ;;
esac
trap 'rm -rf "$out_dir"' EXIT

./tools/flea-bench-chart "$out_dir" >/dev/null || { echo "FAIL the generator did not run"; exit 1; }

stale=0
for f in $art; do
  if [ ! -s "$out_dir/$f" ]; then
    echo "FAIL the generator wrote no $f"
    stale=1
  elif ! cmp -s "$out_dir/$f" "docs/images/$f"; then
    echo "FAIL docs/images/$f is stale, run ./tools/flea-bench-chart"
    stale=1
  fi
done

[ "$stale" -eq 0 ] || exit 1
echo "ok   the 6 charts in docs/images match the bench CSVs"
