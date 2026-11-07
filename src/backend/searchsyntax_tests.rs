use super::*;

fn m(query: &str, name: &str, path: &str) -> bool {
    parse(query).expect("the test query parses").matches(name, path)
}

#[test]
fn a_space_is_and_a_pipe_is_or_and_and_binds_tighter() {
    assert!(m("flea keymap", "flea keymap.txt", "/a/flea keymap.txt"));
    assert!(!m("flea keymap", "flea.txt", "/a/flea.txt"), "both terms must match");
    assert!(m("flea|keymap", "keymap.txt", "/a/keymap.txt"));
    assert!(m("alpha | beta gamma", "beta gamma", "/a/beta gamma"), "a | b c is a or (b and c)");
    assert!(m("alpha | beta gamma", "alpha", "/a/alpha"));
    assert!(!m("alpha | beta gamma", "beta", "/a/beta"));
}

#[test]
fn a_bang_negates_and_angle_brackets_group() {
    assert!(m("!flea", "notes.txt", "/a/notes.txt"));
    assert!(!m("!flea", "flea.txt", "/a/flea.txt"));
    assert!(m("!!flea", "flea.txt", "/a/flea.txt"), "two bangs cancel");
    assert!(m("<flea|keymap> swift", "Keymap.swift", "/a/Keymap.swift"));
    assert!(!m("<flea|keymap> swift", "Flea.md", "/a/Flea.md"));
    assert!(m("<flea", "flea.txt", "/a/flea.txt"), "an unclosed group runs to the end, as Everything's does");
}

#[test]
fn quotes_keep_spaces_and_turn_operators_and_wildcards_into_text() {
    assert!(m("\"flea keymap\"", "flea keymap.txt", "/a/flea keymap.txt"));
    assert!(!m("\"flea keymap\"", "flea.txt", "/a/flea.txt"));
    assert!(m("\"size:1\"", "size:1.txt", "/a/size:1.txt"), "a quoted colon is a literal");
    assert!(m("\"a|b\"", "a|b.txt", "/a/a|b.txt"));
    assert!(m("\"*.txt\"", "a*.txt", "/a/a*.txt"), "quotes make a wildcard literal");
    assert!(!m("\"*.txt\"", "notes.txt", "/a/notes.txt"));
}

#[test]
fn wildcards_anchor_to_the_whole_name() {
    assert!(m("*.txt", "notes.txt", "/a/notes.txt"));
    assert!(m("notes*", "notes.txt", "/a/notes.txt"));
    assert!(m("note?.txt", "notes.txt", "/a/notes.txt"), "? takes one byte");
    assert!(!m("note?.txt", "note.txt", "/a/note.txt"));
    assert!(m("*", "anything", "/a/anything"));
    assert!(!m("*.md", "notes.txt", "/a/notes.txt"));
}

#[test]
fn case_wholefilename_and_path_are_the_declared_flags() {
    assert!(!m("case:Flea", "flea.txt", "/a/flea.txt"), "case: makes the term case-sensitive");
    assert!(m("case:Flea", "Flea.txt", "/a/Flea.txt"));
    assert!(m("wholefilename:flea.md", "flea.md", "/a/flea.md"), "wholefilename: equals the whole name");
    assert!(!m("wholefilename:flea", "flea.md", "/a/flea.md"), "and not a substring of it");
    assert!(m("wholefilename:*.md", "flea.md", "/a/flea.md"), "a wildcard still matches the whole name");
    assert!(m("path:src", "notes.txt", "/home/src/notes.txt"), "path: reads the whole path");
    assert!(!m("src", "notes.txt", "/home/src/notes.txt"), "the default reads the name alone");
    assert!(!m("nopath:src", "notes.txt", "/home/src/notes.txt"), "nopath: puts it back on the name");
    assert!(m("home/src", "notes.txt", "/home/src/notes.txt"), "a term holding / reads the path");
}

#[test]
fn ext_startwith_and_endwith_read_the_name() {
    assert!(m("ext:txt;md", "a.md", "/a/a.md"));
    assert!(m("ext:txt,md", "a.md", "/a/a.md"), "both separators are accepted");
    assert!(!m("ext:txt", "a.md", "/a/a.md"));
    assert!(m("startwith:key", "Keymap.swift", "/a/Keymap.swift"));
    assert!(!m("startwith:map", "Keymap.swift", "/a/Keymap.swift"));
    assert!(m("endwith:.swift", "Keymap.swift", "/a/Keymap.swift"));
    assert!(!m("endwith:key", "Keymap.swift", "/a/Keymap.swift"));
}

#[test]
fn file_lists_files_and_folder_lists_nothing() {
    assert!(m("file:flea", "flea.txt", "/a/flea.txt"));
    assert!(!m("folder:flea", "flea", "/a/flea"), "a This Mac answer is a file list");
}

#[test]
fn the_functions_this_index_cannot_answer_say_so() {
    for query in ["size:>1mb", "dm:today", "dc:2026", "da:2026", "attrib:h", "type:image", "content:flea", "dupe:", "empty:", "len:>3", "sort:name", "parent:src", "infolder:src", "child:x", "root:", "filelist:x", "container:x", "sibling:x", "shell:x", "iso:x", "utf8:x"] {
        let message = parse(query).expect_err("a metadata function is refused");
        assert!(message.contains(&query.split(':').next().unwrap()), "{message} names its function");
    }
    assert!(parse("regex:^flea").unwrap_err().contains("regular expressions"));
    let unknown = parse("foo:bar").expect_err("an unknown function is refused");
    assert!(unknown.contains("unknown function") && unknown.contains("quote"), "{unknown}");
}

#[test]
fn an_empty_query_matches_everything() {
    assert!(m("", "anything", "/a/anything"));
    assert!(m("   ", "anything", "/a/anything"));
}
