// The remote mounts a bulk walk can touch, and the stuck table they share with iomount's single path calls.
use super::iomount::{is_remote, is_stuck, mark_stuck, mount_key, STUCK_TTL};
use std::path::{Path, PathBuf};

// Every remote mount a walk from path can touch: the one holding path and each remote mount point below it, from one table read.
pub(crate) fn remote_mounts_under(path: &Path, body: &str) -> Vec<PathBuf> {
    let mut found = Vec::new();
    if is_remote(path, body) {
        found.push(mount_key(path, body));
    }
    for (mount, fstype) in super::mountinfo::mounts_in(body) {
        if mount.starts_with(path) && super::netfs::can_wedge(&fstype) && !found.contains(&mount) {
            found.push(mount);
        }
    }
    found
}

// The first of these mounts marked stuck inside its TTL, so a bulk walk over it answers at once without a worker.
pub(crate) fn stuck_among(mounts: &[PathBuf]) -> Option<PathBuf> {
    mounts.iter().find(|mount| is_stuck(mount, STUCK_TTL)).cloned()
}

// A walk that stopped counting marks the remote mount holding the folder it sits in, and nothing when that folder is local.
pub(crate) fn mark_holding(path: &Path, body: &str) {
    if is_remote(path, body) {
        mark_stuck(&mount_key(path, body));
    }
}
