use super::*;
use crate::backend::testdir::TestDir;

// A GIF of `n` frames: header, a 4 colour global palette, then per frame a graphic control extension and an image block.
fn gif_of(n: usize) -> Vec<u8> {
    let mut g = b"GIF89a".to_vec();
    g.extend_from_slice(&[4, 0, 4, 0, 0x81, 0, 0]);
    g.extend_from_slice(&[0u8; 12]);
    for _ in 0..n {
        g.extend_from_slice(&[0x21, 0xF9, 4, 0, 10, 0, 0, 0]);
        g.extend_from_slice(&[0x2C, 0, 0, 0, 0, 4, 0, 4, 0, 0, 2, 3, 1, 2, 3, 0]);
    }
    g.push(0x3B);
    g
}

fn frames_of(bytes: &[u8]) -> Option<u32> {
    gif_frame_count(&mut BufReader::new(std::io::Cursor::new(bytes)), bytes.len() as u64)
}

#[test]
fn a_gif_counts_one_two_and_twenty_four_frames_without_decoding() {
    assert_eq!(frames_of(&gif_of(1)), Some(1));
    assert_eq!(frames_of(&gif_of(2)), Some(2));
    assert_eq!(frames_of(&gif_of(24)), Some(24));
}

#[test]
fn a_gif_with_a_local_palette_still_counts_its_frames() {
    let mut g = gif_of(0);
    g.pop();
    // A frame whose own 2 colour palette sits between its descriptor and its pixel data.
    g.extend_from_slice(&[0x2C, 0, 0, 0, 0, 4, 0, 4, 0, 0x80, 0, 0, 0, 0xFF, 0xFF, 0xFF, 2, 3, 1, 2, 3, 0, 0x3B]);
    assert_eq!(frames_of(&g), Some(1));
}

#[test]
fn a_truncated_gif_has_no_frame_count() {
    let g = gif_of(3);
    assert_eq!(frames_of(&g[..g.len() - 1]), None, "no trailer");
    assert_eq!(frames_of(&g[..g.len() - 10]), None, "cut inside a frame");
    assert_eq!(frames_of(&g[..20]), None, "cut inside the palette");
    assert_eq!(frames_of(b"GIF89a"), None);
}

#[test]
fn a_sub_block_length_past_the_end_has_no_frame_count() {
    let mut g = gif_of(2);
    // The last frame's pixel data now claims 200 bytes where 5 remain.
    let at = g.len() - 6;
    g[at] = 200;
    assert_eq!(frames_of(&g), None);
}

// A reader that counts the read calls that reach the source underneath the BufReader.
struct Counting<R> {
    inner: R,
    reads: std::rc::Rc<std::cell::Cell<usize>>,
}

impl<R: Read> Read for Counting<R> {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        self.reads.set(self.reads.get() + 1);
        self.inner.read(buf)
    }
}

impl<R: Seek> Seek for Counting<R> {
    fn seek(&mut self, to: SeekFrom) -> std::io::Result<u64> {
        self.inner.seek(to)
    }
}

#[test]
fn many_small_sub_blocks_cost_about_one_read_per_buffer() {
    let mut g = gif_of(0);
    g.pop();
    g.extend_from_slice(&[0x2C, 0, 0, 0, 0, 4, 0, 4, 0, 0, 2]);
    for _ in 0..4000 {
        g.push(255);
        g.extend_from_slice(&[0u8; 255]);
    }
    g.extend_from_slice(&[0, 0x3B]);
    let size = g.len() as u64;
    let reads = std::rc::Rc::new(std::cell::Cell::new(0));
    let mut r = BufReader::new(Counting { inner: std::io::Cursor::new(g), reads: reads.clone() });
    assert_eq!(gif_frame_count(&mut r, size), Some(1));
    // std's BufReader default capacity (sample: 8192 bytes).
    const CAPACITY: u64 = 8192;
    let buffers = size / CAPACITY + 1;
    assert!(reads.get() as u64 <= buffers + 4, "{} source reads for {} bytes, about {} buffers", reads.get(), size, buffers);
}

#[test]
fn a_sub_block_run_past_the_stated_size_stops_reading_at_the_bound() {
    let mut g = gif_of(0);
    g.pop();
    g.extend_from_slice(&[0x2C, 0, 0, 0, 0, 4, 0, 4, 0, 0, 2]);
    for _ in 0..4000 {
        g.push(255);
        g.extend_from_slice(&[0u8; 255]);
    }
    g.extend_from_slice(&[0, 0x3B]);
    // The file is far longer than the size the walk is told, so the bound is the only thing that ends it.
    let reads = std::rc::Rc::new(std::cell::Cell::new(0));
    let mut r = BufReader::new(Counting { inner: std::io::Cursor::new(g), reads: reads.clone() });
    assert_eq!(gif_frame_count(&mut r, 1000), None);
    assert!(reads.get() <= 2, "{} source reads for a walk bounded at 1000 bytes", reads.get());
}

#[test]
fn an_unknown_block_has_no_frame_count() {
    let mut g = gif_of(1);
    let at = g.len() - 1;
    g[at] = 0x55;
    assert_eq!(frames_of(&g), None);
}

#[test]
fn a_gif_longer_than_the_walk_has_no_frame_count() {
    let mut g = gif_of(1);
    g.pop();
    // One more frame whose pixel data runs past the cap in full sub-blocks, then a trailer.
    g.extend_from_slice(&[0x2C, 0, 0, 0, 0, 4, 0, 4, 0, 0, 2]);
    for _ in 0..(GIF_WALK / 256 + 2) {
        g.push(255);
        g.extend_from_slice(&[0u8; 255]);
    }
    g.extend_from_slice(&[0, 0x3B]);
    assert!(g.len() as u64 > GIF_WALK);
    assert_eq!(frames_of(&g), None);
    let d = TestDir::new("imagesizegifcap");
    std::fs::write(d.join("long.gif"), &g).unwrap();
    std::fs::write(d.join("short.gif"), gif_of(24)).unwrap();
    assert_eq!(gif_frames(&d.join("long.gif")), 0);
    assert_eq!(gif_frames(&d.join("short.gif")), 24);
    assert_eq!(gif_frames(&d.join("missing.gif")), 0);
}
