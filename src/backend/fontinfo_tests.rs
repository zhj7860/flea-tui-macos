use super::*;
use std::io::Cursor;

fn u16be(v: u16) -> Vec<u8> { v.to_be_bytes().to_vec() }
fn u32be(v: u32) -> Vec<u8> { v.to_be_bytes().to_vec() }
fn utf16(s: &str) -> Vec<u8> { s.encode_utf16().flat_map(|u| u.to_be_bytes()).collect() }

// One name record: platform, encoding, language, name id and its text, already encoded.
type Record<'a> = (u16, u16, u16, u16, &'a [u8]);

fn name_table(records: &[Record]) -> Vec<u8> {
    let mut head = u16be(0);
    head.extend(u16be(records.len() as u16));
    head.extend(u16be(6 + 12 * records.len() as u16));
    let mut strings = Vec::new();
    for (platform, encoding, language, id, text) in records {
        for v in [platform, encoding, language, id, &(text.len() as u16), &(strings.len() as u16)] {
            head.extend(u16be(*v));
        }
        strings.extend_from_slice(text);
    }
    head.extend(strings);
    head
}

fn maxp(glyphs: u16) -> Vec<u8> {
    let mut t = u32be(0x0001_0000);
    t.extend(u16be(glyphs));
    t.extend([0u8; 26]);
    t
}

// An sfnt at `base` in a buffer: the header, the directory and the tables, each table's offset counted from the buffer's start.
fn sfnt(base: usize, version: u32, tables: &[(&[u8; 4], Vec<u8>)]) -> Vec<u8> {
    let mut out = vec![0u8; base];
    out.extend(u32be(version));
    out.extend(u16be(tables.len() as u16));
    out.extend([0u8; 6]);
    let mut at = base + 12 + 16 * tables.len();
    let mut body = Vec::new();
    for (tag, bytes) in tables {
        out.extend_from_slice(*tag);
        out.extend(u32be(0));
        out.extend(u32be(at as u32));
        out.extend(u32be(bytes.len() as u32));
        at += bytes.len();
        body.extend_from_slice(bytes);
    }
    out.extend(body);
    out
}

fn win(id: u16, text: &str) -> Vec<u8> { name_table(&[(3, 1, 0x409, id, &utf16(text))]) }

fn facts(bytes: &[u8]) -> Facts {
    parse(&mut Cursor::new(bytes.to_vec()), bytes.len() as u64)
}

fn inter() -> Vec<u8> {
    let names = name_table(&[
        (3, 1, 0x409, 1, &utf16("Inter Display")),
        (3, 1, 0x409, 2, &utf16("Regular")),
        (3, 1, 0x409, 16, &utf16("Inter")),
        (3, 1, 0x409, 17, &utf16("Bold")),
    ]);
    sfnt(0, 0x0001_0000, &[(b"maxp", maxp(2548)), (b"name", names)])
}

#[test]
fn family_and_style_come_from_ids_16_and_17_before_1_and_2() {
    assert_eq!(facts(&inter()), Facts { family: Some("Inter".into()), style: Some("Bold".into()), glyphs: Some(2548) });
}

#[test]
fn ids_1_and_2_answer_where_16_and_17_are_absent() {
    let names = name_table(&[(3, 1, 0x409, 1, &utf16("Hack")), (3, 1, 0x409, 2, &utf16("Regular"))]);
    let f = facts(&sfnt(0, 0x4F54_544F, &[(b"name", names)]));
    assert_eq!((f.family.as_deref(), f.style.as_deref(), f.glyphs), (Some("Hack"), Some("Regular"), None));
}

#[test]
fn a_style_is_chosen_apart_from_its_family() {
    let names = name_table(&[(3, 1, 0x409, 16, &utf16("Inter")), (3, 1, 0x409, 2, &utf16("Italic"))]);
    let f = facts(&sfnt(0, 0x0001_0000, &[(b"name", names)]));
    assert_eq!((f.family.as_deref(), f.style.as_deref()), (Some("Inter"), Some("Italic")));
}

