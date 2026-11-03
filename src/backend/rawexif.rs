// EXIF tag numbers and the value decoders every RAW walk shares, because the facts are the same TIFF tags in any container.
use crate::backend::rawtiff::{rd16, rd32, Src};

// A value longer than this is image data or a corrupt count, and no fact needs more.
const MAX_VALUE: u64 = 65_536;
// SubIFD fan-out is capped, so one count cannot queue unbounded work.
pub(crate) const MAX_PTRS: u32 = 64;
pub(crate) const MAKE: u16 = 0x010F;
pub(crate) const MODEL: u16 = 0x0110;
pub(crate) const ORIENTATION: u16 = 0x0112;
pub(crate) const SUB_IFD: u16 = 0x014A;
pub(crate) const EXIF_IFD_PTR: u16 = 0x8769;
pub(crate) const MAKER_NOTE: u16 = 0x927C;
pub(crate) const EXPOSURE: u16 = 0x829A;
pub(crate) const FNUMBER: u16 = 0x829D;
pub(crate) const ISO: u16 = 0x8827;
pub(crate) const ISO_ALT: u16 = 0x8833;
pub(crate) const TAKEN: u16 = 0x9003;
pub(crate) const FOCAL: u16 = 0x920A;
pub(crate) const LENS: u16 = 0xA434;
pub(crate) const PIXEL_X: u16 = 0xA002;
pub(crate) const PIXEL_Y: u16 = 0xA003;
pub(crate) const JPEG_OFF: u16 = 0x0201;
pub(crate) const JPEG_LEN: u16 = 0x0202;
pub(crate) const STRIP_OFF: u16 = 0x0111;
pub(crate) const STRIP_LEN: u16 = 0x0117;
pub(crate) const COMPRESSION: u16 = 0x0103;
pub(crate) const RW2_JPGFROMRAW: u16 = 0x002E;
pub(crate) const OLY_SETTINGS: u16 = 0x2020;
// TIFF types BYTE and UNDEFINED, and the most value bytes an IFD entry holds inline before it holds an offset instead.
pub(crate) const BYTE: u16 = 1;
pub(crate) const UNDEFINED: u16 = 7;
pub(crate) const INLINE_BYTES: u32 = 4;
// Olympus.pm names the preview start and length by these pairs: 0x0088 and 0x1036 in the note's IFD, 0x0101 in the CameraSettings IFD.
pub(crate) const OLY_PAIR_A: (u16, u16) = (0x0088, 0x0089);
pub(crate) const OLY_PAIR_B: (u16, u16) = (0x1036, 0x1037);
pub(crate) const OLY_PAIR_SETTINGS: (u16, u16) = (0x0101, 0x0102);

// A displayed string is short, so anything longer is a corrupt count, not a name.
const MAX_STR: usize = 64;
const IFD_TYPE: u16 = 13;

// Byte size of one TIFF value of this type; TIFF 6.0 section 2 plus type 13, a 4-byte IFD offset (ExifTool Exif.pm formatSize).
pub(crate) fn type_size(typ: u16) -> Option<u64> {
    match typ {
        1 | 2 | 6 | 7 => Some(1),
        3 | 8 => Some(2),
        4 | 9 | 11 | IFD_TYPE => Some(4),
        5 | 10 | 12 => Some(8),
        _ => None,
    }
}

// Some writers type a SubIFD or ExifIFD pointer as 13, which reads as a LONG offset.
fn is_long(typ: u16) -> bool {
    typ == 4 || typ == IFD_TYPE
}

// Sample input: b"Canon\0\0\0  " (NUL-terminated, space-padded) answers "Canon".
pub(crate) fn ascii(bytes: &[u8]) -> String {
    let end = bytes.iter().position(|&b| b == 0).unwrap_or(bytes.len());
    let mut s = String::from_utf8_lossy(&bytes[..end]).into_owned();
    while s.ends_with(' ') || s.ends_with('\t') {
        s.pop();
    }
    if s.len() > MAX_STR {
        let mut i = MAX_STR;
        while !s.is_char_boundary(i) {
            i -= 1;
        }
        s.truncate(i);
    }
    s
}

// Sample input: numerator(4) denominator(4), each in the IFD's byte order.
pub(crate) fn rational(bytes: &[u8], le: bool) -> Option<(u32, u32)> {
    let v = bytes.get(0..8)?;
    let num = if le {
        u32::from_le_bytes([v[0], v[1], v[2], v[3]])
    } else {
        u32::from_be_bytes([v[0], v[1], v[2], v[3]])
    };
    let den = if le {
        u32::from_le_bytes([v[4], v[5], v[6], v[7]])
    } else {
        u32::from_be_bytes([v[4], v[5], v[6], v[7]])
    };
    Some((num, den))
}

