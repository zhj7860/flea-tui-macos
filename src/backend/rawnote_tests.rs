// MakerNote fixtures in the vendors' own layouts (Nikon, Olympus new and old, Pentax), and notes the walk must skip without entering.
use super::*;
use crate::backend::rawexif as ex;
use crate::backend::rawtiff::inspect_file;
use crate::backend::rawtiff::tests::{at, jpeg, patch, write, Ev, Log, Tb, PLACE};
use crate::backend::rawembed::Ctx;
use crate::backend::testdir::TestDir;

fn order_bytes(le: bool) -> &'static [u8] {
    if le {
        b"II"
    } else {
        b"MM"
    }
}

// One IFD of (tag, type, count, value) entries then a zero next pointer; values are written as given, so a placeholder survives for patching.
fn ifd_with(le: bool, entries: &[(u16, u16, u32, u32)]) -> Vec<u8> {
    let w16 = |v: u16| if le { v.to_le_bytes() } else { v.to_be_bytes() };
    let w32 = |v: u32| if le { v.to_le_bytes() } else { v.to_be_bytes() };
    let mut b = w16(entries.len() as u16).to_vec();
    for &(tag, typ, cnt, value) in entries {
        b.extend_from_slice(&w16(tag));
        b.extend_from_slice(&w16(typ));
        b.extend_from_slice(&w32(cnt));
        b.extend_from_slice(&w32(value));
    }
    b.extend_from_slice(&w32(0));
    b
}

// One IFD of single LONG tags.
fn ifd_of(le: bool, entries: &[(u16, u32)]) -> Vec<u8> {
    let long: Vec<_> = entries.iter().map(|&(tag, value)| (tag, 4, 1, value)).collect();
    ifd_with(le, &long)
}

// Sample input: "Nikon\0" 02 10 00 00, then "MM\0*" and the IFD offset 8 at +10, then the IFD; offsets count from that header.
pub(crate) fn nikon_note(le: bool, entries: &[(u16, u32)]) -> Vec<u8> {
    let mut b = b"Nikon\x00\x02\x10\x00\x00".to_vec();
    b.extend_from_slice(order_bytes(le));
    b.extend_from_slice(&if le { 42u16.to_le_bytes() } else { 42u16.to_be_bytes() });
    b.extend_from_slice(&if le { 8u32.to_le_bytes() } else { 8u32.to_be_bytes() });
    b.extend_from_slice(&ifd_of(le, entries));
    b
}

// Sample input: "OLYMPUS\0" "II" 03 00, then the IFD at +12; offsets count from the note's start.
fn olympus_head(le: bool) -> Vec<u8> {
    [b"OLYMPUS\x00".as_slice(), order_bytes(le), &[0x03, 0x00]].concat()
}

// Sample input: "OM SYSTEM\0" 00 00, "II" 04 00, then the IFD at +16; offsets count from the note's start.
fn om_head(le: bool) -> Vec<u8> {
    [b"OM SYSTEM\x00\x00\x00".as_slice(), order_bytes(le), &[0x04, 0x00]].concat()
}

// Sample input: "OLYMP\0" 01 00, then the IFD at +8 in the file's byte order; offsets count from the file.
fn olymp_head() -> Vec<u8> {
    b"OLYMP\x00\x01\x00".to_vec()
}

fn olympus_note(le: bool, entries: &[(u16, u32)]) -> Vec<u8> {
    [olympus_head(le), ifd_of(le, entries)].concat()
}

// A note whose one IFD entry, 0x2020 of this type, names a CameraSettings IFD placed right after it, at `base` plus its place in the note.
fn settings_note(head: Vec<u8>, le: bool, typ: u16, base: u64, settings: &[(u16, u32)]) -> Vec<u8> {
    let sub = ifd_of(le, settings);
    let sub_at = base + head.len() as u64 + 2 + 12 + 4;
    let cnt = if typ == 7 { sub.len() as u32 } else { 1 };
    [head, ifd_with(le, &[(ex::OLY_SETTINGS, typ, cnt, sub_at as u32)]), sub].concat()
}

