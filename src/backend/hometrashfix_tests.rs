// Review fixes for the home Trash Replace path, and the pins that guard them.
use super::*;

// A files entry another tool left without its info file is not a free name: the Replace takes the next one.
#[test]
fn an_orphan_trash_files_entry_survives_a_replace_under_a_unique_name() {
    let d = TestDir::new("replace261-orphan");
    let xdg = d.dir("xdg");
    let dest = gvfs_dest(&d);
    d.dir("from");
    let photo = d.file("from/photo.png", "yours");
    let there = d.file("run/1000/gvfs/sftp:host=slot.test/home/gm/photo.png", "there");
    std::fs::create_dir_all(xdg.join("Trash/files")).unwrap();
    std::fs::create_dir_all(xdg.join("Trash/info")).unwrap();
    std::fs::write(xdg.join("Trash/files/photo.png"), "earlier").unwrap();
    let _root = test_trash_root(&xdg.join("Trash"));
    let _trash = gvfs_trash(&d, &xdg);
    let (ok, failed, _, errors, entry) = transfer(false, &[&photo], &dest, chosen("replace", asked(1, &[&photo], &dest), &dest));
    assert!(errors.is_empty(), "an orphan Trash entry must not fail the Replace: {errors:?}");
    assert_eq!((ok, failed), (1, 0));
    assert_eq!(text(&there), "yours");
    assert_eq!(std::fs::read_to_string(xdg.join("Trash/files/photo.png")).unwrap(), "earlier", "the orphan survives");
    use crate::backend::undo::Step;
    let uri = match &entry.steps[..] {
        [Step::Trashed(old), Step::Copied { .. }] => old.uri.clone(),
        other => panic!("the journal carries the colliding entry under its own URI: {other:?}"),
    };
    assert_ne!(uri, "trash:///photo.png", "the colliding entry takes a unique name");
    let name = decode(uri.strip_prefix(URI).expect("a trash URI names its file"));
    assert_eq!(std::fs::read_to_string(xdg.join("Trash/files").join(&name)).unwrap(), "there");
    assert!(xdg.join("Trash/info").join(format!("{name}.trashinfo")).is_file(), "the info file matches the unique name");
}

// A folder the remove only half takes keeps its complete Trash copy, and says exactly that.
#[test]
fn a_partly_removed_folder_keeps_its_trash_copy_and_says_so() {
    use crate::backend::hometrash::{set_test_trash_root, trash_to_home, HOME_TRASH_PARTIAL};
    let d = TestDir::new("replace261-half");
    let xdg = d.dir("xdg");
    let album = d.dir("orig/album");
    d.file("orig/album/ok.txt", "ok");
    let sub = d.dir("orig/album/sub");
    d.file("orig/album/sub/in.txt", "in");
    std::fs::set_permissions(&sub, std::fs::Permissions::from_mode(0o555)).unwrap();
    set_test_trash_root(Some(xdg.join("Trash")));
    let r = trash_to_home(&album, &std::sync::atomic::AtomicBool::new(false));
    set_test_trash_root(None);
    std::fs::set_permissions(&sub, std::fs::Permissions::from_mode(0o755)).unwrap();
    let msg = r.expect_err("the remove must fail on the locked child");
    assert_eq!(msg, HOME_TRASH_PARTIAL);
    assert!(!msg.contains("nothing was replaced"), "the partial remove never says nothing moved");
    assert!(xdg.join("Trash/files/album").exists(), "the complete copy stays in Trash");
    assert!(xdg.join("Trash/info/album.trashinfo").exists(), "with its info file, so it stays restorable");
    assert!(album.exists(), "the half-emptied source was not taken away");
}

// A fifo is recreated, never opened: syncing a tree that holds one must answer inside its bound.
#[test]
fn syncing_a_tree_holding_a_fifo_never_opens_it() {
    let d = TestDir::new("hometrash-fifo");
    let tree = d.dir("tree");
    d.file("tree/a.txt", "a");
    crate::backend::fifotest::mkfifo(&tree.join("pipe"));
    let root = tree.clone();
    crate::backend::fifotest::within("syncing a tree holding a fifo", move || super::super::sync_tree(&root))
        .expect("a fifo is skipped, not opened");
    assert!(tree.join("pipe").symlink_metadata().unwrap().file_type().is_fifo());
}

