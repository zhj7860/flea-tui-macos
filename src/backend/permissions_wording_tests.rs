// The words a refused permissions request shows; each pins the sentence a person reads, not the branch that raises it.
use super::*;
use crate::backend::testdir::TestDir;
use std::fs::Permissions as Mode;
use std::os::unix::fs::PermissionsExt;

// An apply with no reviewed item for its id is the same stale selection every sibling refusal names.
#[test]
fn an_apply_without_its_reviewed_item_says_to_reopen_permissions() {
    const STALE: &str = "Selected item changed; reopen Permissions.";
    let d = TestDir::new("permissions-stale-apply");
    let path = d.file("item", "a");
    std::fs::set_permissions(&path, Mode::from_mode(0o644)).unwrap();
    let mut p = Permissions::default();
    assert_eq!(p.apply(1, "600").unwrap_err(), STALE);
    p.inspect(2, &path).unwrap();
    assert_eq!(p.apply(3, "600").unwrap_err(), STALE);
    assert_eq!(path.metadata().unwrap().mode() & 0o777, 0o644, "a refused apply changes nothing");
    // The held descriptor cannot differ from the identity recorded from it, so that refusal is pinned by its source.
    let live = include_str!("permissions.rs").split("\n#[cfg(test)]\nmod tests").next().unwrap();
    for retired in ["Permissions selection expired", "Held item identity changed"] {
        assert!(!live.contains(retired), "retired wording came back: {}", retired);
    }
}
