// Synthetic CR3 in the real nesting: ftyp, moov{uuid{CMT1, CMT2, THMB}}, a PRVW uuid box and mdat, so no Canon file is needed.
use crate::backend::rawembed;
use crate::backend::rawtiff::tests::{at, jpeg, write};
use crate::backend::testdir::TestDir;

pub(crate) const PRVW: [u8; 16] = [
    0xEA, 0xF4, 0x2B, 0x5E, 0x1C, 0x98, 0x4B, 0x88, 0xB9, 0xFB, 0xB7, 0xDC, 0x40, 0x6E, 0x4D, 0x16,
];
pub(crate) const MOOV: [u8; 16] = [
    0x85, 0xC0, 0xB6, 0x87, 0x82, 0x0F, 0x11, 0xE0, 0x81, 0x11, 0xF4, 0xCE, 0x46, 0x2B, 0x6A, 0x48,
];

// One IFD of typed tags: tag(2) type(2) count value-or-offset, data appended after.
pub(crate) fn tiff(entries: &[(u16, u16, &[u8])]) -> Vec<u8> {
    let mut b = b"II*\x00".to_vec();
    b.extend_from_slice(&8u32.to_le_bytes());
    b.extend_from_slice(&(entries.len() as u16).to_le_bytes());
    let mut patches: Vec<(usize, Vec<u8>)> = Vec::new();
    for (tag, typ, val) in entries {
        b.extend_from_slice(&tag.to_le_bytes());
        b.extend_from_slice(&typ.to_le_bytes());
        let ts = match typ {
            1 | 2 | 7 => 1,
            3 => 2,
            5 | 10 | 12 => 8,
            _ => 4,
        };
        b.extend_from_slice(&((val.len() / ts) as u32).to_le_bytes());
        if val.len() <= 4 {
            let mut pad = val.to_vec();
            pad.resize(4, 0);
            b.extend_from_slice(&pad);
        } else {
            patches.push((b.len(), val.to_vec()));
            b.extend_from_slice(&0u32.to_le_bytes());
        }
    }
    b.extend_from_slice(&0u32.to_le_bytes());
    for (pos, data) in patches {
        let off = b.len() as u32;
        b.extend_from_slice(&data);
        b[pos..pos + 4].copy_from_slice(&off.to_le_bytes());
    }
    b
}

pub(crate) fn bx(typ: &[u8; 4], payload: &[u8]) -> Vec<u8> {
    let mut b = ((payload.len() + 8) as u32).to_be_bytes().to_vec();
    b.extend_from_slice(typ);
    b.extend_from_slice(payload);
    b
}

pub(crate) fn uuid(usertype: &[u8; 16], payload: &[u8]) -> Vec<u8> {
    let mut inner = usertype.to_vec();
    inner.extend_from_slice(payload);
    bx(b"uuid", &inner)
}

pub(crate) fn ftyp() -> Vec<u8> {
    bx(b"ftyp", b"crx \0\0\0\0\0\0\0\0")
}

// The picture's width and height read back from its SOF0, so a header field never disagrees with the JPEG it precedes.
fn dims(jpeg: &[u8]) -> (u16, u16) {
    let i = jpeg.windows(2).position(|w| w == [0xFF, 0xC0]).expect("a baseline JPEG");
    (u16::from_be_bytes([jpeg[i + 7], jpeg[i + 8]]), u16::from_be_bytes([jpeg[i + 5], jpeg[i + 6]]))
}

// Sample input after the usertype: 0, 1, PRVW size, "PRVW", 0, u16 1, width, height, u16 1, JPEG length, then the JPEG.
pub(crate) fn prvw_payload(jpeg: &[u8]) -> Vec<u8> {
    let (w, h) = dims(jpeg);
    let mut p = [0u32.to_be_bytes(), 1u32.to_be_bytes(), (jpeg.len() as u32 + 24).to_be_bytes()].concat();
    p.extend_from_slice(b"PRVW");
    p.extend_from_slice(&0u32.to_be_bytes());
    for v in [1u16, w, h, 1] {
        p.extend_from_slice(&v.to_be_bytes());
    }
    p.extend_from_slice(&(jpeg.len() as u32).to_be_bytes());
    p.extend_from_slice(jpeg);
    p
}

