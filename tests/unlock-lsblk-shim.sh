#!/usr/bin/env bash
# The cap_unlock lsblk shim: a loop container lists as a stick in Flea's JSON call, and every other call and byte passes through.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
# The captures file sources its helpers from $repo, which tests/ui.sh sets for every other caller.
repo=$PWD
. tests/ui-captures-unlock.sh

command -v jq >/dev/null || { echo "FAIL: jq is not installed, the shim cannot be driven"; exit 1; }

test_root=$(mktemp -d "$FIXTURE_ROOT/flea-unlock-shim-XXXXXX") || exit 1
case $test_root in
  /*/*) ;;
  *) echo "FAIL: mktemp -d gave '$test_root', which is not an absolute path two components deep"; exit 1 ;;
esac
sandbox_require "$test_root" || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

failed=0
passed=0
check() {
    if [ "$2" = "$3" ]; then passed=$((passed + 1)); else printf 'FAIL: %s: got [%s], want [%s]\n' "$1" "$2" "$3"; failed=$((failed + 1)); fi
}

# The stand-in for the real lsblk: records its argv one per line and answers with BODY's bytes and RC.
fake="$test_root/real-lsblk"
cat > "$fake" <<'FAKE'
#!/bin/bash
printf '%s\n' "$@" > "$ARGS_OUT"
# Where stdout points: the caller's own file after an exec, a pipe when the shim captured the call.
[ -n "${FD_OUT:-}" ] && readlink "/proc/$$/fd/1" > "$FD_OUT"
cat "$BODY"
exit "${RC:-0}"
FAKE
chmod 700 "$fake" || exit 1
export ARGS_OUT="$test_root/args"

shim_dir="$test_root/shim"
cap_unlock_lsblk_shim "$shim_dir" /dev/loop0 "$fake" || { echo "FAIL: the shim for /dev/loop0 was not written"; exit 1; }
shim="$shim_dir/lsblk"
cols=NAME,PATH,LABEL,MOUNTPOINTS,RM,TRAN,SIZE,TYPE,MODEL,FSTYPE,FSVER,PARTTYPENAME,PARTTYPE,PTTYPE,PARTN,UUID

# lsblk 2.41's own layout for ui/DeviceMounts.qml's columns, minipc's disks plus the lane's locked container and a second loop.
cat > "$test_root/locked.json" <<'JSON'
{
   "blockdevices": [
      {
         "name": "loop0",
         "path": "/dev/loop0",
         "label": null,
         "mountpoints": [
             null
         ],
         "rm": false,
         "tran": null,
         "size": 33554432,
         "type": "loop",
         "model": null,
         "fstype": "crypto_LUKS",
         "fsver": "2",
         "parttypename": null,
         "parttype": null,
         "pttype": null,
         "partn": null,
         "uuid": "6f1c2a7e-3b4d-4e5f-8a9b-0c1d2e3f4a5b"
      },{
         "name": "loop1",
         "path": "/dev/loop1",
         "label": null,
         "mountpoints": [
             "/var/lib/snap"
         ],
         "rm": false,
         "tran": null,
         "size": 4096,
         "type": "loop",
         "model": null,
         "fstype": "squashfs",
         "fsver": null,
         "parttypename": null,
         "parttype": null,
         "pttype": null,
         "partn": null,
         "uuid": null
      },{
         "name": "sda",
         "path": "/dev/sda",
         "label": null,
         "mountpoints": [
             null
         ],
         "rm": true,
         "tran": "usb",
         "size": 124656812032,
         "type": "disk",
         "model": "USB Flash Disk",
         "fstype": null,
         "fsver": null,
         "parttypename": null,
         "parttype": null,
         "pttype": "dos",
         "partn": null,
         "uuid": null,
         "children": [
            {
               "name": "sda1",
               "path": "/dev/sda1",
               "label": "128GB",
               "mountpoints": [
                   "/run/media/gm/128GB"
               ],
               "rm": true,
               "tran": null,
               "size": 124656812032,
               "type": "part",
               "model": null,
               "fstype": "vfat",
               "fsver": "1.0",
               "parttypename": "W95 FAT32 (LBA)",
               "parttype": "0xc",
               "pttype": "dos",
               "partn": 1,
               "uuid": "A1B2-C3D4"
            }
         ]
      },{
         "name": "nvme0n1",
         "path": "/dev/nvme0n1",
         "label": null,
         "mountpoints": [
             null
         ],
         "rm": false,
         "tran": "nvme",
         "size": 256060514304,
         "type": "disk",
         "model": "KBG40ZNS256G",
         "fstype": null,
         "fsver": null,
         "parttypename": null,
         "parttype": null,
         "pttype": "gpt",
         "partn": null,
         "uuid": null,
         "children": [
            {
               "name": "nvme0n1p2",
               "path": "/dev/nvme0n1p2",
               "label": null,
               "mountpoints": [
                   "/"
               ],
               "rm": false,
               "tran": "nvme",
               "size": 253910581248,
               "type": "part",
               "model": null,
               "fstype": "ext4",
               "fsver": "1.0",
               "parttypename": "Linux filesystem",
               "parttype": "0fc63daf-8483-4772-8e79-3d69d8477de4",
               "pttype": "gpt",
               "partn": 2,
               "uuid": "0a1b2c3d-4e5f-6071-8293-a4b5c6d7e8f9"
            }
         ]
      }
   ]
}
JSON
# The same box after the unlock: the cleartext leaf hangs under loop0 and is mounted.
jq '(.blockdevices[0]) |= (.children = [{name: "luks-6f1c2a7e", path: "/dev/mapper/luks-6f1c2a7e", label: "S1LUKS",
      mountpoints: ["/run/media/gm/S1LUKS"], rm: false, tran: null, size: 16777216, type: "crypt", model: null,
      fstype: "vfat", parttypename: null, parttype: null, pttype: null, partn: null, uuid: "1234-ABCD"}])' \
    "$test_root/locked.json" > "$test_root/unlocked.json" || exit 1
# A listing with no loop0 at all, whose bytes must come back untouched.
jq --indent 3 'del(.blockdevices[0])' "$test_root/locked.json" > "$test_root/absent.json" || exit 1

# Flea's own call: argv forwarded whole, loop0 renamed and marked, its child marked, every other node unchanged.
for state in locked unlocked; do
    out=$(BODY="$test_root/$state.json" "$shim" --bytes --json -o "$cols")
    check "$state: exit status" "$?" 0
    check "$state: argv reaches the real lsblk unchanged" "$(cat "$ARGS_OUT")" "$(printf '%s\n' --bytes --json -o "$cols")"
    in="$test_root/$state.json"
    check "$state: loop0 is listed as cap-loop0 and removable" \
        "$(jq -c '.blockdevices[] | select(.path == "/dev/loop0") | [.name, .rm]' <<< "$out")" '["cap-loop0",true]'
    check "$state: the locked container's FSVER reaches the caller" \
        "$(jq -r '.blockdevices[] | select(.path == "/dev/loop0") | .fsver' <<< "$out")" '2'
    check "$state: every other node is unchanged" \
        "$(jq -S -c 'del(.blockdevices[] | select(.path == "/dev/loop0"))' <<< "$out")" \
        "$(jq -S -c 'del(.blockdevices[] | select(.path == "/dev/loop0"))' "$in")"
    want='.blockdevices[0] | .name = "cap-loop0" | .rm = true'
    [ "$state" = unlocked ] && want="$want"' | .children[0].rm = true'
    check "$state: loop0 differs from the real listing only in name and rm" \
        "$(jq -S -c '.blockdevices[] | select(.path == "/dev/loop0")' <<< "$out")" "$(jq -S -c "$want" "$in")"
done
check "-J: the short JSON flag takes the shim too" \
    "$(BODY="$test_root/locked.json" "$shim" --bytes -J -o "$cols" | jq -c '.blockdevices[] | select(.path == "/dev/loop0") | [.name, .rm]')" '["cap-loop0",true]'
check "unlocked: the cleartext leaf keeps its name" \
    "$(BODY="$test_root/unlocked.json" "$shim" --bytes --json -o "$cols" | jq -r '.blockdevices[0].children[0].name')" luks-6f1c2a7e

# No loop0 in the listing: the bytes are the real lsblk's, to the last newline.
BODY="$test_root/absent.json" "$shim" --bytes --json -o "$cols" > "$test_root/absent.out"
check "absent: the JSON call is byte-equal" "$(cmp -s "$test_root/absent.json" "$test_root/absent.out" && echo same)" same

# Any other form execs the real lsblk: same argv, same bytes, same status.
printf 'crypto_LUKS\n\n' > "$test_root/plain.txt"
FD_OUT="$test_root/plain.fd" BODY="$test_root/plain.txt" RC=0 "$shim" -no FSTYPE /dev/loop0 > "$test_root/plain.out"
check "plain: the non-JSON call is byte-equal" "$(cmp -s "$test_root/plain.txt" "$test_root/plain.out" && echo same)" same
check "plain: the real lsblk was exec'd onto the caller's own stdout" "$(cat "$test_root/plain.fd")" "$test_root/plain.out"
check "plain: argv reaches the real lsblk unchanged" "$(cat "$ARGS_OUT")" "$(printf '%s\n' -no FSTYPE /dev/loop0)"
BODY="$test_root/locked.json" RC=32 "$shim" --bytes --json -o "$cols" > "$test_root/failed.out"
check "failed: the real exit status comes back" "$?" 32
check "failed: a failed JSON call is byte-equal" "$(cmp -s "$test_root/locked.json" "$test_root/failed.out" && echo same)" same

# Second device for the internal row: renamed only, rm stays false on itself and its children.
jq '.blockdevices += [{name: "loop2", path: "/dev/loop2", label: null, mountpoints: [null], rm: false, tran: null, size: 33554432, type: "loop", model: null, fstype: "crypto_LUKS", fsver: "2", parttypename: null, parttype: null, pttype: null, partn: null, uuid: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", children: [{name: "luks-aaaa", path: "/dev/mapper/luks-aaaa", label: "S1INT", mountpoints: [null], rm: false, tran: null, size: 16777216, type: "crypt", model: null, fstype: "vfat", parttypename: null, parttype: null, pttype: null, partn: null, uuid: "AAAA-BBBB"}]}]' "$test_root/locked.json" > "$test_root/two.json" || exit 1
shim2_dir="$test_root/shim2"
cap_unlock_lsblk_shim "$shim2_dir" /dev/loop0 "$fake" /dev/loop2 || { echo "FAIL: the shim for /dev/loop0 with /dev/loop2 was not written"; exit 1; }
shim2="$shim2_dir/lsblk"
out2=$(BODY="$test_root/two.json" "$shim2" --bytes --json -o "$cols")
check "two: exit status" "$?" 0
check "two: loop0 is listed as cap-loop0 and removable" "$(jq -c '.blockdevices[] | select(.path == "/dev/loop0") | [.name, .rm]' <<< "$out2")" '["cap-loop0",true]'
check "two: loop2 is renamed to cap-loop2" "$(jq -r '.blockdevices[] | select(.path == "/dev/loop2") | .name' <<< "$out2")" 'cap-loop2'
check "two: loop2 keeps rm false" "$(jq -r '.blockdevices[] | select(.path == "/dev/loop2") | .rm' <<< "$out2")" 'false'
check "two: loop2 child keeps its name" "$(jq -r '.blockdevices[] | select(.path == "/dev/loop2") | .children[0].name' <<< "$out2")" 'luks-aaaa'
check "two: loop2 child keeps rm false" "$(jq -r '.blockdevices[] | select(.path == "/dev/loop2") | .children[0].rm' <<< "$out2")" 'false'
check "two: loop2 keeps its FSVER" "$(jq -r '.blockdevices[] | select(.path == "/dev/loop2") | .fsver' <<< "$out2")" '2'

# Only a whole loop device takes the shim, and only over an absolute real lsblk.
for dev in /dev/sda1 /dev/loop0p1 /dev/mapper/luks-6f1c2a7e loop0; do
    cap_unlock_lsblk_shim "$test_root/refused" "$dev" "$fake"
    check "the shim refuses $dev" "$?" 1
done
cap_unlock_lsblk_shim "$test_root/refused" /dev/loop0 real-lsblk
check "the shim refuses a relative real lsblk" "$?" 1
check "a refused shim writes nothing" "$(test -e "$test_root/refused" && echo written)" ""
for dev2 in /dev/sda1 /dev/loop0p1 /dev/mapper/luks-6f1c2a7e loop2 /dev/loop0; do
    cap_unlock_lsblk_shim "$test_root/refused2" /dev/loop0 "$fake" "$dev2"
    check "the shim refuses DEV2 $dev2" "$?" 1
done
check "a refused DEV2 shim writes nothing" "$(test -e "$test_root/refused2" && echo written)" ""

# The passphrase file is owner-only whether it is new or a leftover of a looser mode (umask alone does not narrow an existing file).
keyfile="$test_root/key"
cap_unlock_write_key "$keyfile" 'new pass'
check "key file: a new file is 600" "$(stat -c %a "$keyfile")" 600
check "key file: a new file holds exactly the key" "$(cat "$keyfile")" 'new pass'
chmod 644 "$keyfile" || exit 1
cap_unlock_write_key "$keyfile" 'second pass'
check "key file: a leftover 0644 file ends 600" "$(stat -c %a "$keyfile")" 600
check "key file: a leftover file holds exactly the new key" "$(cat "$keyfile")" 'second pass'

# The captures harness's fail exits its case; here it prints its sentence and exits the subshell, so a refusal can be read.
write_key_refused() { ( fail() { printf '%s' "$*"; exit 1; }; cap_unlock_write_key "$@" ) 2>/dev/null; }
# A relative path is refused before anything is removed or written, and the call runs inside the marked root so a regression lands there.
msg=$(cd "$test_root" && write_key_refused relkey 'rel pass'); status=$?
check "key file: a relative path is refused with its sentence" "$msg" "cap_unlock: the key file path 'relkey' is not absolute"
check "key file: a relative path fails the call" "$status" 1
check "key file: a relative path writes nothing" "$(test -e "$test_root/relkey" && echo written)" ""
# A leftover that cannot be removed stops the write, so its old bytes and mode are never reused as the key file.
[ "$(id -u)" -ne 0 ] || { printf 'unlock-lsblk-shim: run this suite as a user, since root removes a file past its folder mode.\n'; exit 1; }
locked="$test_root/locked-dir"
mkdir "$locked" || exit 1
printf 'old pass' > "$locked/key" || exit 1
chmod 644 "$locked/key" || exit 1
chmod 500 "$locked" || exit 1
msg=$(write_key_refused "$locked/key" 'third pass'); status=$?
chmod 700 "$locked" || exit 1
check "key file: a leftover that cannot be removed fails with its sentence" "$msg" "cap_unlock: the key file could not be written"
check "key file: a leftover that cannot be removed fails the call" "$status" 1
check "key file: a leftover that cannot be removed keeps its old bytes" "$(cat "$locked/key")" 'old pass'

if [ "$failed" -ne 0 ]; then
    printf 'unlock-lsblk-shim: FAIL %s of %s checks\n' "$failed" "$((failed + passed))"
    exit 1
fi
printf 'unlock-lsblk-shim: %s checks passed\n' "$passed"
