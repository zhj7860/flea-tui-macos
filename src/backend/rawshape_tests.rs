// One synthetic file per RAW kind, laid out the way the walker reads it, each with the preview it must choose; rawhard_tests.rs sweeps the table.
use crate::backend::rawbmff::tests::{cr3, tiff as cmt_tiff};
use crate::backend::rawembed::{self, Ctx, Preview, RawFacts};
use crate::backend::rawexif as ex;
use crate::backend::rawnote::tests::{aoc_note, nikon_note};
use crate::backend::rawraf::tests::{jpeg_with_app1, raf};
use crate::backend::rawtiff::inspect_file;
use crate::backend::rawtiff::tests::{at, jpeg, jpeg_sof, pair, patch, strip, write, Ev, Tb, PLACE};
use crate::backend::testdir::TestDir;

pub(crate) struct Shape {
    pub kind: &'static str,
    pub bytes: Vec<u8>,
    pub want: Preview,
}

fn shape(kind: &'static str, bytes: Vec<u8>, jpg: &[u8], width: u32, height: u32) -> Shape {
    let want = Preview { offset: at(&bytes, jpg), length: jpg.len() as u64, width, height };
    Shape { kind, bytes, want }
}

fn cat(a: Vec<(u16, Ev)>, b: Vec<(u16, Ev)>) -> Vec<(u16, Ev)> {
    a.into_iter().chain(b).collect()
}

fn text(tag: u16, s: &str) -> (u16, Ev) {
    (tag, Ev::B(2, format!("{}\0", s).into_bytes()))
}

fn cr2() -> Shape {
    let (big, small, raw) = (jpeg(1620, 1080), jpeg(160, 120), jpeg_sof(0xC3, 5184, 3456));
    let mut t = Tb::new(true);
    let (bo, so, ro) = (t.blob(&big), t.blob(&small), t.blob(&raw));
    let i3 = t.ifd(strip(ro, raw.len(), 6), 0);
    let i1 = t.ifd(pair(so, small.len()), i3);
    let i0 = t.ifd(cat(vec![text(ex::MAKE, "Canon")], strip(bo, big.len(), 6)), i1);
    t.set_ifd0(i0);
    shape("cr2", t.b, &big, 1620, 1080)
}

fn cr3_shape() -> Shape {
    let (big, small) = (jpeg(1620, 1080), jpeg(160, 120));
    let cmt1 = cmt_tiff(&[(ex::MAKE, 2, b"Canon\0"), (ex::MODEL, 2, b"EOS R6\0")]);
    shape("cr3", cr3(&big, &small, &cmt1, &cmt_tiff(&[])), &big, 1620, 1080)
}

// Nikon keeps its preview in a SubIFD of a big-endian file, beside a thumbnail IFD1 and a raw SubIFD.
fn nef() -> Shape {
    let (big, thumb) = (jpeg(4608, 3072), jpeg(160, 120));
    let mut t = Tb::new(false);
    let (bo, to) = (t.blob(&big), t.blob(&thumb));
    let preview = t.ifd(pair(bo, big.len()), 0);
    let raw = t.ifd(vec![(0x0100, Ev::T(4, 6048))], 0);
    let i1 = t.ifd(pair(to, thumb.len()), 0);
    let subs = [preview.to_be_bytes(), raw.to_be_bytes()].concat();
    let i0 = t.ifd(vec![text(ex::MAKE, "NIKON CORPORATION"), (ex::SUB_IFD, Ev::B(4, subs))], i1);
    t.set_ifd0(i0);
    shape("nef", t.b, &big, 4608, 3072)
}

// The preview rides in a Nikon MakerNote with its own TIFF header; IFD1 holds only the thumbnail.
fn nrw() -> Shape {
    let (big, thumb) = (jpeg(1600, 1200), jpeg(160, 120));
    let note = nikon_note(true, &[(ex::JPEG_OFF, PLACE), (ex::JPEG_LEN, big.len() as u32)]);
    let mut t = Tb::new(true);
    let exif = t.ifd(vec![(ex::MAKER_NOTE, Ev::B(7, note))], 0);
    let to = t.blob(&thumb);
    let i1 = t.ifd(pair(to, thumb.len()), 0);
    let i0 = t.ifd(
        vec![text(ex::MAKE, "NIKON"), text(ex::MODEL, "COOLPIX A"), (ex::EXIF_IFD_PTR, Ev::T(4, exif))],
        i1,
    );
    t.set_ifd0(i0);
    let bo = t.blob(&big);
    let note_at = at(&t.b, b"Nikon\x00\x02\x10");
    patch(&mut t.b, true, (bo as u64 - (note_at + 10)) as u32);
    shape("nrw", t.b, &big, 1600, 1200)
}

