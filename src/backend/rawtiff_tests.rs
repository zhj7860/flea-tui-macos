// Synthetic fixtures: a tiny TIFF writer (either endian, chains, SubIFDs, EXIF) and a minimal valid JPEG, so no walk needs a camera file.
use super::*;
use crate::backend::rawembed::{self, Ctx, RawFacts};
use crate::backend::rawexif as ex;
use crate::backend::testdir::TestDir;

fn tsize(t: u16) -> usize {
    match t {
        1 | 2 | 6 | 7 => 1,
        3 | 8 => 2,
        4 | 9 | 11 | 13 => 4,
        _ => 8,
    }
}

pub(crate) enum Ev {
    T(u16, u32),
    B(u16, Vec<u8>),
}

pub(crate) struct Tb {
    pub(crate) b: Vec<u8>,
    pub(crate) le: bool,
}

impl Tb {
    pub(crate) fn new(le: bool) -> Tb {
        let mut b = Vec::new();
        b.extend_from_slice(if le { b"II*\x00" } else { b"MM\x00*" });
        b.extend_from_slice(&[0, 0, 0, 0]);
        Tb { b, le }
    }

    fn w16(&mut self, v: u16) {
        let b = if self.le { v.to_le_bytes() } else { v.to_be_bytes() };
        self.b.extend_from_slice(&b);
    }

    fn w32(&mut self, v: u32) {
        let b = if self.le { v.to_le_bytes() } else { v.to_be_bytes() };
        self.b.extend_from_slice(&b);
    }

    pub(crate) fn blob(&mut self, data: &[u8]) -> u32 {
        let off = self.b.len() as u32;
        self.b.extend_from_slice(data);
        off
    }

    // Appends an IFD and returns its offset; out-of-line values are appended after it.
    pub(crate) fn ifd(&mut self, entries: Vec<(u16, Ev)>, next: u32) -> u32 {
        let off = self.b.len() as u32;
        self.w16(entries.len() as u16);
        let mut patches: Vec<(usize, Vec<u8>)> = Vec::new();
        for (tag, ev) in entries {
            self.w16(tag);
            match ev {
                Ev::T(typ, v) => {
                    self.w16(typ);
                    self.w32(1);
                    if typ == 3 {
                        self.w16(v as u16);
                        self.b.extend_from_slice(&[0, 0]);
                    } else {
                        self.w32(v);
                    }
                }
                Ev::B(typ, data) => {
                    let cnt = (data.len() / tsize(typ)) as u32;
                    self.w16(typ);
                    self.w32(cnt);
                    if data.len() <= 4 {
                        let mut pad = data;
                        pad.resize(4, 0);
                        self.b.extend_from_slice(&pad);
                    } else {
                        patches.push((self.b.len(), data));
                        self.w32(0);
                    }
                }
            }
        }
        self.w32(next);
        for (pos, data) in patches {
            let doff = self.b.len() as u32;
            self.b.extend_from_slice(&data);
            let eb = if self.le { doff.to_le_bytes() } else { doff.to_be_bytes() };
            self.b[pos..pos + 4].copy_from_slice(&eb);
        }
        off
    }

    pub(crate) fn set_ifd0(&mut self, off: u32) {
        let eb = if self.le { off.to_le_bytes() } else { off.to_be_bytes() };
        self.b[4..8].copy_from_slice(&eb);
    }
}

// Sample input: FF D8 | FF E0 len | FF <marker> len precision height(2) width(2) ... | FF D9.
pub(crate) fn jpeg_sof(marker: u8, w: u16, h: u16) -> Vec<u8> {
    let mut v = vec![0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x08, 1, 2, 3, 4, 5, 6];
    v.extend_from_slice(&[0xFF, marker, 0x00, 0x0B, 0x08]);
    v.extend_from_slice(&h.to_be_bytes());
    v.extend_from_slice(&w.to_be_bytes());
    v.extend_from_slice(&[0x01, 0x01, 0x22, 0x00, 0xFF, 0xD9]);
    v
}

pub(crate) fn jpeg(w: u16, h: u16) -> Vec<u8> {
    jpeg_sof(0xC0, w, h)
}

pub(crate) fn write(d: &TestDir, name: &str, bytes: &[u8]) -> std::path::PathBuf {
    let p = d.join(name);
    std::fs::write(&p, bytes).unwrap();
    p
}

