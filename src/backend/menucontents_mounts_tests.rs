// A folder holding a remote mount walks under the bulk deadline and shares iomount's stuck table.
use super::tests::{lines, tree};
use super::*;
use crate::json::{field_bool, field_usize as number};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

// The sandbox is local and holds an nfs mount point at `mnt`, as /run/user/1000 holds the gvfs mount.
fn nested_remote_body(root: &Path) -> String {
    format!("1 0 8:1 / / rw - ext4 /dev/a rw\n30 1 0:45 / {}/mnt rw - nfs n:/s rw\n", root.display())
}

#[test]
fn a_local_folder_holding_a_remote_mount_takes_the_deadline_path_and_one_without_stays_inline() {
    let (_sandbox, root) = tree("contents-nested-remote");
    for n in 0..16 { fs::write(root.join(format!("f{}", n)), "x").unwrap(); }
    fs::create_dir(root.join("mnt")).unwrap();
    let _pace = test_hold_pace(Duration::from_millis(25));
    let run = |body: String| {
        let _body = crate::backend::iomount::test_hold_body(body);
        let cancel = Cancellation::default().next();
        let (tx, rx) = std::sync::mpsc::channel();
        let items = [Selected::inspect(&root.to_string_lossy()).unwrap()];
        let line = r#"{"c":"menuaction","op":"contents","id":4}"#.to_string();
        let started = Instant::now();
        assert!(serve_with_deadline(&line, 4, &items, &tx, &cancel, Duration::from_millis(50)));
        (lines(&rx), started.elapsed())
    };
    let (sent, took) = run(nested_remote_body(&root));
    assert!(took < Duration::from_millis(300), "the deadline bounds a walk that reads a remote mount point: {:?}", took);
    assert!(field_bool(&sent[0], "done") && field_bool(&sent[0], "partial"), "{}", sent[0]);
    let (sent, took) = run("1 0 8:1 / / rw - ext4 /dev/a rw\n".to_string());
    assert!(took >= Duration::from_millis(300), "a folder with no remote mount walks inline, unbounded: {:?}", took);
    let last = sent.last().unwrap();
    assert!(field_bool(last, "done") && !field_bool(last, "partial"), "{}", last);
}

#[test]
fn a_mount_in_the_stuck_table_answers_the_floor_at_once_without_a_walk() {
    let (_sandbox, root) = tree("contents-stuck-answers");
    for n in 0..16 { fs::write(root.join(format!("f{}", n)), "x").unwrap(); }
    fs::create_dir(root.join("mnt")).unwrap();
    let _body = crate::backend::iomount::test_hold_body(nested_remote_body(&root));
    let _stuck = crate::backend::iomount::test_hold_stuck(root.join("mnt"));
    let _pace = test_hold_pace(Duration::from_millis(500));
    let cancel = Cancellation::default().next();
    let (tx, rx) = std::sync::mpsc::channel();
    let items = [Selected::inspect(&root.to_string_lossy()).unwrap()];
    let line = r#"{"c":"menuaction","op":"contents","id":4}"#.to_string();
    let started = Instant::now();
    assert!(serve_with_deadline(&line, 4, &items, &tx, &cancel, Duration::from_secs(5)));
    assert!(started.elapsed() < Duration::from_millis(200), "no walk and no wait: {:?}", started.elapsed());
    let sent = lines(&rx);
    assert_eq!(sent.len(), 1, "{:?}", sent);
    assert!(field_bool(&sent[0], "ok") && field_bool(&sent[0], "done") && field_bool(&sent[0], "partial"), "{}", sent[0]);
    assert_eq!((number(&sent[0], "items"), number(&sent[0], "bytes")), (Some(0), Some(0)), "{}", sent[0]);
}

// The sandbox is itself an nfs mount with another below it, so a walk anywhere in it is a remote walk.
fn remote_root_body(root: &Path) -> String {
    format!("1 0 8:1 / / rw - ext4 /dev/a rw\n30 1 0:45 / {0} rw - nfs n:/s rw\n31 30 0:46 / {0}/mnt rw - nfs n:/t rw\n", root.display())
}

