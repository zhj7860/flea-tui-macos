// What a merge pays per file: no info file synced one by one on a fixed disk, and no 256 KiB buffer for a small file.
use super::*;
use crate::backend::copyfile::test_take_buffers;
use crate::backend::hometrash::test_take_record_syncs;

// Clears the durability marks a test set, on the way out.
struct Marks;
impl Drop for Marks {
    fn drop(&mut self) {
        crate::backend::durable::test_reset();
    }
}

// Three replaced files merged into to/trip with the home Trash in the sandbox; answers the record syncs the merge made.
fn merge_three_replaces(d: &TestDir, durable: bool) -> usize {
    let xdg = d.dir("xdg");
    let to = d.dir("to");
    let album = d.dir("from/trip");
    d.dir("to/trip");
    for i in 0..3 {
        d.file(&format!("from/trip/f{i}.txt"), "yours");
        d.file(&format!("to/trip/f{i}.txt"), "there");
    }
    let (_sandbox, calls) = counted_gio(d, &xdg);
    if durable {
        crate::backend::durable::test_mark_durable(&to);
    }
    test_take_record_syncs();
    test_take_folder_syncs();
    let (ok, failed, _, errors, _, merged, _, _) = transfer(false, &[&album], &to, merged_policy(7, &[&album], &to, "replace"));
    assert!(errors.is_empty(), "{errors:?}");
    assert_eq!((ok, failed, merged), (1, 0, 3));
    assert!(calls.borrow().is_empty(), "{:?}", calls.borrow());
    assert_eq!(test_take_folder_syncs(), (1, 3), "the batch still syncs files/, info/ and the parent once at settle");
    for i in 0..3 {
        assert_eq!(text(&xdg.join(format!("Trash/files/f{i}.txt"))), "there", "the old file sits in the home Trash");
        assert!(info_path_line(&xdg.join(format!("Trash/info/f{i}.txt.trashinfo"))).ends_with(&format!("/f{i}.txt")), "its record names it");
    }
    test_take_record_syncs()
}

#[test]
fn a_fixed_disk_merge_syncs_no_trash_record_one_by_one() {
    let _marks = Marks;
    let d = TestDir::new("merge-speed-fixed");
    assert_eq!(merge_three_replaces(&d, false), 0, "a fixed disk's records are written as gio writes them, with no fsync per Replace");
}

#[test]
fn a_durable_drive_merge_still_syncs_each_record_before_its_item_moves() {
    let _marks = Marks;
    let d = TestDir::new("merge-speed-durable");
    assert_eq!(merge_three_replaces(&d, true), 3, "a drive Flea confirms keeps one record sync per Replace");
}

#[test]
fn a_merge_of_small_files_reads_each_through_a_buffer_its_own_size() {
    let d = TestDir::new("merge-speed-buffers");
    let to = d.dir("to");
    let album = d.dir("from/trip");
    d.dir("to/trip");
    for (name, len) in [("a.dat", 512), ("b.dat", 5000), ("c.dat", 8189), ("d.dat", 20 * 1024), ("e.dat", 300 * 1024)] {
        d.file(&format!("from/trip/{name}"), &"x".repeat(len));
    }
    test_take_buffers();
    let (ok, failed, _, errors, _, merged, _, _) = transfer(false, &[&album], &to, merged_policy(7, &[&album], &to, "replace"));
    assert!(errors.is_empty(), "{errors:?}");
    assert_eq!((ok, failed, merged), (1, 0, 5));
    let mut buffers = test_take_buffers();
    buffers.sort_unstable();
    assert_eq!(buffers, [8192, 8192, 8192, 20 * 1024, 256 * 1024], "a small file takes at least 8 KiB and at most its own size, a large one the 256 KiB chunk");
    for name in ["a.dat", "b.dat", "c.dat", "d.dat", "e.dat"] {
        assert_eq!(std::fs::read(to.join("trip").join(name)).unwrap(), std::fs::read(album.join(name)).unwrap(), "{name} lands byte-exact");
    }
}

#[path = "mergerefused_tests.rs"]
mod refused;