// Sample input: "AOC\0" "MM", then the IFD at +6; offsets count from the file.
pub(crate) fn aoc_note(le: bool, entries: &[(u16, u32)]) -> Vec<u8> {
    let mut b = b"AOC\x00".to_vec();
    b.extend_from_slice(order_bytes(le));
    b.extend_from_slice(&ifd_of(le, entries));
    b
}

// A TIFF whose IFD0 holds the note, with the JPEG after it; the note's placeholder becomes offset(note start, JPEG start).
fn with_note(le: bool, note_le: bool, note: &[u8], pic: &[u8], offset: impl Fn(u64, u64) -> u64) -> (Vec<u8>, u64) {
    let mut t = Tb::new(le);
    let ifd0 = t.ifd(vec![(ex::MAKER_NOTE, Ev::B(7, note.to_vec()))], 0);
    t.set_ifd0(ifd0);
    let jb = t.blob(pic) as u64;
    let note_at = at(&t.b, &note[..8]);
    patch(&mut t.b, note_le, offset(note_at, jb) as u32);
    (t.b, jb)
}

fn candidates(d: &TestDir, name: &str, bytes: &[u8]) -> Vec<(u64, u64)> {
    let p = write(d, name, bytes);
    inspect_file(&mut Ctx::open(&p).expect("opens")).expect("walks").0
}

#[test]
fn a_nikon_type_3_note_has_its_tiff_header_at_plus_10() {
    let d = TestDir::new("rawnikon");
    let pic = jpeg(500, 400);
    for le in [true, false] {
        let note = nikon_note(le, &[(ex::JPEG_OFF, PLACE), (ex::JPEG_LEN, pic.len() as u32)]);
        let (bytes, jb) = with_note(le, le, &note, &pic, |n, jb| jb - (n + 10));
        assert_eq!(candidates(&d, "a.nef", &bytes), vec![(jb, pic.len() as u64)], "little-endian {}", le);
    }
}

#[test]
fn a_camera_settings_sub_ifd_names_the_preview_in_both_new_headers() {
    let d = TestDir::new("rawolynew");
    let pic = jpeg(300, 220);
    let pair = |len: usize| [(ex::OLY_PAIR_SETTINGS.0, PLACE), (ex::OLY_PAIR_SETTINGS.1, len as u32)];
    // The note's byte order may differ from the file's, and 0x2020 may be an IFD, a LONG or an UNDEFINED value holding the IFD.
    for head in [olympus_head as fn(bool) -> Vec<u8>, om_head] {
        for (file_le, note_le) in [(true, true), (true, false), (false, true)] {
            for typ in [13, 4, 7] {
                let note = settings_note(head(note_le), note_le, typ, 0, &pair(pic.len()));
                let (bytes, jb) = with_note(file_le, note_le, &note, &pic, |n, jb| jb - n);
                let got = candidates(&d, "a.orf", &bytes);
                assert_eq!(got, vec![(jb, pic.len() as u64)], "file {} note {} type {}", file_le, note_le, typ);
            }
        }
    }
}

#[test]
fn an_old_olymp_camera_settings_sub_ifd_counts_its_offsets_from_the_file() {
    let d = TestDir::new("rawolyold");
    let pic = jpeg(300, 220);
    let pair = [(ex::OLY_PAIR_SETTINGS.0, PLACE), (ex::OLY_PAIR_SETTINGS.1, pic.len() as u32)];
    for le in [true, false] {
        let build = |note_at| settings_note(olymp_head(), le, 13, note_at, &pair);
        let (bytes, jb) = nested_note(le, le, build, &pic, |_, jb| jb);
        assert_eq!(candidates(&d, "a.orf", &bytes), vec![(jb, pic.len() as u64)], "little-endian {}", le);
    }
}

