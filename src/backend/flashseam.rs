// The bench seam, compiled only with the flash-test-seam feature: a loop device or file inside a marked root.
use std::path::{Path, PathBuf};

// The marker this tree's own sandbox guard owns; a root without it is not a bench root.
const MARKER: &str = ".flea-test-sandbox";
// The one variable that names the marked root the seam may touch.
const ROOT_ENV: &str = "FLEA_FLASH_ALLOW_LOOP";

// The root the bench named in the environment, unchecked: the one place production reads the variable.
pub(crate) fn named_root() -> Option<PathBuf> {
    named_root_from(&|name| std::env::var_os(name))
}

// A set but empty variable names no root.
fn named_root_from(get: &dyn Fn(&str) -> Option<std::ffi::OsString>) -> Option<PathBuf> {
    get(ROOT_ENV).filter(|text| !text.is_empty()).map(PathBuf::from)
}

// A named root that is absolute and carries the marker; any other is no bench root.
pub(crate) fn marked(root: &Path) -> Option<PathBuf> {
    (root.is_absolute() && root.join(MARKER).is_file()).then(|| root.to_path_buf())
}

// The marked root the bench named in the environment.
pub(crate) fn root() -> Option<PathBuf> {
    marked(&named_root()?)
}

// Strictly inside: the root itself is a directory, never the file.
pub(crate) fn inside(root: &Path, path: &Path) -> bool {
    let canonical_root = root.canonicalize().unwrap_or_else(|_| root.to_path_buf());
    let canonical = path.canonicalize().unwrap_or_else(|_| path.to_path_buf());
    canonical.starts_with(&canonical_root) && canonical != canonical_root
}

// Sample backing file: /sys/block/loop0/loop/backing_file answers the file the loop was set up on.
pub(crate) fn loop_backing_inside(named: Option<&Path>, dev: &str, sys: &Path) -> bool {
    let Some(root) = named.and_then(marked) else { return false };
    let text = std::fs::read_to_string(sys.join("block").join(dev).join("loop/backing_file")).unwrap_or_default();
    let backing = text.trim();
    if backing.is_empty() {
        return false;
    }
    match std::fs::symlink_metadata(backing) {
        Ok(meta) if meta.is_file() => inside(&root, Path::new(backing)),
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_root_comes_from_its_one_variable_and_an_empty_one_names_none() {
        // The name AGENTS.md documents, spelled out, so a renamed constant fails here rather than reading a variable nobody sets.
        let named = |value: &'static str| move |name: &str| (name == "FLEA_FLASH_ALLOW_LOOP").then(|| std::ffi::OsString::from(value));
        assert_eq!(named_root_from(&named("/srv/bench")), Some(PathBuf::from("/srv/bench")));
        assert_eq!(named_root_from(&named("")), None, "a set but empty variable names no root");
        assert_eq!(named_root_from(&|_: &str| None), None, "an unset variable names no root");
    }
}
