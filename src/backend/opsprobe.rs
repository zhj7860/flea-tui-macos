// Test-only work counters for a transfer, keyed by the folder a test owns so every thread's work counts and parallel tests never see each other's.
use std::path::{Path, PathBuf};
use std::sync::Mutex;

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub(crate) struct Counts {
    // Reads and parses of the mount table: one per ItemIdentity::inspect and one per Table::read.
    pub table_reads: u64,
    // Path resolutions: one per folder or source canonicalized, a readlink per component.
    pub resolves: u64,
}

static WATCHED: Mutex<Vec<(PathBuf, Counts)>> = Mutex::new(Vec::new());

fn bump(path: &Path, change: impl Fn(&mut Counts)) {
    for (root, counts) in WATCHED.lock().unwrap_or_else(|e| e.into_inner()).iter_mut() {
        if path.starts_with(root) {
            change(counts);
        }
    }
}

// Counts begin at zero for every call whose path sits under `root`, on any thread, until the guard drops.
pub(crate) fn watch(root: &Path) -> Watch {
    WATCHED.lock().unwrap_or_else(|e| e.into_inner()).push((root.to_path_buf(), Counts::default()));
    Watch(root.to_path_buf())
}

pub(crate) struct Watch(PathBuf);

impl Watch {
    pub(crate) fn snapshot(&self) -> Counts {
        WATCHED.lock().unwrap_or_else(|e| e.into_inner()).iter().find(|(root, _)| *root == self.0).map(|(_, counts)| *counts).unwrap_or_default()
    }
}

impl Drop for Watch {
    fn drop(&mut self) {
        WATCHED.lock().unwrap_or_else(|e| e.into_inner()).retain(|(root, _)| *root != self.0);
    }
}

pub(crate) fn table_read(path: &Path) {
    bump(path, |c| c.table_reads += 1);
}

pub(crate) fn resolve(path: &Path) {
    bump(path, |c| c.resolves += 1);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_call_on_another_thread_counts_and_one_outside_the_root_does_not() {
        let watch = watch(Path::new("/probe-root/a"));
        std::thread::spawn(|| { table_read(Path::new("/probe-root/a/x")); resolve(Path::new("/probe-root/a")); }).join().unwrap();
        table_read(Path::new("/probe-root/b/x"));
        assert_eq!(watch.snapshot(), Counts { table_reads: 1, resolves: 1 });
    }
}
