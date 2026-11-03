// A batch of Replace answers shares one deferred trash session: its list cost, put-back and cancel.
use super::replace_tests::working_trash;
use super::tests::{asked, chosen, text, transfer};
use super::*;
use crate::backend::testdir::TestDir;
use crate::backend::trash;
use std::os::unix::fs::PermissionsExt;

#[test]
fn replace_batch_lists_the_trash_once_not_per_file() {
    let d = TestDir::new("replace-batch-lists");
    let to = d.dir("to");
    d.dir("from");
    let mut photos = Vec::new();
    for i in 0..4 {
        photos.push(d.file(&format!("from/p{}.png", i), "yours"));
        d.file(&format!("to/p{}.png", i), "there");
    }
    let refs: Vec<&Path> = photos.iter().map(PathBuf::as_path).collect();
    let (_trash, _can) = working_trash(&d);
    trash::test_reset_list_calls();
    let (ok, failed, _, _, _) = transfer(false, &refs, &to, chosen("replace", asked(1, &refs, &to), &to));
    assert_eq!((ok, failed), (4, 0));
    assert_eq!(trash::test_list_calls(), 2, "N replaces cost one before/after pair, not 2N");
}

#[test]
fn replace_batch_puts_back_the_file_whose_copy_failed() {
    let d = TestDir::new("replace-batch-putback");
    let to = d.dir("to");
    d.dir("from");
    let bad = d.file("from/bad.txt", "yours");
    d.file("to/bad.txt", "there");
    let good = d.file("from/good.txt", "yours-g");
    d.file("to/good.txt", "there-g");
    std::fs::set_permissions(&bad, std::fs::Permissions::from_mode(0o000)).unwrap();
    let (_trash, _can) = working_trash(&d);
    let refs: Vec<&Path> = [&bad, &good].iter().map(|p| p.as_path()).collect();
    let (ok, failed, _, _, entry) = transfer(false, &refs, &to, chosen("replace", asked(1, &refs, &to), &to));
    std::fs::set_permissions(&bad, std::fs::Permissions::from_mode(0o644)).unwrap();
    assert_eq!((ok, failed), (1, 1));
    assert_eq!(text(&to.join("bad.txt")), "there", "the failed replace goes straight back");
    assert_eq!(text(&to.join("good.txt")), "yours-g");
    let mut bad_kept = false;
    let mut good_uri = false;
    for step in &entry.steps {
        if let Step::Trashed(e) = step {
            if e.original == to.join("bad.txt") { bad_kept = true; }
            if e.original == to.join("good.txt") && !e.uri.is_empty() { good_uri = true; }
        }
    }
    assert!(!bad_kept, "a restored put-back leaves no trash step: {:?}", entry.steps);
    assert!(good_uri, "the landed replace stays journaled with its trash URI: {:?}", entry.steps);
}

#[test]
fn replace_batch_cancel_still_settles_every_trashed_item() {
    let d = TestDir::new("replace-batch-cancel");
    let to = d.dir("to");
    d.dir("from");
    let mut files = Vec::new();
    for i in 0..4 {
        files.push(d.file(&format!("from/c{}.txt", i), "yours"));
        d.file(&format!("to/c{}.txt", i), "there");
    }
    let refs: Vec<&Path> = files.iter().map(PathBuf::as_path).collect();
    let (_trash, _can) = working_trash(&d);
    let _cancel_at = crate::backend::opsreq::CancelAtGuard::hold(1);
    let (ok, failed, skipped, _, entry) = transfer(false, &refs, &to, chosen("replace", asked(1, &refs, &to), &to));
    assert_eq!((ok, failed, skipped), (1, 0, 3));
    assert_eq!(text(&to.join("c0.txt")), "yours");
    assert_eq!(text(&to.join("c1.txt")), "there", "the cancelled item's old file is back");
    assert_eq!(text(&to.join("c2.txt")), "there");
    assert!(matches!(&entry.steps[..], [Step::Trashed(old), Step::Copied { .. }] if old.original == to.join("c0.txt") && !old.uri.is_empty()), "the one landed replace is journaled with its URI: {:?}", entry.steps);
}
