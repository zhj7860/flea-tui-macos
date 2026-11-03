// The camera, lens, exposure and capture time the Properties card names for a photo, read from a bounded head of the file's own EXIF block.
use crate::backend::regfile::open_regular;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

// A string off a camera is data, so it is cut to a line a card can hold.
pub const MAX_TEXT: usize = 120;
// A TIFF-based RAW keeps IFD0 and its Exif IFD near the start; what lies past this is not looked for.
const TIFF_HEAD: u64 = 1 << 20;
// Segments walked in a JPEG, and boxes walked at the top of a CR3, before the file is called one with no EXIF.
const SEGMENT_BUDGET: usize = 64;
const BOX_BUDGET: usize = 32;
// A CR3's moov carries every track's tables; a larger one is not read for three small boxes.
const MOOV_MAX: u64 = 4 << 20;
const APP1: u8 = 0xE1;
const EXIF_MAGIC: &[u8] = b"Exif\0\0";
// The uuid box Canon keeps its CMT1 (IFD0), CMT2 (Exif IFD) and CMT3 (maker note) boxes in.
const CANON_UUID: [u8; 16] = [0x85, 0xc0, 0xb6, 0x87, 0x82, 0x0f, 0x11, 0xe0, 0x81, 0x11, 0xf4, 0xce, 0x46, 0x2b, 0x6a, 0x48];

const TAG_MAKE: u16 = 0x010F;
const TAG_MODEL: u16 = 0x0110;
const TAG_EXIF_IFD: u16 = 0x8769;
const TAG_EXPOSURE_TIME: u16 = 0x829A;
const TAG_F_NUMBER: u16 = 0x829D;
const TAG_ISO: u16 = 0x8827;
const TAG_TAKEN: u16 = 0x9003;
const TAG_LENS_MODEL: u16 = 0xA434;
// Canon's maker note names the lens here when the Exif IFD does not.
const TAG_CANON_LENS: u16 = 0x0095;
const ASCII: u16 = 2;
const SHORT: u16 = 3;
const LONG: u16 = 4;
const RATIONAL: u16 = 5;

#[derive(Default, PartialEq, Debug, Clone)]
pub struct Photo {
    pub make: String,
    pub model: String,
    pub lens: String,
    // Numerator and denominator as the file has them, (0, 0) when it names none.
    pub shutter: (u32, u32),
    pub fnumber: (u32, u32),
    pub iso: u32,
    // EXIF's own stamp, "2026:09:12 18:31:07"; the card turns it into its date form.
    pub taken: String,
}

pub fn read(path: &Path) -> Photo {
    let Some(mut f) = open_regular(path) else { return Photo::default() };
    let mut head = [0u8; 12];
    let mut got = 0;
    while got < head.len() {
        match f.read(&mut head[got..]) {
            Ok(0) | Err(_) => break,
            Ok(n) => got += n,
        }
    }
    let head = &head[..got];
    let found = if head.starts_with(&[0xFF, 0xD8]) {
        jpeg(&mut std::io::BufReader::new(f))
    } else if head.starts_with(b"II*\0") || head.starts_with(b"MM\0*") {
        let mut buf = Vec::new();
        let _ = f.seek(SeekFrom::Start(0));
        f.take(TIFF_HEAD).read_to_end(&mut buf).ok().and_then(|_| photo_from_tiff(&buf))
    } else if head.len() == 12 && &head[4..8] == b"ftyp" && &head[8..12] == b"crx " {
        cr3(&mut f)
    } else {
        None
    };
    found.unwrap_or_default()
}

// Sample input: FF D8 | FF E0 <len> ... | FF E1 <len> "Exif\0\0" <TIFF block> | FF C0 ...; the Exif segment comes before the frame.
fn jpeg<R: Read + Seek>(r: &mut R) -> Option<Photo> {
    r.seek(SeekFrom::Start(2)).ok()?;
    for _ in 0..SEGMENT_BUDGET {
        let mut marker = [0u8; 2];
        r.read_exact(&mut marker).ok()?;
        if marker[0] != 0xFF {
            return None;
        }
        // The stand-alone markers carry no length.
        if marker[1] == 0x01 || (0xD0..=0xD8).contains(&marker[1]) {
            continue;
        }
        // A scan or the end: the entropy-coded data holds no EXIF.
        if marker[1] == 0xDA || marker[1] == 0xD9 {
            return None;
        }
        let mut len = [0u8; 2];
        r.read_exact(&mut len).ok()?;
        let body = u64::from(u16::from_be_bytes(len)).checked_sub(2)?;
        if marker[1] == APP1 {
            let mut segment = vec![0u8; body as usize];
            r.read_exact(&mut segment).ok()?;
            if let Some(tiff) = segment.strip_prefix(EXIF_MAGIC) {
                return photo_from_tiff(tiff);
            }
        } else {
            r.seek(SeekFrom::Current(body as i64)).ok()?;
        }
    }
    None
}

