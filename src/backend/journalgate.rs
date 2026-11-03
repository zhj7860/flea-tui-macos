// The order entries reach the journal in: the order the operations were accepted, not the order their entries finished.
use super::undo::Entry;

enum Slot {
    // A batch that was accepted and whose entry is still being made.
    Reserved(usize),
    Ready(Entry),
}

// While a reservation is open every entry queues behind it; the leading ready ones flush in queue order.
#[derive(Default)]
pub(crate) struct Gate {
    queue: Vec<Slot>,
}

impl Gate {
    pub(crate) fn reserve(&mut self, id: usize) {
        self.queue.push(Slot::Reserved(id));
    }

    // The entry comes back when no reservation is open, so the caller files it at once.
    pub(crate) fn hold(&mut self, entry: Entry) -> Option<Entry> {
        if self.queue.is_empty() {
            return Some(entry);
        }
        self.queue.push(Slot::Ready(entry));
        None
    }

    // Fills the batch's reservation; an id with none gives the entry back, to be held like any other.
    pub(crate) fn fill(&mut self, id: usize, entry: Entry) -> Option<Entry> {
        match self.queue.iter_mut().find(|slot| matches!(slot, Slot::Reserved(held) if *held == id)) {
            Some(slot) => {
                *slot = Slot::Ready(entry);
                None
            }
            None => Some(entry),
        }
    }

    // A quit whose drain ran out keeps every ready entry, oldest first, and drops the places nothing will fill now.
    pub(crate) fn release(&mut self) -> Vec<Entry> {
        self.queue.drain(..).filter_map(|slot| if let Slot::Ready(entry) = slot { Some(entry) } else { None }).collect()
    }

    // Every ready entry ahead of the first open reservation, oldest first.
    pub(crate) fn flush(&mut self) -> Vec<Entry> {
        let open = self.queue.iter().position(|slot| matches!(slot, Slot::Reserved(_))).unwrap_or(self.queue.len());
        self.queue.drain(..open).filter_map(|slot| if let Slot::Ready(entry) = slot { Some(entry) } else { None }).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(op: &str) -> Entry {
        Entry { op: op.to_string(), steps: Vec::new() }
    }

    fn ops(list: Vec<Entry>) -> Vec<String> {
        list.into_iter().map(|e| e.op).collect()
    }

    #[test]
    fn with_no_reservation_an_entry_passes_straight_through() {
        let mut gate = Gate::default();
        assert_eq!(gate.hold(entry("a")).map(|e| e.op), Some("a".to_string()));
        assert!(gate.flush().is_empty());
    }

    #[test]
    fn an_entry_behind_a_reservation_waits_for_it_and_flushes_in_queue_order() {
        let mut gate = Gate::default();
        gate.reserve(1);
        assert!(gate.hold(entry("rename")).is_none());
        assert!(gate.flush().is_empty(), "the open reservation holds everything behind it");
        assert!(gate.fill(1, entry("trash")).is_none());
        assert_eq!(ops(gate.flush()), ["trash", "rename"]);
        assert!(gate.hold(entry("later")).is_some(), "the gate is closed again once it drained");
    }

    #[test]
    fn a_later_batch_filling_first_waits_for_the_earlier_one() {
        let mut gate = Gate::default();
        gate.reserve(1);
        gate.reserve(2);
        gate.fill(2, entry("b"));
        assert!(gate.flush().is_empty());
        gate.fill(1, entry("a"));
        assert_eq!(ops(gate.flush()), ["a", "b"]);
    }

    #[test]
    fn a_release_keeps_every_ready_entry_in_order_and_drops_the_open_places() {
        let mut gate = Gate::default();
        gate.reserve(1);
        assert!(gate.hold(entry("rename")).is_none());
        gate.reserve(2);
        assert!(gate.hold(entry("mkdir")).is_none());
        assert_eq!(ops(gate.release()), ["rename", "mkdir"]);
        assert!(gate.hold(entry("later")).is_some(), "nothing is left to wait behind");
    }

    #[test]
    fn a_fill_with_no_reservation_gives_the_entry_back() {
        let mut gate = Gate::default();
        assert_eq!(gate.fill(7, entry("x")).map(|e| e.op), Some("x".to_string()));
    }
}
