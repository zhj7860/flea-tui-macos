// Eligibility layers 1, 3 and 4: which drives may be flashed, from sysfs, mountinfo and swaps.
use crate::backend::flash::{Drive, REFUSED_HOLDSIMAGE, REFUSED_MEMBER, REFUSED_READONLY, REFUSED_SMALL};
use std::path::{Path, PathBuf};

// Never candidates, whatever their flags say.
const EXCLUDED_PREFIXES: [&str; 6] = ["loop", "zram", "dm-", "md", "nbd", "sr"];
// The system paths whose disk is never listed.
const SYSTEM_PATHS: [&str; 6] = ["/", "/home", "/boot", "/efi", "/usr", "/var"];
// Kernel path segments that start a removable bus: usb2, mmc_host and mmc0.
const BUS_PREFIXES: [&str; 2] = ["usb", "mmc"];
// Kernel path segments that hold a removable bus's name anywhere in them.
const BUS_WORDS: [&str; 3] = ["sdhci", "firewire", "ieee1394"];
// 512 bytes, the sector size that sysfs size files count in.
const SECTOR_BYTES: u64 = 512;

// Every reader takes its root, so tests run on fake trees; production passes /sys and /proc paths.
pub struct Roots<'a> {
    pub sys: &'a Path,
    pub dev: &'a Path,
    pub exe: &'a Path,
    pub ui: &'a Path,
    // The bench's named loop root, read from the environment once at production's edge; unused without the flash-test-seam feature.
    pub loop_root: Option<&'a Path>,
}

// Sample sysfs: <sys>/block/sda with removable, ro, size, diskseq, dev, vendor, model and holders/.
pub fn list_drives(roots: &Roots, mountinfo: &str, swaps: &str, image: Option<&Path>, image_bytes: Option<u64>) -> Vec<Drive> {
    // The pane's path may run through a link into a mount; mountinfo names the real one.
    let real = image.map(|path| path.canonicalize().unwrap_or_else(|_| path.to_path_buf()));
    let image = real.as_deref();
    let mut excluded = excluded_disks(roots, mountinfo, swaps);
    let _ = excluded.insert(String::new());
    let mut out = Vec::new();
    for dev in block_names(roots.sys) {
        if let Some(drive) = drive_if_candidate(roots, mountinfo, &excluded, &dev, image, image_bytes) {
            out.push(drive);
        }
    }
    out
}

// The drive the Flash step showed, as flashtargets named it.
pub struct Chosen<'a> {
    pub dev: &'a str,
    pub seq: u64,
    pub serial: &'a str,
    pub bytes: u64,
}

// Layer 4: true when the drive the Flash step showed is gone or differs or now refuses this image, so nothing is touched.
pub fn identity_changed(roots: &Roots, mountinfo: &str, swaps: &str, chosen: &Chosen, image: Option<&Path>, image_bytes: Option<u64>) -> bool {
    let drives = list_drives(roots, mountinfo, swaps, image, image_bytes);
    match drives.iter().find(|d| d.dev == chosen.dev) {
        None => true,
        Some(d) => d.seq != chosen.seq || d.serial != chosen.serial || d.bytes != chosen.bytes || !d.refused.is_empty(),
    }
}

// Sorted, so the pane order is the kernel's and stable across runs.
fn block_names(sys: &Path) -> Vec<String> {
    let mut names = Vec::new();
    let Ok(entries) = std::fs::read_dir(sys.join("block")) else { return names; };
    for entry in entries.flatten() {
        if let Some(name) = entry.file_name().to_str() {
            names.push(name.to_string());
        }
    }
    names.sort();
    names
}