pub(crate) fn prvw_box(jpeg: &[u8]) -> Vec<u8> {
    uuid(&PRVW, &prvw_payload(jpeg))
}

// Sample input: u32 0, width, height, JPEG length(4), u32 0, then the JPEG, all inside one THMB box.
pub(crate) fn thmb(jpeg: &[u8]) -> Vec<u8> {
    let (w, h) = dims(jpeg);
    let mut p = 0u32.to_be_bytes().to_vec();
    p.extend_from_slice(&w.to_be_bytes());
    p.extend_from_slice(&h.to_be_bytes());
    p.extend_from_slice(&(jpeg.len() as u32).to_be_bytes());
    p.extend_from_slice(&0u32.to_be_bytes());
    p.extend_from_slice(jpeg);
    bx(b"THMB", &p)
}

// The real nesting: the Canon uuid is one child of moov, beside the movie header.
pub(crate) fn moov_box(canon: &[u8]) -> Vec<u8> {
    let mut m = bx(b"mvhd", &[0u8; 20]);
    m.extend_from_slice(&uuid(&MOOV, canon));
    bx(b"moov", &m)
}

pub(crate) fn cr3(big: &[u8], small: &[u8], cmt1: &[u8], cmt2: &[u8]) -> Vec<u8> {
    let mut canon = bx(b"CMT1", cmt1);
    canon.extend_from_slice(&bx(b"CMT2", cmt2));
    canon.extend_from_slice(&thmb(small));
    let mut f = ftyp();
    f.extend_from_slice(&moov_box(&canon));
    f.extend_from_slice(&prvw_box(big));
    f.extend_from_slice(&bx(b"mdat", &[0u8; 32]));
    f
}

#[test]
fn a_cr3_yields_the_prvw_pixels_and_the_cmt_facts() {
    let d = TestDir::new("rawcr3");
    let big = jpeg(1620, 1080);
    let small = jpeg(160, 120);
    let cmt1 = tiff(&[(0x010F, 2, b"Canon\0"), (0x0110, 2, b"EOS R6\0")]);
    let mut expo = 1u32.to_le_bytes().to_vec();
    expo.extend_from_slice(&250u32.to_le_bytes());
    let cmt2 = tiff(&[(0x829A, 5, &expo), (0x8827, 3, &[200, 0])]);
    let f = cr3(&big, &small, &cmt1, &cmt2);
    let p = write(&d, "a.cr3", &f);
    let Some((preview, facts)) = rawembed::inspect(&p) else {
        panic!("a valid CR3 inspects");
    };
    let pv = preview.expect("PRVW wins over THMB");
    assert_eq!((pv.width, pv.height), (1620, 1080));
    assert_eq!((pv.offset, pv.length), (at(&f, &big), big.len() as u64), "the span is the JPEG, not the header before it");
    assert_eq!(facts.make.as_deref(), Some("Canon"));
    assert_eq!(facts.model.as_deref(), Some("EOS R6"));
    assert_eq!(facts.exposure, Some((1, 250)));
    assert_eq!(facts.iso, Some(200));
}

#[test]
fn without_prvw_the_thmb_is_the_preview() {
    let d = TestDir::new("rawthmb");
    let small = jpeg(160, 120);
    let mut canon = bx(b"CMT1", &tiff(&[(0x010F, 2, b"C\0")]));
    canon.extend_from_slice(&thmb(&small));
    let mut f = ftyp();
    f.extend_from_slice(&moov_box(&canon));
    let p = write(&d, "b.cr3", &f);
    let (preview, facts) = rawembed::inspect(&p).expect("inspects");
    let pv = preview.expect("THMB is the only candidate");
    assert_eq!((pv.width, pv.height), (160, 120));
    assert_eq!((pv.offset, pv.length), (at(&f, &small), small.len() as u64), "the span is the JPEG, not the 16 bytes before it");
    assert_eq!(facts.make.as_deref(), Some("C"), "the CMT1 in the same uuid is read too");
}