// Sample input: ftyp "crx " | moov { mvhd, uuid CANON_UUID { CNCV, CMT1, CMT2, CMT3 } } | mdat; each box is size(4) type(4) body, size 1 meaning a 64-bit size follows.
fn cr3<R: Read + Seek>(r: &mut R) -> Option<Photo> {
    let mut at = 0u64;
    for _ in 0..BOX_BUDGET {
        r.seek(SeekFrom::Start(at)).ok()?;
        let mut head = [0u8; 16];
        let mut got = 0;
        while got < 8 {
            match r.read(&mut head[got..8]) {
                Ok(0) | Err(_) => return None,
                Ok(n) => got += n,
            }
        }
        let (size, header) = match u32::from_be_bytes([head[0], head[1], head[2], head[3]]) {
            1 => {
                r.read_exact(&mut head[8..16]).ok()?;
                (u64::from_be_bytes(head[8..16].try_into().ok()?), 16)
            }
            0 => return None,
            small => (u64::from(small), 8),
        };
        if size < header {
            return None;
        }
        if &head[4..8] == b"moov" {
            if size - header > MOOV_MAX {
                return None;
            }
            let mut moov = vec![0u8; (size - header) as usize];
            r.read_exact(&mut moov).ok()?;
            return photo_from_canon(&moov);
        }
        at = at.checked_add(size)?;
    }
    None
}

fn photo_from_canon(moov: &[u8]) -> Option<Photo> {
    let canon = boxes(moov).into_iter().find(|(kind, body)| kind == b"uuid" && body.starts_with(&CANON_UUID))?.1;
    let inner = boxes(&canon[CANON_UUID.len()..]);
    let part = |name: &[u8; 4]| inner.iter().find(|(kind, _)| kind == name).and_then(|(_, body)| Tiff::new(body));
    let mut photo = Photo::default();
    if let Some(t) = part(b"CMT1") {
        t.ifd0(&mut photo);
    }
    // CMT2 is the Exif IFD alone, laid out as an IFD0 of its own.
    if let Some(t) = part(b"CMT2") {
        if let Some(at) = t.u32(4) {
            t.exif(at as usize, &mut photo);
        }
    }
    if photo.lens.is_empty() {
        if let Some(t) = part(b"CMT3") {
            photo.lens = t.u32(4).and_then(|at| t.entries(at as usize).find(|e| e.tag == TAG_CANON_LENS)).map(|e| t.text(&e)).unwrap_or_default();
        }
    }
    Some(photo)
}

// The boxes laid end to end in a body; a size that overruns, or is too small to hold its header, ends the list.
fn boxes(mut b: &[u8]) -> Vec<([u8; 4], &[u8])> {
    let mut out = Vec::new();
    while b.len() >= 8 {
        let size = u32::from_be_bytes([b[0], b[1], b[2], b[3]]) as usize;
        let (size, header) = if size == 1 {
            match b.get(8..16).map(|s| u64::from_be_bytes(s.try_into().unwrap())) {
                Some(big) => (big as usize, 16),
                None => break,
            }
        } else if size == 0 {
            (b.len(), 8)
        } else {
            (size, 8)
        };
        if size < header || size > b.len() {
            break;
        }
        out.push(([b[4], b[5], b[6], b[7]], &b[header..size]));
        b = &b[size..];
    }
    out
}

fn photo_from_tiff(b: &[u8]) -> Option<Photo> {
    let t = Tiff::new(b)?;
    let mut photo = Photo::default();
    t.ifd0_at(t.u32(4)? as usize, &mut photo);
    Some(photo)
}

struct Tiff<'a> {
    b: &'a [u8],
    little: bool,
}

struct Entry {
    tag: u16,
    ty: u16,
    count: u32,
    // Where the entry's 4-byte value field sits.
    at: usize,
}