fn contents_run(root: &Path, deadline: Duration) -> (Vec<String>, Duration) {
    let cancel = Cancellation::default().next();
    let (tx, rx) = std::sync::mpsc::channel();
    let items = [Selected::inspect(&root.to_string_lossy()).unwrap()];
    let line = r#"{"c":"menuaction","op":"contents","id":4}"#.to_string();
    let started = Instant::now();
    assert!(serve_with_deadline(&line, 4, &items, &tx, &cancel, deadline));
    (lines(&rx), started.elapsed())
}

#[test]
fn a_walk_that_keeps_counting_past_its_deadline_answers_partial_and_marks_no_mount() {
    let (_sandbox, root) = tree("contents-deadline-marks-nothing");
    for n in 0..40 { fs::write(root.join(format!("f{}", n)), "x").unwrap(); }
    let mounts = [root.clone(), root.join("mnt")];
    let _body = crate::backend::iomount::test_hold_body(remote_root_body(&root));
    let _pace = test_hold_pace(Duration::from_millis(20));
    let (first, _) = contents_run(&root, Duration::from_millis(300));
    assert!(field_bool(first.last().unwrap(), "done") && field_bool(first.last().unwrap(), "partial"), "{}", first.last().unwrap());
    assert!(crate::backend::walkmounts::stuck_among(&mounts).is_none(), "a walk still counting marks a mount stuck");
    let (again, took) = contents_run(&root, Duration::from_millis(300));
    assert!(took >= Duration::from_millis(250), "the repeat answers a cached zero instead of walking: {:?}", took);
    assert!(field_bool(again.last().unwrap(), "done") && field_bool(again.last().unwrap(), "partial"), "{}", again.last().unwrap());
}

// The watcher marks off the menu thread, so a test polls for a mark that may land after the reply.
fn marked_within(mounts: &[PathBuf], wait: Duration) -> Option<PathBuf> {
    let until = Instant::now() + wait;
    loop {
        if let Some(found) = crate::backend::walkmounts::stuck_among(mounts) { return Some(found); }
        if Instant::now() >= until { return None; }
        std::thread::sleep(Duration::from_millis(20));
    }
}

#[test]
fn a_walk_silent_past_the_call_bound_marks_the_mount_it_sits_in_so_a_repeat_skips_the_walk() {
    let (_sandbox, root) = tree("contents-stall-marks-its-mount");
    for n in 0..16 { fs::write(root.join(format!("f{}", n)), "x").unwrap(); }
    let _body = crate::backend::iomount::test_hold_body(remote_root_body(&root));
    let _pace = test_hold_pace(Duration::from_millis(1500));
    let _silence = test_hold_silence(Duration::from_millis(200));
    let (first, took) = contents_run(&root, Duration::from_millis(300));
    assert!(took < Duration::from_millis(1000), "the deadline ends the wait, not the stalled walk: {:?}", took);
    assert!(field_bool(&first[0], "done") && field_bool(&first[0], "partial"), "{}", first[0]);
    assert_eq!(marked_within(std::slice::from_ref(&root), Duration::from_secs(1)), Some(root.clone()), "the stalled walk's mount is marked");
    assert_eq!(crate::backend::walkmounts::stuck_among(&[root.join("mnt")]), None, "only the mount holding the walk is marked");
    let (again, took) = contents_run(&root, Duration::from_secs(5));
    assert!(took < Duration::from_millis(200), "a repeat on a marked mount starts no walk: {:?}", took);
    assert_eq!(again.len(), 1, "{:?}", again);
    assert!(field_bool(&again[0], "done") && field_bool(&again[0], "partial"), "{}", again[0]);
    assert_eq!((number(&again[0], "items"), number(&again[0], "bytes")), (Some(0), Some(0)), "{}", again[0]);
}

