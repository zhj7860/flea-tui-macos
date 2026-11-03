// Layer 6: the descriptor is the disk the step showed, with nothing mounted onto it mid-write.
use crate::backend::flashdisk::disks_of_source;
use crate::backend::flashop::FlashReq;
use std::os::fd::AsRawFd;
use std::os::unix::fs::MetadataExt;
use std::path::Path;

// The block ioctls layer 6 reads, measured against linux/fs.h on this box, in the tree's own variadic spelling.
const BLKGETSIZE64: usize = 0x80081272;
const BLKGETDISKSEQ: usize = 0x80081280;
extern "C" {
    fn ioctl(fd: i32, request: usize, ...) -> i32;
}

// glibc's dev_t packing, sys/sysmacros.h: major is bits 8..19 and 32..51, minor is bits 0..7 and 12..31.
const MAJOR_LOW_SHIFT: u32 = 8;
const MAJOR_LOW_MASK: u64 = 0xfff;
const MAJOR_HIGH_SHIFT: u32 = 32;
const MAJOR_HIGH_MASK: u64 = 0xffff_f000;
const MINOR_LOW_MASK: u64 = 0xff;
const MINOR_HIGH_SHIFT: u32 = 12;
const MINOR_HIGH_MASK: u64 = 0xffff_ff00;

// What fstat and the two block ioctls said about the descriptor; a call that failed is None.
pub(crate) struct Facts {
    pub block: bool,
    pub rdev: u64,
    pub size: Option<u64>,
    pub seq: Option<u64>,
}

// Sample rdev: 0x800 is 8:0 and 0x10300 is 259:0, the shape /sys/block/X/dev holds.
pub(crate) fn majmin(rdev: u64) -> String {
    let major = ((rdev >> MAJOR_LOW_SHIFT) & MAJOR_LOW_MASK) | ((rdev >> MAJOR_HIGH_SHIFT) & MAJOR_HIGH_MASK);
    let minor = (rdev & MINOR_LOW_MASK) | ((rdev >> MINOR_HIGH_SHIFT) & MINOR_HIGH_MASK);
    format!("{major}:{minor}")
}

// The number layer 6 compares with /sys/block/X/dev: st_rdev is the node's own, st_dev the filesystem holding it.
pub(crate) fn node_number(meta: &std::fs::Metadata) -> u64 {
    meta.rdev()
}

// The descriptor's own answers; None when fstat fails, and the ioctls are asked of a block node only.
pub(crate) fn facts_of(file: &std::fs::File) -> Option<Facts> {
    use std::os::unix::fs::FileTypeExt;
    let meta = file.metadata().ok()?;
    let block = meta.file_type().is_block_device();
    let (mut size, mut seq) = (None, None);
    if block {
        let (mut got_size, mut got_seq) = (0u64, 0u64);
        if unsafe { ioctl(file.as_raw_fd(), BLKGETSIZE64, &mut got_size) } == 0 {
            size = Some(got_size);
        }
        if unsafe { ioctl(file.as_raw_fd(), BLKGETDISKSEQ, &mut got_seq) } == 0 {
            seq = Some(got_seq);
        }
    }
    Some(Facts { block, rdev: node_number(&meta), size, seq })
}

// True when the node's number is the one the kernel lists for the disk the step showed.
pub(crate) fn rdev_matches(rdev: u64, sys: &Path, dev: &str) -> bool {
    let have = std::fs::read_to_string(sys.join("block").join(dev).join("dev")).unwrap_or_default();
    have.trim() == majmin(rdev)
}

// Every refusal is changed; an unreadable fact refuses, so layer 6 never fails open.
pub(crate) fn decide(facts: Option<&Facts>, req: &FlashReq, roots: (&Path, &Path), mountinfo: &str, swaps: &str, direct: bool) -> Result<(), &'static str> {
    let (sys, dev) = roots;
    let Some(facts) = facts else { return Err("changed") };
    // A descriptor without O_DIRECT never saw the exclusive open, so it fails closed before any write.
    if !direct {
        return Err("changed");
    }
    if !facts.block || !rdev_matches(facts.rdev, sys, &req.dev) {
        return Err("changed");
    }
    if facts.size != Some(req.bytes) || facts.seq != Some(req.seq) {
        return Err("changed");
    }
    if held(sys, &req.dev) || !mounts_clean(&req.dev, mountinfo, swaps, sys, dev) {
        return Err("changed");
    }
    Ok(())
}