impl<'a> Tiff<'a> {
    // Sample input: "II" 2A 00 | IFD0 offset(4), or "MM" 00 2A with big-endian numbers.
    fn new(b: &'a [u8]) -> Option<Self> {
        let little = match b.get(0..2)? {
            b"II" => true,
            b"MM" => false,
            _ => return None,
        };
        let t = Tiff { b, little };
        (t.u16(2)? == 42).then_some(t)
    }
    fn u16(&self, at: usize) -> Option<u16> {
        let s = self.b.get(at..at.checked_add(2)?)?;
        Some(if self.little { u16::from_le_bytes([s[0], s[1]]) } else { u16::from_be_bytes([s[0], s[1]]) })
    }
    fn u32(&self, at: usize) -> Option<u32> {
        let s = self.b.get(at..at.checked_add(4)?)?;
        Some(if self.little { u32::from_le_bytes([s[0], s[1], s[2], s[3]]) } else { u32::from_be_bytes([s[0], s[1], s[2], s[3]]) })
    }
    // Sample input at an IFD: count(2) | per entry tag(2) type(2) count(4) value(4). An entry past the block ends the list.
    fn entries(&self, ifd: usize) -> impl Iterator<Item = Entry> + '_ {
        let count = self.u16(ifd).unwrap_or(0) as usize;
        (0..count).map_while(move |i| {
            let at = ifd.checked_add(2 + i * 12)?;
            Some(Entry { tag: self.u16(at)?, ty: self.u16(at + 2)?, count: self.u32(at + 4)?, at: at + 8 })
        })
    }
    // A value of up to four bytes sits in the entry; a longer one sits where the entry points.
    fn data(&self, e: &Entry, len: usize) -> Option<&'a [u8]> {
        let start = if len <= 4 { e.at } else { self.u32(e.at)? as usize };
        self.b.get(start..start.checked_add(len)?)
    }
    fn text(&self, e: &Entry) -> String {
        if e.ty != ASCII {
            return String::new();
        }
        let Some(bytes) = self.data(e, e.count as usize) else { return String::new() };
        let bytes = bytes.split(|b| *b == 0).next().unwrap_or(&[]);
        String::from_utf8_lossy(bytes).chars().map(|c| if c.is_control() { ' ' } else { c }).take(MAX_TEXT + 64).collect::<String>().trim().chars().take(MAX_TEXT).collect()
    }
    fn rational(&self, e: &Entry) -> (u32, u32) {
        if e.ty != RATIONAL || e.count != 1 {
            return (0, 0);
        }
        let at = self.u32(e.at).unwrap_or(0) as usize;
        match (self.u32(at), at.checked_add(4).and_then(|d| self.u32(d))) {
            (Some(n), Some(d)) => (n, d),
            _ => (0, 0),
        }
    }
    fn uint(&self, e: &Entry) -> u32 {
        match e.ty {
            SHORT => self.u16(e.at).unwrap_or(0).into(),
            LONG => self.u32(e.at).unwrap_or(0),
            _ => 0,
        }
    }
    // IFD0 as the file's first directory: the camera, and the pointer to the Exif IFD that holds the rest.
    fn ifd0_at(&self, ifd: usize, photo: &mut Photo) {
        let mut exif = None;
        for e in self.entries(ifd) {
            match e.tag {
                TAG_MAKE => photo.make = self.text(&e),
                TAG_MODEL => photo.model = self.text(&e),
                TAG_EXIF_IFD if e.ty == LONG => exif = self.u32(e.at),
                _ => {}
            }
        }
        if let Some(at) = exif {
            self.exif(at as usize, photo);
        }
    }
    fn ifd0(&self, photo: &mut Photo) {
        if let Some(at) = self.u32(4) {
            self.ifd0_at(at as usize, photo);
        }
    }
    fn exif(&self, ifd: usize, photo: &mut Photo) {
        for e in self.entries(ifd) {
            match e.tag {
                TAG_EXPOSURE_TIME => photo.shutter = self.rational(&e),
                TAG_F_NUMBER => photo.fnumber = self.rational(&e),
                TAG_ISO => photo.iso = self.uint(&e),
                TAG_TAKEN => photo.taken = self.text(&e),
                TAG_LENS_MODEL => photo.lens = self.text(&e),
                _ => {}
            }
        }
    }
}

#[cfg(test)]
#[path = "exiffacts_tests.rs"]
mod tests;
