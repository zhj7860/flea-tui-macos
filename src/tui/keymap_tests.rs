use super::*;
#[test]
fn compiled_source_drives_text_and_native_ctrl() {
    let map = Map::load();
    // Every bare letter and digit is typed text in the terminal, so no row may answer one; the
    // arrows carry the movement the vim letters used to.
    assert_eq!(map.action(&Key::character('j', ""), "default"), "");
    assert_eq!(map.action(&Key::character('1', ""), "default"), "");
    assert_eq!(map.action(&Key::named("Down", ""), "default"), "cursorDown");
    assert_eq!(
        map.action(
            &Key {
                name: "X".into(),
                text: "X".into(),
                mods: "ctrl".into(),
                pointer: None,
            },
            "mac"
        ),
        ""
    );
    assert_eq!(
        map.action(
            &Key {
                name: "Insert".into(),
                text: "".into(),
                mods: "shift".into(),
                pointer: None,
            },
            "vim"
        ),
        "paste"
    );
}
#[test]
fn contexts_share_only_declared_actions_and_sheet_matches_preset() {
    let map = Map::load();
    assert_eq!(map.in_context(&Key::character('d', ""), "vim", "pdf"), "");
    assert_eq!(
        map.in_context(&Key::named("Space", ""), "mac", "pdf"),
        "preview"
    );
    assert_eq!(
        map.in_context(&Key::named("Tab", "shift"), "windows", "media"),
        "focusPrevious"
    );
    assert_eq!(
        map.in_context(&Key::named("Insert", "ctrl"), "default", "editor"),
        ""
    );
    assert_eq!(map.action(&Key::character('y', ""), "vim"), "", "the vim letters are the window's");
    assert!(map.sheet("vim").iter().any(|line| line.contains("open")));
    assert!(!map
        .sheet("default")
        .iter()
        .any(|line| line.to_lowercase().contains("grid")));
}
#[test]
fn commented_headers_keep_shipped_mac_navigation_aliases_separate() {
    let map = Map::load();
    for (key, action) in [("Up", "parent"), ("Down", "open"), ("Delete", "trash")] {
        assert_eq!(map.action(&Key::named(key, "ctrl"), "mac"), action);
    }
    assert_eq!(map.action(&Key::character('3', "ctrl"), "mac"), "viewGrid");
}
#[test]
fn default_redo_is_control_shift_z() {
    let map = Map::load();
    assert_eq!(map.action(&Key::character('Z', "ctrlshift"), "default"), "redo");
}
#[test]
fn header_comments_do_not_strip_quoted_hashes_or_accept_other_suffixes() {
    let map = Map::parse(r##"
[[text]] # A header comment can contain = and ]].
char = "#"
action = "literal#action"
# [[preset]] is still a comment.
[[text]]# No intervening space is required.
char = "j"
action = "cursorDown"
[[code]] unexpected
"##);
    assert_eq!(map.blocks.len(), 2);
    assert_eq!(map.action(&Key::character('#', ""), "default"), "literal#action");
    assert_eq!(map.action(&Key::character('j', ""), "default"), "cursorDown");
}
#[test]
fn hints_name_the_shipped_keys_as_the_sheet_spells_them() {
    let map = Map::load();
    let hints = Hints::new(&map, "default");
    assert_eq!(hints.dismiss, "Escape");
    assert_eq!(hints.keys, "?");
    assert_eq!(hints.load_preview, "Ctrl+Space");
    assert_eq!(hints.delete_permanently, "Shift+Delete");
    assert_eq!(hints.trash, "Delete");
    assert_eq!(map.chord("trashArm", "default", "listing"), None, "no shipped key arms a trash here");
    assert_eq!(map.chord("trash", "default", "listing").as_deref(), Some("Delete"));
    assert_eq!(map.chord("noSuchAction", "default", "listing"), None);
}
#[test]
fn every_shipped_preset_names_a_key_for_every_hint() {
    let map = Map::load();
    for preset in ["default", "vim", "mac", "windows"] {
        let hints = Hints::new(&map, preset);
        for (name, chord) in [("dismiss", &hints.dismiss), ("keys", &hints.keys), ("load_preview", &hints.load_preview), ("delete_permanently", &hints.delete_permanently), ("trash", &hints.trash)] {
            assert!(!chord.is_empty(), "{preset} has no key for the {name} hint");
        }
    }
}
#[test]
fn a_rebound_key_reaches_its_chord_and_a_shadowed_one_does_not() {
    let map = Map::parse(r##"
[[preset]]
name = "default"
mods = "ctrl"
key = "P"
action = "loadPreview"
context = "listing"
[[code]]
key = "Backspace"
action = "escape"
[[code]]
key = "Tab"
action = "escape"
[[code]]
key = "Backspace"
action = "parent"
"##);
    assert_eq!(map.chord("loadPreview", "default", "listing").as_deref(), Some("Ctrl+P"));
    assert_eq!(map.chord("loadPreview", "vim", "listing"), None, "another preset does not read the default's chord");
    assert_eq!(map.chord("escape", "default", "listing").as_deref(), Some("Backspace"));
    assert_eq!(map.chord("parent", "default", "listing"), None, "the earlier Backspace row shadows this one");
}

// Every printable character, capital or not, is typed text in the terminal: the vim rows, the
// shifted capitals and the digits all belong to the window, and the commands are chords. Under the
// kitty keyboard protocol a chord with Shift arrives as the base letter with both modifiers, which
// is what lets Ctrl+Shift+S name the reverse order (a legacy terminal cannot tell it from Ctrl+S).
#[test]
fn bare_characters_are_text_and_the_commands_are_chords() {
    let map = Map::load();
    for (key, mods) in [('s', ""), ('s', "shift"), ('S', ""), ('S', "shift"), ('d', ""), ('d', "shift")] {
        assert_eq!(map.action(&Key::character(key, mods), "default"), "", "{key} with {mods:?} is typed text");
    }
    assert_eq!(map.action(&Key::character('S', "ctrl"), "default"), "sortNext", "Ctrl+S cycles the order");
    assert_eq!(map.action(&Key::character('S', "ctrlshift"), "default"), "sortReverse", "Ctrl+Shift+S reverses it");
    assert_eq!(map.action(&Key::character('G', "ctrl"), "default"), "toggleSelect", "Ctrl+G toggles the row");
    assert_eq!(map.action(&Key::character('O', "ctrl"), "default"), "menu", "Ctrl+O opens the menu");
    assert_eq!(map.action(&Key::character('Q', "ctrl"), "default"), "quit", "Ctrl+Q leaves");
    assert_eq!(map.action(&Key::named("Left", "ctrl"), "default"), "historyBack", "Ctrl+Left walks back");
    assert_eq!(map.action(&Key::named("Right", "ctrl"), "default"), "historyForward", "Ctrl+Right walks forward");
    assert_eq!(map.action(&Key::character('F', "ctrl"), "default"), "search", "Ctrl+F is the search key");
    assert_eq!(map.action(&Key::character('O', "ctrlshift"), "default"), "reveal", "Ctrl+Shift+O reveals a result");
    assert_eq!(map.action(&Key::character('T', "ctrlshift"), "default"), "tabNew", "Ctrl+Shift+T opens a tab");
}

