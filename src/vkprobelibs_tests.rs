use super::*;
// Sample input: LD_LIBRARY_PATH="/a::/b" and system dirs [/usr/lib]; the empty entry between them is ".".
#[test]
fn an_empty_ld_library_path_entry_is_the_current_directory_in_its_place() {
    let dirs = lib_search_dirs(Some(OsString::from("/a::/b")), &[PathBuf::from("/usr/lib")]);
    let hwcaps = |dir: &&PathBuf| dir.components().any(|c| c.as_os_str() == "glibc-hwcaps");
    let plain: Vec<&PathBuf> = dirs.iter().filter(|dir| !hwcaps(dir)).collect();
    let want: Vec<PathBuf> = ["/a", ".", "/b", "/usr/lib"].iter().map(PathBuf::from).collect();
    assert_eq!(plain, want.iter().collect::<Vec<_>>());
    assert_eq!(lib_search_dirs(Some(OsString::new()), &[]), Vec::<PathBuf>::new(), "an empty variable is no entries");
}
// Sample input: LD_LIBRARY_PATH="/a" and system dirs [/usr/lib], each preceded by its x86-64-v4, v3 and v2 subdirs.
#[test]
fn each_search_dir_is_preceded_by_its_three_hwcaps_subdirs() {
    let dirs = lib_search_dirs(Some(OsString::from("/a")), &[PathBuf::from("/usr/lib")]);
    let want: Vec<PathBuf> = [
        "/a/glibc-hwcaps/x86-64-v4",
        "/a/glibc-hwcaps/x86-64-v3",
        "/a/glibc-hwcaps/x86-64-v2",
        "/a",
        "/usr/lib/glibc-hwcaps/x86-64-v4",
        "/usr/lib/glibc-hwcaps/x86-64-v3",
        "/usr/lib/glibc-hwcaps/x86-64-v2",
        "/usr/lib",
    ]
    .iter()
    .map(PathBuf::from)
    .collect();
    assert_eq!(dirs, want);
}
