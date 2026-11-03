// Canon CR3 is ISO BMFF: the large JPEG rides in a top-level PRVW uuid box, the CMT TIFFs and the small THMB JPEG in the uuid inside moov.
use crate::backend::rawembed::{Ctx, RawFacts};
use crate::backend::rawtiff;

// Sample input: EA F4 2B 5E 1C 98 4B 88 B9 FB B7 DC 40 6E 4D 16, the PRVW box owner.
const PRVW_UUID: [u8; 16] = [
    0xEA, 0xF4, 0x2B, 0x5E, 0x1C, 0x98, 0x4B, 0x88, 0xB9, 0xFB, 0xB7, 0xDC, 0x40, 0x6E, 0x4D, 0x16,
];
// Sample input: 85 C0 B6 87 82 0F 11 E0 81 11 F4 CE 46 2B 6A 48, the moov box owner.
const MOOV_UUID: [u8; 16] = [
    0x85, 0xC0, 0xB6, 0x87, 0x82, 0x0F, 0x11, 0xE0, 0x81, 0x11, 0xF4, 0xCE, 0x46, 0x2B, 0x6A, 0x48,
];
const MAX_BOXES: u32 = 64;
const MAX_INNER: u32 = 32;
// Sample input after the usertype: 0, 1, PRVW size, "PRVW", 0, u16 1, width, height, u16 1, JPEG length(4), then FF D8.
const PRVW_HEAD: u64 = 32;
const PRVW_TAG_AT: usize = 12;
const PRVW_LEN_AT: usize = 28;
// A THMB payload is u32, width, height, JPEG length(4) and 4 reserved bytes, then the JPEG.
const THMB_HEAD: u64 = 16;
// A plain box header is size(4) and type(4).
const BOX_HEAD: u64 = 8;
// A uuid box names its owner with a usertype of this length right after its header.
const USERTYPE: u64 = 16;
// CMT TIFFs are metadata, so anything larger is a corrupt size, not a directory.
const MAX_CMT: u64 = 262_144;

fn be32(b: &[u8]) -> Option<u32> {
    let s = b.get(0..4)?;
    Some(u32::from_be_bytes([s[0], s[1], s[2], s[3]]))
}

// The PRVW payload names its JPEG length in a header, and the JPEG's bytes stay on disk until validated.
fn prvw(ctx: &mut Ctx, off: u64, len: u64) -> Option<(u64, u64)> {
    if len <= PRVW_HEAD {
        return None;
    }
    let h = ctx.read_at(off, PRVW_HEAD as usize)?;
    if h.get(PRVW_TAG_AT..PRVW_TAG_AT + 4)? != b"PRVW" {
        return None;
    }
    let jl = be32(h.get(PRVW_LEN_AT..)?)? as u64;
    if jl == 0 || jl > len - PRVW_HEAD {
        return None;
    }
    Some((off.checked_add(PRVW_HEAD)?, jl))
}

fn merge(dst: &mut RawFacts, src: RawFacts) {
    if dst.make.is_none() {
        dst.make = src.make;
    }
    if dst.model.is_none() {
        dst.model = src.model;
    }
    if dst.lens.is_none() {
        dst.lens = src.lens;
    }
    if dst.exposure.is_none() {
        dst.exposure = src.exposure;
    }
    if dst.f_number.is_none() {
        dst.f_number = src.f_number;
    }
    if dst.iso.is_none() {
        dst.iso = src.iso;
    }
    if dst.focal_mm.is_none() {
        dst.focal_mm = src.focal_mm;
    }
    if dst.taken.is_none() {
        dst.taken = src.taken;
    }
    if dst.width.is_none() {
        dst.width = src.width;
    }
    if dst.height.is_none() {
        dst.height = src.height;
    }
    if dst.orientation.is_none() {
        dst.orientation = src.orientation;
    }
}

// Sample input: 00 00 00 20 54 48 4D 42 at p, the header of a 32-byte "THMB" box, answered as ("THMB", 32) while it fits before end.
fn child(ctx: &mut Ctx, p: u64, end: u64) -> Option<([u8; 4], u64)> {
    let h = ctx.read_at(p, BOX_HEAD as usize)?;
    let size = be32(&h[0..4])? as u64;
    if size < BOX_HEAD || p.checked_add(size)? > end {
        return None;
    }
    Some(([h[4], h[5], h[6], h[7]], size))
}