#[test]
fn the_note_ifd_pairs_0088_and_1036_name_a_preview_in_each_header() {
    let d = TestDir::new("rawolymain");
    let pic = jpeg(300, 220);
    for (start, len) in [ex::OLY_PAIR_A, ex::OLY_PAIR_B] {
        let entries = [(start, PLACE), (len, pic.len() as u32)];
        for head in [olympus_head as fn(bool) -> Vec<u8>, om_head] {
            let note = [head(true), ifd_of(true, &entries)].concat();
            let (bytes, jb) = with_note(true, true, &note, &pic, |n, jb| jb - n);
            assert_eq!(candidates(&d, "a.orf", &bytes), vec![(jb, pic.len() as u64)], "pair {:04X}", start);
        }
        let (bytes, jb) = with_note(false, false, &[olymp_head(), ifd_of(false, &entries)].concat(), &pic, |_, jb| jb);
        assert_eq!(candidates(&d, "a.orf", &bytes), vec![(jb, pic.len() as u64)], "old pair {:04X}", start);
    }
}

#[test]
fn a_pair_is_read_only_in_the_ifd_whose_table_names_it() {
    let d = TestDir::new("rawolywrong");
    let pic = jpeg(300, 220);
    let settings = [(ex::OLY_PAIR_SETTINGS.0, PLACE), (ex::OLY_PAIR_SETTINGS.1, pic.len() as u32)];
    // 0x0101 and 0x0102 in the note's own IFD are not Olympus tags in the reference.
    let (bytes, _) = with_note(true, true, &olympus_note(true, &settings), &pic, |n, jb| jb - n);
    assert!(candidates(&d, "a.orf", &bytes).is_empty(), "the settings pair in the note IFD");
    // 0x0088 and 0x0089 in the CameraSettings IFD are not either.
    let in_settings = [(ex::OLY_PAIR_A.0, PLACE), (ex::OLY_PAIR_A.1, pic.len() as u32)];
    let note = settings_note(olympus_head(true), true, 13, 0, &in_settings);
    let (bytes, _) = with_note(true, true, &note, &pic, |n, jb| jb - n);
    assert!(candidates(&d, "a.orf", &bytes).is_empty(), "the note pair in the settings IFD");
    // A 0x2020 outside an Olympus note names no CameraSettings IFD.
    let mut t = Tb::new(true);
    let jb = t.blob(&pic);
    let sub = t.ifd(vec![(ex::OLY_PAIR_SETTINGS.0, Ev::T(4, jb)), (ex::OLY_PAIR_SETTINGS.1, Ev::T(4, pic.len() as u32))], 0);
    let ifd0 = t.ifd(vec![(ex::OLY_SETTINGS, Ev::T(13, sub))], 0);
    t.set_ifd0(ifd0);
    assert!(candidates(&d, "a.tif", &t.b).is_empty(), "0x2020 in IFD0");
    // The same bytes in a Nikon note carry no Olympus tag either.
    let nikon = nikon_note(true, &[(ex::OLY_PAIR_A.0, PLACE), (ex::OLY_PAIR_A.1, pic.len() as u32)]);
    let (bytes, _) = with_note(true, true, &nikon, &pic, |n, jb| jb - (n + 10));
    assert!(candidates(&d, "a.nef", &bytes).is_empty(), "the note pair in a Nikon note");
}

#[test]
fn a_pentax_aoc_note_names_its_byte_order_and_counts_from_the_file() {
    let d = TestDir::new("rawaoc");
    let pic = jpeg(160, 120);
    for (file_le, note_le) in [(false, false), (true, true), (true, false)] {
        let note = aoc_note(note_le, &[(ex::JPEG_OFF, PLACE), (ex::JPEG_LEN, pic.len() as u32)]);
        let (bytes, jb) = with_note(file_le, note_le, &note, &pic, |_, jb| jb);
        assert_eq!(candidates(&d, "a.pef", &bytes), vec![(jb, pic.len() as u64)], "file {} note {}", file_le, note_le);
    }
}

type NoteOffer = (Vec<(u64, usize)>, Vec<(u64, u64)>);

