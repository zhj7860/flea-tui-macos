// Pins for Replace inside a merge: one Trash list per merge, the old file put back, and the settle.
use super::*;
use crate::backend::undo::Step;

#[test]
fn merge_replace_lists_the_trash_once_per_merge_not_per_file() {
    let d = TestDir::new("merge-replace-lists");
    let to = d.dir("to");
    let album = d.dir("from/trip");
    d.dir("to/trip");
    for i in 0..3 {
        d.file(&format!("from/trip/f{}.txt", i), "yours");
        d.file(&format!("to/trip/f{}.txt", i), "there");
    }
    let _trash = working_trash(&d);
    trash::test_reset_list_calls();
    let (ok, failed, _, _, _, merged, _, _) = transfer(false, &[&album], &to, merged_policy(7, &[&album], &to, "replace"));
    assert_eq!((ok, failed), (1, 0));
    assert_eq!(merged, 3);
    assert!(trash::test_list_calls() <= 2, "N replaces cost one before/after pair, not 2N: {}", trash::test_list_calls());
}

#[test]
fn merge_replace_puts_the_old_file_back_when_its_copy_fails() {
    let d = TestDir::new("merge-replace-putback");
    let to = d.dir("to");
    let album = d.dir("from/trip");
    d.dir("to/trip");
    let bad = d.file("from/trip/bad.txt", "yours");
    d.file("to/trip/bad.txt", "there");
    d.file("from/trip/good.txt", "yours-g");
    d.file("to/trip/good.txt", "there-g");
    std::fs::set_permissions(&bad, std::fs::Permissions::from_mode(0o000)).unwrap();
    let _trash = working_trash(&d);
    let (ok, failed, _, _, entry, _, _, _) = transfer(false, &[&album], &to, merged_policy(7, &[&album], &to, "replace"));
    assert_eq!((ok, failed), (0, 1));
    assert_eq!(text(&to.join("trip/bad.txt")), "there", "the failed replace goes straight back");
    assert_eq!(text(&to.join("trip/good.txt")), "yours-g");
    let kept: Vec<_> = entry.steps.iter().filter_map(|s| match s {
        crate::backend::undo::Step::Trashed(e) if e.original == to.join("trip/bad.txt") => Some(e.original.clone()),
        _ => None,
    }).collect();
    assert!(kept.is_empty(), "a restored put-back leaves no trash step: {:?}", kept);
}

#[test]
fn merge_replace_refuses_a_destination_that_vanished_before_its_trash() {
    let d = TestDir::new("merge-replace-gone");
    let can = d.dir("can");
    let gone = d.dir("to").join("trip/f.txt");
    let seen = std::rc::Rc::new(std::cell::RefCell::new(Vec::new()));
    let (seen_in, at) = (std::rc::Rc::clone(&seen), can.clone());
    trash::STAND_IN.with(|slot| *slot.borrow_mut() = Some(std::rc::Rc::new(move |args: &[&str]| {
        seen_in.borrow_mut().push(args.join(" "));
        if let ["trash", "--", path] = args {
            if std::path::Path::new(path).symlink_metadata().is_err() {
                return Some(exited(1, String::new()));
            }
        }
        Some(gio_trash(&at, args))
    })));
    let landed = std::rc::Rc::new(std::cell::Cell::new(false));
    let landed_in = std::rc::Rc::clone(&landed);
    let mut deferred = crate::backend::mergeapply::Deferred::begin();
    let mut steps = Vec::new();
    let r = crate::backend::mergeapply::replacing_deferred(&gone, &mut steps, &mut deferred, &std::sync::atomic::AtomicBool::new(false), move |_| { landed_in.set(true); Ok(()) });
    match r {
        Err(e) => assert_eq!(e.msg, crate::backend::collide::TRASH_REFUSED),
        Ok(()) => panic!("a gone destination must refuse, not trash-and-land"),
    }
    assert!(!landed.get(), "land must not run for a gone destination");
    assert!(steps.is_empty(), "a refused trash journals nothing: {:?}", steps);
    assert!(seen.borrow().iter().all(|a| !a.starts_with("trash -- ")), "no gio trash spawn for a gone path: {:?}", seen.borrow());
    trash::STAND_IN.with(|slot| *slot.borrow_mut() = None);
}