#[test]
fn windows_unicode_records_come_before_mac_and_english_before_other_languages() {
    let names = name_table(&[
        (1, 0, 0, 1, b"Mac Name"),
        (3, 1, 0x407, 1, &utf16("Deutscher Name")),
        (3, 1, 0x409, 1, &utf16("English Name")),
    ]);
    assert_eq!(facts(&sfnt(0, 0x0001_0000, &[(b"name", names)])).family.as_deref(), Some("English Name"));
    let names = name_table(&[(1, 0, 0, 1, b"Mac Name"), (3, 10, 0x407, 1, &utf16("Deutscher Name"))]);
    assert_eq!(facts(&sfnt(0, 0x0001_0000, &[(b"name", names)])).family.as_deref(), Some("Deutscher Name"));
    let names = name_table(&[(1, 0, 0, 1, b"Mac Name")]);
    assert_eq!(facts(&sfnt(0, 0x0001_0000, &[(b"name", names)])).family.as_deref(), Some("Mac Name"));
}

#[test]
fn a_mac_record_with_bytes_past_ascii_is_left_out() {
    let names = name_table(&[(1, 0, 0, 1, &[b'C', 0xE9, b'f', 0xE9])]);
    assert_eq!(facts(&sfnt(0, 0x0001_0000, &[(b"name", names)])).family, None);
}

#[test]
fn an_undecodable_record_is_skipped_and_the_next_one_still_answers() {
    let names = name_table(&[(1, 0, 0, 1, &[b'C', 0xE9]), (3, 1, 0x409, 1, &utf16("Cafe"))]);
    assert_eq!(facts(&sfnt(0, 0x0001_0000, &[(b"name", names)])).family.as_deref(), Some("Cafe"));
    let names = name_table(&[(3, 1, 0x407, 1, &[0, b'A', 0]), (3, 1, 0x409, 1, &utf16("Cafe"))]);
    assert_eq!(facts(&sfnt(0, 0x0001_0000, &[(b"name", names)])).family.as_deref(), Some("Cafe"), "an odd UTF-16 record too");
}

#[test]
fn a_symbol_record_names_a_font_that_has_no_other_and_ranks_after_unicode_encoding_1() {
    let names = name_table(&[(3, 0, 0x409, 1, &utf16("Symbol Face"))]);
    assert_eq!(facts(&sfnt(0, 0x0001_0000, &[(b"name", names)])).family.as_deref(), Some("Symbol Face"));
    for records in [[(3, 0, 0x409, 1, utf16("Symbol Face")), (3, 1, 0x407, 1, utf16("Unicode Face"))],
                    [(3, 1, 0x407, 1, utf16("Unicode Face")), (3, 0, 0x409, 1, utf16("Symbol Face"))]] {
        let rows: Vec<Record> = records.iter().map(|(p, e, l, i, t)| (*p, *e, *l, *i, t.as_slice())).collect();
        assert_eq!(facts(&sfnt(0, 0x0001_0000, &[(b"name", name_table(&rows))])).family.as_deref(), Some("Unicode Face"));
    }
}

#[test]
fn a_collection_reads_its_first_face() {
    let first = sfnt(20, 0x0001_0000, &[(b"maxp", maxp(11)), (b"name", win(1, "First"))]);
    let second_at = first.len();
    let second = sfnt(second_at, 0x0001_0000, &[(b"maxp", maxp(22)), (b"name", win(1, "Second"))]);
    let mut file = b"ttcf".to_vec();
    file.extend(u32be(0x0001_0000));
    file.extend(u32be(2));
    file.extend(u32be(20));
    file.extend(u32be(second_at as u32));
    assert_eq!(file.len(), 20);
    file.extend(&first[20..]);
    file.extend(&second[second_at..]);
    let f = facts(&file);
    assert_eq!((f.family.as_deref(), f.glyphs), (Some("First"), Some(11)), "the second face must not answer");
}

#[test]
fn the_glyph_count_is_maxp_num_glyphs_and_zero_is_no_count() {
    assert_eq!(facts(&sfnt(0, 0x0001_0000, &[(b"maxp", maxp(65535))])).glyphs, Some(65535));
    assert_eq!(facts(&sfnt(0, 0x0001_0000, &[(b"maxp", maxp(0))])).glyphs, None);
    assert_eq!(facts(&sfnt(0, 0x0001_0000, &[(b"maxp", vec![0, 1, 0, 0])])).glyphs, None, "a maxp shorter than numGlyphs has no count");
}

