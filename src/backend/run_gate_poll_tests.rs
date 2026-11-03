// A network poll's change and a probe's figures seen during a held scan, driven through the same Loop as run_gate_tests.rs.
use super::*;

// The folder on screen, listed and landed under the caller's remote body, then a second folder's scan held at its read.
fn left_for(l: &mut Loop, tag: &str) -> (PathBuf, PathBuf, scanhold::Hold) {
    let (old, new) = (l.dir.dir("old"), l.dir.dir(tag));
    l.dir.file("old/a.txt", "a");
    let _ = l.dir.file(&format!("{tag}/b.txt"), "b");
    assert!(l.request(&list(&old)) == Control::Continue);
    let landed = l.wait(is_list);
    assert!(l.feed(landed) == Control::Continue);
    l.said();
    let hold = scanhold::hold(&text(&new), Stage::Read);
    assert!(l.request(&list(&new)) == Control::Continue);
    hold.entered.recv_timeout(EVENT_DEADLINE).expect("the second scan is out and held at its read");
    (old, new, hold)
}

// A poll sees the folder being left move while the scan of the next one is out, so it waits and the folder that lands answers nothing.
#[test]
fn a_poll_for_the_folder_being_left_answers_nothing_once_the_scan_lands() {
    let mut l = Loop::new("rungate-pollleft");
    let _body = crate::backend::iomount::test_hold_body(remote_body(l.dir.path()));
    let (old, new, hold) = left_for(&mut l, "new");
    assert!(l.feed(Event::PollChanged(old)) == Control::Continue);
    let early = l.said();
    assert!(early.is_empty(), "the poll waits for the scan: {early}");
    hold.release();
    let landed = l.wait(is_list);
    assert!(l.feed(landed) == Control::Continue);
    let said = l.said();
    assert_eq!(said.lines().count(), 2, "listed and rows only, no changed line for the folder left: {said}");
    assert_eq!(field_str(said.lines().next().unwrap(), "path"), Some(text(&new)), "{said}");
    assert!(l.gate.take_held().is_empty(), "the held poll was judged once and is gone");
}

// A scan that fails leaves the old folder on screen, so a poll held meanwhile is answered once against that folder.
#[test]
fn a_poll_held_over_a_failed_scan_names_the_folder_still_on_screen() {
    let mut l = Loop::new("rungate-pollfail");
    let _body = crate::backend::iomount::test_hold_body(remote_body(l.dir.path()));
    let (old, new, hold) = left_for(&mut l, "gone");
    assert!(l.feed(Event::PollChanged(old.clone())) == Control::Continue);
    std::fs::remove_dir_all(&new).expect("the sandbox drops the folder being scanned");
    hold.release();
    let landed = l.wait(is_list);
    assert!(l.feed(landed) == Control::Continue);
    let said = l.said();
    let lines: Vec<&str> = said.lines().collect();
    assert_eq!(lines.len(), 2, "the error, then one changed line: {said}");
    assert_eq!(field_str(lines[0], "t").as_deref(), Some("error"), "{said}");
    assert_eq!(lines[1], changed_line(&old), "the line names the folder still on screen: {said}");
}

// A probe's figures for the folder being left print nothing while the scan is out, and nothing once another folder landed.
#[test]
fn figures_for_the_folder_being_left_print_nothing_over_the_scan() {
    let mut l = Loop::new("rungate-fsinfoleft");
    let _body = crate::backend::iomount::test_hold_body(remote_body(l.dir.path()));
    let (old, _new, hold) = left_for(&mut l, "new");
    let figures = crate::backend::fsinforeq::Done { root: old.clone(), dir: old, seq: 0, info: None, tagable: false };
    assert!(l.feed(Event::FsInfo(figures)) == Control::Continue);
    let early = l.said();
    assert!(early.is_empty(), "the figures wait for the scan: {early}");
    hold.release();
    let landed = l.wait(is_list);
    assert!(l.feed(landed) == Control::Continue);
    let said = l.said();
    assert!(!said.contains(r#""t":"fsinfo""#), "no figures line for the folder left: {said}");
}

// A newer list takes the place of the held scan, so a poll held meanwhile is answered against the folder still current before the newer one lands.
#[test]
fn a_poll_held_for_a_scan_let_go_is_answered_against_the_folder_still_current() {
    let mut l = Loop::new("rungate-pollletgo");
    let _body = crate::backend::iomount::test_hold_body(remote_body(l.dir.path()));
    let (here, _held, hold) = left_for(&mut l, "held");
    let newer = l.dir.dir("newer");
    l.dir.file("newer/b.txt", "b");
    assert!(l.feed(Event::PollChanged(here.clone())) == Control::Continue);
    assert!(l.request(&list(&newer)) == Control::Continue);
    let landed = l.wait(is_list);
    assert!(l.feed(landed) == Control::Continue);
    let said = l.said();
    let lines: Vec<&str> = said.lines().collect();
    assert_eq!(lines.len(), 3, "the poll's changed line, then listed and rows for the newer folder: {said}");
    assert_eq!(lines[0], changed_line(&here), "the poll was answered against the folder still current: {said}");
    assert_eq!(field_str(lines[1], "path"), Some(text(&newer)), "{said}");
    hold.release();
}