// Without the before list no settle can attribute, so the Replace is refused before anything moves.
#[test]
fn a_replace_refuses_up_front_when_the_before_list_cannot_be_read() {
    let d = TestDir::new("deferred-before-none");
    let to = d.dir("to");
    d.dir("from");
    let photo = d.file("from/p.png", "yours");
    let there = to.join("p.png");
    std::fs::write(&there, "there").unwrap();
    let can = d.dir("can");
    let at = can.clone();
    trash::STAND_IN.with(|slot| *slot.borrow_mut() = Some(std::rc::Rc::new(move |args: &[&str]| {
        if matches!(args, ["trash", "--list"]) {
            return None;
        }
        Some(gio_trash(&at, args))
    })));
    let _guard = StandIn;
    let mut deferred = crate::backend::mergeapply::Deferred::begin();
    let mut steps = Vec::new();
    let landed = std::rc::Rc::new(std::cell::Cell::new(false));
    let landed_in = std::rc::Rc::clone(&landed);
    let r = crate::backend::mergeapply::replacing_deferred(&there, &mut steps, &mut deferred, &std::sync::atomic::AtomicBool::new(false), move |_| {
        landed_in.set(true);
        Ok(())
    });
    assert_eq!(r.expect_err("no before list means no Replace").msg, crate::backend::collide::TRASH_REFUSED);
    assert!(!landed.get(), "land never runs for a refused trash");
    assert!(steps.is_empty(), "a refused trash journals nothing: {steps:?}");
    assert_eq!(text(&there), "there", "nothing was trashed");
    let _ = photo;
}

// One dropped settle list is retried, so a single stall still attributes every Replace in the batch.
#[test]
fn a_settle_list_that_fails_once_is_retried_and_still_attributes() {
    let d = TestDir::new("deferred-settle-retry");
    let to = d.dir("to");
    d.dir("from");
    let photo = d.file("from/p.png", "yours");
    let there = to.join("p.png");
    std::fs::write(&there, "there").unwrap();
    let can = d.dir("can");
    let at = can.clone();
    let lists = std::rc::Rc::new(std::cell::Cell::new(0));
    let lists_in = std::rc::Rc::clone(&lists);
    trash::STAND_IN.with(|slot| *slot.borrow_mut() = Some(std::rc::Rc::new(move |args: &[&str]| {
        if matches!(args, ["trash", "--list"]) {
            lists_in.set(lists_in.get() + 1);
            // The settle's first list drops; the retry answers.
            if lists_in.get() == 2 {
                return None;
            }
        }
        Some(gio_trash(&at, args))
    })));
    let _guard = StandIn;
    let mut deferred = crate::backend::mergeapply::Deferred::begin();
    let mut steps = Vec::new();
    let r = crate::backend::mergeapply::replacing_deferred(&there, &mut steps, &mut deferred, &std::sync::atomic::AtomicBool::new(false), |_| {
        std::fs::rename(&photo, &there).map_err(|e| crate::error::from_io("copy", "p.png", &e))?;
        Ok(())
    });
    assert!(r.is_ok(), "the Replace lands: {r:?}");
    deferred.settle(&mut steps);
    assert_eq!(lists.get(), 3, "before, one dropped settle list, one retry");
    match &steps[..] {
        [Step::Trashed(entry)] => assert!(!entry.uri.is_empty(), "the retry attributed the entry"),
        other => panic!("one attributed Trashed step: {other:?}"),
    }
}

