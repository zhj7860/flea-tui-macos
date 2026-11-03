#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# CSV and TSV as a table in the preview column and in Quick Look over the real backend: the header, the numbers, the frozen widths across a 49,999-row scroll, the quoted newline, the binary, large and empty frames. Offscreen, in the flea-ci image.
set -uo pipefail
. "$(dirname "$0")/../tools/flea-sandbox-guard"
. "$(dirname "$0")/qslog-gate.sh"
cd "$(dirname "$0")/.." || exit 1
for tool in qs dbus-run-session; do
    command -v "$tool" >/dev/null || { printf 'FAIL csv-preview: %s is required; this suite runs in the flea-ci image\n' "$tool"; exit 1; }
done
bin=${FLEA_BIN:-$PWD/target/debug/flea}
[ -x "$bin" ] || { printf 'FAIL csv-preview: build the backend first: %s\n' "$bin"; exit 1; }
sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-csv-preview.XXXXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER"
sandbox_make "$test_root"
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT
mkdir -p "$test_root"/{config,fixture,home,state/flea,cache,runtime} || exit 1
chmod 700 "$test_root/runtime" || exit 1
headless_commons "$test_root" || exit 1
ln -s "$(readlink -m ui/boot/Ui)" "$test_root/config/Ui" || exit 1
cp -a ui "$test_root/config/flea" || exit 1
cp tests/csv-preview.qml "$test_root/config/shell.qml" || exit 1
cp tests/csv-records.js "$test_root/config/CsvRecords.js" || exit 1
printf '{}\n' > "$test_root/state/flea/ui.json"

# Fixtures preserve the board's 24 rows and put later long names beyond big.csv's first screen.
fixture="$test_root/fixture"
preview_bytes=$((1024 * 1024))
setup_start=$EPOCHREALTIME
{
    printf 'fixture,files,folders,depth\n'
    names=(photos music code mixed nested flat)
    depths=(3 4 9 6 12 1)
    suffixes=(1k 10k 100k 1m)
    for ((g = 0; g < ${#names[@]}; g++)); do
        files=1000
        for suffix in "${suffixes[@]}"; do
            printf '%s-%s,%d,%d,%d\n' "${names[g]}" "$suffix" "$files" "$((files / 50))" "${depths[g]}"
            files=$((files * 10))
        done
    done
} > "$fixture/bench.csv"
{
    printf 'name,size,kind,modified\n'
    for ((i = 1; i <= 24; i++)); do
        printf -v name 'file-%02d.txt' "$i"
        [ "$i" -ne 1 ] || name=a-first-name-long-enough-to-stretch-the-first-column-well-past-its-header-and-keep-going-on-and-on
        kind=text
        [ "$((i % 3))" -ne 0 ] || kind=image
        printf '%s,%d,%s,2026-09-%02d\n' "$name" "$((i * 1234 % 99991))" "$kind" "$i"
    done
} > "$fixture/long.csv"
{
    sep=
    for ((c = 1; c <= 12; c++)); do printf '%sc%02d' "$sep" "$c"; sep=,; done
    printf '\n'
    for ((r = 1; r <= 3; r++)); do
        sep=
        for ((c = 1; c <= 12; c++)); do printf '%svalue-%d-%02d-xxxxxx' "$sep" "$r" "$c"; sep=,; done
        printf '\n'
    done
} > "$fixture/wide.csv"
{
    printf 'id,name,size\n'
    for ((i = 1; i <= 49999; i++)); do
        if [ "$i" -ge 60 ] && [ "$i" -le 64 ]; then
            printf -v name '%0120d' "$i"
        else
            printf -v name 'f%05d' "$i"
        fi
        printf '%d,%s,%d\n' "$i" "$name" "$((i * 7))"
    done
} > "$fixture/big.csv"
[ "$(stat -c %s "$fixture/big.csv")" -le "$preview_bytes" ] || { printf 'FAIL csv-preview: big.csv must stay under 1 MiB\n'; exit 1; }
printf 'id,note\n1,"two\nlines",3\n2,plain\n' > "$fixture/quoted.csv"
# Multiline records at the top, beyond the first window and at EOF, in both delimiters.
for extension in csv tsv; do
    separator=,
    [ "$extension" != tsv ] || separator=$'\t'
    for ending in closed open; do
        {
            printf 'id%snote\n' "$separator"
            for ((i = 1; i <= 801; i++)); do
                case "$i" in
                    1) printf '1%s"first\nsecond"\n' "$separator" ;;
                    450) printf '450%s"middle\nsecond\nthird"\n' "$separator" ;;
                    801)
                        printf '801%s"last\nend' "$separator"
                        [ "$ending" != closed ] || printf '"'
                        printf '\n'
                        ;;
                    *) printf '%d%srow%d\n' "$i" "$separator" "$i" ;;
                esac
            done
        } > "$fixture/records-$ending.$extension"
    done
