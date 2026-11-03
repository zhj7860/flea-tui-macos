// XXH64 against vectors this code did not produce: the specification's seed-0 samples and zstd's own frame checksums.
use super::*;

// python-xxhash's README example, a 39-byte input that crosses the stripe loop once while its 7-byte tail takes only the half lane plus 3 bytes.
const README_INPUT: &[u8] = b"Nobody inspects the spammish repetition";
const README_HASH: u64 = 0xfbcea83c8a378bf1;
// The low 32 bits of XXH64 seed 0 over input byte i = (i * 7 + 3) % 256, as zstd --check wrote them into a frame, by length.
const ZSTD_VECTORS: [(usize, u32); 14] = [
    (4, 0x66ee9fda),
    (5, 0xdb7051fe),
    (7, 0x59ce60d8),
    (8, 0xc6f90092),
    (12, 0x33af5133),
    (31, 0xcc4a6119),
    (32, 0xf790fd97),
    (33, 0xba588784),
    (36, 0xcc5e3f7f),
    (39, 0x606e4b37),
    (63, 0x31c7493c),
    (64, 0xf6eeb01f),
    (100, 0x170fe531),
    (4096, 0x432797cc),
];

fn input(len: usize) -> Vec<u8> {
    (0..len).map(|i| ((i * 7 + 3) % 256) as u8).collect()
}

// The specification's own seed-0 sanity vectors.
#[test]
fn the_published_seed_zero_vectors() {
    assert_eq!(hash(b""), 0xef46db3751d8e999);
    assert_eq!(hash(b"a"), 0xd24ec4f1a98c6e5b);
    assert_eq!(hash(b"abc"), 0x44bc2cf5ad770999);
}

#[test]
fn the_readme_vector_holds() {
    assert_eq!(hash(README_INPUT), README_HASH);
}

#[test]
fn every_zstd_frame_checksum_matches() {
    for (len, want) in ZSTD_VECTORS {
        assert_eq!(hash(&input(len)) as u32, want, "length {len}");
    }
}

#[test]
fn a_stripe_boundary_hashes_other_bytes_differently() {
    let body = input(64);
    assert_ne!(hash(&body), hash(&body[1..]));
    assert_ne!(hash(&body[..32]), hash(&body[..33]));
}
