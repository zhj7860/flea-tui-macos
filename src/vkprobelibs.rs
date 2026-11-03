// Where the dynamic loader and the Vulkan loader look for a library name, as the key stats it.
use super::stat_line;
use crate::icdexclude::manifests::manifest_library_path;
use std::ffi::OsString;
use std::path::{Path, PathBuf};
pub(super) const LIBVULKAN: &str = "libvulkan.so.1";
pub(super) const LIB_DIRS: [&str; 2] = ["/usr/lib", "/usr/lib64"];
// The hwcaps subdirectories glibc tries in each directory before the directory itself, best first.
const HWCAPS_SUBDIRS: [&str; 3] = ["glibc-hwcaps/x86-64-v4", "glibc-hwcaps/x86-64-v3", "glibc-hwcaps/x86-64-v2"];
// The cache the loader reads for the system directories, which ldconfig rewrites after every library change.
pub(super) const LD_SO_CACHE: &str = "/etc/ld.so.cache";
// Every directory glibc searches, each after its hwcaps subdirs: LD_LIBRARY_PATH (empty entry is "."), then the system dirs.
pub(super) fn lib_search_dirs(ld_library_path: Option<OsString>, system: &[PathBuf]) -> Vec<PathBuf> {
    let mut dirs: Vec<PathBuf> = Vec::new();
    // An empty variable is no entries to glibc, and an empty entry within one is the current directory.
    for dir in ld_library_path.filter(|value| !value.is_empty()).iter().flat_map(std::env::split_paths) {
        dirs.push(if dir.as_os_str().is_empty() { PathBuf::from(".") } else { dir });
    }
    dirs.extend(system.iter().cloned());
    let mut searched: Vec<PathBuf> = Vec::new();
    for dir in dirs {
        // Searching a subdir the loader would skip only makes the key stricter.
        for subdir in HWCAPS_SUBDIRS {
            searched.push(dir.join(subdir));
        }
        searched.push(dir);
    }
    searched
}
// Every ICD manifest's library as a stat line: absolute as written, with a slash beside the manifest, else by search.
pub(super) fn icd_lib_lines(paths: &[PathBuf], lib_dirs: &[PathBuf]) -> Vec<String> {
    let mut out = Vec::new();
    for path in paths {
        let Some(lib) = manifest_library_path(path) else {
            continue;
        };
        if Path::new(&lib).is_absolute() {
            out.push(stat_line(Path::new(&lib)));
            continue;
        }
        // The loader resolves a relative library_path with a slash against the manifest's directory, else by search.
        if lib.contains('/') {
            let dir = path.parent().unwrap_or_else(|| Path::new("."));
            out.push(stat_line(&dir.join(&lib)));
            continue;
        }
        let mut found = false;
        for dir in lib_dirs {
            let candidate = dir.join(&lib);
            if candidate.is_file() {
                out.push(stat_line(&candidate));
                found = true;
            }
        }
        if !found {
            out.push(format!("absent {lib}"));
        }
    }
    out.sort();
    out
}
// libvulkan.so.1 in every search dir that holds it, following symlinks, since the loader may skip an earlier one.
pub(super) fn libvulkan_line(lib_dirs: &[PathBuf]) -> String {
    let mut found: Vec<String> = Vec::new();
    for dir in lib_dirs {
        if let Ok(real) = std::fs::canonicalize(dir.join(LIBVULKAN)) {
            found.push(stat_line(&real));
        }
    }
    if found.is_empty() {
        return String::from("absent libvulkan.so.1");
    }
    found.join(" ")
}
#[cfg(test)]
#[path = "vkprobelibs_tests.rs"]
mod tests;