pub(crate) fn pair(off: u32, len: usize) -> Vec<(u16, Ev)> {
    vec![(ex::JPEG_OFF, Ev::T(4, off)), (ex::JPEG_LEN, Ev::T(4, len as u32))]
}

pub(crate) fn strip(off: u32, len: usize, compression: u32) -> Vec<(u16, Ev)> {
    vec![
        (ex::STRIP_OFF, Ev::T(4, off)),
        (ex::STRIP_LEN, Ev::T(4, len as u32)),
        (ex::COMPRESSION, Ev::T(3, compression)),
    ]
}

// A byte source that logs every read as (offset, length), so a test can tell a note skipped before a read from one entered and failed.
pub(crate) struct Log<'a> {
    pub(crate) data: &'a [u8],
    pub(crate) reads: Vec<(u64, usize)>,
}

impl Src for Log<'_> {
    fn get(&mut self, off: u64, n: usize) -> Option<Vec<u8>> {
        self.reads.push((off, n));
        let end = off.checked_add(n as u64)?;
        self.data.get(off as usize..end as usize).map(<[u8]>::to_vec)
    }
}

// Where a run of bytes sits in a finished file, so no offset is worked out by hand.
pub(crate) fn at(bytes: &[u8], needle: &[u8]) -> u64 {
    bytes.windows(needle.len()).position(|w| w == needle).expect("the bytes are in the file") as u64
}

// A placeholder a fixture writes where an offset is known only once the layout is fixed.
pub(crate) const PLACE: u32 = 0xDEAD_BEEF;

// Replaces the one placeholder in the file with the offset the finished layout gives it.
pub(crate) fn patch(bytes: &mut [u8], le: bool, value: u32) {
    let from = if le { PLACE.to_le_bytes() } else { PLACE.to_be_bytes() };
    let to = if le { value.to_le_bytes() } else { value.to_be_bytes() };
    let i = at(bytes, &from) as usize;
    bytes[i..i + 4].copy_from_slice(&to);
}

pub(crate) fn ctx_of(p: &std::path::Path) -> Ctx {
    Ctx::open(p).expect("a regular file opens")
}

fn rat(le: bool, num: u32, den: u32) -> Vec<u8> {
    let mut v = Vec::new();
    let (nb, db) = if le {
        (num.to_le_bytes(), den.to_le_bytes())
    } else {
        (num.to_be_bytes(), den.to_be_bytes())
    };
    v.extend_from_slice(&nb);
    v.extend_from_slice(&db);
    v
}

#[test]
fn a_little_endian_tiff_yields_facts_and_its_preview() {
    let d = TestDir::new("rawle");
    let mut t = Tb::new(true);
    let pic = jpeg(640, 480);
    let poff = t.blob(&pic);
    let exif = t.ifd(
        vec![
            (ex::EXPOSURE, Ev::B(5, rat(true, 1, 250))),
            (ex::ISO, Ev::T(3, 200)),
            (ex::TAKEN, Ev::B(2, b"2026:01:02 03:04:05\0".to_vec())),
        ],
        0,
    );
    let ifd0 = t.ifd(
        vec![
            (ex::MAKE, Ev::B(2, b"Canon\0".to_vec())),
            (ex::MODEL, Ev::B(2, b"EOS R5\0".to_vec())),
            (ex::ORIENTATION, Ev::T(3, 6)),
            (ex::EXIF_IFD_PTR, Ev::T(4, exif)),
            (ex::JPEG_OFF, Ev::T(4, poff)),
            (ex::JPEG_LEN, Ev::T(4, pic.len() as u32)),
        ],
        0,
    );
    t.set_ifd0(ifd0);
    let p = write(&d, "a.cr2", &t.b);
    let (cands, facts) = inspect_file(&mut ctx_of(&p)).expect("a valid TIFF walks");
    assert_eq!(cands, vec![(poff as u64, pic.len() as u64)]);
    assert_eq!(facts.make.as_deref(), Some("Canon"));
    assert_eq!(facts.model.as_deref(), Some("EOS R5"));
    assert_eq!(facts.orientation, Some(6));
    assert_eq!(facts.exposure, Some((1, 250)));
    assert_eq!(facts.iso, Some(200));
    assert_eq!(facts.taken.as_deref(), Some("2026:01:02 03:04:05"));
}

