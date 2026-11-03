// Undo puts an in-process home Trash entry back in-process, and a raw-byte name survives the round trip.
use super::*;
use std::ffi::OsStr;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::PermissionsExt;

// One loose file renamed into the sandbox home Trash, the way a Replace leaves it.
fn trashed(d: &TestDir, rel: &str) -> (PathBuf, trash::Entry) {
    let there = d.file(rel, "there");
    let entry = rename_to_home(&there, &mut std::collections::BTreeSet::new(), &mut None).expect("same filesystem").expect("renamed");
    (there, entry)
}

#[test]
fn a_mismatched_path_record_falls_back_to_gio() {
    let d = TestDir::new("undo-trash-mismatch");
    let xdg = d.dir("xdg");
    d.dir("to");
    let (_sandbox, calls) = counted_gio(&d, &xdg);
    let (there, entry) = trashed(&d, "to/f.txt");
    let elsewhere = d.path().join("to/elsewhere.txt");
    let record = format!("[Trash Info]\nPath={}\nDeletionDate=2026-10-09T00:00:00\n", crate::backend::hometrash::percent_encode(elsewhere.as_os_str().as_bytes()));
    std::fs::write(xdg.join("Trash/info/f.txt.trashinfo"), record).unwrap();
    trash::restore(&entry).unwrap();
    assert_eq!(*calls.borrow(), vec!["trash --restore trash:///f.txt".to_string()], "a record naming another path is gio's to restore");
    assert!(there.symlink_metadata().is_err() && text(&elsewhere) == "there", "gio put it where its record says");
}

#[test]
fn an_occupied_original_is_refused_and_the_entry_stays() {
    let d = TestDir::new("undo-trash-occupied");
    let xdg = d.dir("xdg");
    d.dir("to");
    let (_sandbox, calls) = counted_gio(&d, &xdg);
    let (there, entry) = trashed(&d, "to/f.txt");
    std::fs::write(&there, "newcomer").unwrap();
    let refused = trash::restore(&entry).unwrap_err();
    assert_eq!(refused.msg, crate::backend::homerestore::RESTORE_TAKEN);
    assert!(calls.borrow().is_empty(), "no gio: {:?}", calls.borrow());
    assert_eq!(text(&there), "newcomer", "the newcomer is never replaced");
    assert_eq!(text(&xdg.join("Trash/files/f.txt")), "there", "the entry stays in the Trash");
    assert!(xdg.join("Trash/info/f.txt.trashinfo").is_file(), "its record stays too");
}

#[test]
fn a_missing_parent_folder_is_recreated() {
    let d = TestDir::new("undo-trash-parent");
    let xdg = d.dir("xdg");
    d.dir("to/deep/sub");
    let (_sandbox, calls) = counted_gio(&d, &xdg);
    let (there, entry) = trashed(&d, "to/deep/sub/f.txt");
    std::fs::remove_dir(d.path().join("to/deep/sub")).unwrap();
    std::fs::remove_dir(d.path().join("to/deep")).unwrap();
    trash::restore(&entry).unwrap();
    assert!(calls.borrow().is_empty(), "no gio: {:?}", calls.borrow());
    assert_eq!(text(&there), "there", "the folders came back and so did the file");
    assert!(!xdg.join("Trash/info/f.txt.trashinfo").exists(), "the record is gone with the entry");
}

#[test]
fn a_non_utf8_name_round_trips_through_replace_and_undo() {
    let d = TestDir::new("merge-trash-rawname");
    let xdg = d.dir("xdg");
    let to = d.dir("to");
    let album = d.dir("from/trip");
    d.dir("to/trip");
    let name = OsStr::from_bytes(b"caf\xe9.txt");
    std::fs::write(album.join(name), "yours").unwrap();
    let there = to.join("trip").join(name);
    std::fs::write(&there, b"there\xff").unwrap();
    let (_sandbox, calls) = counted_gio(&d, &xdg);
    let (ok, failed, _, errors, entry, _, _, _) = transfer(false, &[&album], &to, merged_policy(7, &[&album], &to, "replace"));
    assert!(errors.is_empty(), "{errors:?}");
    assert_eq!((ok, failed), (1, 0));
    assert_eq!(std::fs::read(xdg.join("Trash/files").join(name)).unwrap(), b"there\xff", "the Trash keeps the raw name");
    let mut record = name.to_os_string();
    record.push(".trashinfo");
    let path = info_path_line(&xdg.join("Trash/info").join(&record));
    assert_eq!(path, crate::backend::hometrash::percent_encode(there.as_os_str().as_bytes()), "Path is the raw bytes encoded");
    assert!(path.ends_with("/caf%E9.txt"), "{path}");
    assert!(entry.steps.iter().any(|s| matches!(s, Step::Trashed(e) if e.original == there && e.uri == "trash:///caf%E9.txt")), "{:?}", entry.steps);
    let mut journal = Journal::new();
    journal.push(entry);
    journal.undo().unwrap();
    assert_eq!(std::fs::read(&there).unwrap(), b"there\xff", "undo puts it back under its own raw name");
    assert!(calls.borrow().is_empty(), "no gio: {:?}", calls.borrow());
    assert_eq!(std::fs::read_dir(xdg.join("Trash/info")).unwrap().count(), 0);
}

// Hands the Trash files folder its mode back, so the test root can be removed whatever the test did.
struct Writable(PathBuf);
impl Drop for Writable {
    fn drop(&mut self) {
        let _ = std::fs::set_permissions(&self.0, std::fs::Permissions::from_mode(0o700));
    }
}

#[test]
fn a_rename_that_fails_with_the_item_present_hands_it_to_gio() {
    let d = TestDir::new("merge-trash-renamefail");
    let xdg = d.dir("xdg");
    let to = d.dir("to");
    let album = d.dir("from/trip");
    d.dir("to/trip");
    d.file("from/trip/f.txt", "yours");
    let there = d.file("to/trip/f.txt", "there");
    let files = d.dir("xdg/Trash/files");
    d.dir("xdg/Trash/info");
    std::fs::set_permissions(&files, std::fs::Permissions::from_mode(0o500)).unwrap();
    let _writable = Writable(files);
    let (_sandbox, calls) = counted_gio(&d, &xdg);
    let (ok, failed, _, errors, _, _, _, _) = transfer(false, &[&album], &to, merged_policy(7, &[&album], &to, "replace"));
    assert!(errors.is_empty(), "the Replace lands through gio: {errors:?}");
    assert_eq!((ok, failed), (1, 0));
    assert_eq!(text(&there), "yours");
    assert_eq!(calls.borrow().iter().filter(|c| c.starts_with("trash -- ")).count(), 1, "gio trashed it: {:?}", calls.borrow());
    assert_eq!(std::fs::read_dir(xdg.join("Trash/info")).unwrap().count(), 0, "no reserved record is left behind");
}