// None when any layer refuses to list the drive at all; refused names why it cannot take the image.
fn drive_if_candidate(roots: &Roots, mountinfo: &str, excluded: &std::collections::HashSet<String>, dev: &str, image: Option<&Path>, image_bytes: Option<u64>) -> Option<Drive> {
    // The bench seam admits a loop whose backing file is inside its root; every other excluded prefix is refused before any flag is read.
    let seam_loop = dev.starts_with("loop") && loop_permitted(dev, roots);
    if EXCLUDED_PREFIXES.iter().any(|p| dev.starts_with(p)) && !seam_loop {
        return None;
    }
    if excluded.contains(dev) {
        return None;
    }
    let base = roots.sys.join("block").join(dev);
    // A loop has no removable flag and no bus path, so the seam admits it on its backing file alone.
    if !seam_loop && !removable_or_bus(roots.sys, &base) {
        return None;
    }
    let bytes = read_num(&base.join("size")).unwrap_or(0).saturating_mul(SECTOR_BYTES);
    let seq = read_num(&base.join("diskseq")).unwrap_or(0);
    let serial = read_text(&base.join("serial")).or_else(|_| read_text(&base.join("device").join("serial"))).unwrap_or_default();
    let model = drive_model(&base);
    let volumes = volumes(roots, dev);
    let label = if volumes.len() == 1 { volumes[0].clone() } else { model.clone() };
    let mut refused = String::new();
    if read_num(&base.join("ro")).unwrap_or(0) == 1 {
        refused = REFUSED_READONLY.to_string();
    } else if crate::backend::flashdesc::held(roots.sys, dev) {
        refused = REFUSED_MEMBER.to_string();
    } else if let Some(path) = image {
        if disk_under(path, mountinfo, roots).iter().any(|disk| disk == dev) {
            refused = REFUSED_HOLDSIMAGE.to_string();
        }
    }
    if refused.is_empty() {
        if let Some(want) = image_bytes {
            if bytes < want {
                refused = REFUSED_SMALL.to_string();
            }
        }
    }
    Some(Drive { dev: dev.to_string(), seq, serial, label, model, bytes, volumes, refused })
}

// Removable, or a kernel path through USB, an MMC host or FireWire, the way udisks derives Removable.
fn removable_or_bus(sys: &Path, base: &Path) -> bool {
    if read_num(&base.join("removable")).unwrap_or(0) == 1 {
        return true;
    }
    // The device link is relative text naming the SCSI address; the canonical path below sys holds the bus segments.
    let (Ok(real), Ok(root)) = (std::fs::canonicalize(base), std::fs::canonicalize(sys)) else { return false };
    real.strip_prefix(&root).unwrap_or(&real).components().any(|part| {
        let segment = part.as_os_str().to_string_lossy().to_lowercase();
        BUS_PREFIXES.iter().any(|prefix| segment.starts_with(prefix)) || BUS_WORDS.iter().any(|word| segment.contains(word))
    })
}

// "if the model contains the vendor, the model alone", omarchy-drive-info's own rule.
fn drive_model(base: &Path) -> String {
    let vendor = read_text(&base.join("device").join("vendor")).or_else(|_| read_text(&base.join("vendor"))).unwrap_or_default();
    let model = read_text(&base.join("device").join("model")).or_else(|_| read_text(&base.join("model"))).unwrap_or_default();
    let (vendor, model) = (vendor.trim().to_string(), model.trim().to_string());
    if model.is_empty() {
        return vendor;
    }
    if !vendor.is_empty() && model.contains(&vendor) {
        return model;
    }
    if vendor.is_empty() {
        return model;
    }
    format!("{vendor} {model}")
}

// Partition entries are subdirectories carrying their own dev file.
fn partitions(base: &Path) -> Vec<String> {
    let mut out = Vec::new();
    let Ok(entries) = std::fs::read_dir(base) else { return out; };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() && path.join("dev").is_file() && path.join("partition").is_file() {
            if let Some(name) = path.file_name().and_then(|n| n.to_str()) {
                out.push(name.to_string());
            }
        }
    }
    out.sort();
    out
}

