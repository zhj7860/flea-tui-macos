// The write pipeline: a reader fills pool buffers from the source and this thread writes each in order.
use crate::backend::flash::{CHUNK_BYTES, CHUNK_COUNT};
use crate::backend::flashio::{no_space, write_at, Aligned};
use crate::backend::flashpipe::input_offset;
use crate::backend::flashwrite::{Fail, Job};
use std::io::Read;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{channel, Receiver, RecvTimeoutError, Sender, TryRecvError};
use std::sync::Arc;
use std::time::{Duration, Instant};

// How often the wait for the next buffer looks at the cancel flag and the stall clock again.
const POLL_STEP: Duration = Duration::from_millis(20);

// Where the bytes come from: a raw image file, or an unpacker's pipe, which is the one that can hang.
pub(crate) struct Feed<'a> {
    pub source: Box<dyn Read + Send>,
    pub unpacker: Option<Unpacker<'a>>,
}

// What a stall is judged by: the pipe's silence and the input offset the unpacker consumes.
pub(crate) struct Unpacker<'a> {
    pub stall: Duration,
    pub input: Option<&'a std::fs::File>,
}

// A filled pool buffer with its byte count, or the reason the source broke.
type Filled = Result<(Aligned, usize), String>;

// What the reader is told when it finds every buffer in use; only a test build listens.
pub(crate) type Starved = Option<Arc<dyn Fn(u64) + Send + Sync>>;

// Fills each free buffer straight from the source and queues it; ends at EOF, a read error or a gone writer.
fn read_loop(mut source: Box<dyn Read + Send>, free: Receiver<Aligned>, full: Sender<Filled>, seen: &AtomicU64, starved: Starved) {
    loop {
        let mut buf = match free.try_recv() {
            Ok(buf) => buf,
            Err(TryRecvError::Disconnected) => return,
            Err(TryRecvError::Empty) => {
                if let Some(hook) = starved.as_ref() {
                    hook(seen.load(Ordering::Relaxed));
                }
                let Ok(buf) = free.recv() else { return };
                buf
            }
        };
        let mut got = 0;
        while got < CHUNK_BYTES {
            match source.read(&mut buf.bytes()[got..]) {
                Ok(0) => break,
                Ok(n) => {
                    got += n;
                    seen.fetch_add(n as u64, Ordering::Relaxed);
                }
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
                Err(e) => {
                    let _ = full.send(Err(e.to_string()));
                    return;
                }
            }
        }
        if got == 0 || full.send(Ok((buf, got))).is_err() || got < CHUNK_BYTES {
            return;
        }
    }
}

// One filled buffer to the drive; a stream past the drive's end stops before the first byte over.
fn place(job: &Job, bytes: &[u8], offset: u64) -> Result<(), Fail> {
    if offset + bytes.len() as u64 > job.drive_bytes {
        return Err(Fail::NoSpace);
    }
    write_at(job.dest, bytes, offset).map_err(|e| if no_space(&e) { Fail::NoSpace } else { Fail::Io(format!("{e} at offset {offset}")) })
}

// Runs the pipeline to its end; a failure leaves the reader behind, so a read hung on a dead mount never holds the answer.
pub(crate) fn drive(feed: Feed, job: &Job, on_progress: &mut dyn FnMut(u64, u64), kill: &mut dyn FnMut()) -> Result<(Vec<u64>, u64), Fail> {
    let (free_tx, free_rx) = channel::<Aligned>();
    let (full_tx, full_rx) = channel::<Filled>();
    // The pool is the whole memory bound: CHUNK_COUNT buffers exist, and the reader waits when all are in use.
    for _ in 0..CHUNK_COUNT {
        let _ = free_tx.send(Aligned::new(CHUNK_BYTES));
    }
    let Feed { source, unpacker } = feed;
    let input = unpacker.as_ref().and_then(|u| u.input);
    let seen = Arc::new(AtomicU64::new(0));
    let reader = {
        let (seen, starved) = (seen.clone(), job.starved_hook());
        std::thread::spawn(move || read_loop(source, free_rx, full_tx, &seen, starved))
    };
    let mut table = Vec::new();
    let mut offset: u64 = 0;
    let mut last_seen = 0;
    let mut last_input = input_offset(input, 0);
    let mut last_move = Instant::now();
    let exit = loop {
        if job.cancel.load(Ordering::Relaxed) {
            break Err(Fail::Cancelled);
        }
        match full_rx.recv_timeout(POLL_STEP) {
            Ok(Ok((buf, len))) => {
                let bytes = &buf.view()[..len];
                if let Err(fail) = place(job, bytes, offset) {
                    break Err(fail);
                }
                table.push(crate::backend::xxh64::hash(bytes));
                offset += len as u64;
                on_progress(offset, input_offset(input, offset));
                // The buffer rejoins the pool only now, so the bound holds while a write or a progress call runs.
                let _ = free_tx.send(buf);
                last_move = Instant::now();
            }
            Ok(Err(e)) => break Err(if unpacker.is_some() { Fail::Decompress(e) } else { Fail::Io(e) }),
            Err(RecvTimeoutError::Disconnected) => break Ok(()),
            Err(RecvTimeoutError::Timeout) => {
                let Some(unpacker) = unpacker.as_ref() else { continue };
                // A stall is silence on both ends: no byte read and the input not moving.
                let (now_seen, now_input) = (seen.load(Ordering::Relaxed), input_offset(input, offset));
                if (now_seen, now_input) != (last_seen, last_input) {
                    (last_seen, last_input) = (now_seen, now_input);
                    last_move = Instant::now();
                }
                if last_move.elapsed() >= unpacker.stall {
                    break Err(Fail::Decompress("the unpacker stalled".to_string()));
                }
            }
        }
    };
    // Both ends of the pool close, so a reader that wakes finds no buffer and no writer and ends on its own.
    drop(full_rx);
    drop(free_tx);
    if exit.is_err() {
        kill();
    } else {
        let _ = reader.join();
    }
    // A stream that ends clean with no bytes wrote nothing, which no flash may call ok.
    exit.and_then(|()| match (offset, unpacker.is_some()) {
        (0, true) => Err(Fail::Decompress("the unpacker produced no bytes".to_string())),
        (0, false) => Err(Fail::Io("the image holds no bytes".to_string())),
        _ => Ok((table, offset)),
    })
}
