// Synthetic RAF: the 16-byte magic, a big-endian JPEG offset at 84 and length at 88, then a JPEG carrying an APP1 Exif TIFF.
use crate::backend::rawembed;
use crate::backend::rawtiff::tests::{jpeg, write};
use crate::backend::testdir::TestDir;

// A minimal APP1 Exif TIFF: one IFD holding Make and Model as ASCII.
fn exif_tiff() -> Vec<u8> {
    let mut b = b"II*\x00".to_vec();
    b.extend_from_slice(&8u32.to_le_bytes());
    b.extend_from_slice(&2u16.to_le_bytes());
    for (tag, val) in [(0x010Fu16, b"FUJIFILM\0".as_slice()), (0x0110, b"X-T5\0".as_slice())] {
        b.extend_from_slice(&tag.to_le_bytes());
        b.extend_from_slice(&2u16.to_le_bytes());
        b.extend_from_slice(&(val.len() as u32).to_le_bytes());
        b.extend_from_slice(&0u32.to_le_bytes());
    }
    b.extend_from_slice(&0u32.to_le_bytes());
    // Patch the two value offsets to the data appended after the IFD.
    let data_at = b.len() as u32;
    b.extend_from_slice(b"FUJIFILM\0X-T5\0");
    let first = 8 + 2 + 8;
    b[first..first + 4].copy_from_slice(&data_at.to_le_bytes());
    let second = 8 + 2 + 12 + 8;
    b[second..second + 4].copy_from_slice(&(data_at + 9).to_le_bytes());
    b
}

pub(crate) fn jpeg_with_app1(w: u16, h: u16) -> Vec<u8> {
    let mut exif = b"Exif\x00\x00".to_vec();
    exif.extend_from_slice(&exif_tiff());
    let mut v = vec![0xFF, 0xD8, 0xFF, 0xE1];
    v.extend_from_slice(&((exif.len() + 2) as u16).to_be_bytes());
    v.extend_from_slice(&exif);
    v.extend_from_slice(&[0xFF, 0xC0, 0x00, 0x0B, 0x08]);
    v.extend_from_slice(&h.to_be_bytes());
    v.extend_from_slice(&w.to_be_bytes());
    v.extend_from_slice(&[0x01, 0x01, 0x22, 0x00, 0xFF, 0xD9]);
    v
}

pub(crate) fn raf(jpeg_off: u32, jpeg_len: u32, jpeg: &[u8]) -> Vec<u8> {
    let mut b = b"FUJIFILMCCD-RAW ".to_vec();
    while b.len() < 84 {
        b.push(0);
    }
    b.extend_from_slice(&jpeg_off.to_be_bytes());
    b.extend_from_slice(&jpeg_len.to_be_bytes());
    while b.len() < jpeg_off as usize {
        b.push(0);
    }
    b.extend_from_slice(jpeg);
    b
}

#[test]
fn a_raf_yields_its_jpeg_and_the_app1_facts() {
    let d = TestDir::new("rawrafok");
    let j = jpeg_with_app1(800, 600);
    let p = write(&d, "a.raf", &raf(128, j.len() as u32, &j));
    let (preview, facts) = rawembed::inspect(&p).expect("a valid RAF inspects");
    let pv = preview.expect("the JPEG validates");
    assert_eq!((pv.width, pv.height), (800, 600));
    assert_eq!(pv.offset, 128);
    assert_eq!(facts.make.as_deref(), Some("FUJIFILM"));
    assert_eq!(facts.model.as_deref(), Some("X-T5"));
}

#[test]
fn hostile_offsets_are_refused_and_junk_is_no_preview() {
    let d = TestDir::new("rawrafno");
    let j = jpeg(100, 80);
    // The header is whole and the offset is inside the file, but the JPEG's last byte is missing: None, never a wrapped read.
    let whole = raf(128, j.len() as u32, &j);
    assert!(rawembed::inspect(&write(&d, "whole.raf", &whole)).is_some(), "the control: the whole file inspects");
    let p = write(&d, "past.raf", &whole[..whole.len() - 1]);
    assert!(rawembed::inspect(&p).is_none());
    // Zero length: recognised, nothing to validate.
    let p = write(&d, "zero.raf", &raf(128, 0, &[]));
    let (preview, _) = rawembed::inspect(&p).expect("a zero-length RAF still inspects");
    assert!(preview.is_none());
    // Bytes that are no JPEG: recognised, no preview, no panic.
    let p = write(&d, "junk.raf", &raf(128, 64, &[7u8; 64]));
    let (preview, _) = rawembed::inspect(&p).expect("inspects");
    assert!(preview.is_none(), "64 non-JPEG bytes validate to nothing");
    // Truncated at every 16 bytes: the walk degrades, never panics.
    let full = raf(128, j.len() as u32, &jpeg_with_app1(800, 600));
    for cut in (0..full.len()).step_by(16) {
        let p = write(&d, &format!("cut{}.raf", cut), &full[..cut]);
        let _ = rawembed::inspect(&p);
    }
}