#[test]
fn a_missing_table_drops_its_part_and_nothing_else() {
    let f = facts(&sfnt(0, 0x0001_0000, &[(b"maxp", maxp(7))]));
    assert_eq!(f, Facts { family: None, style: None, glyphs: Some(7) });
    let f = facts(&sfnt(0, 0x0001_0000, &[(b"name", win(16, "Inter"))]));
    assert_eq!(f, Facts { family: Some("Inter".into()), style: None, glyphs: None });
}

#[test]
fn a_truncated_table_directory_returns_no_facts() {
    let whole = inter();
    for cut in [0, 3, 11, 12, 20, 12 + 16 + 5] {
        assert_eq!(facts(&whole[..cut]), Facts::default(), "cut at {}", cut);
    }
}

#[test]
fn an_offset_past_the_end_returns_no_facts() {
    let whole = inter();
    // Cut inside the tables: the directory is whole and its offsets now point past the end.
    assert_eq!(facts(&whole[..12 + 32 + 4]), Facts::default());
    // A collection whose first face lies beyond the file.
    let mut file = b"ttcf".to_vec();
    file.extend(u32be(0x0001_0000));
    file.extend(u32be(1));
    file.extend(u32be(0x00FF_FFFF));
    assert_eq!(facts(&file), Facts::default());
    // A table that starts at the very end of the file, and one whose length runs past it.
    let mut bad = sfnt(0, 0x0001_0000, &[(b"maxp", maxp(9)), (b"name", win(1, "X"))]);
    let dir_name_offset = 12 + 16 + 8;
    bad[dir_name_offset..dir_name_offset + 4].copy_from_slice(&u32be(u32::MAX));
    let f = facts(&bad);
    assert_eq!((f.family, f.glyphs), (None, Some(9)));
}

#[test]
fn junk_and_hostile_counts_return_no_facts_without_panic() {
    assert_eq!(facts(b""), Facts::default());
    assert_eq!(facts(b"OTTO"), Facts::default());
    assert_eq!(facts(&[0xFFu8; 4096]), Facts::default());
    let mut many = u32be(0x0001_0000);
    many.extend(u16be(60000));
    many.extend([0u8; 4096]);
    assert_eq!(facts(&many), Facts::default(), "a table count past the file");
    let mut names = name_table(&[(3, 1, 0x409, 1, &utf16("A"))]);
    names[2..4].copy_from_slice(&u16be(60000));
    assert_eq!(facts(&sfnt(0, 0x0001_0000, &[(b"name", names)])).family, None, "a record count past the table");
    let mut names = name_table(&[(3, 1, 0x409, 1, &utf16("A"))]);
    names[4..6].copy_from_slice(&u16be(60000));
    assert_eq!(facts(&sfnt(0, 0x0001_0000, &[(b"name", names)])).family, None, "a string storage past the table");
}

#[test]
fn an_odd_utf16_length_or_an_empty_string_is_no_name() {
    let names = name_table(&[(3, 1, 0x409, 1, &[0, b'A', 0]), (3, 1, 0x409, 2, &utf16("  "))]);
    let f = facts(&sfnt(0, 0x0001_0000, &[(b"name", names)]));
    assert_eq!((f.family, f.style), (None, None));
}

#[test]
fn read_opens_a_file_and_a_missing_file_has_no_facts() {
    let d = crate::backend::testdir::TestDir::new("fontinforead");
    d.file("Inter-Bold.ttf", "");
    let path = d.join("Inter-Bold.ttf");
    std::fs::write(&path, inter()).expect("write the font");
    assert_eq!(read(&path).glyphs, Some(2548));
    assert_eq!(read(&d.join("none.ttf")), Facts::default());
}

#[test]
fn a_name_table_past_the_cap_is_not_read() {
    let mut names = win(1, "Inter");
    names.resize(NAME_CAP as usize + 1, 0);
    let f = facts(&sfnt(0, 0x0001_0000, &[(b"maxp", maxp(3)), (b"name", names)]));
    assert_eq!((f.family, f.glyphs), (None, Some(3)));
}