// Offers the note at `at` with `total` bytes to the walk, answering every read it made and what it collected.
fn offer(data: &[u8], at: u64, total: u32) -> NoteOffer {
    let mut src = Log { data, reads: Vec::new() };
    let mut w = Walk::new();
    let loc = IfdLoc { base: 0, little_endian: true, depth: 0, in_sub_ifd: false, index_in_chain: 0, is_exif: false, olympus: Oly::No };
    let _ = makernote(&mut src, &mut w, &loc, 7, total, &(at as u32).to_le_bytes());
    (src.reads, w.cands)
}

// The note is built once to find where the file puts it, then again with that place, for offsets that count from the file.
fn nested_note(file_le: bool, note_le: bool, build: impl Fn(u64) -> Vec<u8>, pic: &[u8], offset: impl Fn(u64, u64) -> u64) -> (Vec<u8>, u64) {
    let (probe, _) = with_note(file_le, note_le, &build(0), pic, &offset);
    with_note(file_le, note_le, &build(at(&probe, &build(0)[..8])), pic, &offset)
}

// The note's bytes then filler that would form a walkable IFD, so a read past the value would not simply fail.
fn after(note: &[u8]) -> Vec<u8> {
    let mut data = note.to_vec();
    data.extend_from_slice(&ifd_of(true, &[(ex::JPEG_OFF, 0), (ex::JPEG_LEN, 64)]));
    data.resize(data.len() + 64, 0);
    data
}

#[test]
fn a_note_is_skipped_after_one_signature_read_or_none() {
    // Too short for any header: no read at all.
    let short = after(b"Nikon\x00\x02");
    assert!(offer(&short, 0, 7).0.is_empty(), "7 bytes is skipped before a read");
    // No known signature: the signature window is read once and the note is not entered.
    let junk = after(b"PENTAXFAKE-not-a-tiff-header!!");
    assert_eq!(offer(&junk, 0, 30).0, vec![(0, 30)]);
    // The control: a whole note reads past its signature, so the log tells entering from skipping.
    let whole = nikon_note(true, &[(ex::JPEG_OFF, 0), (ex::JPEG_LEN, 64)]);
    assert!(offer(&whole, 0, whole.len() as u32).0.len() > 1, "an entered note reads its TIFF header and IFD");
}

#[test]
fn a_note_cut_inside_its_header_is_never_read_past_its_value() {
    // Nikon cut in the middle of its TIFF header: 14 of the 18 bytes the header and its first count need.
    let nikon = after(&nikon_note(true, &[(ex::JPEG_OFF, 0), (ex::JPEG_LEN, 64)])[..14]);
    assert_eq!(offer(&nikon, 0, 14), (vec![(0, 14)], vec![]));
    // Olympus cut after its byte order and version: the IFD count at +12 lies outside the note.
    let olympus = after(&olympus_note(true, &[(ex::OLY_PAIR_A.0, 0), (ex::OLY_PAIR_A.1, 64)])[..12]);
    assert_eq!(offer(&olympus, 0, 12), (vec![(0, 12)], vec![]));
    // OM SYSTEM cut after its byte order and version: the IFD count at +16 lies outside the note.
    let om = after(&[om_head(true), ifd_of(true, &[(ex::OLY_PAIR_A.0, 0), (ex::OLY_PAIR_A.1, 64)])].concat()[..16]);
    assert_eq!(offer(&om, 0, 16), (vec![(0, 16)], vec![]));
    // Pentax with no byte order after its signature is not a note this walk knows.
    let aoc = after(b"AOC\x00\x00\x00\x00\x00\x00\x00\x00\x00");
    assert_eq!(offer(&aoc, 0, 12), (vec![(0, 12)], vec![]));
}

#[test]
fn a_skipped_note_is_not_a_failure() {
    let d = TestDir::new("rawnoteskip");
    let mut t = Tb::new(true);
    let ifd0 = t.ifd(vec![(ex::MAKER_NOTE, Ev::B(7, b"PENTAXFAKE-not-a-tiff-header!!".to_vec()))], 0);
    t.set_ifd0(ifd0);
    assert!(candidates(&d, "a.pef", &t.b).is_empty());
}
