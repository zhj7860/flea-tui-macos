#!/bin/bash
. "$(dirname "$0")/headless-commons.sh"
# The Columns preview as v0.3.4 drew it (the cache file, the original only where none exists) and Quick Look's decode, offscreen; see AGENTS.md "File budget".
set -u
cd "$(dirname "$0")/.." || exit 1

pass=0
fail=0
ok()  { printf 'ok   %s\n' "$*"; pass=$((pass+1)); }
bad() { printf 'FAIL %s\n' "$*"; fail=$((fail+1)); }

for tool in qs magick exiv2 inotifywait; do
    command -v "$tool" >/dev/null || { echo "preview-decode.sh: $tool is not installed"; exit 1; }
done

. "$PWD/tools/flea-sandbox-guard"
sandbox_root_ok
test_root="$SANDBOX_ROOT/flea-preview-decode-$$"
sandbox_make "$test_root"
cleanup() {
    local result=$?
    trap - EXIT
    [ -n "${watcher:-}" ] && kill "$watcher" 2>/dev/null
    wait 2>/dev/null
    # A failed run keeps its root, so every log path a FAIL line prints still points at a file.
    if [ "$result" -ne 0 ]; then
        printf 'preview-decode: keeping %s\n' "$test_root"
        exit "$result"
    fi
    sandbox_remove "$test_root"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

config_dir="$test_root/config"
photos="$test_root/photos"
runtime="$test_root/runtime"
log="$test_root/preview.log"
watchlog="$test_root/watch.log"
mkdir -p "$config_dir" "$photos" "$runtime" || exit 1
chmod 700 "$runtime" || exit 1
ln -s "$PWD/tests/preview-decode.qml" "$config_dir/shell.qml" || exit 1
headless_commons "$test_root" "$config_dir/Commons" || exit 1
ln -s /usr/share/omarchy/shell/Ui "$config_dir/Ui" || exit 1

# Fifty sweep photos with a cache file each, the 6016x3900 PNG rest row and a text start row; only open events are counted, never pixels.
printf 'preview decode rest row, not an image\n' > "$photos/note.txt" \
    || { echo "preview-decode.sh: text fixture generation failed"; exit 1; }
magick -size 640x480 plasma:fractal -seed 3 "$photos/seed0.jpg" \
    || { echo "preview-decode.sh: seed generation failed"; exit 1; }
magick -size 640x480 plasma:fractal -seed 11 "$photos/seed1.jpg" \
    || { echo "preview-decode.sh: seed generation failed"; exit 1; }
magick "$photos/seed0.jpg" -resize 256x "$photos/thumb.png" \
    || { echo "preview-decode.sh: thumbnail generation failed"; exit 1; }
magick -size 6016x3900 xc:gray50 -fill black -draw 'rectangle 0,0 3007,3899' "$photos/big.png" \
    || { echo "preview-decode.sh: rest-row generation failed"; exit 1; }
# The heldbad phase needs its own slow original: reopening big.png leaves the image source unchanged, so no decode starts and Quick Look never reads loading.
cp "$photos/big.png" "$photos/big2.png" \
    || { echo "preview-decode.sh: heldbad fixture generation failed"; exit 1; }
for i in $(seq 0 49); do
    cp "$photos/seed$((i % 2)).jpg" "$photos/s$i.jpg" || exit 1
    cp "$photos/thumb.png" "$photos/t$i.png" || exit 1
done
cp "$photos/thumb.png" "$photos/t50.png" || exit 1

# Quick Look's three: 600x400 pixels exiv2 marks RightTop (EXIF 6), since magick writes no EXIF block; a banner; a PNG smaller than any box.
magick -size 600x400 gradient:white-black "$photos/portrait.jpg" \
    && exiv2 -M"set Exif.Image.Orientation Short 6" "$photos/portrait.jpg" \
    || { echo "preview-decode.sh: portrait generation failed"; exit 1; }
[ "$(magick identify -format '%[orientation]' "$photos/portrait.jpg")" = RightTop ] \
    || { echo "preview-decode.sh: the portrait fixture carries no EXIF turn"; exit 1; }
magick -size 3000x100 xc:gray60 "$photos/banner.png" \
    || { echo "preview-decode.sh: banner generation failed"; exit 1; }
magick -size 120x68 xc:gray40 "$photos/small.png" \
    || { echo "preview-decode.sh: small fixture generation failed"; exit 1; }
# An ASCII STL no Qt plugin decodes, its valid cache thumbnail, and two undecodable PNGs with no thumbnail.
printf 'solid stl-fallback-fixture\nendsolid stl-fallback-fixture\n' > "$photos/model.stl" \
    || { echo "preview-decode.sh: stl fixture generation failed"; exit 1; }
magick -size 256x192 xc:gray40 "$photos/stl-cache.png" \
    || { echo "preview-decode.sh: stl cache generation failed"; exit 1; }
printf 'not a png\n' > "$photos/bad.png" \
    || { echo "preview-decode.sh: bad-png fixture generation failed"; exit 1; }
# Two more models, shown by the Columns preview: one with no thumbnail on offer, one whose thumbnail is still to come.
printf 'solid columns-fixture\nendsolid columns-fixture\n' > "$photos/mount.stl" \
    || { echo "preview-decode.sh: columns stl fixture generation failed"; exit 1; }
cp "$photos/mount.stl" "$photos/pending.stl" \
    || { echo "preview-decode.sh: pending stl fixture generation failed"; exit 1; }
printf 'not a png\n' > "$photos/late.png" \
    || { echo "preview-decode.sh: late-png fixture generation failed"; exit 1; }
# The interim's own cache files: the small one draws at the original's pixels, the large one at 256 wide.
cp "$photos/small.png" "$photos/smallcache.png" \
    || { echo "preview-decode.sh: small cache generation failed"; exit 1; }

# Sample input: 'OPEN|t12.png' is a cache file, 'OPEN|s12.jpg' or 'OPEN|big.png' an original, 'CREATE|sentinel-rest' a phase boundary.
inotifywait -m -e open -e create --format '%e|%f' "$photos" > "$watchlog" 2>&1 &
watcher=$!

( env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE \
    HOME="$test_root" XDG_RUNTIME_DIR="$runtime" TMPDIR="$test_root" \
    XDG_CONFIG_HOME="$test_root/.config" XDG_STATE_HOME="$test_root/.local/state" XDG_CACHE_HOME="$test_root/.cache" \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=generic QT_QUICK_BACKEND=software QT_QPA_UPDATE_IDLE_TIME=1 \
    QT_FORCE_STDERR_LOGGING=1 \
    PREVIEW_UI="$PWD/ui" PREVIEW_PHOTOS="$photos" \
    timeout 120 qs -p "$config_dir" > "$log" 2>&1 )
status=$?
# The watch outlives qs by a breath so its last events flush before it is read.
sleep 1
kill "$watcher" 2>/dev/null
watcher=""
wait 2>/dev/null

if grep -q 'PREVIEW FAIL' "$log" || ! grep -q 'PREVIEW DONE' "$log"; then
    bad "the harness did not finish (qs exit $status): $(grep -a 'PREVIEW FAIL' "$log" | head -1) (log $log)"
else
    # Sample input, one inotifywait line per event: 'OPEN|t0.png' is the first swept row's cache file, 'OPEN|t50.png' the rest row's, and 'CREATE|sentinel-rest' opens the rest window once the sweep one closes.
    got_sweep=0; got_rest=0; got_done=0; phase=0
    sweep_t0=0; sweep_other=0; sweep_other_names=""; rest_big=0; rest_cache=0; rest_sweep=0
    events=""; name=""
    while IFS='|' read -r events name || [ -n "$events" ]; do
        case "$events" in
        *CREATE*)
            if [ "$name" = "sentinel-sweep" ]; then phase=1; got_sweep=1
            elif [ "$name" = "sentinel-rest" ]; then [ "$phase" -eq 1 ] && phase=2; got_rest=1
            elif [ "$name" = "sentinel-done" ]; then [ "$phase" -eq 2 ] && phase=3; got_done=1
            fi
            ;;
        *OPEN*)
            # e80 loads a lone move at once: the sweep starts idle, so it loads t0.png only; repeats trail. One load opens t50.png rest_cache times, so t0.png may open at most that often.
            if [ "$phase" -eq 1 ]; then
                case "$name" in
                sentinel-*) ;;
                t0.png) sweep_t0=$((sweep_t0 + 1)) ;;
                *) sweep_other=$((sweep_other + 1)); [ "$sweep_other" -le 3 ] && sweep_other_names="$sweep_other_names $name" ;;
                esac
            elif [ "$phase" -eq 2 ]; then
                case "$name" in
                big.png) rest_big=$((rest_big + 1)) ;;
                t50.png) rest_cache=$((rest_cache + 1)) ;;
                s*.jpg) rest_sweep=$((rest_sweep + 1)) ;;
                esac
            fi
            ;;
        esac
    done < "$watchlog"
    if [ "$got_sweep" != 1 ] || [ "$got_rest" != 1 ] || [ "$got_done" != 1 ]; then
        bad "a phase sentinel never arrived (sweep=$got_sweep rest=$got_rest done=$got_done) (log $log)"
    else
        if [ "$sweep_other" -ne 0 ]; then
            bad "the sweep opened other row(s):$sweep_other_names besides t0.png (log $log)"
        elif [ "$sweep_t0" -eq 0 ]; then
            bad "the sweep opened no file, want the first row t0.png (log $log)"
        elif [ "$sweep_t0" -gt "$rest_cache" ]; then
            bad "the sweep opened t0.png $sweep_t0 time(s), more than one load opens t50.png $rest_cache time(s) (log $log)"
        else
            ok "the sweep opened only the first row t0.png $sweep_t0 time(s), within one load"
        fi
        if [ "$rest_cache" -ge 1 ]; then
            ok "a rest drew the rested row's cache file"
        else
            bad "the rest never opened t50.png, so the column drew nothing of the row (log $log)"
        fi
        if [ "$rest_big" -eq 0 ] && [ "$rest_sweep" -eq 0 ]; then
            ok "and opened no original, the way v0.3.4 drew the column"
        else
            bad "the rest opened big.png $rest_big time(s) and sweep rows $rest_sweep time(s) (log $log)"
        fi
    fi
    # Sample input: 'PREVIEW QL portrait decoded=400x600 drawn=314x471'; Qt decodes a turned photo whole when its stored size fits the box.
    portrait=$(sed -n 's/.*PREVIEW QL portrait decoded=\([0-9]*x[0-9]*\) drawn=\([0-9]*x[0-9]*\).*/\1 \2/p' "$log")
    case "$portrait" in
        "400x600 314x471") ok "Quick Look draws an EXIF-turned photo upright at the exact fit, 314x471" ;;
        *) bad "Quick Look drew the portrait as '$portrait', not 400x600 upright drawn at 314x471 (log $log)" ;;
    esac
    # 3000x100 at the box's width is 754x25; Fit decoded the covering 14130x471 instead.
    banner=$(sed -n 's/.*PREVIEW QL banner decoded=\([0-9]*x[0-9]*\) drawn=\([0-9]*x[0-9]*\).*/\1 \2/p' "$log")
    case "$banner" in
        "754x25 754x25") ok "and decodes a 3000x100 banner at the exact fit, 754x25" ;;
        *) bad "Quick Look drew the banner as '$banner', not 754x25 decoded and drawn (log $log)" ;;
    esac
    small=$(sed -n 's/.*PREVIEW QL small decoded=\([0-9]*x[0-9]*\) drawn=\([0-9]*x[0-9]*\).*/\1 \2/p' "$log")
    case "$small" in
        "120x68 120x68") ok "and a 120x68 PNG at its own size, never enlarged" ;;
        *) bad "Quick Look drew the small PNG as '$small', not 120x68 (log $log)" ;;
    esac
    # The interim draws the cache file under the full decode within a pixel, adding no open.
    im_line() { grep -a -n "CREATE|sentinel-$1" "$watchlog" | head -1 | cut -d: -f1; }
    rect_ok() { IFS=, read -r -a a <<<"$1"; IFS=, read -r -a b <<<"$2"; [ "${#a[@]}" -eq 4 ] && [ "${#b[@]}" -eq 4 ] || return 1; for i in 0 1 2 3; do d=$((a[i]-b[i])); [ "${d#-}" -le 1 ] || return 1; done; }
    for spec in "small small.png smallcache.png" "large seed0.jpg thumb.png"; do
        set -- $spec
        label=$1; orig=$2; cache=$3
        # Sample input: 'PREVIEW INTERIM small irect=317,201,120,68 frect=317,201,120,68'
        line=$(grep -a "PREVIEW INTERIM $label " "$log" | head -1)
        irect=$(printf '%s' "$line" | sed -n 's/.* irect=\([0-9,]*\).*/\1/p')
        frect=$(printf '%s' "$line" | sed -n 's/.* frect=\([0-9,]*\).*/\1/p')
        if [ -z "$irect" ] || [ -z "$frect" ]; then
            bad "the interim never reported $label (log $log)"
            continue
        fi
        if rect_ok "$irect" "$frect"; then
            ok "the $label interim lands on the final's rect ($irect)"
        else
            bad "the $label interim drew $irect against the final $frect (log $log)"
        fi
        if grep -a -q "PREVIEW INTERIMSTACK $label ok" "$log"; then
            ok "the $label interim draws above the ground and below the final picture"
        else
            bad "the $label interim is not stacked between the ground and the final picture (log $log)"
        fi
        s0=$(im_line "istart-$label"); s1=$(im_line "iend-$label")
        if [ -z "$s0" ] || [ -z "$s1" ]; then
            bad "an interim sentinel never arrived for $label (log $log)"
            continue
        fi
        oopens=$(sed -n "${s0},${s1}p" "$watchlog" | grep -c "^OPEN|$orig\$")
        copens=$(sed -n "${s0},${s1}p" "$watchlog" | grep -c "^OPEN|$cache\$")
        if [ "$oopens" -eq 1 ]; then
            ok "and opened its original once, the interim adding none"
        else
            bad "the $label original opened $oopens time(s), want exactly 1 (log $log)"
        fi
        if [ "$copens" -eq 1 ]; then
            ok "and drew its cache file"
        else
            bad "the $label interim opened $cache $copens time(s), want exactly 1 (log $log)"
        fi
    done
    # Sample input: 'PREVIEW HELD held shown=true ready=true status=loading' is a Ready cache releasing Quick Look while the final still decodes.
    held=$(grep -a "PREVIEW HELD held " "$log" | head -1)
    case "$held" in
        *"shown=true ready=true status=loading"*) ok "a Ready cache shows the interim and releases Quick Look while the final loads" ;;
        *) bad "the held phase did not release on the interim: '$held' (log $log)" ;;
    esac
    # Sample input: 'PREVIEW HELD heldbad shown=false ready=false status=loading' is a missing cache file holding Quick Look on loading.
    heldbad=$(grep -a "PREVIEW HELD heldbad " "$log" | head -1)
    case "$heldbad" in
        *"shown=false ready=false status=loading"*) ok "a missing cache file shows no interim and Quick Look keeps waiting on the final" ;;
        *) bad "the heldbad phase did not wait on the final: '$heldbad' (log $log)" ;;
    esac
    # Sample input: 'PREVIEW REOPEN held' is the close/open while the final still decodes, landed on the interim without the cap.
    if grep -a -q "PREVIEW REOPEN held" "$log"; then
        ok "a reopen while the final decodes lands on the interim without the cap"
    else
        bad "the reopen never landed on the interim (log $log)"
    fi
    # The STL fallback keeps the cache thumbnail as its picture at the column's fit, and no status change carries the sentence.
    # Sample input: 'PREVIEW STLFALLBACK status=image sawfailure=false frect=52,0,516,388 thumb=256x192 box=620x388 handed=false'.
    stl=$(grep -a "PREVIEW STLFALLBACK " "$log" | head -1)
    stl_thumb=$(printf '%s' "$stl" | sed -n 's/.* thumb=\([0-9]*x[0-9]*\).*/\1/p')
    stl_frect=$(printf '%s' "$stl" | sed -n 's/.* frect=\([0-9,]*\).*/\1/p')
    stl_box=$(printf '%s' "$stl" | sed -n 's/.* box=\([0-9]*x[0-9]*\).*/\1/p')
    stl_status=$(printf '%s' "$stl" | sed -n 's/.* status=\(image\|This image could not be read\.\).*/\1/p')
    case "$stl_status" in
        image) ok "Quick Look draws the STL cache thumbnail as its picture" ;;
        *) bad "Quick Look settled the STL as '$stl_status', want image (log $log)" ;;
    esac
    case "$stl" in
        *" sawfailure=false"*) ok "no status change carried the failure sentence" ;;
        *) bad "a status change carried the failure sentence before the thumbnail (log $log)" ;;
    esac
    # awk because the fit is float arithmetic, which bash lacks: it repeats the Thumbs fitScale rule (a 256 CACHE_SIZE entry fills the box aspect-fit, a smaller one draws own-size; 1e18 is Infinity).
    stl_exp=$(printf '%s' "$stl_thumb $stl_box" | awk -F'[x ]' 'NF==4 && $1>0 && $2>0 && $3>0 && $4>0 {tw=$1; th=$2; bw=$3; bh=$4; long=(tw>th?tw:th); lim=(long<256?1:1e18);
        s=bw/tw; t=bh/th; if (t<s) s=t; if (lim<s) s=lim; w=int(tw*s+0.5); h=int(th*s+0.5);
        printf "%d,%d,%d,%d", int((bw-w)/2+0.5), int((bh-h)/2+0.5), w, h}')
    if [ -n "$stl_frect" ] && [ -n "$stl_exp" ] && rect_ok "$stl_frect" "$stl_exp"; then
        ok "the STL thumbnail draws at the column size ($stl_frect)"
    else
        bad "the STL thumbnail drew $stl_frect, want the column size $stl_exp (log $log)"
    fi
    case "$stl" in
        *" handed=false"*) ok "no Image is handed the STL itself when its thumbnail stands in" ;;
        *) bad "an Image held model.stl as its source: '$stl' (log $log)" ;;
    esac
    # The same STL on a row no thumbnailer serves takes the generic file pane, and still no Image is handed it.
    # Sample input: 'PREVIEW STLNOTHUMB status=This file cannot be previewed. kind=unsupported handed=false'.
    stl_none=$(grep -a "PREVIEW STLNOTHUMB " "$log" | head -1)
    case "$stl_none" in
        *"status=This file cannot be previewed. kind=unsupported handed=false"*) ok "an STL no thumbnailer serves takes the generic file pane and no Image is handed it" ;;
        *) bad "the STL no thumbnailer serves: '$stl_none', want the generic file pane and handed=false (log $log)" ;;
    esac
    # The control: an undecodable PNG with no cache thumbnail keeps today's sentence.
    stl_ctl=$(grep -a "PREVIEW STLCONTROL " "$log" | head -1)
    case "$stl_ctl" in
        *"status=This image could not be read."*) ok "an undecodable PNG with no thumbnail keeps the sentence" ;;
        *) bad "the control did not keep the sentence: '$stl_ctl' (log $log)" ;;
    esac
    # Qt has no plugin for a 3D model, so Quick Look asks it to decode none; the undecodable PNG still reaches it.
    # Sample input: 'WARN scene: QML Image at file:///src/ui/PreviewImage.qml[79:5]: Error decoding: file:///t/photos/model.stl: Unsupported image format'.
    # grep -c prints 0 and exits 1 on no match, the pass case, and prints nothing on an unreadable log.
    stl_decodes=$(grep -a -c 'Error decoding: .*/model\.stl' "$log" 2>/dev/null) || true
    png_decodes=$(grep -a -c 'Error decoding: .*/bad\.png' "$log" 2>/dev/null) || true
    if [ -z "$stl_decodes" ] || [ -z "$png_decodes" ]; then
        bad "the decode warnings could not be counted, the log is missing or unreadable (log $log)"
    else
        if [ "$stl_decodes" -eq 0 ]; then
            ok "Quick Look asks Qt to decode no STL"
        else
            bad "Qt was asked to decode model.stl $stl_decodes time(s) (log $log)"
        fi
        if [ "$png_decodes" -ge 1 ]; then
            ok "and the pattern matches the warning Qt logged for the PNG that cannot decode"
        else
            bad "the log carries no decode warning for bad.png, so the pattern may not match Qt's warning (log $log)"
        fi
    fi
    # The Columns preview frame refuses a thumbnail-less model the same way, and settles on the sentence a refused decode shows.
    # Sample input: 'PREVIEW COLMODEL source= seen=false status=3 note=no preview could be made ready=true' where status 3 is Image.Error.
    colmodel=$(grep -a "PREVIEW COLMODEL " "$log" | head -1)
    case "$colmodel" in
        *"PREVIEW COLMODEL source= seen=false "*) ok "the Columns frame never gives mount.stl to its picture" ;;
        *) bad "the Columns frame was given mount.stl as its source: '$colmodel' (log $log)" ;;
    esac
    colmodel_decodes=$(grep -a -c 'Error decoding: .*/mount\.stl' "$log")
    if [ "$colmodel_decodes" -eq 0 ]; then
        ok "the Columns preview asks Qt to decode no STL"
    else
        bad "Qt was asked to decode mount.stl $colmodel_decodes time(s) (log $log)"
    fi
    case "$colmodel" in
        *" status=3 note=no preview could be made ready=true"*) ok "and the frame settles on the sentence a refused decode shows, ready for the swap" ;;
        *) bad "the Columns frame did not settle on a refused decode: '$colmodel' (log $log)" ;;
    esac
    # A model whose thumbnail is still to come is not settled: the frame reads Null, shows no sentence, and the swap keeps waiting.
    # Sample input: 'PREVIEW COLPENDING status=0 note= ready=false sawerror=false sawsentence=false' where status 0 is Image.Null.
    colpending=$(grep -a "PREVIEW COLPENDING " "$log" | head -1)
    case "$colpending" in
        *" status=0 note= ready=false sawerror=false sawsentence=false") ok "a model with its thumbnail pending reads no Error and shows no sentence, so the swap keeps waiting" ;;
        *) bad "the Columns frame settled on a model whose thumbnail is pending: '$colpending' (log $log)" ;;
    esac
    # Sample input: 'PREVIEW COLLAND status=1 source=stl-cache.png note= ready=true sawerror=false sawsentence=false' where status 1 is Image.Ready.
    colland=$(grep -a "PREVIEW COLLAND " "$log" | head -1)
    case "$colland" in
        *" status=1 source=stl-cache.png note= ready=true sawerror=false sawsentence=false") ok "and the frame draws the thumbnail once it lands" ;;
        *) bad "the Columns frame did not draw the thumbnail that landed: '$colland' (log $log)" ;;
    esac
    # #263: Quick Look opened before the row's thumbnail exists asks for it once the decode fails, and waits on the loading state.
    # Sample input: 'PREVIEW LATE landed pend=loading asks=0 pendsaw=false pendframes=0 total=1 rows=7 end=image saw=false frames=0 fallback=true'.
    late() { grep -a "PREVIEW LATE $1 " "$log" | head -1; }
    late_has() { case " $(late "$1") " in *" $2 "*) return 0 ;; esac; return 1; }
    late_all() { local leg=$1; shift; for want in "$@"; do late_has "$leg" "$want" || return 1; done; }
    if late_all model pend=loading asks=0 total=1 rows=7 end=image saw=false frames=0 pendsaw=false pendframes=0 fallback=true; then
        ok "a 3D model a thumbnailer serves opens the image pane before its thumbnail, asks for it, and ends on the picture"
    else
        bad "the model leg: '$(late model)', want the image pane, one ask for row 7, loading throughout, then the picture (log $log)"
    fi
    if late_all landed pend=loading asks=0 total=1 rows=7 end=image saw=false frames=0 pendsaw=false pendframes=0 fallback=true; then
        ok "a cache-only mark waits for its reply, then asks in full, and a thumbnail that lands ends on the picture with no frame of the sentence"
    else
        bad "the landed leg: '$(late landed)', want no ask while the cache-only reply was owed, one ask for row 7, loading throughout, then the picture (log $log)"
    fi
    if late_all refused pend=loading asks=0 total=1 rows=7 end=sentence pendsaw=false pendframes=0; then
        ok "a refused reply ends on the sentence after the loading state"
    else
        bad "the refused leg: '$(late refused)', want loading while the reply was owed, then the sentence (log $log)"
    fi
    if late_all asked pend=loading asks=0 total=0 end=image saw=false frames=0 fallback=true; then
        ok "a row the planner already asked for is waited on, never asked twice"
    else
        bad "the asked leg: '$(late asked)', want no ask of our own and the picture once the reply lands (log $log)"
    fi
    if late_all forgot pend=loading asks=0 total=1 rows=7 end=sentence pendsaw=false; then
        ok "an ask forgotten while its reply is owed ends on the sentence"
    else
        bad "the forgot leg: '$(late forgot)', want one ask, then the sentence once the entry was forgotten (log $log)"
    fi
    if late_all relist pend=loading asks=0 total=2 rows=7,8 held=loading end=image saw=false frames=0 fallback=true; then
        ok "a re-list while the reply is owed finds the file again, asks once on the new listing and ends on the picture"
    else
        bad "the relist leg: '$(late relist)', want a second ask for row 8 and the picture (log $log)"
    fi
    if late_all vanish pend=loading asks=0 total=1 rows=7 held=loading end=sentence; then
        ok "a re-list that drops the file asks nothing more and ends on the sentence"
    else
        bad "the vanish leg: '$(late vanish)', want no second ask and the sentence (log $log)"
    fi
    for leg in off hold; do
        if late_all "$leg" pend=sentence asks=0 total=0 end=sentence; then
            ok "thumbnails $leg asks nothing and keeps the sentence"
        else
            bad "the $leg leg: '$(late "$leg")', want no ask and the sentence (log $log)"
        fi
    done
    if late_all move pend=loading asks=0 second= total=1 rows=8 stale=none held=loading end=sentence pendsaw=false; then
        ok "a cursor move while a reply is owed asks for the new row alone and never binds the old row's reply"
    else
        bad "the move leg: '$(late move)', want the ask for row 8 alone and row 7's reply unbound (log $log)"
    fi
    if late_all drift pend=loading asks=0 total=0 bound=none end=sentence pendsaw=false; then
        ok "a reply for a row that drifted onto another file binds nothing"
    else
        bad "the drift leg: '$(late drift)', want the reply unbound and the sentence (log $log)"
    fi
    if late_all decodable pend=image asks=0 total=0 end=image; then
        ok "a decodable image asks for no thumbnail"
    else
        bad "the decodable leg: '$(late decodable)', want no ask and the picture (log $log)"
    fi
    # e81f-r3: the interim meta-row guards, one PREVIEW GUARD line each.
    if grep -a -q "PREVIEW GUARD1 PASS" "$log"; then
        ok "the interim refuses a meta reply for a row that drifted onto another file"
    else
        bad "guard 1 did not pass: a drifted row's reply must not size the interim (log $log)"
    fi
    if grep -a -q "PREVIEW GUARD2 PASS" "$log"; then
        ok "a drifted capture re-asks at the cursor row and takes that reply"
    else
        bad "guard 2 did not pass: the ask must move to the cursor row (log $log)"
    fi
    if grep -a -q "PREVIEW GUARD3 PASS" "$log"; then
        ok "no row naming the file means no ask and no interim sizing"
    else
        bad "guard 3 did not pass: nothing may be asked when no row names the file (log $log)"
    fi
    if grep -a -q "PREVIEW GUARD4 PASS" "$log"; then
        ok "the captured row keeps the ask when the cursor sits elsewhere"
    else
        bad "guard 4 did not pass: the ask must stay at the captured row (log $log)"
    fi
fi

printf 'preview-decode: %s check(s), %s failed\n' "$((pass + fail))" "$fail"
if [ "$fail" -ne 0 ]; then
    grep -a -E 'TypeError|ReferenceError|ERROR|INTERIM|GUARD|LATE' "$log" | head -20
fi
[ "$fail" -eq 0 ]
