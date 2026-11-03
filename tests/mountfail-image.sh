#!/usr/bin/env bash
# The cap_mountfail image: a filesystem blkid still names whose superblock the kernel rejects, written to the image file alone.
set -u
. "$(dirname "$0")/../tools/flea-sandbox-guard"
cd "$(dirname "$0")/.." || exit 1
repo=$PWD
. tests/ui-captures-unlock.sh
. tests/ui-captures-mountfail.sh

PATH="$PATH:/usr/sbin:/sbin"
for tool in blkid truncate od; do
    command -v "$tool" >/dev/null || { echo "FAIL: $tool is not installed, the image cannot be checked"; exit 1; }
done
command -v mkfs.btrfs >/dev/null || command -v mkfs.ext4 >/dev/null || { echo "mountfail-image: no mkfs.btrfs or mkfs.ext4 here, nothing to build"; exit 0; }

test_root=$(mktemp -d "$FIXTURE_ROOT/flea-mountfail-image-XXXXXX") || exit 1
sandbox_require "$test_root" || exit 1
: > "$test_root/$SANDBOX_MARKER" || exit 1
cleanup() { sandbox_remove "$test_root"; }
trap cleanup EXIT

failed=0
check() {
    [ "$2" = "$3" ] || { printf 'FAIL: %s: got [%s], want [%s]\n' "$1" "$2" "$3"; failed=$((failed + 1)); }
}

img="$test_root/disk.img"
fs=$(cap_mountfail_image "$img") || { echo "FAIL: the corrupted image could not be built"; exit 1; }
check "the image is 64 MiB" "$(stat -c %s "$img")" 67108864
check "blkid names the type" "$(blkid -p -o value -s TYPE "$img")" "$fs"
check "blkid keeps the label" "$(blkid -p -o value -s LABEL "$img")" "DATA #2"
case $fs in
    btrfs)
        # Sample: bytes 48..56 of the superblock at 64 KiB are its own byte number, 65536 on a good one.
        check "the btrfs superblock byte number is zeroed" "$(od -A n -t u8 -j $((65536 + 48)) -N 8 "$img" | tr -d ' ')" 0
        ;;
    ext4)
        # Sample: s_inodes_count is the first u32 of the superblock at 1024, never 0 on a good one.
        check "the ext4 inode count is zeroed" "$(od -A n -t u4 -j 1024 -N 4 "$img" | tr -d ' ')" 0
        ;;
esac
# A second path is refused by the path guard itself, not by mkfs meeting the first image's signature.
if refusal=$(cap_mountfail_image "$img" 2>&1 >/dev/null); then
    echo "FAIL: an existing image path was rebuilt over"
    failed=$((failed + 1))
else
    check "the guard names the existing path" "$refusal" "cap_mountfail_image: $img is not a new absolute path"
fi
[ "$failed" -eq 0 ] || exit 1
echo "mountfail-image: ok ($fs)"