// Sample input after the Canon usertype: size(4) "CMT1" TIFF bytes, then size(4) "THMB" 16 header bytes and the JPEG, answered as the CMT facts and the THMB span.
fn canon(ctx: &mut Ctx, off: u64, len: u64, cands: &mut Vec<(u64, u64)>, facts: &mut RawFacts) {
    let end = match off.checked_add(len) {
        Some(e) if e <= ctx.len => e,
        _ => return,
    };
    let mut p = off;
    let mut n = 0u32;
    while p < end && n < MAX_INNER {
        n += 1;
        let Some((kind, size)) = child(ctx, p, end) else {
            break;
        };
        if kind == *b"CMT1" || kind == *b"CMT2" {
            let dl = size - BOX_HEAD;
            if dl > 0 && dl <= MAX_CMT {
                if let Some(b) = ctx.read_blob(p + BOX_HEAD, dl) {
                    // CMT1 is an IFD0 TIFF and CMT2 an EXIF TIFF, which is what their tops are read as.
                    merge(facts, rawtiff::facts_from_slice(&b, kind == *b"CMT2"));
                }
            }
        } else if kind == *b"THMB" && size > BOX_HEAD + THMB_HEAD {
            cands.push((p + BOX_HEAD + THMB_HEAD, size - BOX_HEAD - THMB_HEAD));
        }
        p += size;
    }
}

// Sample input in the moov payload: size(4) "uuid" 85 C0 B6 87 and 12 more usertype bytes, then boxes, answered as those boxes handed to canon.
fn moov(ctx: &mut Ctx, off: u64, len: u64, cands: &mut Vec<(u64, u64)>, facts: &mut RawFacts) {
    let end = match off.checked_add(len) {
        Some(e) if e <= ctx.len => e,
        _ => return,
    };
    let mut p = off;
    let mut n = 0u32;
    while p < end && n < MAX_INNER {
        n += 1;
        let Some((kind, size)) = child(ctx, p, end) else {
            break;
        };
        if kind == *b"uuid" && size >= BOX_HEAD + USERTYPE {
            let Some(ut) = ctx.read_at(p + BOX_HEAD, USERTYPE as usize) else {
                break;
            };
            if ut.as_slice() == MOOV_UUID {
                canon(ctx, p + BOX_HEAD + USERTYPE, size - BOX_HEAD - USERTYPE, cands, facts);
            }
        }
        p += size;
    }
}

pub(crate) fn inspect_file(ctx: &mut Ctx) -> Option<(Vec<(u64, u64)>, RawFacts)> {
    let mut cands = Vec::new();
    let mut facts = RawFacts::default();
    let mut pos = 0u64;
    let mut n = 0u32;
    while pos < ctx.len && n < MAX_BOXES {
        n += 1;
        let Some(h) = ctx.read_at(pos, BOX_HEAD as usize) else {
            break;
        };
        let mut size = be32(&h[0..4])? as u64;
        let mut hlen = BOX_HEAD;
        if size == 1 {
            let Some(e) = ctx.read_at(pos + BOX_HEAD, 8) else {
                break;
            };
            size = u64::from_be_bytes(e[0..8].try_into().ok()?);
            hlen = 16;
        } else if size == 0 {
            size = ctx.len - pos;
        }
        if size < hlen {
            break;
        }
        let end = match pos.checked_add(size) {
            Some(e) if e <= ctx.len => e,
            _ => break,
        };
        let kind = h.get(4..8);
        if kind == Some(b"moov".as_slice()) {
            moov(ctx, pos + hlen, size - hlen, &mut cands, &mut facts);
        } else if kind == Some(b"uuid".as_slice()) && size >= hlen + USERTYPE {
            // A uuid box shorter than its header and usertype holds no payload.
            let Some(ut) = ctx.read_at(pos + hlen, USERTYPE as usize) else {
                break;
            };
            if ut.as_slice() == PRVW_UUID {
                if let Some(c) = prvw(ctx, pos + hlen + USERTYPE, size - hlen - USERTYPE) {
                    cands.push(c);
                }
            }
        }
        if end <= pos {
            break;
        }
        pos = end;
    }
    Some((cands, facts))
}

#[cfg(test)]
#[path = "rawbmff_tests.rs"]
pub(crate) mod tests;