// The volumes the pane lists: each partition's label from /dev/disk/by-label when it has one, else its kernel name.
fn volumes(roots: &Roots, dev: &str) -> Vec<String> {
    let base = roots.sys.join("block").join(dev);
    let own = partitions(&base);
    let mut labels = std::collections::HashMap::new();
    if let Ok(entries) = std::fs::read_dir(roots.dev.join("disk/by-label")) {
        for entry in entries.flatten() {
            let label = entry.file_name().to_string_lossy().to_string();
            let target = std::fs::read_link(entry.path()).unwrap_or_default();
            let part = target.file_name().and_then(|n| n.to_str()).unwrap_or_default().to_string();
            if own.contains(&part) {
                labels.entry(part).or_insert(label);
            }
        }
    }
    own.into_iter().map(|part| labels.remove(&part).unwrap_or(part)).collect()
}

// Every disk that is never listed: under the six system paths, under an active swap, under Flea itself.
fn excluded_disks(roots: &Roots, mountinfo: &str, swaps: &str) -> std::collections::HashSet<String> {
    let mut out = std::collections::HashSet::new();
    for path in SYSTEM_PATHS {
        out.extend(disk_under(Path::new(path), mountinfo, roots));
    }
    out.extend(swap_disks(swaps, mountinfo, roots));
    for path in [roots.exe, roots.ui] {
        if !path.as_os_str().is_empty() {
            out.extend(disk_under(path, mountinfo, roots));
        }
    }
    out
}

// The disks under a path, from mountinfo's mount source through /dev and sysfs, never from st_dev.
fn disk_under(path: &Path, mountinfo: &str, roots: &Roots) -> Vec<String> {
    match super::mountinfo::mount_entry_in(path, mountinfo) {
        Some(entry) => super::flashdisk::disks_under_mount(&entry, roots.sys, roots.dev),
        None => Vec::new(),
    }
}

// Sample swaps line: "/swapfile file 8388604 2594844 -2", or "/dev/sda3 partition ...".
fn swap_disks(swaps: &str, mountinfo: &str, roots: &Roots) -> Vec<String> {
    let mut out = Vec::new();
    for line in swaps.lines().skip(1) {
        let file = line.split_whitespace().next().unwrap_or_default();
        if file.starts_with("/dev/") {
            out.extend(super::flashdisk::disks_of_source(file, roots.sys, roots.dev));
        } else if !file.is_empty() {
            out.extend(disk_under(Path::new(file), mountinfo, roots));
        }
    }
    out
}

// A loop device is listed only through the bench seam, for a backing file inside its marked root; the feature off compiles it out.
fn loop_permitted(dev: &str, roots: &Roots) -> bool {
    #[cfg(feature = "flash-test-seam")]
    {
        crate::backend::flashseam::loop_backing_inside(roots.loop_root, dev, roots.sys)
    }
    #[cfg(not(feature = "flash-test-seam"))]
    {
        let _ = (dev, roots.sys, roots.loop_root);
        false
    }
}

// The root the bench named in the environment, for the production callers that build Roots; None in a default build.
pub(crate) fn seam_root() -> Option<std::path::PathBuf> {
    #[cfg(feature = "flash-test-seam")]
    {
        crate::backend::flashseam::named_root()
    }
    #[cfg(not(feature = "flash-test-seam"))]
    {
        None
    }
}

fn read_num(path: &Path) -> Option<u64> {
    std::fs::read_to_string(path).ok()?.trim().parse().ok()
}

fn read_text(path: &Path) -> Result<String, ()> {
    let text = std::fs::read_to_string(path).map_err(|_| ())?;
    Ok(text.trim().to_string())
}

pub fn roots_for_production() -> (PathBuf, PathBuf) {
    let exe = std::env::current_exe().unwrap_or_default();
    let ui = crate::paths::ui_dir().unwrap_or_default();
    (exe, ui)
}

#[cfg(test)]
#[path = "flasheligible_tests.rs"]
mod tests;
