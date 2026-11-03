// The replay's own tests, beside it so redo.rs stays under the file budget.
use super::*;
use crate::backend::{ops, testdir::TestDir, undo::Journal};
use std::sync::mpsc::channel;

fn guard(sandbox: &TestDir, paths: &[&Path]) {
    for path in paths {
        assert!(!path.as_os_str().is_empty() && path.is_absolute() && path.starts_with(sandbox.path()));
    }
    assert!(sandbox.path().join(".flea-test-sandbox").is_file());
}
// Before Linux 6.13 ctime ticks every few milliseconds, so the rewrite repeats until the filesystem records it.
fn rewrite_until_recorded(path: &Path, payload: &str) {
    const TRIES: u32 = 1_000_000;
    let before = ItemIdentity::inspect(path).unwrap();
    for _ in 0..TRIES {
        std::fs::write(path, payload).unwrap();
        if !before.unchanged_for_move(&ItemIdentity::inspect(path).unwrap()) {
            return;
        }
    }
    panic!("{} kept its ctime across {} rewrites", path.display(), TRIES);
}
fn redo(journal: &mut Journal) -> Result<String, FleaError> {
    let (tx, _rx) = channel();
    journal.redo(1, &AtomicBool::new(false), &tx)
}

#[test]
fn redo_classifies_the_existing_parent_not_the_missing_name() {
    let sandbox = TestDir::new("redo-parent");
    let original = sandbox.file("original", "payload");
    let (result, steps) = ops::duplicate(&original);
    let copy = result.unwrap();
    let mut journal = Journal::new();
    journal.push(Entry { op: "duplicate".into(), steps });
    assert_eq!(journal.undo().unwrap(), "duplicate");
    assert!(!copy.exists());
    // Only the missing name is marked, so probing it answers durable and probing its parent does not.
    crate::backend::durable::test_reset();
    crate::backend::durable::test_mark_durable(&copy);
    crate::backend::durable::test_set_fail_dirs(true);
    let redone = redo(&mut journal);
    crate::backend::durable::test_set_fail_dirs(false);
    crate::backend::durable::test_reset();
    assert!(redone.is_ok(), "the parent was classified, so no folder flush ran to fail: {:?}", redone.err().map(|e| e.msg));
}

#[test]
fn copy_rename_chain_survives_two_complete_undo_redo_cycles() {
    let sandbox = TestDir::new("redo-chain");
    let original = sandbox.file("original", "keep this payload");
    let (result, steps) = ops::duplicate(&original);
    let copy = result.unwrap();
    let mut journal = Journal::new();
    journal.push(Entry { op: "duplicate".into(), steps });
    let (renamed, steps) = ops::rename(&copy, "renamed").unwrap();
    journal.push(Entry { op: "rename".into(), steps });
    for _ in 0..2 {
        guard(&sandbox, &[&original, &copy, &renamed]);
        assert_eq!(journal.undo().unwrap(), "rename");
        guard(&sandbox, &[&original, &copy, &renamed]);
        assert_eq!(journal.undo().unwrap(), "duplicate");
        assert!(!copy.exists() && !renamed.exists());
        assert_eq!(redo(&mut journal).unwrap(), "duplicate");
        assert_eq!(redo(&mut journal).unwrap(), "rename");
        assert_eq!(std::fs::read_to_string(&renamed).unwrap(), "keep this payload");
        assert_eq!(std::fs::read_to_string(&original).unwrap(), "keep this payload");
    }
}

#[test]
fn recreated_parent_rebinds_child_destination_without_accepting_a_foreign_parent() {
    let sandbox = TestDir::new("redo-parent");
    let mut journal = Journal::new();
    let (parent, steps) = ops::mkdir(sandbox.path(), "parent").unwrap();
    journal.push(Entry { op: "mkdir".into(), steps });
    let (child, steps) = ops::mkdir(&parent, "child").unwrap();
    journal.push(Entry { op: "mkdir".into(), steps });
    guard(&sandbox, &[&parent, &child]);
    journal.undo().unwrap();
    guard(&sandbox, &[&parent, &child]);
    journal.undo().unwrap();
    redo(&mut journal).unwrap();
    redo(&mut journal).unwrap();
    assert!(child.is_dir());
    guard(&sandbox, &[&parent, &child]);
    journal.undo().unwrap();
    let moved = sandbox.join("old-parent");
    guard(&sandbox, &[&parent, &moved]);
    std::fs::rename(&parent, &moved).unwrap();
    std::fs::create_dir(&parent).unwrap();
    assert_eq!(redo(&mut journal).unwrap_err().msg, "the destination folder was replaced, so nothing was redone");
    assert!(!child.exists());
}