// IFD0 carries a JPEG-compressed strip as the preview, IFD1 the thumbnail, and a SubIFD the raw data.
fn arw() -> Shape {
    let (big, thumb) = (jpeg(1616, 1080), jpeg(160, 120));
    let mut t = Tb::new(true);
    let (bo, to) = (t.blob(&big), t.blob(&thumb));
    let raw = t.ifd(vec![(0x0100, Ev::T(4, 6000))], 0);
    let i1 = t.ifd(pair(to, thumb.len()), 0);
    let head = vec![text(ex::MAKE, "SONY"), text(ex::MODEL, "ILCE-7M3"), (ex::SUB_IFD, Ev::B(4, raw.to_le_bytes().to_vec()))];
    let i0 = t.ifd(cat(head, strip(bo, big.len(), 6)), i1);
    t.set_ifd0(i0);
    shape("arw", t.b, &big, 1616, 1080)
}

// No preview in IFD0 or its SubIFD: the only JPEG is the chained IFD1 pair.
fn sr2() -> Shape {
    let thumb = jpeg(320, 240);
    let mut t = Tb::new(true);
    let to = t.blob(&thumb);
    let raw = t.ifd(vec![(0x0100, Ev::T(4, 3000))], 0);
    let i1 = t.ifd(pair(to, thumb.len()), 0);
    let i0 = t.ifd(
        vec![text(ex::MAKE, "SONY"), text(ex::MODEL, "DSC-R1"), (ex::SUB_IFD, Ev::B(4, raw.to_le_bytes().to_vec()))],
        i1,
    );
    t.set_ifd0(i0);
    shape("sr2", t.b, &thumb, 320, 240)
}

// DNG: IFD0 holds the flat image, one SubIFD the lossless raw (SOF3, refused) and one the reduced preview.
fn dng() -> Shape {
    let (flat, raw, prev) = (vec![9u8; 64], jpeg_sof(0xC3, 2000, 1500), jpeg(800, 600));
    let mut t = Tb::new(true);
    let (fo, ro, po) = (t.blob(&flat), t.blob(&raw), t.blob(&prev));
    let a = t.ifd(strip(ro, raw.len(), 7), 0);
    let b = t.ifd(strip(po, prev.len(), 7), 0);
    let subs = [a.to_le_bytes(), b.to_le_bytes()].concat();
    let i0 = t.ifd(cat(strip(fo, flat.len(), 1), vec![(ex::SUB_IFD, Ev::B(4, subs))]), 0);
    t.set_ifd0(i0);
    shape("dng", t.b, &prev, 800, 600)
}

// Fujifilm: the JPEG offset and length sit at fixed header positions and its APP1 carries the facts.
fn raf_shape() -> Shape {
    let j = jpeg_with_app1(800, 600);
    shape("raf", raf(128, j.len() as u32, &j), &j, 800, 600)
}

fn orf() -> Shape {
    let pic = jpeg(1024, 768);
    let mut t = Tb { b: b"IIRO\x08\x00\x00\x00".to_vec(), le: true };
    let po = t.blob(&pic);
    let i0 = t.ifd(cat(vec![text(ex::MAKE, "OLYMPUS CORPORATION")], pair(po, pic.len())), 0);
    t.set_ifd0(i0);
    shape("orf", t.b, &pic, 1024, 768)
}

// Panasonic stores the JPEG as the bytes of the JpgFromRaw tag.
fn rw2() -> Shape {
    let pic = jpeg(1920, 1080);
    let mut t = Tb { b: b"IIU\x00\x08\x00\x00\x00".to_vec(), le: true };
    let i0 = t.ifd(vec![text(ex::MAKE, "Panasonic"), (ex::RW2_JPGFROMRAW, Ev::B(7, pic.clone()))], 0);
    t.set_ifd0(i0);
    shape("rw2", t.b, &pic, 1920, 1080)
}

