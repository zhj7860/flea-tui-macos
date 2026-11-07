// The tab strip's own menu, driven through the shipped key dispatch: Close Tab, Close Other Tabs
// and New Tab, with the current pane kept unless the tab it stands on is the one removed.
use super::sort_tests::{drain, press};
use super::*;
use crate::tui::input::Key;
use crate::tui::model::Model;
use crate::tui::model::Tab;
use std::path::PathBuf;

fn tab(path: &str) -> Tab {
    Tab { path: PathBuf::from(path), cursor: 0, back: Vec::new(), forward: Vec::new() }
}

fn opened(wire: &mut Wire) -> Vec<String> {
    drain(wire)
        .iter()
        .filter(|value| text(value, "c") == "list")
        .map(|value| text(value, "path").to_string())
        .collect()
}

#[test]
fn close_tab_removes_a_tab_before_the_current_one_without_relisting() {
    let (mut wire, reader) = echo_wire();
    let mut model = Model::new(PathBuf::from("/three"), &Json::Null);
    model.tabs = vec![tab("/one"), tab("/two"), tab("/three")];
    model.tab = 2;
    model.tab_menu = true;
    model.tab_menu_target = 0;
    press(&mut model, &mut wire, &Key::named("Return", ""));
    assert_eq!(model.tabs.len(), 2, "Close Tab removes the clicked tab");
    assert_eq!(model.tab, 1, "the current tab moves down with its index");
    assert_eq!(model.path, PathBuf::from("/three"), "the pane stays where it was");
    assert!(model.pending.is_none(), "and asks for no listing");
    assert!(opened(&mut wire).is_empty(), "a tab before the current one re-lists nothing");
    assert!(!model.tab_menu, "the menu closes on its choice");
    finish(wire, reader);
}

#[test]
fn closing_the_current_tab_opens_its_neighbour() {
    let (mut wire, reader) = echo_wire();
    let mut model = Model::new(PathBuf::from("/one"), &Json::Null);
    model.tabs = vec![tab("/one"), tab("/two")];
    model.tab = 0;
    model.tab_menu = true;
    model.tab_menu_target = 0;
    press(&mut model, &mut wire, &Key::named("Return", ""));
    assert_eq!(model.tabs.len(), 1);
    assert_eq!(model.pending, Some(PathBuf::from("/two")), "the neighbour is asked for");
    assert_eq!(opened(&mut wire), vec![String::from("/two")], "the pane lists the neighbour");
    finish(wire, reader);
}

#[test]
fn close_other_tabs_keeps_the_clicked_one() {
    let (mut wire, reader) = echo_wire();
    let mut model = Model::new(PathBuf::from("/one"), &Json::Null);
    model.tabs = vec![tab("/one"), tab("/two"), tab("/three")];
    model.tab = 0;
    model.tab_menu = true;
    model.tab_menu_target = 1;
    model.tab_menu_cursor = 1;
    press(&mut model, &mut wire, &Key::named("Return", ""));
    assert_eq!(model.tabs.len(), 1, "only the clicked tab survives");
    assert_eq!(model.tabs[0].path, PathBuf::from("/two"));
    assert_eq!(model.pending, Some(PathBuf::from("/two")), "the kept tab is asked for");
    assert_eq!(opened(&mut wire), vec![String::from("/two")]);
    finish(wire, reader);
}

#[test]
fn the_new_tab_row_adds_one_and_the_disabled_rows_do_nothing() {
    let (mut wire, reader) = echo_wire();
    let mut model = Model::new(PathBuf::from("/one"), &Json::Null);
    model.tab_menu = true;
    model.tab_menu_target = 0;
    assert!(!model.tab_menu_enabled(1), "Close Other Tabs greys on one tab");
    model.tab_menu_cursor = 1;
    press(&mut model, &mut wire, &Key::named("Return", ""));
    assert_eq!(model.tabs.len(), 1, "a greyed row runs nothing");
    assert!(model.tab_menu, "and leaves the menu standing");
    model.tab_menu_cursor = 2;
    press(&mut model, &mut wire, &Key::named("Return", ""));
    assert_eq!(model.tabs.len(), 2, "New Tab adds one");
    assert!(!model.tab_menu, "the menu closes on its choice");
    finish(wire, reader);
}

#[test]
fn escape_closes_the_tab_menu_and_nine_tabs_grey_new_tab() {
    let (mut wire, reader) = echo_wire();
    let mut model = Model::new(PathBuf::from("/one"), &Json::Null);
    model.tab_menu = true;
    press(&mut model, &mut wire, &Key::named("Escape", ""));
    assert!(!model.tab_menu, "Escape closes the menu");
    model.tabs = (0..crate::uischema::MAX_LAST_TABS).map(|i| tab(&format!("/t{i}"))).collect();
    assert!(!model.tab_menu_enabled(2), "a full strip greys New Tab");
    finish(wire, reader);
}
