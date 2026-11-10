// The listing's own key paths on macOS: typing narrows the folder (a letter with no action opens
// the filter on itself and the letters after it narrow the same line), F5 lists again, and the
// menu's Copy file row is the same copy the Ctrl+C chord makes, asked for through the menu's
// snapshot.
use super::sort_tests::{drain, open_names, press, requests};
use super::*;
use crate::tui::input::Key;
use crate::tui::model::Model;
use crate::tui::wire::finish;
use std::path::PathBuf;

#[test]
fn a_letter_with_no_action_starts_the_filter_with_itself() {
    let (mut wire, reader) = echo_wire();
    let mut model = Model::new(PathBuf::from("/listing"), &Json::Null);
    open_names(&mut model, &mut wire, &[("alpha", false), ("beta", false), ("charlie", false)]);
    press(&mut model, &mut wire, &Key::character('b', ""));
    assert_eq!(model.filter, "b", "a typed letter filters on itself");
    let editor = model.editor.as_ref().expect("the filter line opens on the first letter");
    assert_eq!(editor.kind, "filter");
    assert_eq!(editor.value, "b");
    press(&mut model, &mut wire, &Key::character('e', ""));
    assert_eq!(model.filter, "be", "the next letter narrows the same line, not a second one");
    assert_eq!(model.editor.as_ref().map(|e| e.value.as_str()), Some("be"));
    press(&mut model, &mut wire, &Key::named("Escape", ""));
    assert!(model.filter.is_empty(), "Esc clears the filter as it does for /");
    assert!(model.editor.is_none(), "and closes the line");
    press(&mut model, &mut wire, &Key::named("Return", ""));
    assert!(model.filter.is_empty(), "a bare Return on no filter still opens the cursor row");
    finish(wire, reader);
}

#[test]
fn no_bare_letter_or_digit_is_an_action() {
    let (mut wire, reader) = echo_wire();
    let mut model = Model::new(PathBuf::from("/listing"), &Json::Null);
    open_names(&mut model, &mut wire, &[("alpha", false), ("beta", false)]);
    press(&mut model, &mut wire, &Key::named("Down", ""));
    assert!(model.filter.is_empty(), "the arrow moves rather than filtering");
    assert_eq!(model.cursor, 1);
    for letter in ['j', 'z', '1'] {
        model.editor = None;
        model.apply_filter(String::new());
        press(&mut model, &mut wire, &Key::character(letter, ""));
        assert_eq!(model.filter, letter.to_string(), "{letter} starts the filter instead of acting");
    }
    finish(wire, reader);
}

// The window's own rows are scoped to it (`frontend = "gui"`), so their letters are unbound here
// and therefore typed text; the PDF preview's `e` is a separate, all-frontends row.
#[test]
fn a_letter_the_window_owns_is_typeahead_here() {
    let (mut wire, reader) = echo_wire();
    let mut model = Model::new(PathBuf::from("/listing"), &Json::Null);
    open_names(&mut model, &mut wire, &[("alpha", false), ("beta", false)]);
    for letter in ['T', 'i', 'c', 'P', 'V', 'Y', 'a', 'e'] {
        model.editor = None;
        model.apply_filter(String::new());
        press(&mut model, &mut wire, &Key::character(letter, ""));
        assert_eq!(model.filter, letter.to_string(), "{letter} is typed for the filter");
        assert_eq!(model.editor.as_ref().map(|e| e.kind), Some("filter"));
    }
    finish(wire, reader);
}

