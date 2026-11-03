#!/usr/bin/env bash
# sandbox_trash_files_dir follows g_local_file_trash; sandbox_trash_remove_own removes only owned entries.
set -u
set -o pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
. "$repo/tools/flea-sandbox-guard"
[ "$(id -u)" != 0 ] || { printf 'TRASHLOC REFUSED running as uid 0 makes [ -w ] meaningless\n' >&2; exit 1; }

checks=0
ok() {
    checks=$((checks + 1))
    printf 'ok %s\n' "$*"
}
fail() {
    printf 'TRASHLOC FAIL %s\n' "$*" >&2
    exit 1
}

sandbox_root_ok
test_root=$(mktemp -d "$SANDBOX_ROOT/flea-trashloc-XXXXXXXX") || fail "mktemp under $SANDBOX_ROOT failed"
: > "$test_root/$SANDBOX_MARKER" || fail "could not mark $test_root"
# The other-device home lives in a second marked root, so cleanup leaves nothing outside a marked root.
second_parent=""
second_root=""
second_dev=""
root_dev=$(stat -c %d -- "$test_root") || fail "no device for $test_root"
home_dev=$(stat -c %d -- "$HOME") || fail "no device for $HOME"
for candidate in /tmp /dev/shm; do
    [[ -d "$candidate" ]] || continue
    candidate_dev=$(stat -c %d -- "$candidate" 2>/dev/null) || continue
    [[ "$candidate_dev" != "$root_dev" && "$candidate_dev" != "$home_dev" ]] || continue
    second_parent=$(mktemp -d "$candidate/flea-trashloc-XXXXXXXX") || fail "mktemp under $candidate failed"
    second_root="$second_parent/root"
    mkdir -p "$second_root" || fail "could not make $second_root"
    : > "$second_root/$SANDBOX_MARKER" || fail "could not mark $second_root"
    second_dev=$candidate_dev
    break
