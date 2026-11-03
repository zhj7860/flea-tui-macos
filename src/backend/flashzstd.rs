// A zstd file's unpacked size: the sum of every frame's recorded content size, read as machine fields by bounded preads.
use std::os::unix::fs::FileExt;
use std::path::Path;

const FRAME_MAGIC: [u8; 4] = [0x28, 0xB5, 0x2F, 0xFD];
// Skippable frames carry the magic 0x184D2A50 to 0x184D2A5F, little endian, then a four byte length.
const SKIP_MAGIC_FIRST: u32 = 0x184D_2A50;
const SKIP_MAGIC_LAST: u32 = 0x184D_2A5F;
const SKIP_HEADER_BYTES: u64 = 8;
// Magic, descriptor, window, dictionary id and content size at their longest: 4 + 1 + 1 + 4 + 8.
const HEADER_MAX_BYTES: usize = 18;
const DESCRIPTOR_AT: usize = 4;
// The descriptor byte itself, and the window byte every frame but a single-segment one carries after it.
const DESCRIPTOR_BYTES: usize = 1;
const WINDOW_BYTES: usize = 1;
// Dictionary id widths by the descriptor's two low bits, content size widths by its two top bits.
const DICT_ID_BYTES: [usize; 4] = [0, 1, 2, 4];
const SIZE_FIELD_BYTES: [usize; 4] = [0, 2, 4, 8];
// Size flag 0 still records the size in one byte when the frame is single segment.
const SINGLE_SIZE_BYTES: usize = 1;
// The size flag whose two byte field is stored minus SIZE_BIAS.
const BIASED_SIZE_FLAG: u8 = 1;
// One little endian word, the width of a magic and of a skippable frame's length.
const WORD_BYTES: usize = 4;
// Frame descriptor bits: the content size flag in the top two, single segment, content checksum, the dictionary id flag in the low two.
const SIZE_FLAG_SHIFT: u8 = 6;
const SINGLE_SEGMENT: u8 = 0x20;
const HAS_CHECKSUM: u8 = 0x04;
const DICT_FLAG_MASK: u8 = 0x03;
// A two byte content size is stored minus this much.
const SIZE_BIAS: u64 = 256;
const CHECKSUM_BYTES: u64 = 4;
// A block header is three bytes little endian: bit 0 last, bits 1 and 2 type, the rest the size.
const BLOCK_HEADER_BYTES: u64 = 3;
const BLOCK_LAST: u32 = 1;
const BLOCK_TYPE_SHIFT: u32 = 1;
const BLOCK_TYPE_MASK: u32 = 3;
const BLOCK_SIZE_SHIFT: u32 = 3;
const BLOCK_RAW: u32 = 0;
const BLOCK_RLE: u32 = 1;
const BLOCK_COMPRESSED: u32 = 2;
// A hostile file of tiny blocks cannot keep the probe reading: past this many headers the size is unknown.
const MAX_BLOCK_HEADERS: u32 = 1 << 20;

// One frame header: its length in bytes, the content size it records when it records one, and whether a checksum follows the blocks.
#[derive(Debug, PartialEq)]
pub(crate) struct Header {
    pub len: u64,
    pub content: Option<u64>,
    pub checksum: bool,
}

// Sample header: 28 B5 2F FD 20 05 is magic, descriptor 0x20 (single segment, no checksum) and a one byte size of 5.
pub(crate) fn parse_header(bytes: &[u8]) -> Option<Header> {
    if bytes.len() <= DESCRIPTOR_AT || bytes[..FRAME_MAGIC.len()] != FRAME_MAGIC {
        return None;
    }
    let descriptor = bytes[DESCRIPTOR_AT];
    let single = descriptor & SINGLE_SEGMENT != 0;
    let mut at = DESCRIPTOR_AT + DESCRIPTOR_BYTES + if single { 0 } else { WINDOW_BYTES };
    at += DICT_ID_BYTES[usize::from(descriptor & DICT_FLAG_MASK)];
    let size_flag = descriptor >> SIZE_FLAG_SHIFT;
    let size_len = if size_flag == 0 && single { SINGLE_SIZE_BYTES } else { SIZE_FIELD_BYTES[usize::from(size_flag)] };
    let bias = if size_flag == BIASED_SIZE_FLAG { SIZE_BIAS } else { 0 };
    let field = bytes.get(at..at + size_len)?;
    let content = if size_len == 0 {
        None
    } else {
        let raw = field.iter().rev().fold(0u64, |acc, byte| (acc << u8::BITS) | u64::from(*byte));
        Some(raw.checked_add(bias)?)
    };
    Some(Header { len: (at + size_len) as u64, content, checksum: descriptor & HAS_CHECKSUM != 0 })
}

fn word_at(file: &std::fs::File, at: u64, bytes: usize) -> Option<u32> {
    let mut buf = [0u8; WORD_BYTES];
    file.read_exact_at(&mut buf[..bytes], at).ok()?;
    Some(u32::from_le_bytes(buf))
}

// Sample frame: header 28 B5 2F FD 20 05, block header 29 00 00 (last, raw, 5 bytes), "hello"; it ends 14 bytes on.
fn frame_end(file: &std::fs::File, at: u64, header: &Header, headers_left: &mut u32) -> Option<u64> {
    let mut pos = at.checked_add(header.len)?;
    loop {
        *headers_left = headers_left.checked_sub(1)?;
        let block = word_at(file, pos, BLOCK_HEADER_BYTES as usize)?;
        let size = u64::from(block >> BLOCK_SIZE_SHIFT);
        let stored = match (block >> BLOCK_TYPE_SHIFT) & BLOCK_TYPE_MASK {
            BLOCK_RAW | BLOCK_COMPRESSED => size,
            BLOCK_RLE => 1,
            _ => return None,
        };
        pos = pos.checked_add(BLOCK_HEADER_BYTES)?.checked_add(stored)?;
        if block & BLOCK_LAST != 0 {
            break;
        }
    }
    if header.checksum {
        pos = pos.checked_add(CHECKSUM_BYTES)?;
    }
    Some(pos)
}

// Sums every frame's content size and walks the blocks to find each frame's end; any doubt answers unknown.
pub(crate) fn unpacked_size(path: &Path) -> (u64, bool) {
    sum_frames(path).map_or((0, false), |total| (total, true))
}

// Sample file: a skippable frame 50 2A 4D 18 03 00 00 00 plus 3 bytes, then the "hello" frame above, sums to 5.
fn sum_frames(path: &Path) -> Option<u64> {
    let file = std::fs::File::open(path).ok()?;
    let len = file.metadata().ok()?.len();
    let (mut at, mut total, mut headers_left) = (0u64, 0u64, MAX_BLOCK_HEADERS);
    while at < len {
        let magic = word_at(&file, at, WORD_BYTES)?;
        if (SKIP_MAGIC_FIRST..=SKIP_MAGIC_LAST).contains(&magic) {
            at = at.checked_add(SKIP_HEADER_BYTES)?.checked_add(u64::from(word_at(&file, at + WORD_BYTES as u64, WORD_BYTES)?))?;
        } else {
            let mut head = [0u8; HEADER_MAX_BYTES];
            let got = file.read_at(&mut head, at).ok()?;
            let header = parse_header(&head[..got])?;
            total = total.checked_add(header.content?)?;
            at = frame_end(&file, at, &header, &mut headers_left)?;
        }
        if at > len {
            return None;
        }
    }
    Some(total)
}

#[cfg(test)]
#[path = "flashzstd_tests.rs"]
mod tests;
