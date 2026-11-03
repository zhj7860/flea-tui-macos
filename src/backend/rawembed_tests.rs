// Dispatcher and choice tests: extension matching, format routing, the largest-valid rule with its tie-break, and the hostile shapes, end to end.
use super::*;
use crate::backend::rawexif as ex;
use crate::backend::rawtiff::tests::{jpeg, jpeg_sof, pair, strip, write, Ev, Tb};
use crate::backend::testdir::TestDir;

// A TIFF chaining one IFD per JPEG, blobs first and the IFDs last to first so each knows its next; answers the blob offsets too.
fn tiff_chain(blobs: &[&[u8]]) -> (Vec<u8>, Vec<u32>) {
    let mut t = Tb::new(true);
    let offs: Vec<u32> = blobs.iter().map(|b| t.blob(b)).collect();
    let mut next = 0;
    for (off, blob) in offs.iter().zip(blobs).rev() {
        next = t.ifd(pair(*off, blob.len()), next);
    }
    t.set_ifd0(next);
    (t.b, offs)
}

// A TIFF with a single JPEG pair in IFD0: 8 + 2 + 24 + 4 = 38 bytes before the blob.
pub(super) fn tiff_one(off: u32, len: u32) -> Vec<u8> {
    let mut t = Tb::new(true);
    let ifd0 = t.ifd(pair(off, len as usize), 0);
    t.set_ifd0(ifd0);
    t.b
}

// A baseline JPEG buried behind segs 60 KiB APP1 segments, so one validation walks ~segs*60 KiB.
pub(super) fn fat_jpeg(w: u16, h: u16, segs: usize) -> Vec<u8> {
    let mut v = vec![0xFF, 0xD8];
    for _ in 0..segs {
        v.extend_from_slice(&[0xFF, 0xE1]);
        v.extend_from_slice(&60002u16.to_be_bytes());
        v.extend_from_slice(&vec![0u8; 60000]);
    }
    v.extend_from_slice(&[0xFF, 0xC0, 0x00, 0x0B, 0x08]);
    v.extend_from_slice(&h.to_be_bytes());
    v.extend_from_slice(&w.to_be_bytes());
    v.extend_from_slice(&[0x01, 0x01, 0x22, 0x00, 0xFF, 0xD9]);
    v
}

// Five JPEGs that each cost segs x 60 KB of SOF walk, then a huge one riding last; the winner shows whether the huge one was validated.
fn winner_after_five_mediums(d: &TestDir, segs: usize) -> Option<(u32, u32)> {
    let med = fat_jpeg(320, 240, segs);
    let huge = jpeg(640, 480);
    let blobs: [&[u8]; 6] = [&med, &med, &med, &med, &med, &huge];
    let p = write(d, "budget.cr2", &tiff_chain(&blobs).0);
    inspect(&p).expect("inspects").0.map(|v| (v.width, v.height))
}

#[test]
fn sof_validation_stops_when_the_mib_is_spent() {
    let d = TestDir::new("rawsofbudget");
    // The control: five cheap walks leave the budget alone, so the sixth candidate is reached and wins on pixels.
    assert_eq!(winner_after_five_mediums(&d, 1), Some((640, 480)));
    // Four walks of ~240 KiB stay under the 1 MiB, the fifth runs out before its SOF, and nothing is left for the huge one.
    assert_eq!(winner_after_five_mediums(&d, 4), Some((320, 240)));
}

#[test]
fn extensions_match_case_insensitively_on_the_basename() {
    for good in ["a.cr2", "A.CR3", "x.nef", "x.NRW", "x.arw", "x.sr2", "x.srf", "x.dng", "x.raf", "x.orf", "x.rw2", "x.pef", "/tmp/dir/a.DNG"] {
        assert!(is_raw_name(good), "{}", good);
    }
    for bad in ["a.jpg", "a.tif", "a.cr2x", "noext", "", "a.", ".cr2.bak", "cr2"] {
        assert!(!is_raw_name(bad), "{}", bad);
    }
}