done
[[ -n "$second_root" ]] || fail "no different-device directory for the other branch"
cleanup() {
    sandbox_remove "$test_root" 2>/dev/null || printf 'TRASHLOC CLEANUP test_root %s was not removed\n' "$test_root"
    if [[ -n "$second_root" && -n "$second_parent" ]]; then
        FIXTURE_ROOT=$second_parent sandbox_remove "$second_root" 2>/dev/null || printf 'TRASHLOC CLEANUP second_root %s was not removed\n' "$second_root"
        case "$second_parent" in /tmp/*|/dev/shm/*) rmdir -- "$second_parent" 2>/dev/null || printf 'TRASHLOC CLEANUP second_parent %s was not removed\n' "$second_parent" ;; esac
    fi
}
trap cleanup EXIT
# Only under a marked root, absolute and non-empty in the command.
wipe() {
    case "${1:-}" in "$test_root/"*|"$second_root/"*) rm -rf -- "$1" || fail "could not remove $1" ;; *) fail "refusing to remove outside a marked root: ${1:-}" ;; esac
}

uid=$(id -u) || fail "no uid"
export XDG_DATA_HOME="$test_root/data"
mkdir -p "$XDG_DATA_HOME" || fail "no data home"

# Home branch: item and HOME on one device.
home_same="$test_root/home"
mkdir -p "$home_same" || fail "no same-device home"
printf 'body\n' > "$test_root/item.txt" || fail "no fixture item"
got=$(sandbox_trash_files_dir "$test_root/item.txt" "$home_same") || fail "home branch refused"
[[ "$got" == "$XDG_DATA_HOME/Trash/files" ]] || fail "home branch gave $got, not $XDG_DATA_HOME/Trash/files"
ok "home branch: $got"

# The default HOME takes the same path when it sits on the item's device.
real_home="$HOME"
HOME="$home_same"
got=$(sandbox_trash_files_dir "$test_root/item.txt") || { HOME="$real_home"; fail "default HOME refused"; }
HOME="$real_home"
[[ "$got" == "$XDG_DATA_HOME/Trash/files" ]] || fail "default HOME gave $got"
ok "default HOME: $got"

# Other branch: HOME on another device, so the item's mount top answers.
home_other="$second_root/home"
mkdir -p "$home_other" || fail "no other-device home"
printf 'devices root=%s other=%s\n' "$root_dev" "$second_dev"

# The minipc layout: the item shares a device with XDG_DATA_HOME but not with HOME, so the backend renames into $XDG_DATA_HOME/Trash.
printf 'body\n' > "$second_root/item.txt" || fail "no data-device item"
mkdir -p "$second_root/data" || fail "no data-device data home"
data_real="$XDG_DATA_HOME"
XDG_DATA_HOME="$second_root/data"
got=$(sandbox_trash_files_dir "$second_root/item.txt" "$home_same") || { XDG_DATA_HOME="$data_real"; fail "data-device branch refused"; }
[[ "$got" == "$second_root/data/Trash/files" ]] || { XDG_DATA_HOME="$data_real"; fail "data-device branch gave $got, not $second_root/data/Trash/files"; }
ok "item on the data home's device, HOME elsewhere: $got"
# The same layout through a direct gio trash: GLib compares with HOME's device only, so the data home on the item's device does not keep it home.
got=$(sandbox_trash_gio_dir "$second_root/item.txt" "$home_same") || { XDG_DATA_HOME="$data_real"; fail "gio rule refused the data-device layout"; }
[[ "$got" != "$second_root/data/Trash/files" && "$got" == */.Trash*/files ]] || { XDG_DATA_HOME="$data_real"; fail "gio rule gave $got for the data-device layout"; }
gio_want=$got
got=$(sandbox_trash_gio_dir "$second_root/gone/deeper/item.txt" "$home_same") || { XDG_DATA_HOME="$data_real"; fail "gio rule refused a moved-away folder"; }
[[ "$got" == "$gio_want" ]] || { XDG_DATA_HOME="$data_real"; fail "gio rule gave $got for a moved-away folder, not $gio_want"; }
got=$(sandbox_trash_gio_dir "$test_root/item.txt" "$home_same") || { XDG_DATA_HOME="$data_real"; fail "gio rule refused the HOME-device item"; }
[[ "$got" == "$second_root/data/Trash/files" ]] || { XDG_DATA_HOME="$data_real"; fail "gio rule gave $got for the HOME-device item"; }
ok "direct gio trash, data home on the item's device and HOME elsewhere: $gio_want"
# A Trash root not made yet is judged by the nearest folder above it that exists, as the backend does.
XDG_DATA_HOME="$second_root/not/yet/made"
got=$(sandbox_trash_files_dir "$second_root/item.txt" "$home_same") || { XDG_DATA_HOME="$data_real"; fail "unmade data home refused"; }
[[ "$got" == "$second_root/not/yet/made/Trash/files" ]] || { XDG_DATA_HOME="$data_real"; fail "unmade data home gave $got"; }
ok "unmade data home uses the nearest existing folder: $got"
# An item on neither the data home's device nor HOME's falls to the mount top.
XDG_DATA_HOME="$data_real"
got=$(sandbox_trash_files_dir "$second_root/item.txt" "$home_same") || fail "third-device item refused"
[[ "$got" != "$data_real/Trash/files" && "$got" == */.Trash*/files ]] || fail "third-device item gave $got"
ok "item off the data home's device and HOME's: $got"
# A folder moved away is judged by its nearest existing ancestor, as when a Restore finds its parent gone.
want=$got
got=$(sandbox_trash_files_dir "$second_root/gone/deeper/item.txt" "$home_same") || fail "moved-away folder on a third device refused"
[[ "$got" == "$want" ]] || fail "moved-away folder on a third device gave $got, not $want"
got=$(sandbox_trash_files_dir "$test_root/gone/deeper/item.txt" "$home_same") || fail "moved-away folder on HOME's device refused"
[[ "$got" == "$XDG_DATA_HOME/Trash/files" ]] || fail "moved-away folder on HOME's device gave $got"
ok "item under a missing folder follows the nearest existing ancestor: $want"
# An item whose own device differs from its folder's (a nested volume) goes to gio, never into the data home Trash, though its folder shares the data home's device.
printf 'body\n' > "$second_root/nested.txt" || fail "no nested-volume item"
stat() {
    if [[ "${1:-}" == "-c" && "${2:-}" == "%d" && "${3:-}" == "--" && "${4:-}" == "$second_root/nested.txt" ]]; then
        printf '%s\n' "$((second_dev + 1))"
        return 0
    fi
    command stat "$@"
}
XDG_DATA_HOME="$second_root/data"
got=$(sandbox_trash_files_dir "$second_root/nested.txt" "$home_same") || { unset -f stat; XDG_DATA_HOME="$data_real"; fail "nested-volume item refused"; }
unset -f stat
XDG_DATA_HOME="$data_real"
[[ "$got" != "$second_root/data/Trash/files" && "$got" == */.Trash*/files ]] || fail "nested-volume item gave $got"
ok "item on its own device inside the data home's folder goes to gio: $got"
# trash_guard_rows judges each row by one rule: Flea's rename by the files rule, a gio trash by the gio rule, never either.
. "$repo/tests/ui-trash.sh"
trash_box=$second_root
trash_private() { :; }
trash_backing() { printf '%s\n' "$stub_backing"; }
rows_item="$second_root/item.txt"
rows_listing=$(printf 'trash:///item.txt\t%s' "$rows_item")
XDG_DATA_HOME="$second_root/data"
rows_flea=$(sandbox_trash_files_dir "$rows_item" "$home_same") || { XDG_DATA_HOME="$data_real"; fail "rows: Flea rule refused"; }
rows_gio=$(sandbox_trash_gio_dir "$rows_item" "$home_same") || { XDG_DATA_HOME="$data_real"; fail "rows: gio rule refused"; }
[[ "$rows_flea" != "$rows_gio" ]] || { XDG_DATA_HOME="$data_real"; fail "rows: the two rules agree, so the layout proves nothing"; }
rows_judge() { ( trash_gio_rows=(); [[ "$1" == gio ]] && trash_gio_rows[$rows_item]=1; stub_backing="$2/item.txt"; trash_guard_rows "$rows_listing" "$home_same" ) >/dev/null 2>&1; }
rows_judge flea "$rows_flea" || { XDG_DATA_HOME="$data_real"; fail "rows: a Flea row in Flea's store was refused"; }
rows_judge gio "$rows_gio" || { XDG_DATA_HOME="$data_real"; fail "rows: a gio row in the gio store was refused"; }
! rows_judge flea "$rows_gio" || { XDG_DATA_HOME="$data_real"; fail "rows: a Flea row in the gio store passed"; }
! rows_judge gio "$rows_flea" || { XDG_DATA_HOME="$data_real"; fail "rows: a gio row in Flea's store passed"; }
# A Flea row never asks the gio rule, so a mount-top trash that cannot resolve leaves it passing.
( sandbox_trash_gio_dir() { return 1; }; rows_judge flea "$rows_flea" ) || { XDG_DATA_HOME="$data_real"; fail "rows: a Flea row failed when the gio rule could not resolve"; }
XDG_DATA_HOME="$data_real"
ok "row guard: each row is judged by its own rule, both wrong stores refused"
# The remaining mount-top cases keep the data home on the other device, apart from the item.
export XDG_DATA_HOME="$second_root/data"

