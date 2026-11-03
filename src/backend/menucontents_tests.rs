use super::*;
use crate::backend::dirsize::{walk_core, walk_while, DevLookup};
use crate::backend::testdir::TestDir;
use crate::json::{field_bool, field_usize as number};
use std::cell::Cell;
use std::fs;
use std::os::unix::fs::{symlink, MetadataExt};
use std::path::Path;
use std::time::{Duration, Instant};

pub(super) fn tree(tag: &str) -> (TestDir, PathBuf) {
    let sandbox = TestDir::new(tag);
    let root = sandbox.dir("tree");
    (sandbox, root)
}
fn size_of(path: &Path) -> u64 { fs::symlink_metadata(path).unwrap().size() }
// A file, a folder and two files in it: four entries below the start.
fn nested(root: &Path) {
    fs::write(root.join("a.txt"), "abc").unwrap();
    fs::create_dir(root.join("sub")).unwrap();
    fs::write(root.join("sub/b.txt"), "de").unwrap();
    fs::write(root.join("sub/c.txt"), "f").unwrap();
}
fn nested_bytes(root: &Path) -> u64 {
    ["", "a.txt", "sub", "sub/b.txt", "sub/c.txt"].iter().map(|name| size_of(&root.join(name))).sum()
}
pub(super) fn lines(rx: &std::sync::mpsc::Receiver<OpMsg>) -> Vec<String> {
    let mut out = Vec::new();
    while let Ok(OpMsg::Meta { line }) = rx.try_recv() { out.push(line); }
    out
}
// The snapshot holds `id`; the request line names `asked`.
fn contents(path: &Path, id: usize, asked: usize, cancel: &Cancellation) -> Vec<String> {
    let (tx, rx) = std::sync::mpsc::channel();
    let items = [Selected::inspect(&path.to_string_lossy()).unwrap()];
    assert!(serve(&format!(r#"{{"c":"menuaction","op":"contents","id":{}}}"#, asked), id, &items, &tx, cancel));
    lines(&rx)
}

#[test]
fn the_walk_counts_the_entries_below_the_folder_and_not_the_folder() {
    let (_sandbox, root) = tree("contents-count");
    assert_eq!(walk_counted(&root, &|| false, None).items, 0, "an empty folder holds nothing");
    nested(&root);
    let tally = walk_counted(&root, &|| false, None);
    assert_eq!(tally.items, 4, "two files, a folder and the file in it, not the start itself");
    assert!(!tally.partial);
}

#[test]
fn a_nested_mount_and_a_symlink_count_once_and_are_not_entered() {
    let (_sandbox, root) = tree("contents-mount");
    let (_target_sandbox, target) = tree("contents-link-target");
    fs::write(target.join("far.bin"), vec![0u8; 5_000]).unwrap();
    fs::create_dir(root.join("keep")).unwrap();
    fs::write(root.join("keep/in.txt"), "12345678").unwrap();
    fs::create_dir(root.join("other")).unwrap();
    fs::write(root.join("other/out.txt"), "12345678").unwrap();
    symlink(&target, root.join("link")).unwrap();
    let start_dev = fs::symlink_metadata(&root).unwrap().dev();
    let other = root.join("other");
    let dev_of = |p: &Path| (p == other).then_some(start_dev.wrapping_add(1));
    let lookup: DevLookup<'_> = Some(&dev_of);
    let tally = walk_core(&root, &|| false, lookup, None);
    assert_eq!(tally.items, 4, "keep, keep/in.txt, the mount's own entry and the link's own entry");
    let want = size_of(&root) + size_of(&root.join("keep")) + size_of(&root.join("keep/in.txt")) + size_of(&other) + size_of(&root.join("link"));
    assert_eq!(tally.bytes, want, "neither the mount's payload nor the link's target adds bytes");
}

#[test]
fn the_listing_numbers_are_the_counted_walks_numbers() {
    let (_sandbox, root) = tree("contents-listing");
    nested(&root);
    let counted = walk_counted(&root, &|| false, None);
    let sized = walk_while(&root, &|| false);
    assert_eq!((counted.bytes, counted.partial), (sized.bytes, sized.partial));
    assert_eq!(counted.bytes, nested_bytes(&root));
}

#[test]
fn progress_arrives_on_the_cadence_and_never_per_entry() {
    let (_sandbox, root) = tree("contents-cadence");
    for n in 0..16 { fs::write(root.join(format!("f{}", n)), "x").unwrap(); }
    // A slow stop makes the walk last well past the cadence without any assertion on how long it took.
    let slow = || { std::thread::sleep(Duration::from_millis(25)); false };
    let seen: std::cell::RefCell<Vec<(Instant, u64)>> = Default::default();
    let tally = walk_counted(&root, &slow, Some(Progress { every: PROGRESS_EVERY, report: &mut |t| seen.borrow_mut().push((Instant::now(), t.items)), entering: None }));
    let seen = seen.into_inner();
    assert!(!seen.is_empty(), "a walk past the cadence reports");
    assert!((seen.len() as u64) < tally.items, "{} reports for {} entries is per entry", seen.len(), tally.items);
    for pair in seen.windows(2) {
        assert!(pair[1].0 - pair[0].0 >= PROGRESS_EVERY, "two reports closer than the cadence");
        assert!(pair[1].1 > pair[0].1, "each report carries more than the last");
    }
}

#[test]
fn a_walk_that_ends_inside_the_cadence_sends_only_its_final_line() {
    let (_sandbox, root) = tree("contents-final");
    nested(&root);
    let sent = contents(&root, 4, 4, &Cancellation::default().next());
    assert_eq!(sent.len(), 1, "{:?}", sent);
    assert!(field_bool(&sent[0], "ok") && field_bool(&sent[0], "done") && !field_bool(&sent[0], "partial"));
    assert_eq!(number(&sent[0], "items"), Some(4));
    assert_eq!(number(&sent[0], "bytes"), Some(nested_bytes(&root) as usize));
}

#[test]
fn a_cancelled_walk_stops_at_once_and_never_says_done() {
    let (_sandbox, root) = tree("contents-cancel");
    nested(&root);
    let cancel = Cancellation::default().next();
    let _ = cancel.next();
    let sent = contents(&root, 4, 4, &cancel);
    assert_eq!(sent.len(), 1);
    assert!(field_bool(&sent[0], "cancelled") && !field_bool(&sent[0], "done"), "{}", sent[0]);
    assert_eq!(number(&sent[0], "items"), Some(0), "no directory was read after the cancel");
    // Mid walk: the stop fires from inside a report, and nothing is counted after it.
    let live = Cancellation::default().next();
    let reported = Cell::new(0u64);
    let after_stop = Cell::new(0u32);
    let stop = || live.check().is_err();
    let tally = walk_counted(&root, &stop, Some(Progress { every: Duration::ZERO, report: &mut |t| {
        if live.check().is_err() { after_stop.set(after_stop.get() + 1); }
        else if t.items >= 1 { let _ = live.next(); }
        reported.set(t.items);
    }, entering: None }));
    assert!(tally.partial && tally.items < 4, "the walk is a floor of what it counted");
    assert_eq!(after_stop.get(), 0, "nothing was counted after the stop fired");
    assert_eq!(tally.items, reported.get(), "the last report carries the final count");
}

// The stand-in mount table the iomount tests use: the sandbox reads as a remote nfs mount.
fn remote_body(root: &Path) -> String {
    format!("1 0 8:1 / / rw - ext4 /dev/a rw\n30 1 0:45 / {} rw - nfs n:/s rw\n", root.display())
}

#[test]
fn a_remote_walk_past_its_deadline_answers_the_floor_and_stops() {
    let (_sandbox, root) = tree("contents-remote-deadline");
    for n in 0..16 { fs::write(root.join(format!("f{}", n)), "x").unwrap(); }
    let _body = crate::backend::iomount::test_hold_body(remote_body(&root));
    assert!(crate::backend::iomount::is_remote(&root, &crate::backend::iomount::mount_body()), "the stand-in mount reads as remote");
    let _pace = test_hold_pace(Duration::from_millis(25));
    let cancel = Cancellation::default().next();
    let (tx, rx) = std::sync::mpsc::channel();
    let items = [Selected::inspect(&root.to_string_lossy()).unwrap()];
    let line = r#"{"c":"menuaction","op":"contents","id":4}"#.to_string();
    let started = Instant::now();
    assert!(serve_with_deadline(&line, 4, &items, &tx, &cancel, Duration::from_millis(50)));
    assert!(started.elapsed() < Duration::from_millis(300), "the menu worker never waits out the walk: {:?}", started.elapsed());
    let sent = lines(&rx);
    assert_eq!(sent.len(), 1, "{:?}", sent);
    assert!(field_bool(&sent[0], "done") && field_bool(&sent[0], "partial"), "{}", sent[0]);
    assert!(!sent[0].contains("cancelled"), "a deadline is a floor, never a cancel: {}", sent[0]);
    assert!(number(&sent[0], "items").is_some_and(|n| n < 16), "the floor stops short of the whole tree: {}", sent[0]);
}

#[test]
fn a_cancel_during_a_remote_walk_answers_the_floor_at_once() {
    let (_sandbox, root) = tree("contents-remote-cancel");
    for n in 0..40 { fs::write(root.join(format!("f{}", n)), "x").unwrap(); }
    let _body = crate::backend::iomount::test_hold_body(remote_body(&root));
    let _pace = test_hold_pace(Duration::from_millis(500));
    let base = Cancellation::default();
    let cancel = base.next();
    let (tx, rx) = std::sync::mpsc::channel();
    let items = [Selected::inspect(&root.to_string_lossy()).unwrap()];
    let line = r#"{"c":"menuaction","op":"contents","id":4}"#.to_string();
    let newer = std::thread::spawn(move || { std::thread::sleep(Duration::from_millis(80)); let _ = base.next(); });
    let started = Instant::now();
    assert!(serve_with_deadline(&line, 4, &items, &tx, &cancel, Duration::from_secs(5)));
    newer.join().unwrap();
    assert!(started.elapsed() < Duration::from_millis(300), "the cancel ends the wait, not the walk's next stop check or the deadline: {:?}", started.elapsed());
    let sent = lines(&rx);
    assert_eq!(sent.len(), 1, "{:?}", sent);
    assert!(field_bool(&sent[0], "cancelled") && !field_bool(&sent[0], "done"), "{}", sent[0]);
}

#[test]
fn a_remote_walk_inside_its_deadline_answers_whole() {
    let (_sandbox, root) = tree("contents-remote-whole");
    nested(&root);
    let _body = crate::backend::iomount::test_hold_body(remote_body(&root));
    let cancel = Cancellation::default().next();
    let (tx, rx) = std::sync::mpsc::channel();
    let items = [Selected::inspect(&root.to_string_lossy()).unwrap()];
    let line = r#"{"c":"menuaction","op":"contents","id":4}"#.to_string();
    assert!(serve_with_deadline(&line, 4, &items, &tx, &cancel, Duration::from_secs(5)));
    let sent = lines(&rx);
    assert_eq!(sent.len(), 1, "{:?}", sent);
    assert!(field_bool(&sent[0], "ok") && field_bool(&sent[0], "done") && !field_bool(&sent[0], "partial"), "{}", sent[0]);
    assert_eq!(number(&sent[0], "items"), Some(4));
    assert_eq!(number(&sent[0], "bytes"), Some(nested_bytes(&root) as usize));
}

#[test]
fn a_failed_progress_send_stops_the_walk() {
    let (_sandbox, root) = tree("contents-closed-receiver");
    for n in 0..16 { fs::write(root.join(format!("f{}", n)), "x").unwrap(); }
    let _pace = test_hold_pace(Duration::from_millis(25));
    let cancel = Cancellation::default().next();
    let (tx, rx) = std::sync::mpsc::channel();
    drop(rx);
    let items = [Selected::inspect(&root.to_string_lossy()).unwrap()];
    let line = r#"{"c":"menuaction","op":"contents","id":4}"#.to_string();
    let started = Instant::now();
    assert!(!serve(&line, 4, &items, &tx, &cancel), "a gone receiver ends the worker with it");
    assert!(started.elapsed() < Duration::from_millis(300), "the walk stops at the failed send instead of counting on: {:?}", started.elapsed());
}

#[test]
fn only_a_captured_folder_has_contents() {
    let (_sandbox, root) = tree("contents-refuse");
    nested(&root);
    symlink(&root, root.join("link")).unwrap();
    let cancel = Cancellation::default().next();
    for (path, id, asked) in [(root.join("a.txt"), 4, 4), (root.join("link"), 4, 4), (root.clone(), 4, 5), (root.clone(), 0, 0)] {
        let sent = contents(&path, id, asked, &cancel);
        assert!(sent.len() == 1 && !field_bool(&sent[0], "ok"), "{} answers {:?}", path.display(), sent);
    }
}