#[test]
fn a_big_endian_tiff_walks_the_same_tags() {
    let d = TestDir::new("rawbe");
    let mut t = Tb::new(false);
    let pic = jpeg(320, 200);
    let poff = t.blob(&pic);
    let ifd0 = t.ifd(
        vec![
            (ex::MAKE, Ev::B(2, b"Phase One\0".to_vec())),
            (ex::JPEG_OFF, Ev::T(4, poff)),
            (ex::JPEG_LEN, Ev::T(4, pic.len() as u32)),
        ],
        0,
    );
    t.set_ifd0(ifd0);
    let p = write(&d, "a.nef", &t.b);
    let (cands, facts) = inspect_file(&mut ctx_of(&p)).expect("big-endian walks too");
    assert_eq!(cands.len(), 1);
    assert_eq!(cands[0].0, poff as u64);
    assert_eq!(facts.make.as_deref(), Some("Phase One"));
}

#[test]
fn several_previews_are_all_collected_for_the_chooser() {
    let d = TestDir::new("rawmulti");
    let mut t = Tb::new(true);
    let small = jpeg(160, 120);
    let big = jpeg(800, 600);
    let so = t.blob(&small);
    let bo = t.blob(&big);
    let sub = t.ifd(
        vec![
            (ex::JPEG_OFF, Ev::T(4, bo)),
            (ex::JPEG_LEN, Ev::T(4, big.len() as u32)),
        ],
        0,
    );
    let mut subarr = Vec::new();
    subarr.extend_from_slice(&sub.to_le_bytes());
    let ifd0 = t.ifd(
        vec![
            (ex::JPEG_OFF, Ev::T(4, so)),
            (ex::JPEG_LEN, Ev::T(4, small.len() as u32)),
            (ex::SUB_IFD, Ev::B(4, subarr)),
        ],
        0,
    );
    t.set_ifd0(ifd0);
    let p = write(&d, "a.arw", &t.b);
    let (cands, _) = inspect_file(&mut ctx_of(&p)).expect("walks");
    assert_eq!(cands.len(), 2, "both IFDs contribute, the choice is rawembed's job");
    assert!(cands.contains(&(so as u64, small.len() as u64)));
    assert!(cands.contains(&(bo as u64, big.len() as u64)));
}

#[test]
fn a_jpeg_strip_is_a_preview_in_any_ifd_and_sof3_is_refused() {
    let d = TestDir::new("rawstrip");
    let mut t = Tb::new(true);
    let pic = jpeg(400, 300);
    let po = t.blob(&pic);
    // IFD0, unmarked: Canon CR2 keeps its full-size preview exactly here, so it counts.
    let ifd0 = t.ifd(
        vec![
            (ex::STRIP_OFF, Ev::T(4, po)),
            (ex::STRIP_LEN, Ev::T(4, pic.len() as u32)),
            (ex::COMPRESSION, Ev::T(3, 6)),
        ],
        0,
    );
    t.set_ifd0(ifd0);
    let p = write(&d, "main.dng", &t.b);
    let (cands, _) = inspect_file(&mut ctx_of(&p)).expect("walks");
    assert_eq!(cands.len(), 1);
    // A lossless SOF3 strip is collected as a candidate but refused at the SOF walk.
    let mut t2 = Tb::new(true);
    let raw = jpeg_sof(0xC3, 900, 700);
    let ro = t2.blob(&raw);
    let only = t2.ifd(
        vec![
            (ex::STRIP_OFF, Ev::T(4, ro)),
            (ex::STRIP_LEN, Ev::T(4, raw.len() as u32)),
            (ex::COMPRESSION, Ev::T(3, 6)),
        ],
        0,
    );
    t2.set_ifd0(only);
    let p2 = write(&d, "raw.dng", &t2.b);
    let (cands2, _) = inspect_file(&mut ctx_of(&p2)).expect("walks");
    assert_eq!(cands2.len(), 1, "collected, since the SOF rule is the validator's job");
    let (preview, _) = rawembed::inspect(&p2).expect("inspects");
    assert!(preview.is_none(), "SOF3 is raw sensor data, not a preview");
}