# One literal expectation per GLib layout, through a stat interposition for %m.
fake_top="$test_root/faketop"
slash_top="$test_root/slashtop"
slash_fake="$test_root/slashfake"
mkdir -p "$fake_top" "$slash_top" "$slash_fake" || fail "no fake tops"
printf 'body\n' > "$fake_top/item.txt" || fail "no fake top item"
printf 'body\n' > "$slash_top/item.txt" || fail "no slash top item"
stat() {
    if [[ "${1:-}" == "-c" && "${2:-}" == "%m" ]]; then
        case "${@: -1}" in
            "$fake_top"*) printf '%s\n' "$fake_top"; return 0 ;;
            "$slash_top"*) printf '%s/\n' "$slash_fake"; return 0 ;;
        esac
    fi
    command stat "$@"
}
# Spec layout: sticky .Trash holding a user-owned plain .Trash/$UID.
wipe "$fake_top/.Trash"
mkdir -p "$fake_top/.Trash/$uid" || fail "no spec per-user trash"
chmod 1755 "$fake_top/.Trash" || fail "no sticky bit on the fake global trash"
got=$(sandbox_trash_files_dir "$fake_top/item.txt" "$home_other") || fail "spec layout refused"
[[ "$got" == "$fake_top/.Trash/$uid/files" ]] || fail "spec layout gave $got"
ok "sticky .Trash with owned .Trash/\$UID: $got"
# Sticky .Trash with no .Trash/$UID: GLib creates it, so it is usable.
wipe "$fake_top/.Trash"
mkdir -p "$fake_top/.Trash" || fail "no global trash"
chmod 1755 "$fake_top/.Trash" || fail "no sticky bit on the global trash"
got=$(sandbox_trash_files_dir "$fake_top/item.txt" "$home_other") || fail "absent per-user trash refused"
[[ "$got" == "$fake_top/.Trash/$uid/files" ]] || fail "absent per-user trash gave $got"
ok "sticky .Trash without .Trash/\$UID: $got"
# A sticky .Trash the user cannot write in: the per-user dir cannot be created there, so fallback.
wipe "$fake_top/.Trash"
mkdir -p "$fake_top/.Trash" || fail "no global trash"
chmod 1755 "$fake_top/.Trash" || fail "no sticky bit on the global trash"
chmod a-w "$fake_top/.Trash" || fail "could not lock the global trash"
got=$(sandbox_trash_files_dir "$fake_top/item.txt" "$home_other") || fail "locked choice refused"
[[ "$got" == "$fake_top/.Trash-$uid/files" ]] || fail "locked choice gave $got"
ok "non-writable sticky .Trash falls back: $got"
chmod u+w "$fake_top/.Trash" || fail "could not unlock the global trash"
# Sticky .Trash whose $UID entry is a file: not a directory, so not usable.
printf 'blocking\n' > "$fake_top/.Trash/$uid" || fail "no blocking file"
got=$(sandbox_trash_files_dir "$fake_top/item.txt" "$home_other") || fail "file entry refused"
[[ "$got" == "$fake_top/.Trash-$uid/files" ]] || fail "file entry gave $got"
ok "sticky .Trash with file .Trash/\$UID: $got"
# Sticky .Trash whose $UID entry is a symlink: lstat is not a directory, so not usable.
wipe "$fake_top/.Trash/$uid"
ln -s "$test_root" "$fake_top/.Trash/$uid" || fail "no per-user trash symlink"
got=$(sandbox_trash_files_dir "$fake_top/item.txt" "$home_other") || fail "symlink entry refused"
[[ "$got" == "$fake_top/.Trash-$uid/files" ]] || fail "symlink entry gave $got"
ok "sticky .Trash with symlinked .Trash/\$UID: $got"
# Non-sticky .Trash with a plain per-user dir: the sticky bit belongs on .Trash, so fallback.
wipe "$fake_top/.Trash"
mkdir -p "$fake_top/.Trash/$uid" || fail "no plain per-user trash"
chmod 0755 "$fake_top/.Trash" || fail "could not clear the sticky bit"
got=$(sandbox_trash_files_dir "$fake_top/item.txt" "$home_other") || fail "non-sticky choice refused"
[[ "$got" == "$fake_top/.Trash-$uid/files" ]] || fail "non-sticky choice gave $got"
ok "non-sticky .Trash: $got"
# Symlinked .Trash: lstat is not a directory, so fallback.
wipe "$fake_top/.Trash"
ln -s "$test_root" "$fake_top/.Trash" || fail "no global trash symlink"
mkdir -p "$fake_top/.Trash-$uid" || fail "no fake fallback trash"
got=$(sandbox_trash_files_dir "$fake_top/item.txt" "$home_other") || fail "symlink choice refused"
[[ "$got" == "$fake_top/.Trash-$uid/files" ]] || fail "symlink choice gave $got"
ok "symlinked .Trash falls back: $got"
# Absent .Trash: no global dir, so fallback.
wipe "$fake_top/.Trash"
got=$(sandbox_trash_files_dir "$fake_top/item.txt" "$home_other") || fail "absent choice refused"
[[ "$got" == "$fake_top/.Trash-$uid/files" ]] || fail "absent choice gave $got"
ok "absent .Trash falls back: $got"
# A trailing-slash top still names its trash with one slash, inside this marked root.
got=$(sandbox_trash_files_dir "$slash_top/item.txt" "$home_other") || fail "slash top refused"
[[ "$got" == "$slash_fake/.Trash-$uid/files" ]] || fail "slash top gave $got"
ok "slash top: $got"
unset -f stat