done

printf 'a\tb\tc\n1\tx,y\t3\n4\t5\t6\n' > "$fixture/fixture.tsv"
printf 'a,b\0c\n1,2\n' > "$fixture/nul.csv"
yes 'a,b,c' | head -c "$((preview_bytes + 1))" > "$fixture/over.csv"
: > "$fixture/empty.csv"
printf 'plain text\n' > "$fixture/plain.txt"
{
    printf 'id,note\n'
    for ((i = 1; i < 400; i++)); do printf '%d,row%d\n' "$i" "$i"; done
    printf '400,"jump head\n'
    for ((i = 402; i <= 701; i++)); do printf 'jump continuation\n'; done
    printf 'jump tail",9\n'
    for ((i = 702; i < 900; i++)); do printf '%d,row%d\n' "$i" "$i"; done
} > "$fixture/jump.csv"
{
    printf 'id,note\n1,"open head\n'
    for ((i = 3; i <= 70; i++)); do printf 'open continuation\n'; done
    printf 'open tail",9\n2,last\n'
} > "$fixture/open.csv"

{
    opening=$'id,note\n1,"open\n'
    printf '%s' "$opening"
    remaining=$((preview_bytes - ${#opening}))
    continuation='malformed continuation with a quote that never closes anywhere'
    while [ "$remaining" -gt "${#continuation}" ]; do
        printf '%s\n' "$continuation"
        remaining=$((remaining - ${#continuation} - 1))
    done
    printf '%s' "${continuation:0:remaining}"
} > "$fixture/malformed.csv"
setup_end=$EPOCHREALTIME
printf 'csv-preview: fixture setup_ms=%d\n' "$(( (${setup_end/./} - ${setup_start/./}) / 1000 ))"

failures=0
log="$test_root/csv-preview.log"
( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root/home" XDG_STATE_HOME="$test_root/state" XDG_CACHE_HOME="$test_root/cache" \
    XDG_RUNTIME_DIR="$test_root/runtime" FLEA_BIN="$bin" FLEA_REDUCED_MOTION=1 \
    CSVPREV_DIR="$fixture" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_FORCE_STDERR_LOGGING=1 \
    dbus-run-session -- bash -c 'timeout 240 qs -p "$1" > "$2" 2>&1' _ "$test_root/config" "$log" 2> "$test_root/bus.log" ) 2>/dev/null
status=$?
[ -z "${FLEA_CI_SUITE_LOGS:-}" ] || cp "$log" "$FLEA_CI_SUITE_LOGS/csv-preview.log" 2>/dev/null
grep -a 'CSVPREV \(PASS\|FAIL\|DONE\|MEASURE\)' "$log" | sed 's/^/csv-preview: /'
loops=$(grep -ac 'Binding loop detected' "$log")
if [ "$loops" -ne 0 ]; then
    printf 'FAIL csv-preview: %s binding loop(s)\n' "$loops"
    failures=$((failures + 1))
fi
qslog_crash "csv-preview" "$log" || failures=$((failures + 1))
if [ "$status" -ne 0 ] || [ "$(grep -ac 'CSVPREV DONE' "$log")" -ne 1 ] || grep -aqE 'CSVPREV FAIL|TypeError|ReferenceError|Unable to assign|Cannot assign' "$log"; then
    printf 'FAIL csv-preview: the run did not hold (qs exit %s)\n' "$status"
    grep -aE 'TypeError|ReferenceError|Unable to assign|Cannot assign' "$log" | head -5
    failures=$((failures + 1))
fi
printf 'csv-preview: %s failed\n' "$failures"
[ "$failures" -eq 0 ]