// A settle no list answers twice keeps the path and the time, and undo resolves the URI from a fresh list.
#[test]
fn a_settle_no_list_answers_keeps_path_and_time_for_undo_to_resolve() {
    let d = TestDir::new("deferred-settle-unresolved");
    let to = d.dir("to");
    d.dir("from");
    let photo = d.file("from/p.png", "yours");
    let there = to.join("p.png");
    std::fs::write(&there, "there").unwrap();
    let can = d.dir("can");
    let at = can.clone();
    let at_first = at.clone();
    // A prior trash entry from this same path, so the before list holds it and the undo resolution must skip it.
    std::fs::write(can.join("9"), "prior bytes").unwrap();
    std::fs::write(can.join("9.original"), there.to_string_lossy().as_bytes()).unwrap();
    let lists = std::rc::Rc::new(std::cell::Cell::new(0));
    let lists_in = std::rc::Rc::clone(&lists);
    trash::STAND_IN.with(|slot| *slot.borrow_mut() = Some(std::rc::Rc::new(move |args: &[&str]| {
        if matches!(args, ["trash", "--list"]) {
            lists_in.set(lists_in.get() + 1);
            // The before list answers; the settle's two lists never do.
            if lists_in.get() > 1 {
                return None;
            }
        }
        Some(gio_trash(&at_first, args))
    })));
    let _guard = StandIn;
    let mut deferred = crate::backend::mergeapply::Deferred::begin();
    let mut steps = Vec::new();
    let before_trash = crate::backend::hometrash::deletion_date_local();
    let mut after_trash = String::new();
    let r = crate::backend::mergeapply::replacing_deferred(&there, &mut steps, &mut deferred, &std::sync::atomic::AtomicBool::new(false), |_| {
        after_trash = crate::backend::hometrash::deletion_date_local();
        // A landing that runs past a second boundary, so a settle-time stamp could not pass for the trash time.
        std::thread::sleep(std::time::Duration::from_millis(1100));
        std::fs::rename(&photo, &there).map_err(|e| crate::error::from_io("copy", "p.png", &e))?;
        Ok(())
    });
    assert!(r.is_ok(), "the Replace lands: {r:?}");
    deferred.settle(&mut steps);
    let entry = match &steps[..] {
        [Step::Trashed(entry)] => entry.clone(),
        other => panic!("one Trashed step: {other:?}"),
    };
    assert!(entry.uri.is_empty(), "no list answered, so no URI was recorded");
    assert_eq!(entry.original, there);
    assert!(before_trash <= entry.trashed_at && entry.trashed_at <= after_trash, "the time is the trash's, not the settle's: {} not in {before_trash}..{after_trash}", entry.trashed_at);
    assert_eq!(entry.before, ["trash:///9"], "the before list stays for the undo resolution");
    // The lists answer again, so undo resolves the URI from a fresh one and restores.
    trash::STAND_IN.with(|slot| *slot.borrow_mut() = Some(std::rc::Rc::new(move |args: &[&str]| Some(gio_trash(&at, args)))));
    // The replacement is already undone ahead of its trash step, as the journal orders them.
    std::fs::remove_file(&there).unwrap();
    crate::backend::trash::restore(&entry).expect("a fresh list resolves the entry");
    assert_eq!(text(&there), "there", "undo brings the old item back to its path");
}

// A merge that replaces nothing lists the trash never: the first list waits for the first trash.
#[test]
fn a_merge_with_no_replace_lists_the_trash_never() {
    let d = TestDir::new("merge-no-replace-lists");
    let to = d.dir("to");
    let album = d.dir("from/trip");
    d.file("from/trip/new.txt", "yours");
    d.dir("to/trip");
    d.file("to/trip/old.txt", "stays");
    let _trash = working_trash(&d);
    trash::test_reset_list_calls();
    let (ok, failed, _, _, _, merged, _, _) = transfer(false, &[&album], &to, merged_policy(7, &[&album], &to, "keep"));
    assert_eq!((ok, failed), (1, 0));
    assert_eq!(merged, 1);
    assert_eq!(trash::test_list_calls(), 0, "no Replace means no list");
}

#[path = "mergetrash_tests.rs"]
mod inprocess;
