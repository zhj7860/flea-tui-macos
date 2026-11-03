use super::tests::{amd_box, LAVAPIPE, NVIDIA};
use super::*;
use crate::backend::fifotest::{mkfifo, within};
use crate::backend::testdir::TestDir;
use crate::vulkan::MANIFEST_BYTES;
use std::os::unix::ffi::OsStringExt;

// The loader compares names case-insensitively in every directory, so a kept driver protects its name.
#[test]
fn a_name_shared_with_a_kept_driver_is_never_disabled() {
    let t = TestDir::new("icdexclude-shared");
    let (pci, drm, icd) = amd_box(&t);
    let user = t.dir("user");
    std::fs::write(user.join("NVIDIA_ICD.json"), LAVAPIPE).unwrap();
    std::fs::create_dir(user.join("intel_icd.x86_64.json")).unwrap();
    // Only the hasvk manifest has no kept namesake here, so only it is disabled.
    assert_eq!(absent_vendor_manifests(&pci, &drm, &[icd, user]), vec!["intel_hasvk_icd.x86_64.json"]);
}

// The loader reads ICD.library_path as C strings, so a library_path elsewhere names nothing and a NUL keeps the driver.
#[test]
fn only_the_icd_library_path_names_the_driver() {
    let t = TestDir::new("icdexclude-scope");
    let (pci, drm, _) = amd_box(&t);
    let icd = t.dir("scope");
    std::fs::write(icd.join("amd_icd.json"), "{\"library_path\":\"libGLX_nvidia.so.0\",\"ICD\":{\"library_path\":\"libvulkan_radeon.so\"}}\n").unwrap();
    std::fs::write(icd.join("escaped_icd.json"), "{\"ICD\":{\"library_path\":\"\\/usr\\/lib\\/libGLX_nvidia.so.0\"}}\n").unwrap();
    // Both drive the AMD GPU here: the loader stops at the NUL, in the path and in the first ICD's name.
    std::fs::write(icd.join("nul_value_icd.json"), "{\"ICD\":{\"library_path\":\"libvulkan_radeon.so\\u0000/../libGLX_nvidia.so.0\"}}\n").unwrap();
    std::fs::write(icd.join("nul_key_icd.json"), "{\"ICD\\u0000x\":{\"library_path\":\"libvulkan_radeon.so\"},\"ICD\":{\"library_path\":\"libGLX_nvidia.so.0\"}}\n").unwrap();
    assert_eq!(absent_vendor_manifests(&pci, &drm, &[icd]), vec!["escaped_icd.json"]);
}

#[test]
fn a_driver_named_only_by_its_directory_or_past_the_size_cap_is_kept() {
    let t = TestDir::new("icdexclude-path");
    let (pci, drm, _) = amd_box(&t);
    let icd = t.dir("opt");
    std::fs::write(icd.join("lvp_icd.json"), "{\"ICD\":{\"library_path\":\"/opt/intel/nvidia/libvulkan_lvp.so\"}}\n").unwrap();
    std::fs::write(icd.join("big_icd.json"), format!("{}{}", NVIDIA, " ".repeat(MANIFEST_BYTES))).unwrap();
    assert!(absent_vendor_manifests(&pci, &drm, &[icd]).is_empty());
}

// Only a packaged driver's own library name is known, so a vendor word elsewhere names nothing and protects its namesakes.
#[test]
fn an_unfamiliar_library_is_kept_whatever_vendor_its_name_mentions() {
    let t = TestDir::new("icdexclude-unfamiliar");
    let (pci, drm, icd) = amd_box(&t);
    let user = t.dir("user");
    std::fs::write(user.join("emu_icd.json"), "{\"ICD\":{\"library_path\":\"libvulkan_intel-emulation.so\"}}\n").unwrap();
    std::fs::write(user.join("nvidia_icd.json"), "{\"ICD\":{\"library_path\":\"/opt/wrap/libGLX_nvidia-wrapper.so.0\"}}\n").unwrap();
    assert_eq!(absent_vendor_manifests(&pci, &drm, &[icd, user]), vec!["intel_hasvk_icd.x86_64.json", "intel_icd.x86_64.json"]);
}

#[test]
fn a_name_the_loader_would_read_as_a_glob_is_never_written() {
    let t = TestDir::new("icdexclude-glob");
    let (pci, drm, _) = amd_box(&t);
    let icd = t.dir("odd");
    for name in ["nv*_icd.json", "a,b_icd.json", "nvidia icd.json", "~nv_icd.json"] {
        std::fs::write(icd.join(name), NVIDIA).unwrap();
    }
    assert!(absent_vendor_manifests(&pci, &drm, &[icd]).is_empty());
}

// A fifo is read only when something writes to it, so opening one would hold the launch for good.
#[test]
fn a_fifo_named_like_a_manifest_neither_holds_the_launch_nor_loses_its_name() {
    let t = TestDir::new("icdexclude-fifo");
    let (pci, drm, icd) = amd_box(&t);
    let pipes = t.dir("pipes");
    mkfifo(&pipes.join("nvidia_icd.json"));
    let names = within("a fifo named like a manifest", move || absent_vendor_manifests(&pci, &drm, &[icd, pipes]));
    assert_eq!(names, vec!["intel_hasvk_icd.x86_64.json", "intel_icd.x86_64.json"]);
}

// One packaged driver reached through a symlink in /etc and a case variant in the config home is still one absent driver.
#[test]
fn one_absent_driver_seen_through_a_symlink_and_a_case_variant_is_disabled_once() {
    let t = TestDir::new("icdexclude-dup");
    let (pci, drm, icd) = amd_box(&t);
    let (etc, user) = (t.dir("etc"), t.dir("user"));
    std::os::unix::fs::symlink(icd.join("nvidia_icd.json"), etc.join("nvidia_icd.json")).unwrap();
    std::fs::write(user.join("NVIDIA_ICD.json"), NVIDIA).unwrap();
    assert_eq!(absent_vendor_manifests(&pci, &drm, &[user, etc, icd]), vec!["nvidia_icd.json", "intel_hasvk_icd.x86_64.json", "intel_icd.x86_64.json"]);
}

#[test]
fn the_search_covers_every_loader_root_and_keeps_a_path_that_is_not_utf8() {
    let odd = OsString::from_vec(b"/data/\xff".to_vec());
    let mut data_dirs = odd.clone();
    data_dirs.push(":/opt/share");
    let roots = xdg_roots(|name| match name {
        "HOME" => Some(OsString::from("/home/u")),
        "XDG_CONFIG_DIRS" => Some(OsString::from("/cfg/a::/cfg/b")),
        "XDG_DATA_DIRS" => Some(data_dirs.clone()),
        "XDG_DATA_HOME" => Some(OsString::new()),
        _ => None,
    });
    for want in ["/home/u/.config", "/cfg/a", "/cfg/b", "/etc/xdg", "/etc", "/home/u/.local/share", "/opt/share", "/usr/local/share", "/usr/share"] {
        assert!(roots.contains(&PathBuf::from(want)), "{want} missing from {roots:?}");
    }
    assert!(roots.contains(&PathBuf::from(odd)), "the non-UTF-8 data dir");
    assert!(!roots.contains(&PathBuf::new()), "an empty list entry is no root");
}
