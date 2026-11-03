// A Replace on the home Trash's own filesystem renames the old item there in-process and runs no gio at all.
use super::*;
use crate::backend::hometrash::{rename_to_home, set_test_trash_root, test_set_other_filesystem, test_take_folder_syncs};
use std::cell::RefCell;
use std::os::unix::ffi::OsStrExt;

// Points this thread's home Trash at the sandbox and clears it, the gio stand-in and the filesystem seam on the way out.
struct Sandbox;
impl Drop for Sandbox {
    fn drop(&mut self) {
        set_test_trash_root(None);
        test_set_other_filesystem(false);
        trash::STAND_IN.with(|slot| *slot.borrow_mut() = None);
    }
}

// gio played faithfully over the sandbox Trash, recording every call so a test can count the spawns.
fn counted_gio(d: &TestDir, xdg: &Path) -> (Sandbox, Rc<RefCell<Vec<String>>>) {
    set_test_trash_root(Some(xdg.join("Trash")));
    let calls = Rc::new(RefCell::new(Vec::new()));
    let (seen, can, held) = (Rc::clone(&calls), d.dir("can"), xdg.to_path_buf());
    trash::STAND_IN.with(|slot| *slot.borrow_mut() = Some(Rc::new(move |args: &[&str]| {
        seen.borrow_mut().push(args.join(" "));
        Some(crate::backend::hometrash::tests::gio_like(&can, &held, args))
    })));
    (Sandbox, calls)
}

fn info_path_line(info: &Path) -> String {
    let body = std::fs::read_to_string(info).unwrap();
    assert!(body.starts_with("[Trash Info]\n"), "the info file opens with its section header: {body}");
    let date = body.lines().find_map(|l| l.strip_prefix("DeletionDate=")).expect("the info file stamps the deletion date");
    assert_eq!((date.len(), &date[4..5], &date[10..11]), (19, "-", "T"), "DeletionDate is local YYYY-MM-DDTHH:MM:SS: {date}");
    body.lines().find_map(|l| l.strip_prefix("Path=")).expect("the info file names the original path").to_string()
}

#[test]
fn a_merge_replace_on_the_trash_filesystem_runs_no_gio_and_undo_restores_every_file() {
    let d = TestDir::new("merge-trash-inprocess");
    let xdg = d.dir("xdg");
    let to = d.dir("to");
    let album = d.dir("from/trip");
    d.dir("to/trip");
    for i in 0..3 {
        d.file(&format!("from/trip/f {i}.txt"), &format!("yours-{i}"));
        d.file(&format!("to/trip/f {i}.txt"), &format!("there-{i}\u{1}\u{ff}"));
    }
    let (_sandbox, calls) = counted_gio(&d, &xdg);
    let (ok, failed, _, errors, entry, merged, _, _) = transfer(false, &[&album], &to, merged_policy(7, &[&album], &to, "replace"));
    assert!(errors.is_empty(), "every Replace lands: {errors:?}");
    assert_eq!((ok, failed, merged), (1, 0, 3));
    assert!(calls.borrow().is_empty(), "no gio process runs for a Replace on the home Trash's filesystem: {:?}", calls.borrow());
    for i in 0..3 {
        let there = to.join(format!("trip/f {i}.txt"));
        assert_eq!(text(&there), format!("yours-{i}"));
        assert_eq!(text(&xdg.join(format!("Trash/files/f {i}.txt"))), format!("there-{i}\u{1}\u{ff}"), "the old file sits in the home Trash");
        let path = info_path_line(&xdg.join(format!("Trash/info/f {i}.txt.trashinfo")));
        assert_eq!(path, crate::backend::hometrash::percent_encode(there.as_os_str().as_bytes()), "Path is the percent-encoded original");
        let uri = format!("trash:///f%20{i}.txt");
        assert!(entry.steps.iter().any(|s| matches!(s, Step::Trashed(e) if e.original == there && e.uri == uri)), "journaled as {uri}: {:?}", entry.steps);
    }
    let mut journal = Journal::new();
    journal.push(entry);
    assert_eq!(journal.undo().unwrap(), "merge");
    for i in 0..3 {
        assert_eq!(std::fs::read(to.join(format!("trip/f {i}.txt"))).unwrap(), format!("there-{i}\u{1}\u{ff}").into_bytes(), "undo puts the old file back byte-exact");
    }
    assert!(calls.borrow().is_empty(), "undo restores its own entries in-process too: {:?}", calls.borrow());
    assert_eq!(std::fs::read_dir(xdg.join("Trash/files")).unwrap().count(), 0, "the home Trash is empty again");
    assert_eq!(std::fs::read_dir(xdg.join("Trash/info")).unwrap().count(), 0, "and so are its records");
}

