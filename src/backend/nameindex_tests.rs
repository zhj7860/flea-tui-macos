use super::*;
use crate::backend::testdir::TestDir;

// The parser under the index: every test query is the real syntax, never a hand-built matcher.
fn find(index: &Index, text: &str, hidden: bool, under: Option<&str>, limit: usize) -> (Vec<(String, bool)>, usize, usize) {
    let query = crate::backend::searchsyntax::parse(text).expect("the test query parses");
    query_in(index, &query, hidden, under, limit)
}

// A small tree the test builds itself; every path stays inside the sandbox TestDir.
fn fixture(name: &str) -> TestDir {
    let d = TestDir::new(name);
    d.dir("projects/Rust");
    d.file("projects/Rust/Cargo.toml", "");
    d.file("projects/notes.txt", "");
    d.file("report.txt", "");
    d.file(".secretonly.txt", "");
    d
}

#[test]
fn a_built_index_answers_by_name_without_a_walk() {
    let d = fixture("nameindex-answer");
    let index = build(&[d.path().to_path_buf()]);
    let (rows, matched, population) = find(&index, "cargo", false, None, 50);
    assert_eq!(population, index.len(), "the whole snapshot is the population");
    assert_eq!(matched, 1, "one Cargo.toml in the tree");
    assert!(rows[0].0.ends_with("projects/Rust/Cargo.toml"), "{}", rows[0].0);
    assert!(!rows[0].1, "a file is not a directory");
}

#[test]
fn a_hidden_name_is_answered_only_when_hidden_is_on() {
    let d = fixture("nameindexdot");
    let index = build(&[d.path().to_path_buf()]);
    assert_eq!(find(&index, "secretonly", false, None, 10).1, 0, "a dotfile is hidden by default");
    let (rows, matched, _) = find(&index, "secretonly", true, None, 10);
    assert_eq!(matched, 1);
    assert!(rows[0].0.ends_with(".secretonly.txt"));
}

#[test]
fn an_exact_name_outranks_a_longer_one() {
    let d = fixture("nameindex-rank");
    let index = build(&[d.path().to_path_buf()]);
    let (rows, _, _) = find(&index, "report.txt", false, None, 10);
    assert!(rows[0].0.ends_with("report.txt"), "the exact name leads: {}", rows[0].0);
}

#[test]
fn a_cached_snapshot_round_trips_through_the_file_format() {
    let d = fixture("nameindex-cache");
    let index = build(&[d.path().to_path_buf()]);
    let path = d.path().join("snapshot.idx");
    store(&path, &index);
    let back = load(&path).expect("our own snapshot parses");
    assert_eq!(back.len(), index.len());
    for row in 0..index.len() {
        assert_eq!(back.path(row), index.path(row));
        assert_eq!(back.is_dir(row), index.is_dir(row));
    }
    // A truncated file is refused rather than read past its end.
    let bytes = std::fs::read(&path).unwrap();
    std::fs::write(&path, &bytes[..bytes.len() / 2]).unwrap();
    assert!(load(&path).is_none(), "a truncated snapshot is refused");
}

#[test]
fn a_folder_filter_keeps_only_that_subtree() {
    let d = fixture("nameindex-under");
    d.dir("projects-old");
    d.file("projects-old/Cargo.toml", "");
    let index = build(&[d.path().to_path_buf()]);
    let root = d.path().to_string_lossy().into_owned();
    let inside = format!("{root}/projects");
    let (rows, matched, population) = find(&index, "cargo", false, Some(&inside), 10);
    assert_eq!(population, index.len(), "the population still counts the whole snapshot");
    assert_eq!(matched, 1, "projects-old is not under projects, so it is not a match");
    assert!(rows[0].0.ends_with("/projects/Rust/Cargo.toml"), "{}", rows[0].0);
    assert_eq!(find(&index, "cargo", false, None, 10).1, 2, "the whole disk holds both");
    assert_eq!(find(&index, "cargo", false, Some("/"), 10).1, 2, "the root filters nothing");
}

#[test]
fn only_a_file_whose_own_name_matches_is_an_answer() {
    let d = TestDir::new("nameindex-names");
    d.dir("Sources/Flea");
    d.file("Sources/Flea/Keymap.swift", "");
    d.file("Sources/Flea/Flea.md", "");
    let index = build(&[d.path().to_path_buf()]);
    let (rows, matched, _) = find(&index, "Flea", false, None, 10);
    assert_eq!(matched, 1, "the folder called Flea and the file that only sits under it are not answers");
    assert!(rows[0].0.ends_with("/Sources/Flea/Flea.md"), "{}", rows[0].0);
    assert!(!rows[0].1, "a directory is never an answer");
}