// The first value of a SHORT or LONG field, which is how Orientation and ISO are stored.
pub(crate) fn small(bytes: &[u8], typ: u16, le: bool) -> Option<u32> {
    if typ == 3 {
        let v = bytes.get(0..2)?;
        Some(if le {
            u16::from_le_bytes([v[0], v[1]]) as u32
        } else {
            u16::from_be_bytes([v[0], v[1]]) as u32
        })
    } else if is_long(typ) {
        let v = bytes.get(0..4)?;
        Some(if le {
            u32::from_le_bytes([v[0], v[1], v[2], v[3]])
        } else {
            u32::from_be_bytes([v[0], v[1], v[2], v[3]])
        })
    } else {
        None
    }
}

pub(crate) enum Val {
    Inline([u8; 4]),
    At(u64),
}

// The value's bytes, wherever they live: inline in the entry, or at an offset past it.
pub(crate) fn locate(base: u64, le: bool, typ: u16, cnt: u32, val: &[u8]) -> Option<(Val, usize)> {
    let total = type_size(typ)?.checked_mul(cnt as u64)?;
    if total > MAX_VALUE {
        return None;
    }
    if total <= 4 {
        let mut inline = [0u8; 4];
        inline.copy_from_slice(val.get(0..4)?);
        Some((Val::Inline(inline), total as usize))
    } else {
        let off = rd32(val, le)? as u64;
        Some((Val::At(base.checked_add(off)?), total as usize))
    }
}

// A byte blob's span with no MAX_VALUE cap, for a preview the file length bounds; four bytes or fewer ride inline and are too short to be one.
pub(crate) fn blob_at(base: u64, le: bool, cnt: u32, val: &[u8]) -> Option<(u64, u64)> {
    if cnt <= 4 {
        return None;
    }
    Some((base.checked_add(rd32(val, le)? as u64)?, cnt as u64))
}

pub(crate) fn bytes_of<S: Src>(src: &mut S, v: Val, total: usize) -> Option<Vec<u8>> {
    match v {
        Val::Inline(a) => Some(a[..total].to_vec()),
        Val::At(off) => src.get(off, total),
    }
}

// A single SHORT or LONG value; arrays use offsets() instead.
pub(crate) fn one_u32<S: Src>(
    src: &mut S,
    base: u64,
    le: bool,
    typ: u16,
    cnt: u32,
    val: &[u8],
) -> Option<u64> {
    if cnt == 0 || (typ != 3 && !is_long(typ)) {
        return None;
    }
    let (v, total) = locate(base, le, typ, cnt, val)?;
    let b = bytes_of(src, v, total)?;
    small(&b, typ, le).map(u64::from)
}

pub(crate) fn offsets<S: Src>(
    src: &mut S,
    base: u64,
    le: bool,
    typ: u16,
    cnt: u32,
    val: &[u8],
) -> Option<Vec<u64>> {
    if typ != 3 && !is_long(typ) {
        return None;
    }
    let n = (cnt as u64).min(MAX_PTRS as u64) as usize;
    if n == 0 {
        return None;
    }
    let stride = if typ == 3 { 2 } else { 4 };
    let (v, total) = locate(base, le, typ, cnt.min(MAX_PTRS), val)?;
    let b = bytes_of(src, v, total)?;
    let mut out = Vec::with_capacity(n);
    for i in 0..n {
        let piece = b.get(i * stride..i * stride + stride)?;
        // A SHORT offset fills its half; a LONG fills the whole piece.
        out.push(if typ == 3 {
            u64::from(rd16(piece, le)?)
        } else {
            u64::from(rd32(piece, le)?)
        });
    }
    Some(out)
}

pub(crate) fn ascii_of<S: Src>(
    src: &mut S,
    base: u64,
    le: bool,
    typ: u16,
    cnt: u32,
    val: &[u8],
) -> Option<String> {
    if typ != 1 && typ != 2 {
        return None;
    }
    let (v, total) = locate(base, le, typ, cnt, val)?;
    let capped = total.min(MAX_STR);
    let b = match v {
        Val::Inline(a) => a[..capped].to_vec(),
        Val::At(off) => src.get(off, capped)?,
    };
    Some(ascii(&b))
}

pub(crate) fn rational_of<S: Src>(
    src: &mut S,
    base: u64,
    le: bool,
    typ: u16,
    cnt: u32,
    val: &[u8],
) -> Option<(u32, u32)> {
    if typ != 5 || cnt == 0 {
        return None;
    }
    let (v, total) = locate(base, le, typ, cnt, val)?;
    if total < 8 {
        return None;
    }
    rational(&bytes_of(src, v, total)?, le)
}

#[cfg(test)]
#[path = "rawexif_tests.rs"]
mod tests;
