// Which whole disks a mount, a swap or a kernel name rests on: sysfs and /dev only, never st_dev or a name trimmed of digits.
use crate::backend::mountinfo::MountEntry;
use std::collections::BTreeSet;
use std::path::Path;

// How many partition and slave hops a chain may take before it is called unresolvable.
const MAX_HOPS: usize = 8;
const DEV_PREFIX: &str = "/dev/";

// The disks under a mount: its source through /dev first, the maj:min link when the source names no device.
pub(crate) fn disks_under_mount(entry: &MountEntry, sys: &Path, dev: &Path) -> Vec<String> {
    let named = disks_of_source(&entry.source, sys, dev);
    if named.is_empty() { disks_of_majmin(&entry.majmin, sys) } else { named }
}

// Sample source: "/dev/mapper/root" links to ../dm-0, "/dev/nvme0n1p2" is the node itself; both answer a kernel name.
pub(crate) fn disks_of_source(source: &str, sys: &Path, dev: &Path) -> Vec<String> {
    let Some(rel) = source.strip_prefix(DEV_PREFIX) else { return Vec::new() };
    let node = dev.join(rel);
    let target = std::fs::read_link(&node).unwrap_or(node);
    match target.file_name().and_then(|n| n.to_str()) {
        Some(name) => disks_of_name(name, sys),
        None => Vec::new(),
    }
}

// Sample link: sys/dev/block/8:1 answers ../../block/sda/sda1, whose last component is the kernel name.
fn disks_of_majmin(majmin: &str, sys: &Path) -> Vec<String> {
    let Ok(target) = std::fs::read_link(sys.join("dev/block").join(majmin)) else { return Vec::new() };
    match target.file_name().and_then(|n| n.to_str()) {
        Some(name) => disks_of_name(name, sys),
        None => Vec::new(),
    }
}

// Every whole disk a kernel name rests on: a partition maps to its disk, a device-mapper or md device to its slaves' disks.
pub(crate) fn disks_of_name(name: &str, sys: &Path) -> Vec<String> {
    let mut found = BTreeSet::new();
    let mut seen = BTreeSet::new();
    let mut queue = vec![(name.to_string(), 0usize)];
    while let Some((current, hops)) = queue.pop() {
        if hops > MAX_HOPS || !seen.insert(current.clone()) {
            continue;
        }
        if let Some(disk) = disk_owning_partition(sys, &current) {
            queue.push((disk, hops + 1));
            continue;
        }
        let base = sys.join("block").join(&current);
        if !base.is_dir() {
            continue;
        }
        let held = slaves(&base);
        if held.is_empty() {
            found.insert(current);
        }
        queue.extend(held.into_iter().map(|slave| (slave, hops + 1)));
    }
    found.into_iter().collect()
}

// The disk whose directory holds a partition file for name; a whole disk holds none for itself.
fn disk_owning_partition(sys: &Path, name: &str) -> Option<String> {
    let entries = std::fs::read_dir(sys.join("block")).ok()?;
    for entry in entries.flatten() {
        let disk = entry.file_name().to_string_lossy().to_string();
        if disk != name && sys.join("block").join(&disk).join(name).join("partition").is_file() {
            return Some(disk);
        }
    }
    None
}

// The slaves a device-mapper or md device is built on; holders point the other way, at what uses the disk.
fn slaves(base: &Path) -> Vec<String> {
    let Ok(entries) = std::fs::read_dir(base.join("slaves")) else { return Vec::new() };
    entries.flatten().filter_map(|entry| entry.file_name().to_str().map(str::to_string)).collect()
}