// The whole Replace of a folder holding a fifo lands through the home Trash inside the same bound.
#[test]
fn a_replaced_folder_holding_a_fifo_lands_without_hanging() {
    let d = TestDir::new("replace261-fifo");
    let ((ok, failed, _, errors, _), d) = crate::backend::fifotest::within("a Replace holding a fifo", move || {
        let xdg = d.dir("xdg");
        let dest = gvfs_dest(&d);
        d.dir("from/album");
        d.file("from/album/new.txt", "new");
        let album = d.dir("run/1000/gvfs/sftp:host=slot.test/home/gm/album");
        d.file("run/1000/gvfs/sftp:host=slot.test/home/gm/album/old.txt", "old");
        crate::backend::fifotest::mkfifo(&album.join("pipe"));
        let src = d.path().join("from/album");
        let _trash_root = test_trash_root(&xdg.join("Trash"));
        let _trash = gvfs_trash(&d, &xdg);
        let out = transfer(false, &[&src], &dest, chosen("replace", asked(1, &[&src], &dest), &dest));
        (out, d)
    });
    assert!(errors.is_empty(), "a fifo in the replaced folder must not fail it: {errors:?}");
    assert_eq!((ok, failed), (1, 0));
    assert_eq!(std::fs::read_to_string(d.join("run/1000/gvfs/sftp:host=slot.test/home/gm/album/new.txt")).unwrap(), "new");
    assert_eq!(std::fs::read_to_string(d.join("xdg/Trash/files/album/old.txt")).unwrap(), "old");
    assert!(d.join("xdg/Trash/files/album/pipe").symlink_metadata().unwrap().file_type().is_fifo(), "the fifo rides along as a fifo");
}

// An out-of-space shaped copy failure refuses cleanly: no partial, no orphan info, the original stands.
#[test]
fn an_out_of_space_copy_leaves_no_partial_and_reports_from_the_trash_root() {
    use crate::backend::copyfile::test_set_precheck;
    let d = TestDir::new("replace261-nospace");
    let xdg = d.dir("xdg");
    let dest = gvfs_dest(&d);
    d.dir("from");
    let photo = d.file("from/photo.png", "yours");
    let there = d.file("run/1000/gvfs/sftp:host=slot.test/home/gm/photo.png", "there");
    let _root = test_trash_root(&xdg.join("Trash"));
    let _trash = gvfs_trash(&d, &xdg);
    test_set_precheck(Some(0), Some(1), None);
    crate::backend::hometrash::test_set_free(Some((xdg.join("Trash").join("files"), 0)));
    let (ok, failed, _, errors, entry) = transfer(false, &[&photo], &dest, chosen("replace", asked(1, &[&photo], &dest), &dest));
    test_set_precheck(None, None, None);
    crate::backend::hometrash::test_set_free(None);
    assert_eq!((ok, failed), (0, 1));
    assert!(entry.steps.is_empty(), "a refused home Trash copy journals nothing: {:?}", entry.steps);
    assert_eq!(text(&there), "there", "the original never moved");
    assert_eq!(text(&photo), "yours");
    assert!(std::fs::read_dir(xdg.join("Trash/files")).map(|mut i| i.next().is_none()).unwrap_or(true), "no partial copy stays behind");
    assert!(std::fs::read_dir(xdg.join("Trash/info")).map(|mut i| i.next().is_none()).unwrap_or(true), "no orphan info file stays behind");
    assert_eq!(errors, vec![crate::backend::hometrash::HOME_TRASH_FULL.to_string()], "the sentence follows the Trash root's room: {errors:?}");
}

// A home Trash Replace names its own entry, so a gio that cannot list never refuses it and the batch lists nothing.
#[test]
fn a_home_trash_replace_needs_no_gio_list() {
    let d = TestDir::new("replace261-nolist");
    let xdg = d.dir("xdg");
    let dest = gvfs_dest(&d);
    d.dir("from");
    let photo = d.file("from/photo.png", "yours");
    let there = d.file("run/1000/gvfs/sftp:host=slot.test/home/gm/photo.png", "there");
    let _root = test_trash_root(&xdg.join("Trash"));
    let can = d.dir("can");
    let held = xdg.clone();
    trash::STAND_IN.with(|slot| *slot.borrow_mut() = Some(Rc::new(move |args: &[&str]| {
        if matches!(args, ["trash", "--list"]) {
            return None;
        }
        Some(gio_like(&can, &held, args))
    })));
    let _trash = StandIn;
    trash::test_reset_list_calls();
    let (ok, failed, _, errors, entry) = transfer(false, &[&photo], &dest, chosen("replace", asked(1, &[&photo], &dest), &dest));
    assert!(errors.is_empty(), "a home Trash Replace never waits on a gio list: {errors:?}");
    assert_eq!((ok, failed), (1, 0));
    assert_eq!(text(&there), "yours");
    assert_eq!(trash::test_list_calls(), 0, "the home Trash names its own entry, so nothing lists");
    use crate::backend::undo::Step;
    assert!(matches!(&entry.steps[..], [Step::Trashed(old), Step::Copied { .. }] if old.uri.starts_with(URI)), "{:?}", entry.steps);
}

