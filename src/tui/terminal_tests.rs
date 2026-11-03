use super::*;
use crate::backend::testdir::TestDir;
use std::os::unix::fs::{symlink, PermissionsExt};

#[test]
fn the_shared_memory_query_names_a_fresh_private_pixel() {
    let dir = TestDir::new("shm");
    let root = dir.path();
    let query = shm_query(root, "flea-tui-shm-1").expect("query");
    assert_eq!(query, format!("\x1b_Gi=32,s=1,v=1,a=q,t=s,f=24;{}\x1b\\", crate::tui::graphics::base64(b"/flea-tui-shm-1")));
    let made = root.join("flea-tui-shm-1");
    assert_eq!(std::fs::read(&made).unwrap(), [0, 0, 0]);
    assert_eq!(std::fs::metadata(&made).unwrap().permissions().mode() & 0o777, 0o600);
}

#[test]
fn a_planted_link_at_the_name_is_replaced_never_followed() {
    let dir = TestDir::new("shm");
    let root = dir.path();
    let target = root.join("bystander");
    std::fs::write(&target, b"keep").unwrap();
    symlink(&target, root.join("flea-tui-shm-2")).unwrap();
    assert!(shm_query(root, "flea-tui-shm-2").is_some());
    assert_eq!(std::fs::read(&target).unwrap(), b"keep");
    assert!(!std::fs::symlink_metadata(root.join("flea-tui-shm-2")).unwrap().file_type().is_symlink());
}

#[test]
fn the_opening_asks_about_shared_memory_before_the_kitty_probe() {
    let dir = TestDir::new("shm");
    let bytes = opening(&shm_query(dir.path(), "flea-tui-shm-3").expect("query"));
    let shared = bytes.find("\x1b_Gi=32,").expect("the shared memory query");
    let kitty = bytes.find("\x1b_Gi=31,").expect("the kitty probe");
    let attributes = bytes.find("\x1b[c").expect("the attributes query that closes the probe");
    assert!(shared < kitty && kitty < attributes, "kitty would answer the kitty probe first, so a launch could start mpv at rest");
}

// The opening is the only thing enter writes after raw mode, in one print and one flush.
#[test]
fn enter_writes_the_opening() {
    let source: String = include_str!("terminal.rs").lines().filter(|line| !line.trim_start().starts_with("//")).collect::<Vec<_>>().join("\n");
    let enter = &source[source.find("pub fn enter()").expect("Terminal::enter")..source.find("pub fn run_editor").expect("run_editor")];
    assert!(enter.contains("print!(\"{}\", opening(") && !enter.contains("screen(true)"), "enter no longer writes the opening");
}

#[test]
fn an_editor_that_exits_nonzero_ends_the_rename_with_its_status() {
    assert!(editor_result(std::process::ExitStatus::from_raw(0)).is_ok());
    // Raw wait status 1 << 8 is exit code 1.
    let failed = editor_result(std::process::ExitStatus::from_raw(1 << 8)).unwrap_err();
    assert_eq!(failed.to_string(), "The editor could not finish (exit status: 1)");
}

#[test]
fn a_terminal_cannot_open_in_a_file() {
    let file = std::env::current_exe().unwrap();
    assert_eq!(launch(&file, false).unwrap_err().to_string(), "That is not a folder, so no terminal was opened");
}

#[test]
fn a_failed_stty_call_says_what_it_was_for() {
    assert!(stty_result(std::process::ExitStatus::from_raw(0), PREPARE_FAILED).is_ok());
    let failed = std::process::ExitStatus::from_raw(1 << 8);
    assert_eq!(stty_result(failed, PREPARE_FAILED).unwrap_err().to_string(), "The terminal could not be prepared");
    assert_eq!(stty_result(failed, RESTORE_FAILED).unwrap_err().to_string(), "The terminal could not be restored");
    assert_eq!(stty_result(failed, PREPARE_FOR_EDITOR_FAILED).unwrap_err().to_string(), "The terminal could not be prepared for the editor");
    assert_eq!(stty_result(failed, RESTORE_AFTER_EDITOR_FAILED).unwrap_err().to_string(), "The terminal could not be restored after the editor");
}