# Own-entry removal: mount-top .trashinfo Path is relative to the mount top, as GLib writes it.
fake_files="$test_root/top/.Trash-$uid/files"
fake_info="$test_root/top/.Trash-$uid/info"
mkdir -p "$fake_files" "$fake_info" "$test_root/top/payload" || fail "no fake mount-top trash"
printf 'mine\n' > "$fake_files/own.txt" || fail "no owned files entry"
printf 'mine\n' > "$test_root/top/payload/own.txt" || fail "no owned payload"
printf '[Trash Info]\nPath=payload/own.txt\nDeletionDate=2026-10-11T00:00:00\n' > "$fake_info/own.txt.trashinfo" || fail "no owned info entry"
printf 'absolute\n' > "$fake_files/abs.txt" || fail "no absolute files entry"
printf 'absolute\n' > "$test_root/top/payload/abs.txt" || fail "no absolute payload"
printf '[Trash Info]\nPath=%s\nDeletionDate=2026-10-11T00:00:00\n' "$test_root/top/payload/abs.txt" > "$fake_info/abs.txt.trashinfo" || fail "no absolute info entry"
printf 'theirs\n' > "$fake_files/other.txt" || fail "no foreign files entry"
printf '[Trash Info]\nPath=/elsewhere/other.txt\nDeletionDate=2026-10-11T00:00:00\n' > "$fake_info/other.txt.trashinfo" || fail "no foreign info entry"
printf 'escaped\n' > "$fake_files/escape.txt" || fail "no escaping files entry"
printf '[Trash Info]\nPath=../../outside.txt\nDeletionDate=2026-10-11T00:00:00\n' > "$fake_info/escape.txt.trashinfo" || fail "no escaping info entry"
printf 'unclaimed\n' > "$fake_files/orphan.txt" || fail "no info-less entry"
sandbox_trash_remove_own "$fake_files" "$test_root" own.txt abs.txt orphan.txt missing.txt || fail "owned removal refused"
rc=0; sandbox_trash_remove_own "$fake_files" "$test_root" other.txt escape.txt || rc=$?
[[ "$rc" == 2 ]] || fail "foreign removal gave $rc, not 2"
[[ ! -e "$fake_files/own.txt" && ! -e "$fake_info/own.txt.trashinfo" ]] || fail "owned relative pair survived"
[[ ! -e "$fake_files/abs.txt" && ! -e "$fake_info/abs.txt.trashinfo" ]] || fail "owned absolute pair survived"
[[ "$(cat "$fake_files/other.txt")" == theirs && -f "$fake_info/other.txt.trashinfo" ]] || fail "foreign pair changed"
[[ -f "$fake_files/escape.txt" && -f "$fake_info/escape.txt.trashinfo" ]] || fail "escaping pair changed"
[[ -f "$fake_files/orphan.txt" ]] || fail "info-less entry changed"
[[ -d "$fake_files" && -d "$fake_info" ]] || fail "trash directories changed"
ok "owned removal keeps foreign entries and the trash itself"
printf 'gone\n' > "$fake_files/gone.txt" || fail "no gone files entry"
printf '[Trash Info]\nPath=payload/gone.txt\nDeletionDate=2026-10-11T00:00:00\n' > "$fake_info/gone.txt.trashinfo" || fail "no gone info entry"
sandbox_trash_remove_own "$fake_files" "$test_root" gone.txt || fail "gone-original removal refused"
[[ ! -e "$fake_files/gone.txt" && ! -e "$fake_info/gone.txt.trashinfo" ]] || fail "gone-original pair survived"
ok "removal clears an entry whose original is already gone"
mkdir -p "$fake_files/owndir" "$test_root/top/payload/owndir" || fail "no owned dir entries"
printf 'child\n' > "$fake_files/owndir/child.txt" || fail "no owned dir child"
printf '[Trash Info]\nPath=payload/owndir\nDeletionDate=2026-10-11T00:00:00\n' > "$fake_info/owndir.trashinfo" || fail "no owned dir info"
mkdir -p "$fake_files/extdir" || fail "no foreign dir entry"
printf '[Trash Info]\nPath=/elsewhere/extdir\nDeletionDate=2026-10-11T00:00:00\n' > "$fake_info/extdir.trashinfo" || fail "no foreign dir info"
sandbox_trash_remove_own "$fake_files" "$test_root" owndir || fail "owned dir removal refused"
rc=0; sandbox_trash_remove_own "$fake_files" "$test_root" extdir || rc=$?
[[ "$rc" == 2 ]] || fail "foreign dir removal gave $rc, not 2"
[[ ! -e "$fake_files/owndir" && ! -e "$fake_info/owndir.trashinfo" ]] || fail "owned dir survived"
[[ -d "$fake_files/extdir" && -f "$fake_info/extdir.trashinfo" ]] || fail "foreign dir changed"
[[ -d "$test_root/.flea-trash-quarantine" ]] || fail "no quarantine dir in the marked root"
ok "owned dir moves into the marked root, foreign dir stays"
# A per-user mount-top trash resolves its relative Path against the same top.
pu_files="$test_root/top/.Trash/$uid/files"
pu_info="$test_root/top/.Trash/$uid/info"
mkdir -p "$pu_files" "$pu_info" "$test_root/top/payload2" || fail "no fake per-user trash"
printf 'mine\n' > "$pu_files/pu.txt" || fail "no per-user files entry"
printf 'mine\n' > "$test_root/top/payload2/pu.txt" || fail "no per-user payload"
printf '[Trash Info]\nPath=payload2/pu.txt\nDeletionDate=2026-10-11T00:00:00\n' > "$pu_info/pu.txt.trashinfo" || fail "no per-user info entry"
sandbox_trash_remove_own "$pu_files" "$test_root" pu.txt || fail "per-user removal refused"
[[ ! -e "$pu_files/pu.txt" && ! -e "$pu_info/pu.txt.trashinfo" ]] || fail "per-user pair survived"
ok "per-user mount-top removal resolves relative Path"
# A home trash has no mount top, so a relative Path there stays foreign even when it names the root.
home_files="$test_root/hometrash/Trash/files"
home_info="$test_root/hometrash/Trash/info"
mkdir -p "$home_files" "$home_info" || fail "no fake home trash"
printf 'evil\n' > "$home_files/evil.txt" || fail "no home files entry"
printf '[Trash Info]\nPath=%s\nDeletionDate=2026-10-11T00:00:00\n' "${test_root#/}/payload/evil.txt" > "$home_info/evil.txt.trashinfo" || fail "no home info entry"
rc=0; sandbox_trash_remove_own "$home_files" "$test_root" evil.txt || rc=$?
[[ "$rc" == 2 ]] || fail "home relative removal gave $rc, not 2"
[[ -f "$home_files/evil.txt" && -f "$home_info/evil.txt.trashinfo" ]] || fail "relative home-trash pair changed"
ok "relative Path in a home trash stays foreign"
pct_root="$test_root/sp ace%pct"
pct_files="$pct_root/.Trash-$uid/files"
pct_info="$pct_root/.Trash-$uid/info"
mkdir -p "$pct_files" "$pct_info" "$pct_root/payload" || fail "no percent trash"
printf 'pct\n' > "$pct_files/pct.txt" || fail "no percent files entry"
printf 'pct\n' > "$pct_root/payload/pct.txt" || fail "no percent payload"
printf '[Trash Info]\nPath=payload/pc%%74.txt\nDeletionDate=2026-10-11T00:00:00\n' > "$pct_info/pct.txt.trashinfo" || fail "no percent info entry"
printf 'pct\n' > "$pct_files/abspct.txt" || fail "no percent absolute files entry"
printf 'pct\n' > "$pct_root/payload/abs pct.txt" || fail "no percent absolute payload"
escaped_root=${pct_root//%/\%25}; escaped_root=${escaped_root// /%20}
printf '[Trash Info]\nPath=%s/payload/abs%%20pct.txt\nDeletionDate=2026-10-11T00:00:00\n' "$escaped_root" > "$pct_info/abspct.txt.trashinfo" || fail "no percent absolute info"
sandbox_trash_remove_own "$pct_files" "$pct_root" pct.txt abspct.txt || fail "percent removal refused"
[[ ! -e "$pct_files/pct.txt" && ! -e "$pct_info/pct.txt.trashinfo" ]] || fail "percent relative pair survived"
[[ ! -e "$pct_files/abspct.txt" && ! -e "$pct_info/abspct.txt.trashinfo" ]] || fail "percent absolute pair survived"
ok "percent-escaped Paths match a space-and-percent root"
sandbox_trash_remove_own "$fake_files" "$test_root" "../escape.txt" && fail "slash name accepted"
sandbox_trash_remove_own "$test_root/top" "$test_root" own.txt && fail "non-files trash accepted"
ok "removal refuses slash names and non-files trashes"

# A %XX escape followed by a glob character decodes literally: the cut for the two hex digits is not a pattern.
sandbox_trash_unescape 'a%41*b%41[c%41?d%2541' || fail "unescape refused a glob after an escape"
[[ "$_SANDBOX_TRASH_UNESCAPED" == 'aA*bA[cA?d%41' ]] || fail "glob after an escape decoded to $_SANDBOX_TRASH_UNESCAPED"
ok "a glob character after an escape decodes literally"

# The EXIT trap legs drive the guard functions in a child shell, each with its own fake mount-top trash inside the marked root.
trapleg="$test_root/trapleg.sh"
cat > "$trapleg" <<'LEG'
#!/usr/bin/env bash
. "$GUARD"
mode=$1
case "$mode" in
fail)
    sandbox_trash_trap_own "$FILES" "$ROOT" a.txt || exit 9
    exit 1
    ;;