#[test]
fn the_largest_valid_preview_wins_and_length_breaks_ties() {
    let d = TestDir::new("rawchoice");
    let small = jpeg(160, 120);
    let short = jpeg(640, 480);
    // The same pixels with a longer tail, so only the length tells the two apart.
    let mut long = jpeg(640, 480);
    long.extend_from_slice(&[0u8; 64]);
    let junk = vec![7u8; 200];
    // The longer one rides both before and after the shorter, so neither a first-wins nor a last-wins chooser passes.
    let cases: [([&[u8]; 4], usize); 2] = [([&small, &long, &short, &junk], 1), ([&small, &short, &long, &junk], 2)];
    for (n, (blobs, winner)) in cases.iter().enumerate() {
        let (f, offs) = tiff_chain(blobs);
        let p = write(&d, &format!("choice{}.cr2", n), &f);
        let pv = inspect(&p).expect("inspects").0.expect("a valid candidate exists");
        assert_eq!((pv.width, pv.height), (640, 480), "case {}", n);
        assert_eq!(pv.length, long.len() as u64, "case {}: equal pixels break the tie by length", n);
        assert_eq!(pv.offset, offs[*winner] as u64, "case {}", n);
    }
}

#[test]
fn a_non_jpeg_candidate_is_quietly_skipped() {
    let d = TestDir::new("rawnojpeg");
    // One pair pointing at the file's own tail, where the junk starts.
    let mut f = tiff_one(38, 64);
    f.extend_from_slice(&[7u8; 64]);
    let p = write(&d, "junk.cr2", &f);
    let (preview, facts) = inspect(&p).expect("a recognised file inspects");
    assert!(preview.is_none(), "junk bytes are no preview");
    assert_eq!(facts, RawFacts::default());
}

#[test]
fn a_length_past_the_end_of_the_file_is_no_preview_and_a_u64_overflow_is_not_read() {
    let d = TestDir::new("rawpasteof");
    let pic = jpeg(640, 480);
    // The JPEG is whole and in place; only the length field names bytes the file does not hold.
    let with_len = |len: u32| {
        let mut f = tiff_one(38, len);
        f.extend_from_slice(&pic);
        f
    };
    let exact = write(&d, "exact.cr2", &with_len(pic.len() as u32));
    assert!(inspect(&exact).expect("inspects").0.is_some(), "the exact length is a preview");
    for len in [pic.len() as u32 + 1, u32::MAX] {
        let p = write(&d, "past.cr2", &with_len(len));
        assert!(inspect(&p).expect("inspects").0.is_none(), "length {} runs past the end", len);
    }
    // TIFF fields are u32, so only a direct call reaches a sum past u64.
    let mut ctx = Ctx::open(&exact).expect("opens");
    assert_eq!(preview_dims(&mut ctx, u64::MAX - 10, 100), None);
}

#[test]
fn header_reads_are_counted_and_stop_at_one_mib() {
    let d = TestDir::new("rawbudget");
    let p = write(&d, "big.cr2", &vec![0u8; 2 * 1024 * 1024]);
    let mut ctx = Ctx::open(&p).expect("opens");
    assert!(ctx.read_at(0, 600 * 1024).is_some());
    assert!(ctx.read_at(0, 424 * 1024).is_some(), "exactly at the budget still reads");
    assert!(ctx.read_at(0, 1).is_none(), "past it nothing reads, and nothing panics");
    // Blobs ride outside the budget but inside their own cap and the file.
    assert!(ctx.read_blob(0, 262_144).is_some());
    assert!(ctx.read_blob(0, 2 * 1024 * 1024).is_none(), "over the blob cap");
    assert!(ctx.read_blob(u64::MAX - 10, 100).is_none(), "overflow is not a read");
}