#[test]
fn a_trash_name_collision_takes_the_next_numbered_name() {
    let d = TestDir::new("merge-trash-collision");
    let xdg = d.dir("xdg");
    let to = d.dir("to");
    let album = d.dir("from/trip");
    d.dir("to/trip");
    d.file("from/trip/photo.png", "yours");
    let there = d.file("to/trip/photo.png", "there");
    d.dir("xdg/Trash/files");
    d.dir("xdg/Trash/info");
    d.file("xdg/Trash/files/photo.png", "earlier");
    d.file("xdg/Trash/info/photo.png.trashinfo", "[Trash Info]\nPath=/earlier\nDeletionDate=2026-01-01T00:00:00\n");
    let (_sandbox, calls) = counted_gio(&d, &xdg);
    let (ok, failed, _, errors, entry, _, _, _) = transfer(false, &[&album], &to, merged_policy(7, &[&album], &to, "replace"));
    assert!(errors.is_empty(), "a collision still replaces: {errors:?}");
    assert_eq!((ok, failed), (1, 0));
    assert!(calls.borrow().is_empty(), "{:?}", calls.borrow());
    assert_eq!(text(&xdg.join("Trash/files/photo.png")), "earlier", "the earlier entry is untouched");
    assert_eq!(text(&xdg.join("Trash/files/photo.2.png")), "there");
    assert!(info_path_line(&xdg.join("Trash/info/photo.2.png.trashinfo")).ends_with("/to/trip/photo.png"));
    assert!(entry.steps.iter().any(|s| matches!(s, Step::Trashed(e) if e.original == there && e.uri == "trash:///photo.2.png")), "{:?}", entry.steps);
}

#[test]
fn a_replace_on_another_filesystem_still_goes_through_gio() {
    let d = TestDir::new("merge-trash-otherfs");
    let xdg = d.dir("xdg");
    let to = d.dir("to");
    let album = d.dir("from/trip");
    d.dir("to/trip");
    d.file("from/trip/photo.png", "yours");
    let there = d.file("to/trip/photo.png", "there");
    let (_sandbox, calls) = counted_gio(&d, &xdg);
    test_set_other_filesystem(true);
    test_take_folder_syncs();
    let (ok, failed, _, errors, entry, _, _, _) = transfer(false, &[&album], &to, merged_policy(7, &[&album], &to, "replace"));
    assert!(errors.is_empty(), "{errors:?}");
    assert_eq!(test_take_folder_syncs(), (0, 0), "a batch with no rename syncs no folder");
    assert_eq!((ok, failed), (1, 0));
    assert_eq!(text(&there), "yours");
    let calls = calls.borrow();
    assert_eq!(calls.iter().filter(|c| c.starts_with("trash -- ")).count(), 1, "gio trashes the item: {calls:?}");
    assert_eq!(calls.iter().filter(|c| *c == "trash --list").count(), 2, "under today's before and after lists: {calls:?}");
    assert!(!xdg.join("Trash").exists(), "the home Trash is never touched in-process");
    assert!(entry.steps.iter().any(|s| matches!(s, Step::Trashed(e) if e.original == there && e.uri.starts_with("trash:///"))), "{:?}", entry.steps);
}