#[test]
fn the_menu_copy_file_row_asks_for_the_rows_paths() {
    let (mut wire, reader) = echo_wire();
    let mut model = Model::new(PathBuf::from("/listing"), &Json::Null);
    open_names(&mut model, &mut wire, &[("alpha", false), ("beta", false)]);
    press(&mut model, &mut wire, &Key::character('O', "ctrl"));
    let sent = drain(&mut wire);
    assert_eq!(requests(&sent, "menuaction").len(), 1, "the menu asks for its snapshot");
    let snapshot = format!(r#"{{"t":"menuaction","op":"snapshot","id":{},"ok":true,"count":2}}"#, model.action_id);
    model.receive(jsondoc::parse(&snapshot).unwrap(), &mut wire).unwrap();
    assert!(drain(&mut wire).is_empty(), "a snapshot reply sends nothing on its own");
    press(&mut model, &mut wire, &Key::named("Down", ""));
    press(&mut model, &mut wire, &Key::named("Down", ""));
    assert_eq!(model.menu_cursor, 2, "two steps past Open lands on Copy file");
    assert!(drain(&mut wire).is_empty(), "stepping sends nothing");
    press(&mut model, &mut wire, &Key::named("Return", ""));
    let sent = drain(&mut wire);
    assert_eq!(requests(&sent, "paths").len(), 1, "Copy file asks for the row's paths");
    assert!(!model.menu, "the menu closes on the choice");
    finish(wire, reader);
}

#[test]
fn f5_lists_the_folder_again() {
    let (mut wire, reader) = echo_wire();
    let mut model = Model::new(PathBuf::from("/listing"), &Json::Null);
    open_names(&mut model, &mut wire, &[("alpha", false)]);
    press(&mut model, &mut wire, &Key::named("F5", ""));
    let sent = drain(&mut wire);
    assert_eq!(requests(&sent, "list").len(), 1, "F5 re-lists the folder");
    finish(wire, reader);
}

#[test]
fn the_window_only_rows_leave_the_pdf_preview_its_key() {
    let map = crate::tui::keymap::Map::load();
    let e = Key::character('e', "");
    assert_eq!(map.action(&e, "default"), "", "the listing has no expand action");
    assert_eq!(map.in_context(&e, "default", "pdf"), "expand", "a PDF preview keeps e");
    for letter in ['T', 'i', 'c', 'P', 'V', 'Y', 'a'] {
        let key = Key::character(letter, "");
        assert_eq!(map.action(&key, "default"), "", "{letter} is the window's and unbound here");
    }
}

// A filter matched names the listing had not sent yet, so it read only the screenful: a row past the
// first window could not be found. One whole-listing read now answers it.
#[test]
fn a_filter_reads_the_whole_listing_to_find_a_row_off_the_screen() {
    let (mut wire, reader) = echo_wire();
    let mut model = Model::new(PathBuf::from("/listing"), &Json::Null);
    model.height = 4;
    model.open(model.path.clone(), &mut wire).unwrap();
    drain(&mut wire);
    let listed = jsondoc::parse(r#"{"t":"listed","n":30,"read":0.0,"sort":0.0,"v":1,"path":"/listing"}"#).unwrap();
    model.receive(listed, &mut wire).unwrap();
    drain(&mut wire);
    // The first screenful only; the row the filter wants sorts past it.
    let first = (0..4).map(|i| format!(r#"{{"n":"a{i}.txt"}}"#)).collect::<Vec<_>>().join(",");
    model.receive(jsondoc::parse(&format!(r#"{{"t":"rows","start":0,"rows":[{first}]}}"#)).unwrap(), &mut wire).unwrap();
    drain(&mut wire);
    press(&mut model, &mut wire, &Key::character('z', ""));
    let sent = drain(&mut wire);
    let windows = requests(&sent, "window");
    assert_eq!(windows.len(), 1, "one whole-listing read answers a filter");
    assert_eq!(count(windows[0], "count"), 30, "it asks for every row the listing holds");
    assert_eq!(count(windows[0], "start"), 0, "from the first row");
    // The whole listing lands: the match beyond the first screen becomes the cursor.
    let rest = (4..30).map(|i| format!(r#"{{"n":"a{i}.txt"}}"#)).chain(std::iter::once(r#"{"n":"zzz.csv"}"#.to_string())).collect::<Vec<_>>().join(",");
    model.receive(jsondoc::parse(&format!(r#"{{"t":"rows","start":4,"rows":[{rest}]}}"#)).unwrap(), &mut wire).unwrap();
    drain(&mut wire);
    assert_eq!(model.filter, "z");
    assert_eq!(model.rows.get(&model.cursor).map(|r| r.name.as_str()), Some("zzz.csv"), "the off-screen row answers the filter");
    finish(wire, reader);
}

// A filter's matches can outlast the screen, so the view scrolls through them and End lands on the last.
#[test]
fn a_filter_longer_than_the_screen_scrolls() {
    let (mut wire, reader) = echo_wire();
    let mut model = Model::new(PathBuf::from("/listing"), &Json::Null);
    model.height = 5;
    let names: Vec<String> = (0..30).map(|i| format!("ax{i:02}.txt")).collect();
    let names: Vec<(&str, bool)> = names.iter().map(|n| (n.as_str(), false)).collect();
    open_names(&mut model, &mut wire, &names);
    press(&mut model, &mut wire, &Key::character('x', ""));
    assert_eq!(model.shown().len(), 30, "every row matches");
    // Enter keeps the filter and hands the keys back to the listing.
    press(&mut model, &mut wire, &Key::named("Return", ""));
    assert!(model.editor.is_none(), "the filter line is closed");
    press(&mut model, &mut wire, &Key::named("End", ""));
    assert_eq!(model.cursor, 29, "End lands on the last match");
    assert_eq!(model.top, 25, "and the view scrolled to hold it");
    for _ in 0..4 {
        press(&mut model, &mut wire, &Key::named("Up", ""));
    }
    assert_eq!(model.cursor, 25);
    assert_eq!(model.top, 25, "the cursor stays on the bottom row while it is on screen");
    for _ in 0..2 {
        press(&mut model, &mut wire, &Key::named("Up", ""));
    }
    assert_eq!(model.cursor, 23);
    assert_eq!(model.top, 23, "a step past the top row scrolls the view with it");
    press(&mut model, &mut wire, &Key::named("Escape", ""));
    let sent = drain(&mut wire);
    assert_eq!(requests(&sent, "window").len(), 1, "leaving the filter reads the screenful again");
    assert_eq!(requests(&sent, "window")[0].get("count").and_then(Json::as_f64), Some(5.0), "one screenful, not the whole listing");
    finish(wire, reader);
}
