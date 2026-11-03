#!/usr/bin/env bash
. "$(dirname "$0")/headless-commons.sh"
# Release hunt: board behavior through real picker keys and backend responses.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$PWD/tools/flea-sandbox-guard"
sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-picker-hunt.XXXXXXXX") || exit 1
: > "$test_root/$SANDBOX_MARKER"
trap 'sandbox_remove "$test_root"' EXIT
fixture="$test_root/fixture"
mkdir -p "$test_root/config" "$fixture/sub"
ln -s "$PWD/ui" "$test_root/config/flea"
headless_commons "$test_root" || exit 1
ln -s "$(readlink -f ui/boot/Ui)" "$test_root/config/Ui"
cp tests/picker-040.qml "$test_root/config/shell.qml"
for name in {a..l}; do printf '%s\n' "$name" > "$fixture/$name.txt"; done
# A picture the Text filter refuses, here and one folder down, and a text file beside it.
printf 'p\n' > "$fixture/p.png"
printf 'b\n' > "$fixture/sub/b.txt"
printf 'c\n' > "$fixture/sub/c.png"
# A folder of several windows' rows, so a typed file can sit outside the held window.
mkdir -p "$fixture/big"
for index in $(seq -w 0 299); do printf 'f\n' > "$fixture/big/f$index.txt"; done
printf 'z\n' > "$fixture/big/zz.png"
failures=0
phases=0
probe_timeout_seconds=15
for view in list grid; do
    for scenario in fresh-save backend-save pointer-save list-folder list-file field-cancel field-keys listing-sort listing-view header-edit path collision replace replace-button return-twice ends cancel far probe tab answers single marked; do
        phase="$test_root/$view-$scenario"
        mkdir -p "$phase"/{home,state/flea,cache,data,runtime,tmp}
        chmod 700 "$phase/runtime"
        mode=open
        multiple=true
        preset=default
        case "$scenario" in fresh-save|backend-save|pointer-save|list-folder|list-file|field-cancel|field-keys|listing-sort|listing-view|header-edit|collision|replace|replace-button|return-twice|ends|cancel|probe|tab) mode=save; multiple=false ;; esac
        [ "$scenario" = single ] && multiple=false
        # The path leg keeps one favourite, so a typed name shows the Jump dropdown over the listing.
        places=""
        [ "$scenario" = path ] && places=$(printf ',"places":{"favourites":[{"label":"sub","path":"%s/sub"}]}' "$fixture")
        # Base size 14 is pinned, so the strip, the field and the dropdown are the board's numbers whatever Omarchy's own size is.
        printf '{"pickerView":"%s","keys":"%s","display":{"textSize":{"mode":14}}%s}' "$view" "$preset" "$places" > "$phase/state/flea/ui.json"
        request=$(python3 - "$mode" "$multiple" "$fixture" "$scenario" <<'PY'
import json,sys
request=dict(mode=sys.argv[1],multiple=sys.argv[2]=='true',folder=sys.argv[3],name='new.txt' if sys.argv[4]=='probe' else 'a.txt',title='Picker hunt')
if sys.argv[4] in ('path','far','collision','replace','replace-button','return-twice','ends','cancel','tab'):request['filters']=[dict(label='Text',globs=['*.txt'],mimes=[])]
if sys.argv[4] in ('fresh-save','backend-save','pointer-save','list-folder','list-file','field-cancel','field-keys','listing-sort','listing-view','header-edit'):request['name']='report.pdf'
if sys.argv[4]=='single':request.update(title='X \u00b7 Firefox')
if sys.argv[4]=='answers':request.update(title='All Files',app='org.chromium.Chromium',current='Pictures',filters=[dict(label=name,globs=[glob],mimes=[]) for name,glob in (('Text','*.txt'),('Pictures','*.png'),('Data','*.dat'))])
print(json.dumps(request))
PY
        )
        output=$(env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
            HOME="$phase/home" XDG_STATE_HOME="$phase/state" XDG_CONFIG_HOME="$phase/home/.config" \
            XDG_CACHE_HOME="$phase/cache" XDG_DATA_HOME="$phase/data" XDG_RUNTIME_DIR="$phase/runtime" TMPDIR="$phase/tmp" \
            FLEA_BIN="$PWD/target/debug/flea" FLEA_PICKER="$request" FLEA_PICKER_REPLY="$phase/reply.json" \
            FLEA_PICKER_HUNT_CASE="$scenario" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software \
            QT_FORCE_STDERR_LOGGING=1 timeout "$probe_timeout_seconds" qs -p "$test_root/config" 2>&1)
        code=$?
        phases=$((phases+1))
        printf 'PICKER_HUNT CASE %s %s exit=%s\n' "$view" "$scenario" "$code"
        printf '%s\n' "$output" | sed -n '/PICKER_HUNT/p'
        # The file leg answers: the reply file is the proof, and an answering picker ends itself with TERM once it is written.
        if [ "$scenario" = path ] || [ "$scenario" = far ]; then
            want="file://$fixture/a.txt"
            [ "$scenario" = far ] && want="file://$fixture/big/f000.txt"
            if ! grep -q -F "\"$want\"" "$phase/reply.json" 2>/dev/null; then
                printf 'FAIL picker phase %s %s %s reply holds %s\n' "${preset:-default}" "$view" "$scenario" "$(cat "$phase/reply.json" 2>/dev/null || echo none)"
                failures=$((failures+1))
            fi
            if [ "$code" -eq 143 ]; then code=0; fi
        fi
        # A save answer is the reply file too: only Replace answers OK over a taken name, a second Return answers nothing, Cancel refuses.
        case "$scenario" in
            replace|replace-button) want="{\"response\":0,\"uris\":[\"file://$fixture/a.txt\"],\"filter\":0}" ;;
            fresh-save|list-file) want="{\"response\":0,\"uris\":[\"file://$fixture/report.pdf\"],\"filter\":-1}" ;;
            pointer-save) want="{\"response\":0,\"uris\":[\"file://$test_root/report.pdf\"],\"filter\":-1}" ;;
            field-cancel|cancel) want='{"response":1}' ;;
            *) want="" ;;
        esac
        if [ "$scenario" = return-twice ] && { [ -e "$phase/reply.json" ] || [ "$(cat "$fixture/a.txt")" != a ]; }; then
            printf 'FAIL picker phase %s %s a second Return answered or touched a.txt: %s\n' "$view" "$scenario" "$(cat "$phase/reply.json" 2>/dev/null || echo none)"
            failures=$((failures+1))
        fi
        if [ -n "$want" ]; then
            [ "$(cat "$phase/reply.json" 2>/dev/null)" = "$want" ] || { printf 'FAIL picker phase %s %s reply holds %s\n' "$view" "$scenario" "$(cat "$phase/reply.json" 2>/dev/null || echo none)"; failures=$((failures+1)); }
            [ "$code" -eq 143 ] && code=0
        fi
        if [ "$code" -ne 0 ]; then
            printf 'FAIL picker phase %s %s %s exit=%s\n' "${preset:-default}" "$view" "$scenario" "$code"
            failures=$((failures+1))
        elif grep -q 'PICKER_HUNT FAIL' <<< "$output"; then
            printf 'FAIL picker phase %s %s %s reported failed checks\n' "$preset" "$view" "$scenario"
            failures=$((failures+1))
        elif ! grep -q 'PICKER_HUNT DONE.*0 failed' <<< "$output"; then
            echo 'FAIL picker hunt did not reach a clean verdict'
            printf '%s\n' "$output" | tail -8
            failures=$((failures+1))
        fi
        warnings=$(printf '%s\n' "$output" | grep -E 'TypeError|ReferenceError|Unable to assign|Binding loop detected' || true)
        if [ -n "$warnings" ]; then printf 'FAIL picker binding warning: %s\n' "$warnings"; failures=$((failures+1)); fi
    done
done
printf 'picker-040: %s phases, %s failed\n' "$phases" "$failures"
[ "$failures" -eq 0 ]
