// A trash whose settle lists are cut short still undoes: the journal step carries the time and the URIs it knew.
use super::tests::{ok_output, StandIn};
use super::*;
use std::cell::RefCell;
use std::os::unix::process::ExitStatusExt;
use std::rc::Rc;

// One item the stand-in Trash holds: where it was, the date gio would stamp, and where its bytes sit.
struct Held {
    uri: String,
    original: PathBuf,
    date: String,
    kept: PathBuf,
}

// Stands in for gio's Trash on disk: trash moves into `can`, list prints it, info answers a date, restore moves back, and the list calls numbered in `cut` exit 1.
fn fake_gio(can: PathBuf, held: Rc<RefCell<Vec<Held>>>, cut: &'static [usize]) -> StandInFn {
    let lists = std::cell::Cell::new(0usize);
    let answer = |code: i32, stdout: String| {
        Some(std::process::Output { status: std::process::ExitStatus::from_raw(code << 8), stdout: stdout.into_bytes(), stderr: Vec::new() })
    };
    Rc::new(move |args: &[&str]| match args {
        ["trash", "--list"] => {
            let call = lists.get();
            lists.set(call + 1);
            if cut.contains(&call) {
                return answer(1, String::new());
            }
            answer(0, held.borrow().iter().map(|h| format!("{}\t{}\n", h.uri, h.original.display())).collect())
        }
        ["trash", "--restore", uri] => {
            let mut all = held.borrow_mut();
            let Some(at) = all.iter().position(|h| h.uri == *uri) else { return answer(1, String::new()) };
            if all[at].original.symlink_metadata().is_ok() || std::fs::rename(&all[at].kept, &all[at].original).is_err() {
                return answer(1, String::new());
            }
            all.remove(at);
            answer(0, String::new())
        }
        ["trash", "--", paths @ ..] => {
            for path in paths {
                let (path, mut all) = (PathBuf::from(path), held.borrow_mut());
                let name = path.file_name().unwrap().to_string_lossy().to_string();
                let taken = all.iter().filter(|h| h.original.file_name() == path.file_name()).count();
                let uri = if taken == 0 { format!("trash:///{name}") } else { format!("trash:///{name}.{}", taken + 1) };
                let kept = can.join(format!("{}-{name}", all.len()));
                std::fs::rename(&path, &kept).unwrap();
                all.push(Held { uri, original: path, date: crate::backend::hometrash::deletion_date_local(), kept });
            }
            answer(0, String::new())
        }
        ["info", _, uri] => {
            let all = held.borrow();
            let Some(h) = all.iter().find(|h| h.uri == *uri) else { return answer(1, String::new()) };
            answer(0, format!("attributes:\n  trash::deletion-date: {}\n", h.date))
        }
        _ => Some(ok_output()),
    })
}

fn journaled_then_decoded(entry: &Entry) -> Entry {
    let crate::jsondoc::Json::Obj(pairs) = encode_step(entry) else { panic!("a Trashed step encodes as an object") };
    let Some(crate::backend::undo::Step::Trashed(back)) = decode_step(&pairs) else { panic!("and decodes as a Trashed step") };
    back
}

#[test]
fn an_item_trashed_while_the_settle_list_after_fails_comes_back_at_undo() {
    let d = crate::backend::testdir::TestDir::new("trash-undo-after-cut");
    let (can, file) = (d.dir("can"), d.file("a.txt", "kept bytes"));
    let held = Rc::new(RefCell::new(Vec::new()));
    let _stand = StandIn::hold(fake_gio(can, Rc::clone(&held), &[1]));
    let (ok, failed, _) = trash_checked(std::slice::from_ref(&file), None).expect("a cut list is not an error");
    assert_eq!((ok.len(), failed), (1, 0));
    assert!(!file.exists(), "the trash took it");
    restore(&journaled_then_decoded(&ok[0])).expect("undo restores the item after the journal round trip");
    assert_eq!(std::fs::read_to_string(&file).unwrap(), "kept bytes", "back under its name with its content");
}

#[test]
fn an_item_trashed_while_the_settle_list_before_fails_comes_back_at_undo() {
    let d = crate::backend::testdir::TestDir::new("trash-undo-before-cut");
    let (can, file) = (d.dir("can"), d.file("b.txt", "other bytes"));
    let held = Rc::new(RefCell::new(Vec::new()));
    let _stand = StandIn::hold(fake_gio(can, Rc::clone(&held), &[0]));
    let (ok, failed, _) = trash_checked(std::slice::from_ref(&file), None).expect("a cut list is not an error");
    assert_eq!((ok.len(), failed), (1, 0));
    restore(&journaled_then_decoded(&ok[0])).expect("undo restores the item after the journal round trip");
    assert_eq!(std::fs::read_to_string(&file).unwrap(), "other bytes");
}

