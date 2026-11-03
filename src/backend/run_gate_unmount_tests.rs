// An unmount seen during a held scan, driven through the same Loop as run_gate_tests.rs.
use super::*;

// The pending folder's descriptor, as the worker's watch names it in a burst, read while its scan is held at the read.
fn pending_wd(l: &mut Loop, dir: &Path) -> i32 {
    std::fs::create_dir(dir.join("burst")).expect("the sandbox takes a folder");
    let Event::Changed(wd) = l.wait(is_changed) else { panic!("not a change") };
    wd
}

// An unmount for the folder being scanned names a descriptor that is not current yet, so it waits and is answered once.
#[test]
fn an_unmount_in_the_folder_being_scanned_is_answered_once_it_lands() {
    let mut l = Loop::new("rungate-unmount");
    let new = l.dir.dir("new");
    l.dir.file("new/b.txt", "b");
    let _body = crate::backend::iomount::test_hold_body(remote_body(l.dir.path()));
    let hold = scanhold::hold(&text(&new), Stage::Read);
    assert!(l.request(&list(&new)) == Control::Continue);
    hold.entered.recv_timeout(EVENT_DEADLINE).expect("the scan is out and held at its read");
    let pending = pending_wd(&mut l, &new);
    assert!(l.feed(Event::Unmounted(pending)) == Control::Continue);
    let early = l.said();
    assert!(early.is_empty(), "the unmount waits for the scan: {early}");
    hold.release();
    let landed = l.wait(is_list);
    assert!(l.feed(landed) == Control::Continue);
    let said = l.said();
    let lines: Vec<&str> = said.lines().collect();
    assert_eq!(lines.len(), 3, "listed, rows, then one unmounted line: {said}");
    assert_eq!(field_str(lines[2], "t").as_deref(), Some("unmounted"), "{said}");
    assert_eq!(field_str(lines[2], "path"), Some(text(&new)), "the line names the folder that became current: {said}");
    assert!(l.gate.take_unmounts().is_empty(), "the held unmount was replayed once and is gone");
}

// An unmount in the folder just left is judged against the descriptor that became current, so it answers nothing.
#[test]
fn an_unmount_in_the_folder_being_left_answers_nothing_once_the_scan_lands() {
    let mut l = Loop::new("rungate-unmountleft");
    let (old, new) = (l.dir.dir("old"), l.dir.dir("new"));
    l.dir.file("old/a.txt", "a");
    l.dir.file("new/b.txt", "b");
    let _body = crate::backend::iomount::test_hold_body(remote_body(l.dir.path()));
    assert!(l.request(&list(&old)) == Control::Continue);
    let landed = l.wait(is_list);
    assert!(l.feed(landed) == Control::Continue);
    l.said();
    let hold = scanhold::hold(&text(&new), Stage::Read);
    assert!(l.request(&list(&new)) == Control::Continue);
    hold.entered.recv_timeout(EVENT_DEADLINE).expect("the second scan is out and held at its read");
    let left = pending_wd(&mut l, &old);
    assert!(l.feed(Event::Unmounted(left)) == Control::Continue);
    let early = l.said();
    assert!(early.is_empty(), "nothing is answered against the folder being left while the scan is out: {early}");
    hold.release();
    let landed = l.wait(is_list);
    assert!(l.feed(landed) == Control::Continue);
    let said = l.said();
    let lines: Vec<&str> = said.lines().collect();
    assert_eq!(lines.len(), 2, "listed and rows only, no unmounted line for the folder left: {said}");
    assert_eq!(field_str(lines[0], "path"), Some(text(&new)), "{said}");
}

// A change and an unmount held together are both answered, the change as it always was and the unmount after it.
#[test]
fn a_held_unmount_leaves_the_held_change_as_it_was() {
    let mut l = Loop::new("rungate-unmountchange");
    let new = l.dir.dir("new");
    l.dir.file("new/b.txt", "b");
    let _body = crate::backend::iomount::test_hold_body(remote_body(l.dir.path()));
    let hold = scanhold::hold(&text(&new), Stage::Read);
    assert!(l.request(&list(&new)) == Control::Continue);
    hold.entered.recv_timeout(EVENT_DEADLINE).expect("the scan is out and held at its read");
    let pending = pending_wd(&mut l, &new);
    assert!(l.feed(Event::Changed(pending)) == Control::Continue);
    assert!(l.feed(Event::Changed(pending)) == Control::Continue);
    assert!(l.feed(Event::Unmounted(pending)) == Control::Continue);
    let early = l.said();
    assert!(early.is_empty(), "both wait for the scan: {early}");
    hold.release();
    let landed = l.wait(is_list);
    assert!(l.feed(landed) == Control::Continue);
    let said = l.said();
    let lines: Vec<&str> = said.lines().collect();
    assert_eq!(lines.len(), 4, "listed, rows, one changed line for the two bursts, then the unmounted line: {said}");
    assert_eq!(lines[2], changed_line(&new), "the changes are answered exactly once, as before");
    assert_eq!(field_str(lines[3], "t").as_deref(), Some("unmounted"), "{said}");
}

// A scan that fails leaves the old folder on screen, so an unmount held meanwhile is answered once against that folder.
#[test]
fn an_unmount_held_over_a_failed_scan_names_the_folder_still_on_screen() {
    let mut l = Loop::new("rungate-unmountfail");
    let (old, new) = (l.dir.dir("old"), l.dir.dir("new"));
    l.dir.file("old/a.txt", "a");
    let _body = crate::backend::iomount::test_hold_body(remote_body(l.dir.path()));
    assert!(l.request(&list(&old)) == Control::Continue);
    let landed = l.wait(is_list);
    assert!(l.feed(landed) == Control::Continue);
    l.said();
    let hold = scanhold::hold(&text(&new), Stage::Read);
    assert!(l.request(&list(&new)) == Control::Continue);
    hold.entered.recv_timeout(EVENT_DEADLINE).expect("the second scan is out and held at its read");
    let left = pending_wd(&mut l, &old);
    assert!(l.feed(Event::Unmounted(left)) == Control::Continue);
    // The folder asked for goes away under its held read, so the scan fails.
    std::fs::remove_dir(&new).expect("the sandbox drops the empty folder being scanned");
    let early = l.said();
    assert!(early.is_empty(), "the unmount waits for the scan: {early}");
    hold.release();
    let landed = l.wait(is_list);
    assert!(l.feed(landed) == Control::Continue);
    let said = l.said();
    let lines: Vec<&str> = said.lines().collect();
    assert_eq!(lines.len(), 2, "the error, then one unmounted line: {said}");
    assert_eq!(field_str(lines[0], "t").as_deref(), Some("error"), "{said}");
    assert_eq!(field_str(lines[0], "path"), Some(text(&new)), "the error names the folder asked for: {said}");
    assert_eq!(field_str(lines[1], "t").as_deref(), Some("unmounted"), "{said}");
    assert_eq!(field_str(lines[1], "path"), Some(text(&old)), "the line names the folder still on screen, not the one asked for: {said}");
    assert!(l.gate.take_unmounts().is_empty(), "the held unmount was replayed once and is gone");
}
