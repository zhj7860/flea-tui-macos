// XXH64 against the published vectors, for the flasher's per-chunk table.

// The five 64-bit primes the xxHash specification names.
const P1: u64 = 0x9E3779B185EBCA87;
const P2: u64 = 0xC2B2AE3D27D4EB4F;
const P3: u64 = 0x165667B19E3779F9;
const P4: u64 = 0x85EBCA77C2B2AE63;
const P5: u64 = 0x27D4EB2F165667C5;
// 32 bytes, the four-lane stripe the loop consumes.
const STRIPE: usize = 32;
// 8 bytes, one lane.
const LANE: usize = 8;
// 4 bytes, the half lane the tail takes after the whole lanes.
const HALF_LANE: usize = 4;
// The rotations the specification names: a round, the four lanes' convergence, a whole lane, a half lane and a byte.
const ROUND_ROTATE: u32 = 31;
const CONVERGE_ROTATES: [u32; 4] = [1, 7, 12, 18];
const LANE_ROTATE: u32 = 27;
const HALF_LANE_ROTATE: u32 = 23;
const BYTE_ROTATE: u32 = 11;
// The three avalanche shifts: 33, 29 and 32.
const MIX_SHIFT_A: u32 = 33;
const MIX_SHIFT_B: u32 = 29;
const MIX_SHIFT_C: u32 = 32;

// One round of the specification's mixing step.
fn round(acc: u64, lane: u64) -> u64 {
    acc.wrapping_add(lane.wrapping_mul(P2)).rotate_left(ROUND_ROTATE).wrapping_mul(P1)
}

// The merge round that folds one lane back into the accumulator.
fn merge(acc: u64, lane: u64) -> u64 {
    (acc ^ round(0, lane)).wrapping_mul(P1).wrapping_add(P4)
}

// The specification's one-shot hash with seed 0, the only seed this tree uses.
// Sample input: b"abc" answers 0x44bc2cf5ad770999.
pub fn hash(bytes: &[u8]) -> u64 {
    let mut at = 0;
    let mut acc: u64;
    if bytes.len() >= STRIPE {
        let mut v1 = P1.wrapping_add(P2);
        let mut v2 = P2;
        let mut v3 = 0;
        let mut v4 = P1.wrapping_neg();
        while at + STRIPE <= bytes.len() {
            v1 = round(v1, lane_at(bytes, at));
            v2 = round(v2, lane_at(bytes, at + LANE));
            v3 = round(v3, lane_at(bytes, at + 2 * LANE));
            v4 = round(v4, lane_at(bytes, at + 3 * LANE));
            at += STRIPE;
        }
        let [r1, r2, r3, r4] = CONVERGE_ROTATES;
        acc = v1.rotate_left(r1).wrapping_add(v2.rotate_left(r2)).wrapping_add(v3.rotate_left(r3)).wrapping_add(v4.rotate_left(r4));
        acc = merge(merge(merge(merge(acc, v1), v2), v3), v4);
    } else {
        acc = P5;
    }
    acc = acc.wrapping_add(bytes.len() as u64);
    while at + LANE <= bytes.len() {
        acc ^= round(0, lane_at(bytes, at));
        acc = acc.rotate_left(LANE_ROTATE).wrapping_mul(P1).wrapping_add(P4);
        at += LANE;
    }
    if at + HALF_LANE <= bytes.len() {
        let word = u32::from_le_bytes(bytes[at..at + HALF_LANE].try_into().unwrap_or([0; HALF_LANE]));
        acc ^= u64::from(word).wrapping_mul(P1);
        acc = acc.rotate_left(HALF_LANE_ROTATE).wrapping_mul(P2).wrapping_add(P3);
        at += HALF_LANE;
    }
    while at < bytes.len() {
        acc ^= u64::from(bytes[at]).wrapping_mul(P5);
        acc = acc.rotate_left(BYTE_ROTATE).wrapping_mul(P1);
        at += 1;
    }
    acc ^= acc >> MIX_SHIFT_A;
    acc = acc.wrapping_mul(P2);
    acc ^= acc >> MIX_SHIFT_B;
    acc = acc.wrapping_mul(P3);
    acc ^= acc >> MIX_SHIFT_C;
    acc
}

// One little-endian lane starting at a position the caller proved is in bounds.
fn lane_at(bytes: &[u8], at: usize) -> u64 {
    u64::from_le_bytes(bytes[at..at + LANE].try_into().unwrap_or([0; LANE]))
}

#[cfg(test)]
#[path = "xxh64_tests.rs"]
mod tests;