// Everything's syntax through the real index: names only, no fuzzy noise, boolean terms.
#[test]
fn the_whole_disk_answer_speaks_everythings_syntax() {
    let d = TestDir::new("nameindex-syntax");
    d.dir("Sources/Flea");
    d.file("Sources/Flea/Keymap.swift", "");
    d.file("Sources/Flea.md", "");
    d.file("Sources/LogicAudioFileAIFF.icns", "");
    d.file("Sources/notes.txt", "");
    let index = build(&[d.path().to_path_buf()]);
    let names = |text: &str| find(&index, text, false, None, 20).0.iter().map(|(n, _)| n.rsplit('/').next().unwrap().to_string()).collect::<Vec<_>>();
    assert_eq!(names("flea"), vec!["Flea.md"], "a substring of the name, and no fuzzy neighbour");
    assert_eq!(names("FLEA"), vec!["Flea.md"], "case-insensitive by default");
    assert_eq!(names("flea|notes"), vec!["Flea.md", "notes.txt"], "| is OR, answered in name order");
    assert_eq!(names("!flea"), vec!["Keymap.swift", "LogicAudioFileAIFF.icns", "notes.txt"], "! is NOT");
    assert_eq!(names("flea ext:md"), vec!["Flea.md"], "a space is AND");
    assert_eq!(names("<flea|notes> .md"), vec!["Flea.md"], "< > groups");
    assert_eq!(names("*.md"), vec!["Flea.md"], "* anchors to the whole name");
    assert_eq!(names("Keymap.*"), vec!["Keymap.swift"], "a wildcard suffix matches the extension");
    assert_eq!(names("case:FLEA"), Vec::<String>::new(), "case: makes the text case-sensitive");
    assert_eq!(names("wholefilename:flea.md"), vec!["Flea.md"], "wholefilename: equals the whole name");
    assert_eq!(names("startwith:key"), vec!["Keymap.swift"], "startwith: matches the head of the name");
    assert_eq!(names("endwith:.swift"), vec!["Keymap.swift"], "endwith: matches the tail");
    assert!(crate::backend::searchsyntax::parse("size:>1mb").is_err(), "metadata functions are refused, never silent");
}

// A root directory newer than the snapshot holds an application the snapshot cannot know; the
// search answers its new rows beside the snapshot's, and keeps the snapshot's own rows.
#[test]
fn a_root_that_moved_since_the_snapshot_answers_its_new_child() {
    let d = TestDir::new("nameindex-added");
    d.dir("apps");
    d.file("apps/old.txt", "");
    let root = d.path().join("apps");
    let old = build(&[root.clone()]);
    let snapshot = d.path().join("locate.idx");
    store(&snapshot, &old);
    assert!(added_in(&snapshot, &old, &[root.clone()]).is_none(), "nothing moved yet");
    std::thread::sleep(std::time::Duration::from_millis(20));
    d.file("apps/newapp.txt", "");
    let (_stamps, added) = added_in(&snapshot, &old, &[root.clone()]).expect("the root moved");
    assert_eq!(find(&added, "newapp", false, None, 10).1, 1, "the new file is in the side index");
    assert_eq!(find(&old, "newapp", false, None, 10).1, 0, "the snapshot itself is unchanged");
    let cached = added_index(&snapshot, &old, &[root.clone()]).expect("a stale root");
    assert_eq!(find(&cached, "newapp", false, None, 10).1, 1);
    assert!(added_index(&snapshot, &old, &[root.clone()]).is_some_and(|again| std::sync::Arc::ptr_eq(&again, &cached)),
        "the same changed roots reuse the side index");
    // The union answers both sides by the snapshot's name order.
    let query = crate::backend::searchsyntax::parse("newapp|old").expect("parses");
    let (rows, matched, _) = query_union(&old, &cached, &query, false, None, 10);
    assert_eq!(matched, 2, "one old row and one new row");
    assert!(rows.iter().any(|row| row.0.ends_with("apps/newapp.txt")));
    assert!(rows.iter().any(|row| row.0.ends_with("apps/old.txt")));
    // A snapshot rebuilt after the change knows the child itself, so no side index is needed.
    let rebuilt = build(&[root.clone()]);
    store(&snapshot, &rebuilt);
    assert!(added_index(&snapshot, &rebuilt, &[root]).is_none(), "a fresh snapshot needs no side index");
}

// A .app bundle is a directory to the filesystem and the answer a person searches for.
#[test]
fn an_application_bundle_is_an_answer_while_a_plain_folder_is_not() {
    let d = TestDir::new("nameindex-app");
    d.dir("apps/TencentMeeting.app/Contents/MacOS");
    d.file("apps/TencentMeeting.app/Contents/MacOS/TencentMeeting", "");
    d.dir("apps/PlainFolder");
    d.file("apps/PlainFolder/note.txt", "");
    let index = build(&[d.path().join("apps")]);
    let (rows, matched, _) = find(&index, "tencentmeeting", false, None, 10);
    assert_eq!(matched, 2, "the bundle and its executable both carry the name");
    assert!(rows.iter().any(|row| row.0.ends_with("TencentMeeting.app") && row.1),
        "the bundle is a folder row: {rows:?}");
    assert_eq!(find(&index, "plainfolder", false, None, 10).1, 0, "a plain folder is not an answer");
}
