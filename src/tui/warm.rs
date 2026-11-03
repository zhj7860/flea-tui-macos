// The TUI's gvfs head start: the GUI's prepare and helper spawn, with "-" for the qs shell's page-cache list this process never maps.
pub(crate) fn start(path: &str) -> Option<crate::gvfsprefetch::Prefetch> {
    start_with(path, crate::gvfsprefetch::runtime_dir(), crate::gui::warm_all)
}

// The runtime dir and the spawn ride in as arguments so a test names its own dir and counts the helpers a start launches.
fn start_with(path: &str, runtime: Option<std::path::PathBuf>, mut spawn: impl FnMut(Option<&std::path::Path>, Option<(&str, &std::path::Path)>) -> bool) -> Option<crate::gvfsprefetch::Prefetch> {
    // Sample path: "/run/user/1000/gvfs/smb-share:server=x,share=y/dir".
    let (dest, start_ms) = crate::gvfsprefetch::prepare_for(path, runtime)?;
    if !spawn(None, Some((path, dest.as_path()))) {
        return None;
    }
    Some(crate::gvfsprefetch::Prefetch { dest, path: path.to_string(), start_ms })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::backend::testdir::TestDir;

    #[test]
    fn a_local_start_prepares_nothing_and_spawns_nothing() {
        let d = TestDir::new("tui-warm-local");
        let mut spawned = 0;
        let local = d.path().to_str().unwrap();
        assert!(start_with(local, Some(d.path().to_path_buf()), |_, _| { spawned += 1; true }).is_none(), "prepare answers None off gvfs, so no helper ever spawns");
        assert_eq!(spawned, 0);
        let made: Vec<_> = std::fs::read_dir(d.path()).unwrap().flatten().filter(|e| e.file_name().to_string_lossy().starts_with("gvfs-")).collect();
        assert!(made.is_empty(), "a local start makes nothing in the runtime dir");
    }

    #[test]
    fn a_gvfs_start_prepares_and_spawns_a_helper() {
        let d = TestDir::new("tui-warm-gvfs");
        // The dir is a value this process's XDG_RUNTIME_DIR does not hold, so the dest proves the argument was read.
        let runtime = d.path().join("runtime-given").join("flea");
        // Sample path: "/run/user/1000/gvfs/smb-share:server=x,share=y/dir".
        let path = "/run/user/1000/gvfs/smb-share:server=x,share=y/dir";
        let mut spawned = 0;
        let found = start_with(path, Some(runtime.clone()), |list, gvfs| {
            spawned += 1;
            assert!(list.is_none() && gvfs.is_some_and(|(at, _)| at == path), "the one helper warms the gvfs path alone");
            true
        })
        .expect("a gvfs start prepares");
        assert_eq!(found.path, path);
        assert_eq!(spawned, 1, "one start spawns exactly one helper");
        assert!(found.dest.starts_with(&runtime), "the dest is this launch's file in the given runtime dir: {}", found.dest.display());
        assert!(runtime.is_dir(), "prepare made the given dir");
        assert!(start_with(path, Some(runtime), |_, _| false).is_none(), "a refused spawn is no start");
    }

    #[test]
    fn a_session_without_a_runtime_dir_starts_nothing() {
        let path = "/run/user/1000/gvfs/smb-share:server=x,share=y/dir";
        assert!(start_with(path, None, |_, _| panic!("no runtime dir, no helper")).is_none());
    }
}
