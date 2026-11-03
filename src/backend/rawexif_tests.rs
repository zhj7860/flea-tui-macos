use super::*;
use crate::backend::rawtiff::tests::Log;
use crate::backend::rawtiff::SliceSrc;

#[test]
fn ascii_stops_at_nul_and_trims_spaces() {
    assert_eq!(ascii(b"Canon\0\0\0"), "Canon");
    assert_eq!(ascii(b"NIKON   "), "NIKON");
    assert_eq!(ascii(b""), "");
    assert_eq!(ascii(b"\0hidden"), "");
}

#[test]
fn ascii_caps_at_the_string_cap_on_a_char_boundary() {
    assert_eq!(ascii(&[b'A'; 200]).len(), MAX_STR);
    // The cap falls inside a two-byte é, so the cut lands one byte earlier, before it.
    let mut multi = vec![b'B'; MAX_STR - 1];
    multi.extend_from_slice("é".as_bytes());
    multi.extend_from_slice(b"tail");
    assert_eq!(ascii(&multi), "B".repeat(MAX_STR - 1));
}

#[test]
fn ascii_of_reads_no_more_than_the_string_cap() {
    let mut data = vec![0u8; 8];
    data.extend_from_slice(&[b'A'; 200]);
    let mut src = Log { data: &data, reads: Vec::new() };
    let s = ascii_of(&mut src, 0, true, 2, 200, &8u32.to_le_bytes()).expect("a string reads");
    assert_eq!(src.reads, vec![(8, MAX_STR)], "only the head of a 200-byte value is read");
    assert_eq!(s.len(), MAX_STR);
}

#[test]
fn ascii_replaces_non_utf8_lossily() {
    let s = ascii(b"ab\xFFcd\0");
    assert_eq!(s, "ab\u{FFFD}cd");
}

#[test]
fn rational_reads_both_orders() {
    let le = [0x28, 0x00, 0x00, 0x00, 0x0A, 0x00, 0x00, 0x00];
    assert_eq!(rational(&le, true), Some((40, 10)));
    let be = [0x00, 0x00, 0x00, 0x28, 0x00, 0x00, 0x00, 0x0A];
    assert_eq!(rational(&be, false), Some((40, 10)));
    assert_eq!(rational(&le[..7], true), None, "a short read is None, not a panic");
}

#[test]
fn small_reads_short_and_long_first_values() {
    assert_eq!(small(&[0x06, 0x00, 0x00, 0x00], 3, true), Some(6));
    assert_eq!(small(&[0x00, 0x06, 0x00, 0x00], 3, false), Some(6));
    assert_eq!(small(&[0x64, 0x00, 0x00, 0x00], 4, true), Some(100));
    assert_eq!(small(&[0x01], 3, true), None);
    assert_eq!(small(&[0x01, 0x00, 0x00, 0x00], 5, true), None, "a rational is not a small");
}

#[test]
fn type_size_covers_the_tiff_table_and_refuses_the_rest() {
    for t in [1u16, 2, 6, 7] {
        assert_eq!(type_size(t), Some(1));
    }
    for t in [3u16, 8] {
        assert_eq!(type_size(t), Some(2));
    }
    for t in [4u16, 9, 11, 13] {
        assert_eq!(type_size(t), Some(4));
    }
    for t in [5u16, 10, 12] {
        assert_eq!(type_size(t), Some(8));
    }
    assert_eq!(type_size(0), None);
    assert_eq!(type_size(14), None);
    assert_eq!(type_size(0xFFFF), None);
}

#[test]
fn type_13_is_a_four_byte_ifd_offset_read_as_a_long() {
    assert_eq!(small(&[0x64, 0x00, 0x00, 0x00], 13, true), Some(100));
    let mut none = SliceSrc::new(&[]);
    assert_eq!(one_u32(&mut none, 0, true, 13, 1, &[0x64, 0x00, 0x00, 0x00]), Some(100));
    let mut data = vec![0u8; 8];
    data.extend_from_slice(&[16, 0, 0, 0, 32, 0, 0, 0]);
    let mut src = SliceSrc::new(&data);
    assert_eq!(offsets(&mut src, 0, true, 13, 2, &8u32.to_le_bytes()), Some(vec![16, 32]));
}

#[test]
fn a_byte_blob_past_the_value_cap_keeps_its_span() {
    assert_eq!(blob_at(100, true, 200_000, &8u32.to_le_bytes()), Some((108, 200_000)));
    assert_eq!(blob_at(100, true, 4, &[0; 4]), None, "an inline value is too short to be a JPEG");
    assert_eq!(blob_at(u64::MAX, true, 200_000, &8u32.to_le_bytes()), None, "the offset sum overflows");
}