status)
    trap 'printf "%s" "$?" > "$FLAG"' EXIT
    sandbox_trash_trap_own "$FILES" "$ROOT" a.txt || exit 9
    exit 7
    ;;
errexit)
    set -e
    trap 'printf "%s" "$?" > "$FLAG"' EXIT
    sandbox_trash_trap_own "$FILES" "$ROOT" a.txt || exit 9
    exit 7
    ;;
rechain)
    sandbox_trash_trap_own "$FILES" "$ROOT" a.txt || exit 9
    trap 'printf ran > "$FLAG"' EXIT
    sandbox_trash_trap_own "$FILES" "$ROOT" b.txt || exit 9
    exit 1
    ;;
subshell)
    trap 'printf parent > "$FLAG"' EXIT
    (
        sandbox_trash_trap_own "$FILES" "$ROOT" c.txt || exit 9
        exit 0
    )
    [ -e "$FILES/c.txt" ] && echo SUB_LEFT_C
    [ -e "$FLAG" ] && echo SUB_RAN_PARENT_EARLY
    sandbox_trash_trap_own "$FILES" "$ROOT" a.txt || exit 9
    (
        sandbox_trash_trap_own "$FILES" "$ROOT" b.txt || exit 9
        exit 0
    )
    [ -e "$FILES/b.txt" ] && echo SUB_LEFT_B
    [ -e "$FILES/a.txt" ] || echo SUB_TOOK_A
    [ -e "$FLAG" ] && echo SUB_RAN_PARENT
    exit 0
    ;;
