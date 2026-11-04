use super::*;
use crate::backend::testdir::TestDir;

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
    let (rows, matched, population) = query_in(&index, "cargo", false, 50);
    assert_eq!(population, index.len(), "the whole snapshot is the population");
    assert_eq!(matched, 1, "one Cargo.toml in the tree");
    assert!(rows[0].0.ends_with("projects/Rust/Cargo.toml"), "{}", rows[0].0);
    assert!(!rows[0].1, "a file is not a directory");
}

#[test]
fn a_hidden_name_is_answered_only_when_hidden_is_on() {
    let d = fixture("nameindexdot");
    let index = build(&[d.path().to_path_buf()]);
    assert_eq!(query_in(&index, "secretonly", false, 10).1, 0, "a dotfile is hidden by default");
    let (rows, matched, _) = query_in(&index, "secretonly", true, 10);
    assert_eq!(matched, 1);
    assert!(rows[0].0.ends_with(".secretonly.txt"));
}

#[test]
fn an_exact_name_outranks_a_longer_one() {
    let d = fixture("nameindex-rank");
    let index = build(&[d.path().to_path_buf()]);
    let (rows, _, _) = query_in(&index, "report.txt", false, 10);
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
