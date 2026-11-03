// The progress cadence of one whole operation and the bytes its lines still owe the client, see docs/protocol.md "transferprogress".
use super::{OpMsg, PROGRESS_EVERY};
use std::cell::{Cell, RefCell};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::Sender;
use std::time::Instant;

// What a client counts for an item that ended: the bytes of the items before it that no line of theirs carried.
type Owed = (usize, String, u64);

pub(super) struct Pace {
    last: Cell<Option<Instant>>,
    // The item in flight and the bytes the copy has reported for it, sent or not.
    live: Cell<(usize, u64)>,
    // What finished items copied, and what a client counts from the lines it saw.
    copied: Cell<u64>,
    counted: Cell<u64>,
    // The last line sent for the item in flight: its index and what a client counts from it.
    sent: Cell<Option<(usize, u64)>>,
    // The last item to end, which the bytes owed ride on: the client has closed it, so they join its sum.
    ended: RefCell<Option<(usize, String)>>,
}

pub(super) struct Sampled {
    pub(super) owed: Option<Owed>,
    pub(super) bytes: u64,
    pub(super) total: u64,
}

impl Pace {
    pub(super) fn new() -> Self {
        Pace { last: Cell::new(None), live: Cell::new((usize::MAX, 0)), copied: Cell::new(0), counted: Cell::new(0), sent: Cell::new(None), ended: RefCell::new(None) }
    }

    // One byte report of the item in flight, on the wire when its window is open.
    pub(super) fn report(&self, tx: &Sender<OpMsg>, id: usize, (index, name): (usize, &str), (done, total): (u64, u64), settled: &AtomicU64) {
        let Some(line) = self.sample(now(), index, done, total) else { return };
        let scanned = settled.load(Ordering::Relaxed);
        if let Some((owed_index, owed_name, bytes)) = line.owed {
            let _ = tx.send(OpMsg::Progress { id, index: owed_index, name: owed_name, bytes, total: 0, scanned });
        }
        let _ = tx.send(OpMsg::Progress { id, index, name: name.to_string(), bytes: line.bytes, total: line.total, scanned });
    }

    // The bytes still unreported after the last item go out under that item, ahead of the drive flush the card shows as copied.
    pub(super) fn close(&self, tx: &Sender<OpMsg>, id: usize, settled: &AtomicU64) {
        if let Some((index, name, bytes)) = self.take_owed() {
            let _ = tx.send(OpMsg::Progress { id, index, name, bytes, total: 0, scanned: settled.load(Ordering::Relaxed) });
        }
    }

    // What to put on the wire now, or None while the window is open: the bytes skipped items left unreported go first, under the item that ended last, then the item's own.
    pub(super) fn sample(&self, now: Instant, index: usize, done: u64, total: u64) -> Option<Sampled> {
        self.live.set((index, done));
        if self.last.get().is_some_and(|last| now.saturating_duration_since(last) < PROGRESS_EVERY) {
            return None;
        }
        self.last.set(Some(now));
        let owed = self.take_owed();
        self.sent.set(Some((index, if total > 0 { total } else { done })));
        Some(Sampled { owed, bytes: done, total })
    }

    // The item is over, whatever it ended in: its bytes join the totals on both sides, and a short one counts whole where its line named a total.
    pub(super) fn ended(&self, index: usize, name: &str) {
        let (live, done) = self.live.get();
        let done = if live == index { done } else { 0 };
        let counted = match self.sent.get() {
            Some((sent, counted)) if sent == index => counted,
            _ => 0,
        };
        self.copied.set(self.copied.get() + done.max(counted));
        self.counted.set(self.counted.get() + counted);
        self.sent.set(None);
        self.live.set((usize::MAX, 0));
        *self.ended.borrow_mut() = Some((index, name.to_string()));
    }

    fn take_owed(&self) -> Option<Owed> {
        let owed = self.copied.get().saturating_sub(self.counted.get());
        let (index, name) = self.ended.borrow().clone().filter(|_| owed > 0)?;
        self.counted.set(self.copied.get());
        Some((index, name, owed))
    }
}

// The clock Pace samples; test builds can freeze it, so a test decides which items share a window.
pub(super) fn now() -> Instant {
    #[cfg(test)]
    if let Some(frozen) = FROZEN.with(Cell::get) {
        return frozen;
    }
    Instant::now()
}

#[cfg(test)]
thread_local! {
    static FROZEN: Cell<Option<Instant>> = const { Cell::new(None) };
}
// Unfrozen on drop, so a failing test never freezes the next one on its thread.
#[cfg(test)]
pub(crate) struct FrozenClock;
#[cfg(test)]
impl FrozenClock {
    pub(crate) fn hold() -> Self {
        FROZEN.with(|v| v.set(Some(Instant::now())));
        FrozenClock
    }
}
#[cfg(test)]
impl Drop for FrozenClock {
    fn drop(&mut self) {
        FROZEN.with(|v| v.set(None));
    }
}

#[cfg(test)]
#[path = "opspace_tests.rs"]
mod tests;
