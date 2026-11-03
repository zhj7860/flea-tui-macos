// The flash worker's progress meter: one line per 150 ms, and the permille each phase owes.
use crate::backend::flash::{flashprogress_line, permille, PROGRESS_EVERY_MS};
use crate::backend::flashslot::FlashMsg;
use std::sync::mpsc::Sender;
use std::time::{Duration, Instant};

#[cfg(test)]
pub(crate) type Probe<'a> = Box<dyn FnMut(&str, u64) + 'a>;

pub(crate) struct Meter<'a> {
    id: usize,
    tx: &'a Sender<FlashMsg>,
    known: bool,
    total: u64,
    file_bytes: u64,
    last: Instant,
    // A test's probe of every beat, throttled or not: it flips a byte or sets the cancel at a phase.
    #[cfg(test)]
    pub(crate) hook: Option<Probe<'a>>,
}

impl<'a> Meter<'a> {
    pub(crate) fn new(id: usize, tx: &'a Sender<FlashMsg>, known: bool, total: u64, file_bytes: u64) -> Meter<'a> {
        let last = Instant::now().checked_sub(Duration::from_millis(PROGRESS_EVERY_MS)).unwrap_or_else(Instant::now);
        Meter { id, tx, known, total, file_bytes, last, #[cfg(test)] hook: None }
    }

    // The write ended: the written bytes are the size now, so every later phase measures against them.
    pub(crate) fn settle(&mut self, written: u64) {
        self.known = true;
        self.total = written;
    }

    // One progress line, throttled unless forced; input is the consumed compressed offset when the size is unknown.
    pub(crate) fn beat(&mut self, phase: &str, written: u64, input: u64, force: bool) {
        #[cfg(test)]
        if let Some(hook) = self.hook.as_mut() {
            hook(phase, written);
        }
        let now = Instant::now();
        if force || now.duration_since(self.last).as_millis() >= PROGRESS_EVERY_MS as u128 {
            self.last = now;
            let perm = if self.known { permille(written, self.total) } else { permille(input, self.file_bytes) };
            let line = flashprogress_line(self.id, phase, written, self.total, perm);
            let _ = self.tx.send(FlashMsg { id: self.id, line, terminal: false });
        }
    }
}