#[test]
fn rw2_jpgfromraw_and_orf_magic_are_walked() {
    let d = TestDir::new("rawrw2");
    let mut b = vec![0u8; 8];
    b[0..4].copy_from_slice(b"IIU\x00");
    b[4..8].copy_from_slice(&8u32.to_le_bytes());
    let mut t = Tb { b, le: true };
    let pic = jpeg(200, 150);
    // JpgFromRaw carries the JPEG bytes in the tag's value area, out of line.
    let ifd0 = t.ifd(vec![(ex::RW2_JPGFROMRAW, Ev::B(7, pic.clone()))], 0);
    t.set_ifd0(ifd0);
    let p = write(&d, "a.rw2", &t.b);
    let (cands, _) = inspect_file(&mut ctx_of(&p)).expect("RW2 walks");
    assert_eq!(cands.len(), 1, "JpgFromRaw contributes its value bytes");
    let bytes = std::fs::read(&p).unwrap();
    assert!(bytes[cands[0].0 as usize..].starts_with(&[0xFF, 0xD8]));
    let mut o = vec![0u8; 8];
    o[0..4].copy_from_slice(b"IIRO");
    o[4..8].copy_from_slice(&8u32.to_le_bytes());
    let mut t2 = Tb { b: o, le: true };
    let i2 = t2.ifd(vec![(ex::MAKE, Ev::B(2, b"OM Digital\0".to_vec()))], 0);
    t2.set_ifd0(i2);
    let p2 = write(&d, "a.orf", &t2.b);
    let (_, facts) = inspect_file(&mut ctx_of(&p2)).expect("ORF walks");
    assert_eq!(facts.make.as_deref(), Some("OM Digital"));
}

#[test]
fn hostile_files_are_none_or_empty_and_never_panic() {
    let d = TestDir::new("rawhostile");
    let mut t = Tb::new(true);
    let pic = jpeg(64, 48);
    let po = t.blob(&pic);
    let ifd0 = t.ifd(
        vec![
            (ex::MAKE, Ev::B(2, b"T\0".to_vec())),
            (ex::JPEG_OFF, Ev::T(4, po)),
            (ex::JPEG_LEN, Ev::T(4, pic.len() as u32)),
        ],
        0,
    );
    t.set_ifd0(ifd0);
    // Truncated at every 8 bytes: no length panics, and the whole file still walks.
    for cut in (0..t.b.len()).step_by(8) {
        let p = write(&d, &format!("cut{}.cr2", cut), &t.b[..cut]);
        let mut ctx = ctx_of(&p);
        let _ = inspect_file(&mut ctx);
    }
    let p = write(&d, "whole.cr2", &t.b);
    assert!(inspect_file(&mut ctx_of(&p)).is_some(), "the uncut file walks");
    // An IFD that points at itself ends at the visited set, not in a loop.
    let mut c = Tb::new(true);
    let cyc = c.ifd(vec![(ex::MAKE, Ev::B(2, b"T\0".to_vec()))], 8);
    c.set_ifd0(cyc);
    let pc = write(&d, "cycle.cr2", &c.b);
    assert!(inspect_file(&mut ctx_of(&pc)).is_some(), "a self-cycle terminates");
    // An empty file and a non-TIFF file walk nothing.
    let pz = write(&d, "empty.cr2", &[]);
    assert!(inspect_file(&mut ctx_of(&pz)).is_none());
    assert_eq!(facts_from_slice(b"not a tiff at all....", false), RawFacts::default());
}

#[test]
fn a_two_ifd_cycle_collects_each_preview_once() {
    let d = TestDir::new("rawcycle2");
    let mut t = Tb::new(true);
    let pic = jpeg(64, 48);
    let po = t.blob(&pic);
    // A holds the pair and B points back at A: without the visited set the pair is collected on every lap.
    let a = t.ifd(
        vec![
            (ex::JPEG_OFF, Ev::T(4, po)),
            (ex::JPEG_LEN, Ev::T(4, pic.len() as u32)),
        ],
        0,
    );
    let b = t.ifd(vec![(ex::MAKE, Ev::B(2, b"B\0".to_vec()))], a);
    let apos = a as usize + 2 + 2 * 12;
    t.b[apos..apos + 4].copy_from_slice(&b.to_le_bytes());
    t.set_ifd0(a);
    let p = write(&d, "cycle2.cr2", &t.b);
    let (cands, _) = inspect_file(&mut ctx_of(&p)).expect("a two-cycle terminates");
    assert_eq!(cands, vec![(po as u64, pic.len() as u64)]);
}