// A Replace cancelled before its trash step journals nothing and leaves the old item and the Trash untouched (the loop, not the early return, may stop it).
#[test]
fn a_cancelled_replace_starts_no_home_trash_copy() {
    let d = TestDir::new("replace261-cancel");
    let xdg = d.dir("xdg");
    let dest = gvfs_dest(&d);
    d.dir("from");
    let photo = d.file("from/photo.png", "yours");
    let there = d.file("run/1000/gvfs/sftp:host=slot.test/home/gm/photo.png", "there");
    let _root = test_trash_root(&xdg.join("Trash"));
    let _trash = gvfs_trash(&d, &xdg);
    let _cancel_at = crate::backend::opsreq::CancelAtGuard::hold(0);
    crate::backend::hometrash::test_take_record_syncs();
    let (_, _, _, errors, entry) = transfer(false, &[&photo], &dest, chosen("replace", asked(1, &[&photo], &dest), &dest));
    assert_eq!(crate::backend::hometrash::test_take_record_syncs(), 0, "the old item was copied into the home Trash after the cancel");
    assert_eq!(errors, vec!["cancelled".to_string()]);
    assert_eq!(text(&there), "there", "the old item stays in place");
    assert!(entry.steps.is_empty(), "a cancelled Replace journals nothing: {:?}", entry.steps);
    assert!(std::fs::read_dir(xdg.join("Trash/files")).map(|mut i| i.next().is_none()).unwrap_or(true), "no Trash copy stays behind");
}

// A cancel already set when trash_to_home starts costs no Trash entry: the early return stops before the Trash folders exist.
#[test]
fn a_cancel_set_before_trash_to_home_makes_no_trash_entry() {
    use crate::backend::hometrash::trash_to_home;
    let d = TestDir::new("hometrash-cancel-early");
    let xdg = d.dir("xdg");
    d.dir("orig");
    let old = d.file("orig/photo.png", "there");
    let _root = test_trash_root(&xdg.join("Trash"));
    crate::backend::hometrash::test_take_record_syncs();
    let r = trash_to_home(&old, &std::sync::atomic::AtomicBool::new(true));
    assert_eq!(r.expect_err("a cancelled trash step answers an error"), crate::backend::collide::CANCELLED);
    assert_eq!(crate::backend::hometrash::test_take_record_syncs(), 0, "nothing was recorded for the Trash");
    assert!(!xdg.join("Trash").exists(), "the Trash folders were not even made");
    assert_eq!(text(&old), "there", "the old item stays in place");
}

// A cancel that lands mid-copy in place_copy answers the cancelled word and leaves no partial copy and no info file.
#[test]
fn a_cancel_landing_mid_copy_returns_the_cancelled_word_and_leaves_no_trace() {
    use crate::backend::copyfile::test_cancel_after_write;
    use crate::backend::hometrash::trash_to_home;
    let d = TestDir::new("hometrash-cancel-mid");
    let xdg = d.dir("xdg");
    d.dir("orig");
    let old = d.file("orig/photo.png", "there");
    let _root = test_trash_root(&xdg.join("Trash"));
    let cancel = std::sync::atomic::AtomicBool::new(false);
    test_cancel_after_write(true);
    let r = trash_to_home(&old, &cancel);
    test_cancel_after_write(false);
    assert!(cancel.load(std::sync::atomic::Ordering::Relaxed), "the copy raised the caller's own flag");
    assert_eq!(r.expect_err("a cancelled copy answers an error"), crate::backend::collide::CANCELLED);
    assert!(std::fs::read_dir(xdg.join("Trash/files")).map(|mut i| i.next().is_none()).unwrap_or(true), "no partial copy stays behind");
    assert!(std::fs::read_dir(xdg.join("Trash/info")).map(|mut i| i.next().is_none()).unwrap_or(true), "no info file stays behind");
    assert_eq!(text(&old), "there", "the old item stays in place");
}