casetrap)
    trap 'printf parent >> "$FLAG"' EXIT
    (
        trap - EXIT
        trap 'printf case >> "$FLAG"' EXIT
        sandbox_trash_trap_own "$FILES" "$ROOT" d.txt || exit 9
        exit 1
    )
    [ -e "$FILES/d.txt" ] && echo CASE_LEFT_D
    [ "$(cat "$FLAG" 2>/dev/null)" = case ] || echo CASE_TRAP_LOST
    exit 0
    ;;
esac
LEG
# Makes one trashed entry the trap may remove: a files entry, its payload and a mount-top relative trashinfo.
trapleg_entry() {
    local files="$1" top="$2" name="$3"
    printf 'mine\n' > "$files/$name" || fail "no trap files entry $name"
    printf 'mine\n' > "$top/payload/$name" || fail "no trap payload $name"
    printf '[Trash Info]\nPath=payload/%s\nDeletionDate=2026-10-11T00:00:00\n' "$name" > "${files%/files}/info/$name.trashinfo" || fail "no trap info $name"
}
# Runs the driver in a fresh fake mount top; sets leg_files, leg_flag and leg_out, and returns the driver's status.
trapleg_run() {
    local mode="$1" name rc=0
    shift
    leg_top="$test_root/trapleg-$mode"
    leg_files="$leg_top/.Trash-$uid/files"
    leg_flag="$leg_top/flag"
    mkdir -p "$leg_files" "${leg_files%/files}/info" "$leg_top/payload" || fail "no trap leg trash for $mode"
    for name in "$@"; do trapleg_entry "$leg_files" "$leg_top" "$name"; done
    leg_out=$(GUARD="$repo/tools/flea-sandbox-guard" FILES="$leg_files" ROOT="$leg_top" FLAG="$leg_flag" bash "$trapleg" "$mode" 2>/dev/null) || rc=$?
    return "$rc"
}
trapleg_gone() {
    local name
    for name in "$@"; do
        [[ ! -e "$leg_files/$name" && ! -e "${leg_files%/files}/info/$name.trashinfo" ]] || return 1
    done
}