// Layer 6 on the live tree; a regular file passes only through the bench seam, in a default build never.
pub(crate) fn check_descriptor(dest: &std::fs::File, req: &FlashReq) -> Result<(), &'static str> {
    let facts = facts_of(dest);
    if facts.as_ref().is_some_and(|f| !f.block) {
        return if regular_admitted(dest) { Ok(()) } else { Err("changed") };
    }
    let mountinfo = std::fs::read_to_string("/proc/self/mountinfo").unwrap_or_default();
    let swaps = std::fs::read_to_string("/proc/swaps").unwrap_or_default();
    decide(facts.as_ref(), req, (Path::new("/sys"), Path::new("/dev")), &mountinfo, &swaps, crate::backend::flashio::direct_on(dest))
}

#[cfg(feature = "flash-test-seam")]
fn regular_admitted(dest: &std::fs::File) -> bool {
    let Some(root) = crate::backend::flashseam::root() else { return false };
    let Ok(path) = std::fs::read_link(format!("/proc/self/fd/{}", dest.as_raw_fd())) else { return false };
    crate::backend::flashseam::inside(&root, &path)
}

#[cfg(not(feature = "flash-test-seam"))]
fn regular_admitted(_dest: &std::fs::File) -> bool {
    false
}

// Sample mountinfo line: "28 1 8:1 / / rw - ext4 /dev/sda1 rw" and swaps line: "/dev/sda2 partition 1 0 -2".
pub(crate) fn mounts_clean(dev: &str, mountinfo: &str, swaps: &str, sys: &Path, devdir: &Path) -> bool {
    let sources = mountinfo.lines().filter_map(|line| {
        let fields: Vec<&str> = line.split_whitespace().collect();
        let split = fields.iter().position(|f| *f == "-")?;
        fields.get(split + 2).map(|source| source.to_string())
    });
    let swapped = swaps.lines().filter(|line| !line.starts_with("Filename")).filter_map(|line| line.split_whitespace().next().map(str::to_string));
    !sources.chain(swapped).any(|source| rests_on(&source, dev, sys, devdir))
}

// True when a /dev source is the disk or rests on it, through a partition or a dm or md chain the sysfs links name.
fn rests_on(source: &str, dev: &str, sys: &Path, devdir: &Path) -> bool {
    let Some(rest) = source.strip_prefix("/dev/") else { return false };
    // The disk itself or one of its partitions by name, sda beside sda1 and nvme0n1 beside nvme0n1p1, when sysfs says nothing.
    if rest == dev {
        return true;
    }
    let tail = rest.strip_prefix(dev).unwrap_or_default();
    // A digit-ending disk takes pN partitions, so nvme0n10 and loop10 are other disks, the helper's on_drive rule.
    let named = if tail.is_empty() {
        false
    } else if dev.ends_with(|c: char| c.is_ascii_digit()) {
        tail.len() > 1 && tail.starts_with('p') && tail[1..].chars().all(|c| c.is_ascii_digit())
    } else {
        tail.chars().all(|c| c.is_ascii_digit())
    };
    if named {
        return true;
    }
    disks_of_source(source, sys, devdir).iter().any(|disk| disk == dev)
}

// True when a dm or md device still holds the disk or one of its partitions, mounted or not.
pub(crate) fn held(sys: &Path, dev: &str) -> bool {
    let base = sys.join("block").join(dev);
    let has_holder = |dir: &Path| std::fs::read_dir(dir.join("holders")).is_ok_and(|mut entries| entries.next().is_some());
    if has_holder(&base) {
        return true;
    }
    let Ok(entries) = std::fs::read_dir(&base) else { return false };
    entries.flatten().any(|entry| entry.path().join("partition").is_file() && has_holder(&entry.path()))
}

// Gone when the kernel no longer lists the disk, so no wipe is attempted on a missing drive.
pub(crate) fn gone(sys: &Path, dev: &str) -> bool {
    !sys.join("block").join(dev).is_dir()
}

// Sample file: sys/block/sda/diskseq holding "2\n" answers Some(2); a swapped medium reads a new number.
pub(crate) fn disk_seq(sys: &Path, dev: &str) -> Option<u64> {
    std::fs::read_to_string(sys.join("block").join(dev).join("diskseq")).ok()?.trim().parse().ok()
}

#[cfg(test)]
#[path = "flashdesc_tests.rs"]
mod tests;
