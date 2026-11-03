// The words a refused picker check shows; each pins the sentence a person reads, not the branch that raises it.
use super::*;
use crate::backend::testdir::TestDir;

#[test]
fn a_refused_save_says_what_to_change() {
    let dir = TestDir::new("picker-save-words");
    let folder = dir.dir("folder");
    let file = dir.file("file", "one");
    let mut state = State::default();
    let cancel = Cancellation::default();
    let save = |folder: &Path, name: &str| format!(r#"{{"op":"save","id":1,"folder":"{}","name":"{}"}}"#, escape(&folder.to_string_lossy()), name);
    assert_eq!(state.handle(&save(&folder, "a/b"), &cancel).unwrap_err(), "A name cannot contain /.");
    assert_eq!(state.handle(&save(&folder, ".."), &cancel).unwrap_err(), "A name cannot be a single dot or a double dot.");
    assert_eq!(state.handle(&save(&folder, ""), &cancel).unwrap_err(), "A name cannot be empty.");
    assert_eq!(state.handle(&save(&folder, "a\\u0000b"), &cancel).unwrap_err(), "A name cannot contain a null character.");
    assert_eq!(state.handle(&save(&file, "out"), &cancel).unwrap_err(), "The selected save location is not a folder.");
    state.handle(&save(&folder, "output"), &cancel).unwrap();
    dir.file("folder/output", "arrived");
    assert_eq!(state.handle(r#"{"op":"review","id":2,"review":1}"#, &cancel).unwrap_err(),
        "An item with this name just appeared there; review it again.");
    assert_eq!(std::fs::read_to_string(file).unwrap(), "one");
}

#[test]
fn an_output_location_that_cannot_be_inspected_names_the_cause_and_ends_once() {
    use std::os::unix::fs::PermissionsExt;
    let dir = TestDir::new("picker-output-denied");
    let folder = dir.dir("folder");
    let mut state = State::default();
    let cancel = Cancellation::default();
    let save = |id: usize| format!(r#"{{"op":"save","id":{},"folder":"{}","name":"output"}}"#, id, escape(&folder.to_string_lossy()));
    state.handle(&save(1), &cancel).unwrap();
    dir.assert_contains(&folder);
    std::fs::set_permissions(&folder, std::fs::Permissions::from_mode(0o0)).unwrap();
    let review = state.handle(r#"{"op":"review","id":2,"review":1}"#, &cancel);
    let again = state.handle(&save(3), &cancel);
    std::fs::set_permissions(&folder, std::fs::Permissions::from_mode(0o700)).unwrap();
    assert_eq!(review.unwrap_err(), "Could not inspect output location: permission denied.");
    assert_eq!(again.unwrap_err(), "Could not inspect output location: permission denied.");
    assert!(!folder.join("output").exists());
}

#[test]
fn a_busy_or_stopped_picker_says_what_to_do() {
    let (replies, answers) = std::sync::mpsc::channel();
    let (requests, receiver) = sync_channel::<String>(1);
    let mut picker = Picker { requests, replies, cancellation: Cancellation::default() };
    let check = |id: usize| format!(r#"{{"c":"picker","op":"validate","id":{}}}"#, id);
    picker.request(check(1));
    picker.request(check(2));
    drop(receiver);
    picker.request(check(3));
    let mut said = Vec::new();
    while let Ok(OpMsg::Meta { line }) = answers.try_recv() { said.push((field_usize(&line, "id"), field_str(&line, "error"))); }
    assert_eq!(said, vec![(Some(2), Some("Flea is still checking this item; try again.".to_string())),
                          (Some(3), Some("The check stopped; open the file chooser again.".to_string()))]);
}

// Lines no fixture reaches (a limit the kernel will not report) are pinned by their source.
#[test]
fn retired_picker_wording_is_gone_from_the_live_source() {
    let picker = include_str!("picker.rs");
    for retired in ["A picker check", "The picker check", "reopen this request", "without a separator", "is not a directory",
                    "output name is a directory", "this output location", "descriptors exceed", "selection limit of", "open-file limit"] {
        assert!(!picker.contains(retired), "retired wording came back: {}", retired);
    }
    let limits = include_str!("picker_limits.rs").split("\n#[cfg(test)]\nmod tests").next().unwrap();
    assert!(!limits.contains("picker open-file limit"), "retired wording came back in picker_limits.rs");
    assert!(limits.contains("Cannot select items. The file chooser could not read how many it can take: {}."));
}