#[test]
fn a_prvw_header_names_the_jpeg_span_and_a_wrong_one_is_refused() {
    let d = TestDir::new("rawprvwhead");
    let big = jpeg(1620, 1080);
    let mut f = ftyp();
    // A writer's padding after the JPEG stays out of the span, since the header names the length.
    let mut padded = prvw_payload(&big);
    padded.extend_from_slice(&[0u8; 40]);
    f.extend_from_slice(&uuid(&PRVW, &padded));
    let (preview, _) = rawembed::inspect(&write(&d, "padded.cr3", &f)).expect("inspects");
    assert_eq!(preview.map(|v| (v.offset, v.length)), Some((at(&f, &big), big.len() as u64)));
    // The length field sits at payload offset 28; past the box, or zero, there is no preview.
    for bad in [padded.len() as u32 - 31, 0] {
        let mut payload = padded.clone();
        payload[28..32].copy_from_slice(&bad.to_be_bytes());
        let mut f = ftyp();
        f.extend_from_slice(&uuid(&PRVW, &payload));
        // Bytes after the box keep an overlong span inside the file, so only the box bound can refuse it.
        f.extend_from_slice(&bx(b"mdat", &[0u8; 64]));
        let (preview, _) = rawembed::inspect(&write(&d, "bad.cr3", &f)).expect("inspects");
        assert!(preview.is_none(), "a length field of {} names no JPEG", bad);
    }
}

#[test]
fn a_canon_uuid_outside_moov_is_not_read() {
    let d = TestDir::new("rawtoplevel");
    let mut f = ftyp();
    f.extend_from_slice(&uuid(&MOOV, &thmb(&jpeg(160, 120))));
    let (preview, facts) = rawembed::inspect(&write(&d, "top.cr3", &f)).expect("inspects");
    assert!(preview.is_none(), "the Canon uuid lives inside moov");
    assert!(facts.make.is_none());
}

#[test]
fn a_non_crx_brand_is_not_a_cr3() {
    let d = TestDir::new("rawisom");
    let mut f = bx(b"ftyp", b"isom\0\0\0\0\0\0\0\0");
    f.extend_from_slice(&prvw_box(&jpeg(640, 480)));
    let p = write(&d, "a.cr3", &f);
    assert!(rawembed::inspect(&p).is_none(), "an isom file is refused, not misread");
}

#[test]
fn truncated_boxes_never_panic_and_a_largesize_box_walks() {
    let d = TestDir::new("rawboxtrunc");
    let big = jpeg(640, 480);
    let full = cr3(&big, &jpeg(80, 60), &tiff(&[(0x010F, 2, b"C\0")]), &tiff(&[]));
    for cut in (0..full.len()).step_by(16) {
        let p = write(&d, &format!("cut{}.cr3", cut), &full[..cut]);
        let _ = rawembed::inspect(&p);
    }
    // size == 1 names a 64-bit largesize; the walk takes it rather than stopping.
    let mut u = PRVW.to_vec();
    u.extend_from_slice(&prvw_payload(&big));
    let mut f = ftyp();
    f.extend_from_slice(&1u32.to_be_bytes());
    f.extend_from_slice(b"uuid");
    f.extend_from_slice(&(u.len() as u64 + 16).to_be_bytes());
    f.extend_from_slice(&u);
    let p = write(&d, "large.cr3", &f);
    let (preview, _) = rawembed::inspect(&p).expect("a largesize PRVW walks");
    assert_eq!(preview.map(|v| v.width), Some(640));
}
