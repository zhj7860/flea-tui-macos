// The MakerNote walk: a note is entered only when it opens with a known signature, and the layouts are the vendors' own, not one shared header.
use crate::backend::rawexif as ex;
use crate::backend::rawtiff::{rd16, rd32, walk_ifd, IfdLoc, Oly, Src, Walk};

// A MakerNote signature plus its header fit here; the note's payload is never read whole.
const SIG_WINDOW: usize = 64;
// Sample input: "Nikon\0" 02 10 00 00, then the note's own TIFF header "MM\0*" at +10.
const NIKON_TIFF_AT: u64 = 10;
// Sample input: "OLYMPUS\0" "II" 03 00, then the IFD at +12 with offsets counted from the note's start.
const OLYMPUS_IFD_AT: u64 = 12;
// Sample input: "OM SYSTEM\0" 00 00, "II" 04 00, then the IFD at +16 with offsets counted from the note's start.
const OM_IFD_AT: u64 = 16;
// Sample input: "OLYMP\0" 01 00, then the IFD at +8 in the file's byte order with the file's offsets.
const OLYMP_IFD_AT: u64 = 8;
// Sample input: "AOC\0" "MM", then the IFD at +6 with the file's offsets.
const PENTAX_IFD_AT: u64 = 6;

// Sample input: 49 49 for II (little-endian) or 4D 4D for MM, answered as little-endian or not.
fn order_at(head: &[u8], at: usize) -> Option<bool> {
    match head.get(at..at + 2)? {
        [0x49, 0x49] => Some(true),
        [0x4D, 0x4D] => Some(false),
        _ => None,
    }
}

// An 8-byte TIFF header at this offset, answered with its byte order and first IFD.
fn sub_tiff<S: Src>(src: &mut S, at: u64) -> Option<(bool, u64)> {
    let b = src.get(at, 8)?;
    let le = order_at(&b, 0)?;
    if rd16(b.get(2..4)?, le)? != 42 {
        return None;
    }
    Some((le, rd32(b.get(4..8)?, le)? as u64))
}

// Where a recognised note's first IFD sits: the base its offsets count from, its byte order and the IFD from that base.
fn layout<S: Src>(
    src: &mut S,
    head: &[u8],
    at: u64,
    end: u64,
    loc: &IfdLoc,
) -> Option<(u64, bool, u64, bool)> {
    let file_ifd = |ifd_at: u64| at.checked_add(ifd_at)?.checked_sub(loc.base);
    let (base, le, ifd, olympus) = if head.starts_with(b"Nikon\x00\x02") {
        let sub = at.checked_add(NIKON_TIFF_AT)?;
        if sub.checked_add(8)? > end {
            return None;
        }
        let (le, ifd) = sub_tiff(src, sub)?;
        (sub, le, ifd, false)
    } else if head.starts_with(b"OLYMPUS\x00") {
        (at, order_at(head, 8)?, OLYMPUS_IFD_AT, true)
    } else if head.starts_with(b"OM SYSTEM\x00") {
        (at, order_at(head, 12)?, OM_IFD_AT, true)
    } else if head.starts_with(b"OLYMP\x00") {
        (loc.base, loc.little_endian, file_ifd(OLYMP_IFD_AT)?, true)
    } else if head.starts_with(b"AOC\x00") {
        (loc.base, order_at(head, 4)?, file_ifd(PENTAX_IFD_AT)?, false)
    } else {
        return None;
    };
    // The IFD's entry count must lie inside the note.
    (base.checked_add(ifd)?.checked_add(2)? <= end).then_some((base, le, ifd, olympus))
}

pub(crate) fn makernote<S: Src>(
    src: &mut S,
    w: &mut Walk,
    loc: &IfdLoc,
    typ: u16,
    cnt: u32,
    raw: &[u8],
) -> Option<()> {
    let (v, total) = ex::locate(loc.base, loc.little_endian, typ, cnt, raw)?;
    if total < 12 {
        return Some(());
    }
    let at = match v {
        ex::Val::At(off) => off,
        ex::Val::Inline(_) => return Some(()),
    };
    let end = at.checked_add(total as u64)?;
    let head = src.get(at, total.min(SIG_WINDOW))?;
    let Some((base, le, ifd, olympus)) = layout(src, &head, at, end, loc) else {
        return Some(());
    };
    let child = IfdLoc {
        base,
        little_endian: le,
        depth: loc.depth + 1,
        in_sub_ifd: true,
        index_in_chain: 0,
        is_exif: false,
        olympus: if olympus { Oly::Note } else { Oly::No },
    };
    let _ = walk_ifd(src, w, &child, ifd);
    Some(())
}

#[cfg(test)]
#[path = "rawnote_tests.rs"]
pub(crate) mod tests;