#[test]
fn an_older_item_from_the_same_path_stays_in_the_trash_when_the_new_one_comes_back() {
    let d = crate::backend::testdir::TestDir::new("trash-undo-older");
    let (can, file) = (d.dir("can"), d.file("a.txt", "new bytes"));
    let older = can.join("older-a.txt");
    std::fs::write(&older, "old bytes").unwrap();
    let held = Rc::new(RefCell::new(vec![Held { uri: "trash:///a.txt".to_string(), original: file.clone(), date: "2020-01-01T00:00:00".to_string(), kept: older.clone() }]));
    let _stand = StandIn::hold(fake_gio(can, Rc::clone(&held), &[1]));
    let (ok, _, _) = trash_checked(std::slice::from_ref(&file), None).expect("a cut list is not an error");
    restore(&journaled_then_decoded(&ok[0])).expect("only the new item is a candidate");
    assert_eq!(std::fs::read_to_string(&file).unwrap(), "new bytes", "the item this step trashed, not the older one");
    assert_eq!(held.borrow().len(), 1, "the older item is still held");
    assert_eq!(held.borrow()[0].uri, "trash:///a.txt");
}

// One item the Trash holds under a date, restored from a step stamped `stamp`: whether undo takes it.
fn restores_at(stamp: &str, date: &str) -> bool {
    let d = crate::backend::testdir::TestDir::new("trash-undo-window");
    let (can, file) = (d.dir("can"), d.file("w.txt", "window bytes"));
    let kept = can.join("w.txt");
    std::fs::rename(&file, &kept).unwrap();
    let held = Rc::new(RefCell::new(vec![Held { uri: "trash:///w.txt".to_string(), original: file.clone(), date: date.to_string(), kept }]));
    let _stand = StandIn::hold(fake_gio(can, held, &[]));
    restore(&Entry::unresolved(file.clone(), Vec::new(), stamp.to_string())).is_ok()
}

#[test]
fn undo_takes_an_item_deleted_anywhere_inside_the_chunk_that_began_at_the_stamp() {
    let stamp = "2026-10-11T12:00:00";
    assert!(restores_at(stamp, "2026-10-11T12:00:00"), "deleted as the chunk began");
    assert!(restores_at(stamp, "2026-10-11T12:00:11"), "deleted as the longest chunk ended");
    assert!(restores_at(stamp, "2026-10-11T12:00:16"), "and the window past it");
    assert!(!restores_at(stamp, "2026-10-11T12:00:17"), "a later item from the same place is not this step's");
    assert!(!restores_at(stamp, "2026-10-11T11:59:54"), "nor one deleted before the chunk began");
}

#[test]
fn a_chunk_is_stamped_before_gio_starts_trashing_it() {
    let d = crate::backend::testdir::TestDir::new("trash-undo-stamp");
    let (can, file) = (d.dir("can"), d.file("s.txt", "stamp bytes"));
    let held = Rc::new(RefCell::new(Vec::new()));
    let inner = fake_gio(can, Rc::clone(&held), &[1]);
    // The stand-in trashes as gio would, then lets the clock move on a whole second before it returns.
    let slow: StandInFn = Rc::new(move |args: &[&str]| {
        let out = inner(args);
        if args.first() == Some(&"trash") && args.get(1) == Some(&"--") {
            let began = crate::backend::hometrash::deletion_date_local();
            while crate::backend::hometrash::deletion_date_local() == began { std::thread::yield_now(); }
        }
        out
    });
    let _stand = StandIn::hold(slow);
    let (ok, _, _) = trash_checked(std::slice::from_ref(&file), None).expect("a cut list is not an error");
    let date = held.borrow()[0].date.clone();
    assert!(ok[0].trashed_at <= date, "the stamp {} is not after the item's deletion date {}", ok[0].trashed_at, date);
}

#[test]
fn a_replace_is_stamped_before_gio_starts_trashing_it() {
    let d = crate::backend::testdir::TestDir::new("trash-undo-replace-stamp");
    let (can, file) = (d.dir("can"), d.file("r.txt", "replace bytes"));
    let held = Rc::new(RefCell::new(Vec::new()));
    // The settle's two lists are cut, so the step keeps the time it was stamped with.
    let inner = fake_gio(can, Rc::clone(&held), &[1, 2]);
    let slow: StandInFn = Rc::new(move |args: &[&str]| {
        let out = inner(args);
        if args.first() == Some(&"trash") && args.get(1) == Some(&"--") {
            let began = crate::backend::hometrash::deletion_date_local();
            while crate::backend::hometrash::deletion_date_local() == began { std::thread::yield_now(); }
        }
        out
    });
    let _stand = StandIn::hold(slow);
    let mut deferred = crate::backend::mergeapply::Deferred::begin();
    let mut steps = Vec::new();
    let landed = crate::backend::mergeapply::replacing_deferred(&file, &mut steps, &mut deferred, &std::sync::atomic::AtomicBool::new(false), |_| Ok(()));
    assert!(landed.is_ok(), "the Replace lands: {landed:?}");
    deferred.settle(&mut steps);
    let [crate::backend::undo::Step::Trashed(entry)] = &steps[..] else { panic!("one Trashed step: {steps:?}") };
    let date = held.borrow()[0].date.clone();
    assert!(entry.uri.is_empty() && entry.trashed_at <= date, "the stamp {} is not at or before the item's deletion date {}", entry.trashed_at, date);
}

#[test]
fn the_chunk_bound_is_the_bound_gio_runs_under() {
    let secs = |text: &str| text.trim_end_matches('s').parse::<i64>().unwrap();
    assert_eq!(CHUNK_SECS, secs(TRASH_TIMEOUT) + secs(TRASH_KILL_AFTER));
}