#[test]
fn an_item_gone_before_its_move_is_refused_and_nothing_moves() {
    let d = TestDir::new("merge-trash-gone");
    let xdg = d.dir("xdg");
    d.dir("to/trip");
    let gone = d.path().join("to/trip/f.txt");
    let (_sandbox, calls) = counted_gio(&d, &xdg);
    match rename_to_home(&gone, &mut std::collections::BTreeSet::new(), &mut None) {
        Some(Err(reason)) => assert_eq!(reason, crate::backend::collide::TRASH_REFUSED),
        other => panic!("a gone item is refused, not moved and not handed to gio: {other:?}"),
    }
    assert_eq!(std::fs::read_dir(xdg.join("Trash/info")).map(|i| i.count()).unwrap_or(0), 0, "no info file stays reserved");
    assert_eq!(std::fs::read_dir(xdg.join("Trash/files")).map(|i| i.count()).unwrap_or(0), 0, "nothing moved");
    let mut deferred = crate::backend::mergeapply::Deferred::begin();
    let mut steps = Vec::new();
    let r = crate::backend::mergeapply::replacing_deferred(&gone, &mut steps, &mut deferred, &std::sync::atomic::AtomicBool::new(false), |_| panic!("land never runs for a gone item"));
    assert_eq!(r.unwrap_err().msg, crate::backend::collide::TRASH_REFUSED);
    assert!(steps.is_empty() && calls.borrow().is_empty(), "nothing journaled, no gio: {steps:?} {:?}", calls.borrow());
}

#[test]
fn a_plain_multi_select_replace_takes_the_same_in_process_path() {
    use crate::backend::collide::tests::{asked, chosen};
    let d = TestDir::new("plain-trash-inprocess");
    let xdg = d.dir("xdg");
    let to = d.dir("to");
    d.dir("from");
    let a = d.file("from/a.txt", "yours-a");
    let b = d.file("from/b.txt", "yours-b");
    d.file("to/a.txt", "there-a");
    d.file("to/b.txt", "there-b");
    let (_sandbox, calls) = counted_gio(&d, &xdg);
    let (ok, failed, _, errors, _) = crate::backend::collide::tests::transfer(false, &[&a, &b], &to, chosen("replace", asked(1, &[&a, &b], &to), &to));
    assert!(errors.is_empty(), "{errors:?}");
    assert_eq!((ok, failed), (2, 0));
    assert!(calls.borrow().is_empty(), "{:?}", calls.borrow());
    assert_eq!((text(&xdg.join("Trash/files/a.txt")), text(&xdg.join("Trash/files/b.txt"))), ("there-a".to_string(), "there-b".to_string()));
}

#[test]
fn a_batch_of_renames_syncs_its_folders_once_at_the_end() {
    let d = TestDir::new("merge-trash-syncs");
    let xdg = d.dir("xdg");
    let to = d.dir("to");
    let album = d.dir("from/trip");
    d.dir("to/trip");
    for i in 0..3 {
        d.file(&format!("from/trip/f{i}.txt"), "yours");
        d.file(&format!("to/trip/f{i}.txt"), "there");
    }
    let (_sandbox, calls) = counted_gio(&d, &xdg);
    test_take_folder_syncs();
    let (ok, failed, _, errors, _, merged, _, _) = transfer(false, &[&album], &to, merged_policy(7, &[&album], &to, "replace"));
    assert!(errors.is_empty(), "{errors:?}");
    assert_eq!((ok, failed, merged), (1, 0, 3));
    assert!(calls.borrow().is_empty(), "{:?}", calls.borrow());
    assert_eq!(test_take_folder_syncs(), (1, 3), "one sync pass at settle over files/, info/ and the one parent folder, not one per item");
}

#[path = "mergeundo_tests.rs"]
mod undo;

#[path = "mergespeed_tests.rs"]
mod speed;