#[test]
fn unknown_bytes_empty_and_directories_inspect_to_none() {
    let d = TestDir::new("rawdispatch");
    let png = write(&d, "a.png", &[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0, 1, 2, 3, 4, 5]);
    assert!(inspect(&png).is_none(), "a PNG is not a RAW");
    let txt = d.file("a.txt", "plain text, sixteen+ bytes of it here");
    assert!(inspect(&txt).is_none());
    let empty = write(&d, "empty.cr2", &[]);
    assert!(inspect(&empty).is_none(), "an empty file carries no magic");
    let short = write(&d, "short.cr2", b"II*\x00");
    assert!(inspect(&short).is_none(), "a header fragment is not a TIFF");
}

#[test]
fn a_cr2_shaped_file_prefers_ifd0_and_refuses_sof3() {
    let d = TestDir::new("rawcr2shape");
    let big = jpeg(1620, 1080);
    let small = jpeg(160, 120);
    let raw = jpeg_sof(0xC3, 3000, 2000);
    let mut t = Tb::new(true);
    let bo = t.blob(&big);
    let so = t.blob(&small);
    let ro = t.blob(&raw);
    let i3 = t.ifd(strip(ro, raw.len(), 6), 0);
    let i2 = t.ifd(vec![(0x0100, Ev::T(4, 100))], i3);
    let i1 = t.ifd(pair(so, small.len()), i2);
    let i0 = t.ifd(strip(bo, big.len(), 6), i1);
    t.set_ifd0(i0);
    let p = write(&d, "a.cr2", &t.b);
    let (preview, _) = inspect(&p).expect("inspects");
    let pv = preview.expect("IFD0's preview validates");
    // The SOF3 "raw" claims more pixels, so this also proves the refusal, not just the order.
    assert_eq!((pv.width, pv.height), (1620, 1080));
}

#[test]
fn a_dng_shaped_file_prefers_the_reduced_subifd_over_sof3_raw() {
    let d = TestDir::new("rawdngshape");
    let prev = jpeg(800, 600);
    let raw = jpeg_sof(0xC3, 2000, 1500);
    let flat = vec![9u8; 64];
    let mut t = Tb::new(true);
    let fo = t.blob(&flat);
    let ro = t.blob(&raw);
    let po = t.blob(&prev);
    // NewSubfileType rides along as inert data: the SOF rule alone decides, 0 or 1.
    let mut sub_a = strip(ro, raw.len(), 7);
    sub_a.push((0x00FE, Ev::T(4, 0)));
    let mut sub_b = strip(po, prev.len(), 7);
    sub_b.push((0x00FE, Ev::T(4, 1)));
    let a = t.ifd(sub_a, 0);
    let b = t.ifd(sub_b, 0);
    let mut head = strip(fo, flat.len(), 1);
    head.push((ex::SUB_IFD, Ev::B(4, [a.to_le_bytes(), b.to_le_bytes()].concat())));
    let ifd0 = t.ifd(head, 0);
    t.set_ifd0(ifd0);
    let p = write(&d, "a.dng", &t.b);
    let (preview, _) = inspect(&p).expect("inspects");
    assert_eq!(preview.map(|v| (v.width, v.height)), Some((800, 600)));
}

#[test]
fn a_panasonic_jpgfromraw_over_64_kib_is_a_candidate() {
    let d = TestDir::new("rawrw2big");
    let pic = fat_jpeg(1920, 1080, 2);
    assert!(pic.len() > 65_536, "the fixture is past the value cap");
    let mut t = Tb { b: b"IIU\x00\x08\x00\x00\x00".to_vec(), le: true };
    let i0 = t.ifd(vec![(ex::RW2_JPGFROMRAW, Ev::B(7, pic.clone()))], 0);
    t.set_ifd0(i0);
    let p = write(&d, "big.rw2", &t.b);
    let pv = inspect(&p).expect("inspects").0.expect("a JPEG past the value cap is still the preview");
    assert_eq!((pv.width, pv.height, pv.length), (1920, 1080, pic.len() as u64));
}