#[test]
fn a_slow_walk_that_answers_inside_the_call_bound_marks_no_mount_and_the_menu_replies_at_the_deadline() {
    let (_sandbox, root) = tree("contents-slow-walk-marks-nothing");
    for n in 0..8 { fs::write(root.join(format!("f{}", n)), "x").unwrap(); }
    let _body = crate::backend::iomount::test_hold_body(remote_root_body(&root));
    let _pace = test_hold_pace(Duration::from_millis(500));
    let _silence = test_hold_silence(Duration::from_secs(2));
    let (sent, took) = contents_run(&root, Duration::from_millis(300));
    assert!(took >= Duration::from_millis(250) && took < Duration::from_millis(450), "the menu still answers at the deadline: {:?}", took);
    assert!(field_bool(&sent[0], "done") && field_bool(&sent[0], "partial"), "{}", sent[0]);
    assert_eq!(marked_within(&[root.clone(), root.join("mnt")], Duration::from_millis(2500)), None, "a walk that answers inside the call bound marks a mount");
}

#[test]
fn a_stall_inside_a_nested_remote_mount_marks_that_mount_and_not_the_one_holding_the_walk() {
    let (_sandbox, root) = tree("contents-stall-in-nested-mount");
    fs::create_dir(root.join("mnt")).unwrap();
    let _body = crate::backend::iomount::test_hold_body(remote_root_body(&root));
    let _pace = test_hold_pace(Duration::from_millis(600));
    let _silence = test_hold_silence(Duration::from_millis(100));
    contents_run(&root, Duration::from_secs(2));
    assert_eq!(marked_within(&[root.join("mnt")], Duration::from_secs(1)), Some(root.join("mnt")), "the nested mount holds the hung stat");
    assert_eq!(crate::backend::walkmounts::stuck_among(std::slice::from_ref(&root)), None, "the healthy outer mount stays unmarked");
}

#[test]
fn a_stall_in_a_local_folder_that_holds_a_remote_mount_marks_nothing() {
    let (_sandbox, root) = tree("contents-local-stall-marks-nothing");
    for n in 0..16 { fs::write(root.join(format!("f{}", n)), "x").unwrap(); }
    fs::create_dir(root.join("mnt")).unwrap();
    let _body = crate::backend::iomount::test_hold_body(nested_remote_body(&root));
    let _pace = test_hold_pace(Duration::from_millis(1500));
    let _silence = test_hold_silence(Duration::from_millis(200));
    let (first, _) = contents_run(&root, Duration::from_millis(300));
    assert!(field_bool(&first[0], "done") && field_bool(&first[0], "partial"), "{}", first[0]);
    let held = [PathBuf::from("/"), root.clone(), root.join("mnt")];
    assert_eq!(marked_within(&held, Duration::from_secs(1)), None, "a stall in a local folder marks a mount");
}

#[test]
fn a_walk_hands_back_to_its_folder_after_each_crossing_so_a_later_stall_is_not_the_nested_mounts() {
    let (_sandbox, root) = tree("contents-hand-back");
    let mounts: std::collections::HashSet<PathBuf> = (0..6).map(|n| root.join(format!("mnt{}", n))).collect();
    for mount in &mounts { fs::create_dir(mount).unwrap(); }
    for n in 0..4 { fs::write(root.join(format!("f{}", n)), "x").unwrap(); }
    let at = std::cell::RefCell::new(root.clone());
    let stops = std::cell::RefCell::new(Vec::new());
    let stop = || { stops.borrow_mut().push(at.borrow().clone()); false };
    let entering = |folder: &Path| *at.borrow_mut() = folder.to_path_buf();
    let dev_of = |entry: &Path| mounts.contains(entry).then_some(u64::MAX);
    let progress = Progress { every: Duration::ZERO, report: &mut |_| {}, entering: Some(&entering) };
    walk_core(&root, &stop, Some(&dev_of), Some(progress));
    let stops = stops.into_inner();
    assert!(stops.len() >= 10, "every entry asks to stop, so the check is not vacuous: {}", stops.len());
    assert!(stops.iter().all(|folder| *folder == root), "a stop after a crossing sat in a nested mount: {:?}", stops);
}
