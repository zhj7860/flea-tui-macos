use crate::tui::model::Model;
use std::time::{Duration, Instant};

// Never draw between a listed and its rows: the first paint waits for rows or the 150 ms slow-source cap (ui/js/Swap.js HOLD_MS, the search-mode hold-off).
pub const FIRST_PAINT_MS: u64 = 150;
// The same 150 ms once painted: the TUI hold mirrors Swap.js HOLD_MS, not the 66 ms listing-swap cap Swap.CAP_MS.
pub const HOLD_MS: u64 = 150;

pub struct Hold {
    painted: bool,
    start: Option<Instant>,
    was_pending: bool,
}
impl Hold {
    pub fn new() -> Self {
        Self { painted: false, start: None, was_pending: false }
    }
    pub fn mark_painted(&mut self) {
        self.painted = true;
    }
    // A fresh request starts the cap; landed rows with their peek, or a settled empty directory, end it.
    pub fn sync(&mut self, model: &Model, now: Instant) {
        let pending = model.pending.is_some();
        if pending && !self.was_pending {
            self.start = Some(now);
        }
        if !pending && (!model.rows.is_empty() && !model.peek_out() || model.total == 0 && !model.searching) {
            self.start = None;
        }
        self.was_pending = pending;
    }
    // A text preview is open while the reader still owes the cursor's body (or its error).
    fn preview_open(model: &Model) -> bool {
        model.preview_reader.outstanding(model.preview_generation)
    }
    fn needs(&self, model: &Model) -> bool {
        if model.searching {
            return false;
        }
        let settled_empty = model.rows.is_empty() && model.pending.is_none() && model.total == 0;
        if settled_empty {
            return false;
        }
        let need_rows = model.rows.is_empty();
        // Rows without their parent column are still partial (render.rs draws parents beside them), so an outstanding peek joins the hold.
        let need_peek = model.peek_out();
        // First screen only: the cursor preview body joins under the launch cap.
        let need_preview = !self.painted && Self::preview_open(model);
        need_rows || need_peek || need_preview
    }
    fn cap(&self, launched: Instant) -> Option<Instant> {
        if self.painted {
            self.start.map(|start| start + Duration::from_millis(HOLD_MS))
        } else {
            Some(launched + Duration::from_millis(FIRST_PAINT_MS))
        }
    }
    pub fn hold(&self, model: &Model, now: Instant, launched: Instant) -> bool {
        if !self.needs(model) {
            return false;
        }
        match self.cap(launched) {
            Some(end) => now < end,
            None => false,
        }
    }
    // Wait budget while held: the hold deadline rounded up to a whole millisecond, so no wait ends short of it, else the loop's input wait.
    pub fn wait_ms(&self, model: &Model, now: Instant, launched: Instant, input_wait: i32) -> i32 {
        if !self.needs(model) {
            return input_wait;
        }
        match self.cap(launched) {
            Some(end) if end > now => end.duration_since(now).as_micros().div_ceil(1000).min(input_wait.max(0) as u128) as i32,
            _ => input_wait,
        }
    }
}