// Pentax: a big-endian file with the preview in a SubIFD and a thumbnail in an "AOC" MakerNote.
fn pef() -> Shape {
    let (big, thumb) = (jpeg(1024, 768), jpeg(160, 120));
    let note = aoc_note(false, &[(ex::JPEG_OFF, PLACE), (ex::JPEG_LEN, thumb.len() as u32)]);
    let mut t = Tb::new(false);
    let bo = t.blob(&big);
    let exif = t.ifd(vec![(ex::MAKER_NOTE, Ev::B(7, note))], 0);
    let sub = t.ifd(pair(bo, big.len()), 0);
    let i0 = t.ifd(
        vec![
            text(ex::MAKE, "PENTAX"),
            text(ex::MODEL, "K-3"),
            (ex::SUB_IFD, Ev::B(4, sub.to_be_bytes().to_vec())),
            (ex::EXIF_IFD_PTR, Ev::T(4, exif)),
        ],
        0,
    );
    t.set_ifd0(i0);
    let to = t.blob(&thumb);
    patch(&mut t.b, false, to);
    shape("pef", t.b, &big, 1024, 768)
}

pub(crate) fn shapes() -> Vec<Shape> {
    vec![cr2(), cr3_shape(), nef(), nrw(), arw(), sr2(), dng(), raf_shape(), orf(), rw2(), pef()]
}

fn kind(name: &str) -> Shape {
    shapes().into_iter().find(|s| s.kind == name).expect("a known kind")
}

fn inspected(s: &Shape) -> (Option<Preview>, RawFacts) {
    let d = TestDir::new("rawshape");
    let p = write(&d, &format!("a.{}", s.kind), &s.bytes);
    rawembed::inspect(&p).expect("a shaped file inspects")
}

fn candidates(s: &Shape) -> Vec<(u64, u64)> {
    let d = TestDir::new("rawshapecands");
    let p = write(&d, &format!("a.{}", s.kind), &s.bytes);
    inspect_file(&mut Ctx::open(&p).expect("opens")).expect("a TIFF walks").0
}

#[test]
fn an_nrw_shaped_file_yields_the_note_preview_over_the_chained_thumbnail() {
    let s = kind("nrw");
    let (preview, facts) = inspected(&s);
    assert_eq!(preview, Some(s.want.clone()));
    assert_eq!((s.want.width, s.want.height, s.want.length), (1600, 1200, jpeg(1600, 1200).len() as u64));
    assert_eq!(facts.model.as_deref(), Some("COOLPIX A"));
    assert_eq!(candidates(&s).len(), 2, "the note's pair and IFD1's pair are both collected");
}

#[test]
fn an_arw_shaped_file_yields_the_ifd0_strip_over_the_chained_thumbnail() {
    let s = kind("arw");
    let (preview, facts) = inspected(&s);
    assert_eq!(preview, Some(s.want.clone()));
    assert_eq!((s.want.width, s.want.height, s.want.length), (1616, 1080, jpeg(1616, 1080).len() as u64));
    assert_eq!(facts.model.as_deref(), Some("ILCE-7M3"));
    assert_eq!(candidates(&s).len(), 2, "the strip and IFD1's pair are both collected");
}

#[test]
fn an_sr2_shaped_file_yields_the_chained_ifd_pair_when_it_is_the_only_preview() {
    let s = kind("sr2");
    let (preview, facts) = inspected(&s);
    assert_eq!(preview, Some(s.want.clone()));
    assert_eq!((s.want.width, s.want.height, s.want.length), (320, 240, jpeg(320, 240).len() as u64));
    assert_eq!(facts.model.as_deref(), Some("DSC-R1"));
    assert_eq!(candidates(&s).len(), 1);
}

#[test]
fn a_pef_shaped_file_yields_the_subifd_preview_and_walks_the_aoc_note() {
    let s = kind("pef");
    let (preview, facts) = inspected(&s);
    assert_eq!(preview, Some(s.want.clone()));
    assert_eq!((s.want.width, s.want.height, s.want.length), (1024, 768, jpeg(1024, 768).len() as u64));
    assert_eq!(facts.model.as_deref(), Some("K-3"));
    let thumb = jpeg(160, 120);
    let cands = candidates(&s);
    assert_eq!(cands.len(), 2, "the SubIFD pair and the AOC note's pair");
    assert!(cands.iter().any(|&(off, len)| len == thumb.len() as u64 && off == at(&s.bytes, &thumb)));
}

#[test]
fn every_kind_yields_the_preview_its_shape_names() {
    let all = shapes();
    assert_eq!(all.len(), 11, "CR2 CR3 NEF NRW ARW SR2 DNG RAF ORF RW2 PEF");
    for s in &all {
        assert_eq!(inspected(s).0, Some(s.want.clone()), "{}", s.kind);
    }
}