#[test]
fn redo_refuses_changed_sources_and_destination_collisions() {
    let sandbox = TestDir::new("redo-refusal");
    let original = sandbox.file("original", "before");
    let (result, steps) = ops::duplicate(&original);
    let copy = result.unwrap();
    let mut journal = Journal::new();
    journal.push(Entry { op: "duplicate".into(), steps });
    guard(&sandbox, &[&original, &copy]);
    journal.undo().unwrap();
    rewrite_until_recorded(&original, "changed payload");
    assert!(redo(&mut journal).unwrap_err().msg.contains("changed"));
    assert!(!copy.exists());
    let (result, steps) = ops::duplicate(&original);
    let copy = result.unwrap();
    journal.push(Entry { op: "duplicate".into(), steps });
    guard(&sandbox, &[&original, &copy]);
    journal.undo().unwrap();
    std::fs::write(&copy, "foreign destination").unwrap();
    assert_eq!(redo(&mut journal).unwrap_err().msg, "an item with that name is already there, so redo left it in place");
    assert_eq!(std::fs::read_to_string(&copy).unwrap(), "foreign destination");
}

#[test]
fn a_cancel_before_redo_starts_is_answered_before_any_step_is_checked() {
    let sandbox = TestDir::new("redo-cancel");
    let original = sandbox.file("original", "payload");
    let (result, steps) = ops::duplicate(&original);
    let copy = result.unwrap();
    let mut journal = Journal::new();
    journal.push(Entry { op: "duplicate".into(), steps });
    guard(&sandbox, &[&original, &copy]);
    journal.undo().unwrap();
    std::fs::write(&copy, "foreign destination").unwrap();
    let (tx, _rx) = channel();
    assert_eq!(journal.redo(1, &AtomicBool::new(true), &tx).unwrap_err().msg, "redo cancelled", "the check never ran past the cancel");
    assert_eq!(std::fs::read_to_string(&copy).unwrap(), "foreign destination");
}

#[test]
fn new_file_is_recreated_but_changed_or_replaced_files_survive_undo() {
    let sandbox = TestDir::new("redo-newfile");
    let (path, identity) = super::super::menu_actions::create_file(sandbox.path(), "new").unwrap();
    let mut journal = Journal::new();
    journal.push(Entry { op: "newfile".into(), steps: vec![Step::MadeFile { path: path.clone(), identity }] });
    guard(&sandbox, &[&path]);
    journal.undo().unwrap();
    redo(&mut journal).unwrap();
    assert_eq!(path.metadata().unwrap().len(), 0);
    std::fs::write(&path, "user content").unwrap();
    guard(&sandbox, &[&path]);
    assert!(journal.undo().unwrap_err().msg.contains("changed"));
    assert_eq!(std::fs::read_to_string(&path).unwrap(), "user content");
    let (empty, identity) = super::super::menu_actions::create_file(sandbox.path(), "empty").unwrap();
    journal.push(Entry { op: "newfile".into(), steps: vec![Step::MadeFile { path: empty.clone(), identity }] });
    let saved = sandbox.join("saved");
    guard(&sandbox, &[&empty, &saved]);
    std::fs::rename(&empty, &saved).unwrap();
    std::fs::write(&empty, "replacement").unwrap();
    guard(&sandbox, &[&empty, &saved]);
    assert!(journal.undo().is_err());
    assert_eq!(std::fs::read_to_string(empty).unwrap(), "replacement");
}

// Sample output: "1 item was left in place: a: no", or "2 items were left in place: a: no; b: no".
#[test]
fn skipped_items_are_one_whole_sentence_for_one_and_for_many() {
    assert_eq!(left_in_place(&["a: no".to_string()]), "1 item was left in place: a: no");
    assert_eq!(left_in_place(&["a: no".to_string(), "b: no".to_string()]), "2 items were left in place: a: no; b: no");
}

#[test]
fn an_operation_with_no_recorded_source_says_it_cannot_be_redone() {
    let created = || Step::Created { path: PathBuf::from("/d/x") };
    assert_eq!(Replay::capture(Entry { op: "mkdir".into(), steps: vec![created()] }).err().unwrap().msg, "this operation cannot be redone");
    let (tx, _rx) = channel();
    let saved = ReplayStep { step: created(), input: None, parent: None };
    assert_eq!(apply(&saved, 1, 0, &AtomicBool::new(false), &tx, &mut Vec::new()).unwrap_err().msg, "this operation cannot be redone");
}