rc=0; trapleg_run fail a.txt || rc=$?
[[ "$rc" == 1 ]] || fail "failing leg exited $rc, not 1"
trapleg_gone a.txt || fail "a failing script left its registered entry in the mount-top trash"
ok "trap: a registered entry goes when the script exits by exit 1"

rc=0; trapleg_run status a.txt || rc=$?
[[ "$rc" == 7 ]] || fail "status leg exited $rc, not 7"
[[ "$(cat "$leg_flag" 2>/dev/null)" == 7 ]] || fail "a trap set before the registration saw status $(cat "$leg_flag" 2>/dev/null), not 7"
trapleg_gone a.txt || fail "the status leg left its registered entry"
ok "trap: a trap set before the first registration still runs and sees exit 7"

rc=0; trapleg_run errexit a.txt || rc=$?
[[ "$rc" == 7 ]] || fail "errexit leg exited $rc, not 7"
[[ "$(cat "$leg_flag" 2>/dev/null)" == 7 ]] || fail "under errexit the chained trap saw status $(cat "$leg_flag" 2>/dev/null), not 7"
trapleg_gone a.txt || fail "the errexit leg left its registered entry"
ok "trap: under errexit, as tests/ui.sh runs each case, the chained trap still runs and sees exit 7"

rc=0; trapleg_run rechain a.txt b.txt || rc=$?
[[ "$rc" == 1 ]] || fail "rechain leg exited $rc, not 1"
[[ "$(cat "$leg_flag" 2>/dev/null)" == ran ]] || fail "the trap set after a registration did not run"
trapleg_gone a.txt b.txt || fail "a trap set after a registration disarmed the recorded removals"
ok "trap: a trap set after a registration is chained again by the next one"

rc=0; trapleg_run subshell a.txt b.txt c.txt || rc=$?
[[ "$rc" == 0 && -z "$leg_out" ]] || fail "subshell leg exited $rc with [$leg_out]"
trapleg_gone a.txt b.txt c.txt || fail "the subshell leg left an entry"
[[ "$(cat "$leg_flag" 2>/dev/null)" == parent ]] || fail "the parent trap did not run at the parent's exit"
ok "trap: a subshell removes its own names and never runs the parent's trap or jobs"

rc=0; trapleg_run casetrap d.txt || rc=$?
[[ "$rc" == 0 && -z "$leg_out" ]] || fail "case trap leg exited $rc with [$leg_out]"
trapleg_gone d.txt || fail "the case subshell left its registered entry"
[[ "$(cat "$leg_flag" 2>/dev/null)" == caseparent ]] || fail "a case subshell's own EXIT trap was not chained: flag $(cat "$leg_flag" 2>/dev/null)"
ok "trap: a case subshell that set its own EXIT trap keeps it chained, as tests/ui.sh runs each case"

