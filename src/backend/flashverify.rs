// The verify pass and the wipe, beside the write pipeline.
use crate::backend::flash::{CHUNK_BYTES, CHUNK_COUNT, DIRECT_ALIGN, WIPE_BYTES};
use crate::backend::flashio::{flush, full_pread, write_at, Aligned};
use crate::backend::flashwrite::Fail;
use std::os::fd::AsRawFd;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{channel, Receiver, Sender};

// One read-back chunk on its way to the hasher: its index, its buffer and its written length.
type Slice = (usize, Aligned, usize);

fn drive_ended() -> Fail {
    Fail::Io("the drive ended before the image".to_string())
}

// Reads every written byte back and compares each chunk's XXH64 with the table; total sizes the last chunk.
pub fn verify(dest: &std::fs::File, table: &[u64], total: u64, cancel: &AtomicBool, on_progress: &mut dyn FnMut(u64)) -> Result<(), Fail> {
    let (free_tx, free_rx) = channel::<Aligned>();
    let (work_tx, work_rx) = channel::<Slice>();
    // The pool bounds the memory: the reader waits for a buffer the hasher has finished with.
    for _ in 0..CHUNK_COUNT {
        let _ = free_tx.send(Aligned::new(CHUNK_BYTES));
    }
    std::thread::scope(|scope| {
        // One hasher, in order: it stops at the first chunk that differs and names its index.
        let hasher = scope.spawn(move || {
            for (index, buf, len) in work_rx {
                if crate::backend::xxh64::hash(&buf.view()[..len]) != table[index] {
                    return Some(index);
                }
                if free_tx.send(buf).is_err() {
                    break;
                }
            }
            None
        });
        let read = read_back(dest, table.len(), total, (&free_rx, &work_tx), cancel, on_progress);
        drop(work_tx);
        let bad = hasher.join().map_err(|_| Fail::Io("the hash worker went away".to_string()))?;
        // A difference outranks a cancel or a short read: the bytes already read are known bad.
        match bad {
            Some(index) => Err(Fail::Mismatch((index * CHUNK_BYTES) as u64)),
            None => read,
        }
    })
}

// Reads each chunk into a pool buffer and hands it to the hasher, stopping when the hasher stops.
fn read_back(dest: &std::fs::File, chunks: usize, total: u64, pool: (&Receiver<Aligned>, &Sender<Slice>), cancel: &AtomicBool, on_progress: &mut dyn FnMut(u64)) -> Result<(), Fail> {
    let fd = dest.as_raw_fd();
    let mut read_bytes: u64 = 0;
    for index in 0..chunks {
        if cancel.load(Ordering::Relaxed) {
            return Err(Fail::Cancelled);
        }
        // The last chunk is as long as the write left it, so no zero tail past it is hashed in.
        let want = total.saturating_sub(read_bytes).min(CHUNK_BYTES as u64) as usize;
        if want == 0 {
            return Err(drive_ended());
        }
        // The read is rounded up to a block for O_DIRECT; the hash covers only the written length.
        let padded = want.div_ceil(DIRECT_ALIGN) * DIRECT_ALIGN;
        let Ok(mut buf) = pool.0.recv() else { return Ok(()) };
        let n = full_pread(fd, &mut buf.bytes()[..padded], read_bytes).map_err(|e| Fail::Io(format!("{e} at offset {read_bytes}")))?;
        if n < want {
            return Err(drive_ended());
        }
        pool.1.send((index, buf, want)).map_err(|_| Fail::Io("the hash worker went away".to_string()))?;
        read_bytes += want as u64;
        on_progress(read_bytes);
    }
    Ok(())
}

// Zeroes the first and last MiB and flushes, so a cancelled flash reads as blank, never half bootable.
pub fn wipe_ends(dest: &std::fs::File, drive_bytes: u64) -> bool {
    let zeros = Aligned::new(WIPE_BYTES as usize + DIRECT_ALIGN);
    let first = WIPE_BYTES.min(drive_bytes);
    // The last MiB starts on a block so O_DIRECT takes its offset; a ragged end goes through the buffered flag.
    let block = DIRECT_ALIGN as u64;
    let last_start = drive_bytes.saturating_sub(WIPE_BYTES) / block * block;
    write_at(dest, &zeros.view()[..first as usize], 0).is_ok()
        && write_at(dest, &zeros.view()[..(drive_bytes - last_start) as usize], last_start).is_ok()
        && flush(dest).is_ok()
}

#[cfg(test)]
#[path = "flashverify_tests.rs"]
mod tests;
