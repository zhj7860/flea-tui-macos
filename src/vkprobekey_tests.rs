use super::*;
use crate::backend::testdir::TestDir;
// A fake sysfs and manifest tree, so no test reads the real ones.
struct Fake {
    t: TestDir,
    boot: PathBuf,
    pci: PathBuf,
    drm: PathBuf,
    icd: PathBuf,
    layer: PathBuf,
    lib: PathBuf,
    exe: PathBuf,
    settings: PathBuf,
    ld_cache: PathBuf,
}
fn fake(tag: &str) -> Fake {
    let t = TestDir::new(tag);
    let (pci, drm, icd, layer, lib) = (t.dir("pci"), t.dir("drm"), t.dir("icd"), t.dir("layer"), t.dir("lib"));
    let slot = pci.join("0000:00:02.0");
    std::fs::create_dir_all(&slot).unwrap();
    std::fs::write(slot.join("class"), "0x030000\n").unwrap();
    std::fs::write(slot.join("vendor"), "0x8086\n").unwrap();
    std::fs::write(slot.join("device"), "0xa788\n").unwrap();
    let card = drm.join("card0").join("device");
    std::fs::create_dir_all(&card).unwrap();
    std::fs::write(card.join("vendor"), "0x8086\n").unwrap();
    std::fs::write(card.join("device"), "0xa788\n").unwrap();
    std::fs::write(icd.join("intel_icd.json"), "{\"ICD\":{\"library_path\":\"libvulkan_intel.so\"}}\n").unwrap();
    std::fs::write(lib.join("libvulkan_intel.so"), "lib one\n").unwrap();
    std::fs::write(layer.join("VK_LAYER_MESA_overlay.json"), "{\"layer\":1}\n").unwrap();
    let boot = t.file("boot_id", "boot-one\n");
    let exe = t.file("flea", "exe one\n");
    let settings = t.join("vk_loader_settings.json");
    let ld_cache = t.file("ld.so.cache", "cache one\n");
    Fake { t, boot, pci, drm, icd, layer, lib, exe, settings, ld_cache }
}
fn env_one() -> Vec<(String, String)> {
    vec![
        ("VK_ICD_FILENAMES".into(), "a.json".into()),
        ("XDG_DATA_HOME".into(), "/x".into()),
    ]
}
fn key_with_libs(f: &Fake, env_vars: &[(String, String)], surface: &str, libs: &[PathBuf]) -> Option<String> {
    let icd = vec![f.icd.clone()];
    let layer = vec![f.layer.clone()];
    let settings = vec![f.settings.clone()];
    key_for(&Roots {
        boot: &f.boot,
        pci: &f.pci,
        drm: &f.drm,
        icd_dirs: &icd,
        layer_dirs: &layer,
        lib_dirs: libs,
        settings_files: &settings,
        ld_cache: &f.ld_cache,
        exe: &f.exe,
        env_vars,
        surface,
    })
}
fn key_opt(f: &Fake, env_vars: &[(String, String)], surface: &str) -> Option<String> {
    key_with_libs(f, env_vars, surface, std::slice::from_ref(&f.lib))
}
fn key_of(f: &Fake, env_vars: &[(String, String)], surface: &str) -> String {
    key_opt(f, env_vars, surface).expect("a whole inventory has a key")
}
#[test]
fn the_same_inputs_give_the_same_key() {
    let f = fake("vkkey-same");
    let env_vars = env_one();
    assert_eq!(key_of(&f, &env_vars, "VK_KHR_wayland_surface"), key_of(&f, &env_vars, "VK_KHR_wayland_surface"));
}
#[test]
fn an_inventory_that_cannot_be_had_whole_has_no_key() {
    let f = fake("vkkey-nokey");
    let env_vars = env_one();
    assert!(key_opt(&f, &env_vars, "VK_KHR_wayland_surface").is_some());
    for n in 0..256 {
        std::fs::write(f.icd.join(format!("filler{n}_icd.json")), "{}\n").unwrap();
    }
    assert_eq!(key_opt(&f, &env_vars, "VK_KHR_wayland_surface"), None, "257 manifests are not a driver set");
}
#[test]
fn a_boot_id_is_part_of_the_key() {
    let f = fake("vkkey-boot");
    let env_vars = env_one();
    let base = key_of(&f, &env_vars, "VK_KHR_wayland_surface");
    std::fs::write(&f.boot, "boot-two\n").unwrap();
    assert_ne!(key_of(&f, &env_vars, "VK_KHR_wayland_surface"), base);
}
#[test]
fn a_pci_vendor_is_part_of_the_key() {
    let f = fake("vkkey-pci");
    let env_vars = env_one();
    let base = key_of(&f, &env_vars, "VK_KHR_wayland_surface");
    std::fs::write(f.pci.join("0000:00:02.0").join("vendor"), "0x10de\n").unwrap();
    assert_ne!(key_of(&f, &env_vars, "VK_KHR_wayland_surface"), base);
}
#[test]
fn a_drm_card_added_changes_the_key() {
    let f = fake("vkkey-drm");
    let env_vars = env_one();
    let base = key_of(&f, &env_vars, "VK_KHR_wayland_surface");
    let card = f.drm.join("card1").join("device");
    std::fs::create_dir_all(&card).unwrap();
    std::fs::write(card.join("vendor"), "0x10de\n").unwrap();
    std::fs::write(card.join("device"), "0x27e0\n").unwrap();
    assert_ne!(key_of(&f, &env_vars, "VK_KHR_wayland_surface"), base);
}
#[test]
fn a_manifest_added_changes_the_key() {
    let f = fake("vkkey-manifest");
    let env_vars = env_one();
    let base = key_of(&f, &env_vars, "VK_KHR_wayland_surface");
    std::fs::write(f.icd.join("extra_icd.json"), "{\"ICD\":{\"library_path\":\"libvulkan_radeon.so\"}}\n").unwrap();
    assert_ne!(key_of(&f, &env_vars, "VK_KHR_wayland_surface"), base);
}
#[test]
fn a_manifest_mtime_is_part_of_the_key() {
    let f = fake("vkkey-mtime");
    let env_vars = env_one();
    let base = key_of(&f, &env_vars, "VK_KHR_wayland_surface");
    std::thread::sleep(std::time::Duration::from_millis(25));
    let body = std::fs::read(f.icd.join("intel_icd.json")).unwrap();
    std::fs::write(f.icd.join("intel_icd.json"), body).unwrap();
    assert_ne!(key_of(&f, &env_vars, "VK_KHR_wayland_surface"), base);
}
#[test]
fn a_manifest_library_replaced_changes_the_key() {
    let f = fake("vkkey-lib");
    let env_vars = env_one();
    let base = key_of(&f, &env_vars, "VK_KHR_wayland_surface");
    std::fs::write(f.lib.join("libvulkan_intel.so"), "lib two, longer\n").unwrap();
    assert_ne!(key_of(&f, &env_vars, "VK_KHR_wayland_surface"), base);
}
#[test]
fn an_implicit_layer_added_changes_the_key() {
    let f = fake("vkkey-layer");
    let env_vars = env_one();
    let base = key_of(&f, &env_vars, "VK_KHR_wayland_surface");
    std::fs::write(f.layer.join("extra_layer.json"), "{\"layer\":2}\n").unwrap();
    assert_ne!(key_of(&f, &env_vars, "VK_KHR_wayland_surface"), base);
}
fn fake_env(pairs: &[(&str, &str)]) -> Vec<(String, String)> {
    collect_env(pairs.iter().map(|(k, v)| (OsString::from(k), OsString::from(v))))
}
#[test]
fn a_loader_or_device_order_variable_is_part_of_the_key() {
    let f = fake("vkkey-env");
    let base = key_of(&f, &fake_env(&[("XDG_DATA_HOME", "/x")]), "VK_KHR_wayland_surface");
    for name in ["VK_ICD_FILENAMES", "MESA_VK_DEVICE_SELECT", "DRI_PRIME"] {
        let env_vars = fake_env(&[("XDG_DATA_HOME", "/x"), (name, "1")]);
        assert_ne!(key_of(&f, &env_vars, "VK_KHR_wayland_surface"), base, "{name}");
    }
}
#[test]
fn the_surface_choice_is_part_of_the_key() {
    let f = fake("vkkey-surface");
    let env_vars = env_one();
    assert_ne!(key_of(&f, &env_vars, "VK_KHR_wayland_surface"), key_of(&f, &env_vars, "VK_KHR_xcb_surface"));
}
#[test]
fn the_binary_is_part_of_the_key() {
    let f = fake("vkkey-exe");
    let env_vars = env_one();
    let base = key_of(&f, &env_vars, "VK_KHR_wayland_surface");
    std::fs::write(&f.exe, "exe two, longer\n").unwrap();
    assert_ne!(key_of(&f, &env_vars, "VK_KHR_wayland_surface"), base);
}
// The loader reads a library_path with a slash relative to the manifest's own directory, not through the search path.
#[test]
fn a_manifest_relative_library_replaced_changes_the_key() {
    let f = fake("vkkey-rel");
    let env_vars = env_one();
    std::fs::write(f.icd.join("rel_icd.json"), "{\"ICD\":{\"library_path\":\"../lib/x.so\"}}\n").unwrap();
    std::fs::write(f.lib.join("x.so"), "lib one\n").unwrap();
    let base = key_with_libs(&f, &env_vars, "VK_KHR_wayland_surface", &[]);
    std::fs::write(f.lib.join("x.so"), "lib two, longer\n").unwrap();
    assert_ne!(key_with_libs(&f, &env_vars, "VK_KHR_wayland_surface", &[]), base);
}
// The dynamic loader searches LD_LIBRARY_PATH before the system dirs, so a libvulkan.so.1 there is the one loaded.
#[test]
fn a_libvulkan_in_an_ld_library_path_dir_replaced_changes_the_key() {
    let f = fake("vkkey-ld");
    let env_vars = env_one();
    let ld = f.t.dir("ld");
    let dirs = libs::lib_search_dirs(Some(ld.clone().into_os_string()), std::slice::from_ref(&f.lib));
    std::fs::write(ld.join("libvulkan.so.1"), "loader one\n").unwrap();
    let base = key_with_libs(&f, &env_vars, "VK_KHR_wayland_surface", &dirs);
    std::fs::write(ld.join("libvulkan.so.1"), "loader two, longer\n").unwrap();
    assert_ne!(key_with_libs(&f, &env_vars, "VK_KHR_wayland_surface", &dirs), base);
}
// The loader reads vk_loader_settings.json from every root, so adding one changes what the probe sees.
#[test]
fn a_loader_settings_file_added_changes_the_key() {
    let f = fake("vkkey-settings");
    let env_vars = env_one();
    let base = key_of(&f, &env_vars, "VK_KHR_wayland_surface");
    std::fs::write(&f.settings, "{}\n").unwrap();
    assert_ne!(key_of(&f, &env_vars, "VK_KHR_wayland_surface"), base);
}
// glibc searches each directory's glibc-hwcaps subdirs before the directory, so a library there is the one loaded.
#[test]
fn a_libvulkan_in_a_hwcaps_subdir_replaced_changes_the_key() {
    let f = fake("vkkey-hwcaps");
    let env_vars = env_one();
    let ld = f.t.dir("ld");
    let hwcaps = f.t.dir("ld/glibc-hwcaps/x86-64-v3");
    let dirs = libs::lib_search_dirs(Some(ld.into_os_string()), std::slice::from_ref(&f.lib));
    std::fs::write(hwcaps.join("libvulkan.so.1"), "loader one\n").unwrap();
    let base = key_with_libs(&f, &env_vars, "VK_KHR_wayland_surface", &dirs);
    std::fs::write(hwcaps.join("libvulkan.so.1"), "loader two, longer\n").unwrap();
    assert_ne!(key_with_libs(&f, &env_vars, "VK_KHR_wayland_surface", &dirs), base);
}
// The system directories come from /etc/ld.so.cache, which ldconfig rewrites whenever a driver is installed or removed.
#[test]
fn the_ld_so_cache_replaced_changes_the_key() {
    let f = fake("vkkey-ldcache");
    let env_vars = env_one();
    let base = key_of(&f, &env_vars, "VK_KHR_wayland_surface");
    std::fs::write(&f.ld_cache, "cache two, longer\n").unwrap();
    assert_ne!(key_of(&f, &env_vars, "VK_KHR_wayland_surface"), base);
}
// The loader skips a hwcaps subdir this CPU lacks, so a libvulkan.so.1 behind an earlier one can be the one loaded.
#[test]
fn a_libvulkan_behind_an_earlier_search_dir_replaced_changes_the_key() {
    let f = fake("vkkey-shadow");
    let env_vars = env_one();
    let ld = f.t.dir("ld");
    let (v4, v3) = (f.t.dir("ld/glibc-hwcaps/x86-64-v4"), f.t.dir("ld/glibc-hwcaps/x86-64-v3"));
    let dirs = libs::lib_search_dirs(Some(ld.into_os_string()), std::slice::from_ref(&f.lib));
    std::fs::write(v4.join("libvulkan.so.1"), "loader v4\n").unwrap();
    std::fs::write(v3.join("libvulkan.so.1"), "loader v3\n").unwrap();
    let base = key_with_libs(&f, &env_vars, "VK_KHR_wayland_surface", &dirs);
    std::fs::write(v3.join("libvulkan.so.1"), "loader v3, longer\n").unwrap();
    assert_ne!(key_with_libs(&f, &env_vars, "VK_KHR_wayland_surface", &dirs), base);
}
// The loader reads env-named driver files and layer dirs, so those files and their libraries join the key.
#[test]
fn env_named_driver_and_layer_files_are_part_of_the_key() {
    let f = fake("vkkey-envfiles");
    let lib = f.t.join("env_driver_lib.so");
    std::fs::write(&lib, "lib one\n").unwrap();
    let driver = f.t.join("env_driver.json");
    std::fs::write(&driver, format!("{{\"ICD\":{{\"library_path\":\"{}\"}}}}\n", lib.display())).unwrap();
    let layerdir = f.t.dir("envlayer");
    std::fs::write(layerdir.join("env_layer.json"), "{\"layer\":1}\n").unwrap();
    let ds = driver.to_string_lossy().into_owned();
    let ls = layerdir.to_string_lossy().into_owned();
    let env_vars = fake_env(&[("XDG_DATA_HOME", "/x"), ("VK_ICD_FILENAMES", ds.as_str()), ("VK_ADD_LAYER_PATH", ls.as_str())]);
    let base = key_of(&f, &env_vars, "VK_KHR_wayland_surface");
    std::fs::write(&driver, format!("{{\"ICD\":{{\"library_path\":\"{}\"}}}}\n  \n", lib.display())).unwrap();
    let after_driver = key_of(&f, &env_vars, "VK_KHR_wayland_surface");
    assert_ne!(after_driver, base, "env driver manifest size");
    std::fs::write(&lib, "lib two, longer\n").unwrap();
    let after_lib = key_of(&f, &env_vars, "VK_KHR_wayland_surface");
    assert_ne!(after_lib, after_driver, "env driver library size");
    std::fs::write(layerdir.join("env_layer.json"), "{\"layer\":1}\n  \n").unwrap();
    assert_ne!(key_of(&f, &env_vars, "VK_KHR_wayland_surface"), after_lib, "env layer manifest size");
    // The loader reads four layer directory lists, so a manifest named only by each one joins the key.
    for name in ["VK_LAYER_PATH", "VK_ADD_LAYER_PATH", "VK_IMPLICIT_LAYER_PATH", "VK_ADD_IMPLICIT_LAYER_PATH"] {
        let named = f.t.dir(&format!("layer-{name}"));
        std::fs::write(named.join("named_layer.json"), "{\"layer\":1}\n").unwrap();
        let named_text = named.to_string_lossy().into_owned();
        let env_vars = fake_env(&[("XDG_DATA_HOME", "/x"), (name, named_text.as_str())]);
        let base = key_of(&f, &env_vars, "VK_KHR_wayland_surface");
        std::fs::write(named.join("named_layer.json"), "{\"layer\":1}\n  \n").unwrap();
        assert_ne!(key_of(&f, &env_vars, "VK_KHR_wayland_surface"), base, "{name} names a layer directory");
    }
}
// A driver variable may name a directory, and the loader then reads every manifest in it.
#[test]
fn an_env_named_driver_directory_keys_its_manifests() {
    let f = fake("vkkey-envdir");
    let dir = f.t.dir("envdrivers");
    std::fs::write(dir.join("a_icd.json"), "{\"ICD\":{}}\n").unwrap();
    let ds = dir.to_string_lossy().into_owned();
    let env_vars = fake_env(&[("XDG_DATA_HOME", "/x"), ("VK_DRIVER_FILES", ds.as_str())]);
    let base = key_of(&f, &env_vars, "VK_KHR_wayland_surface");
    std::fs::write(dir.join("a_icd.json"), "{\"ICD\":{}}\n  \n").unwrap();
    assert_ne!(key_of(&f, &env_vars, "VK_KHR_wayland_surface"), base, "a manifest inside an env-named driver directory");
}