# Removes a trash dir this check made once its files and info dirs are empty; anything else stays.
gio_sweep() {
    [[ "${2:-1}" == 0 ]] || return 0
    case "${1:-}" in "$gio_top/.Trash/$uid"|"$gio_top/.Trash-$uid") ;; *) return 0 ;; esac
    [[ -n "${1:-}" ]] || return 0
    local sub leftovers
    for sub in files info; do
        if [[ -d "$1/$sub" ]]; then
            if [[ -n "$(ls -A -- "$1/$sub" 2>/dev/null)" ]]; then
                printf 'TRASHLOC CLEANUP %s holds other entries, left in place\n' "$1/$sub"
                return 0
            fi
            rmdir -- "$1/$sub" 2>/dev/null || printf 'TRASHLOC CLEANUP %s was not removed\n' "$1/$sub"
        elif [[ -e "$1/$sub" ]] || [[ -L "$1/$sub" ]]; then
            return 0
        fi
    done
    leftovers=$(ls -A -- "$1" 2>/dev/null) || return 0
    [[ -z "$leftovers" ]] || return 0
    rmdir -- "$1" 2>/dev/null || printf 'TRASHLOC CLEANUP %s was not removed\n' "$1"
}
# Real cross-check: gio trash off the home device lands where the helper says; the test root first (a sandbox subvolume), else the second root.
gio_dir=$second_root
[[ "$root_dev" != "$home_dev" ]] && gio_dir=$test_root
gio_dev=$(stat -c %d -- "$gio_dir") || fail "no device for $gio_dir"
# The data home sits on the other marked root, so gio and the helper both leave the home Trash alone.
export XDG_DATA_HOME="$test_root/data"
[[ "$gio_dir" == "$test_root" ]] && export XDG_DATA_HOME="$second_root/data"
if ! command -v gio >/dev/null 2>&1; then
    printf 'skip gio cross-check: gio is not installed\n'
elif [[ "$gio_dev" == "$home_dev" ]]; then
    printf 'skip gio cross-check: no device outside $HOME\n'
else
    gio_top=$(stat -c %m -- "$gio_dir") || fail "no mount top for $gio_dir"
    gio_top=${gio_top%/}
    had_uid_trash=0; had_dash_trash=0
    [[ -e "$gio_top/.Trash/$uid" ]] && had_uid_trash=1
    [[ -e "$gio_top/.Trash-$uid" ]] && had_dash_trash=1
    gio_name="gio-own-$uid-$$.txt"
    printf 'gio payload\n' > "$gio_dir/$gio_name" || fail "no gio payload"
    gio_out=$(gio trash "$gio_dir/$gio_name" 2>&1) || {
        wipe "$gio_dir/$gio_name"
        [[ "$gio_out" == *"not supported"* ]] || fail "gio trash refused $gio_name: $gio_out"
        printf 'skip gio cross-check: gio refuses trash here: %s\n' "$gio_out"
        printf 'TRASHLOC PASS checks=%s\n' "$checks"
        exit 0
    }
    [[ -e "$gio_dir/$gio_name" ]] && fail "gio trash left $gio_name in place"
    gio_trash=""
    for candidate in "$gio_top/.Trash/$uid" "$gio_top/.Trash-$uid"; do
        if [[ -f "$candidate/files/$gio_name" && -f "$candidate/info/$gio_name.trashinfo" ]]; then gio_trash="$candidate/files"; break; fi
    done
    [[ -n "$gio_trash" ]] || fail "gio put $gio_name outside $gio_top/.Trash and $gio_top/.Trash-$uid"
    sandbox_trash_trap_own "$gio_trash" "$gio_dir" "$gio_name" || fail "gio entry registration refused"
    got=$(sandbox_trash_files_dir "$gio_dir/probe" "$HOME") || fail "helper refused the gio branch"
    [[ "$got" == "$gio_trash" ]] || fail "helper named $got, gio used $gio_trash"
    sandbox_trash_remove_own "$gio_trash" "$gio_dir" "$gio_name" || fail "owned removal refused the gio entry"
    [[ ! -e "$gio_trash/$gio_name" && ! -e "${gio_trash%/files}/info/$gio_name.trashinfo" ]] || fail "gio entry survived owned removal"
    gio_sweep "$gio_top/.Trash/$uid" "$had_uid_trash"
    gio_sweep "$gio_top/.Trash-$uid" "$had_dash_trash"
    ok "gio cross-check: helper names gio's trash and removal clears the entry"
fi
printf 'TRASHLOC PASS checks=%s\n' "$checks"
