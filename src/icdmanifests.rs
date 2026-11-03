// The manifest inventory: which ICD manifests the loader would read, and what each one's library says about its driver.
use crate::backend::regfile;
use crate::vulkan::{icd_library, MANIFEST_BYTES};
use crate::vulkan::{PCI_VENDOR_AMD, PCI_VENDOR_INTEL, PCI_VENDOR_NVIDIA};
use std::io::Read;
use std::path::{Path, PathBuf};

// More manifests than this is not a desktop's driver set, and they are counted before any is opened.
pub(super) const MAX_MANIFESTS: usize = 256;
// hasvk drives Gen7 and Gen8 Intel only, so it is matched whole and apart from the vendor table.
const HASVK_LIBRARY: &str = "libvulkan_intel_hasvk.so";
// Only these drive one vendor alone, matched whole; any other name, however vendor-like, is kept.
const KNOWN_LIBRARIES: [(&str, u32); 6] = [
    ("libGLX_nvidia.so.0", PCI_VENDOR_NVIDIA),
    ("libvulkan_nouveau.so", PCI_VENDOR_NVIDIA),
    ("libvulkan_radeon.so", PCI_VENDOR_AMD),
    ("amdvlk64.so", PCI_VENDOR_AMD),
    ("amdvlk32.so", PCI_VENDOR_AMD),
    ("libvulkan_intel.so", PCI_VENDOR_INTEL),
];

// Every manifest file in those directories, or None when the inventory cannot be had whole.
pub(crate) fn manifest_paths(dirs: &[PathBuf]) -> Option<Vec<PathBuf>> {
    let mut found = Vec::new();
    for dir in dirs {
        // A directory that is not there, or that the loader could not read either, holds nothing to compare.
        let Ok(entries) = std::fs::read_dir(dir) else { continue };
        for entry in entries {
            let entry = entry.ok()?;
            let name = entry.file_name().to_string_lossy().into_owned();
            if !name.to_ascii_lowercase().ends_with(".json") {
                continue;
            }
            if found.len() == MAX_MANIFESTS {
                return None;
            }
            found.push(entry.path());
        }
    }
    Some(found)
}

// One manifest as (file name, vendor of its library, whether that library is hasvk).
pub(super) type Manifest = (String, Option<u32>, bool);

// Every manifest in those directories, or None when the inventory cannot be had whole.
pub(super) fn manifests_in(dirs: &[PathBuf]) -> Option<Vec<Manifest>> {
    let found = manifest_paths(dirs)?;
    Some(found.into_iter().map(|path| {
        let name = path.file_name().map(|name| name.to_string_lossy().into_owned()).unwrap_or_default();
        let (vendor, hasvk) = manifest_identity(&path);
        (name, vendor, hasvk)
    }).collect())
}

// A manifest's (vendor of its library, whether that library is hasvk), read once, since both come from the one library_path.
// Sample input: the packaged nvidia_icd.json, whose ICD.library_path libGLX_nvidia.so.0 names NVIDIA.
fn manifest_identity(path: &Path) -> (Option<u32>, bool) {
    let library = manifest_library(path);
    let vendor = library.as_deref().and_then(manifest_vendor);
    let hasvk = library.is_some_and(|name| name == HASVK_LIBRARY);
    (vendor, hasvk)
}

// The library_path an ICD manifest names, as written, shared with the probe cache's key.
// Sample input: {"ICD":{"library_path":"/usr/lib/libvulkan_radeon.so"}} gives /usr/lib/libvulkan_radeon.so.
pub(crate) fn manifest_library_path(path: &Path) -> Option<String> {
    // Only a regular file, and opened non-blocking, so a fifo swapped in after the check cannot hold the launch.
    let file = regfile::open_regular(path)?;
    let mut body = String::new();
    file.take(MANIFEST_BYTES as u64 + 1).read_to_string(&mut body).ok()?;
    icd_library(&body)
}

// The packaged library's file name, whole, so neither a directory such as /opt/intel nor a name like libvulkan_intel-emulation.so names Intel.
fn manifest_library(path: &Path) -> Option<String> {
    let library = manifest_library_path(path)?;
    Path::new(&library).file_name()?.to_str().map(str::to_owned)
}

// Sample input: libGLX_nvidia.so.0 names NVIDIA, and libvulkan_lvp.so names no vendor at all.
fn manifest_vendor(library: &str) -> Option<u32> {
    KNOWN_LIBRARIES.iter().find(|(known, _)| *known == library).map(|(_, vendor)| *vendor)
}
