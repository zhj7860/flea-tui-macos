// Fujifilm RAF: after 16 magic bytes, a big-endian u32 JPEG offset at 84 and length at 88; the facts ride in that JPEG's APP1 Exif TIFF.
use crate::backend::rawembed::{Ctx, RawFacts, JPEG_PREFIX};
use crate::backend::rawtiff;

// The magic is matched by the dispatcher; the offset below is this module's whole contract.

fn be32(b: &[u8]) -> Option<u32> {
    let s = b.get(0..4)?;
    Some(u32::from_be_bytes([s[0], s[1], s[2], s[3]]))
}

// The APP1 segment starting "Exif\0\0" carries the TIFF; the scan never leaves the prefix.
fn app1_facts(jpeg: &[u8]) -> RawFacts {
    if !jpeg.starts_with(&[0xFF, 0xD8]) || jpeg.len() < 4 {
        return RawFacts::default();
    }
    let mut p = 2usize;
    while p + 4 <= jpeg.len() {
        if jpeg[p] != 0xFF {
            p += 1;
            continue;
        }
        let m = jpeg[p + 1];
        if m == 0xD9 || m == 0xDA {
            break;
        }
        if m == 0x01 || (0xD0..=0xD8).contains(&m) {
            p += 2;
            continue;
        }
        let ln = u16::from_be_bytes([jpeg[p + 2], jpeg[p + 3]]) as usize;
        if ln < 2 || p + 2 + ln > jpeg.len() {
            break;
        }
        if m == 0xE1 {
            let pay = &jpeg[p + 4..p + 2 + ln];
            if pay.starts_with(b"Exif\x00\x00") {
                // A standard Exif block: IFD0 facts plus its own EXIF IFD below it.
                return rawtiff::facts_from_slice(&pay[6..], false);
            }
        }
        p += 2 + ln;
    }
    RawFacts::default()
}

pub(crate) fn inspect_file(ctx: &mut Ctx) -> Option<(Vec<(u64, u64)>, RawFacts)> {
    let b = ctx.read_at(84, 8)?;
    let off = be32(b.get(0..4)?)? as u64;
    let len = be32(b.get(4..8)?)? as u64;
    if len == 0 {
        return Some((Vec::new(), RawFacts::default()));
    }
    if off.checked_add(len)? > ctx.len {
        return None;
    }
    let facts = match ctx.read_blob(off, len.min(JPEG_PREFIX)) {
        Some(prefix) => app1_facts(&prefix),
        None => RawFacts::default(),
    };
    Some((vec![(off, len)], facts))
}

#[cfg(test)]
#[path = "rawraf_tests.rs"]
pub(crate) mod tests;
