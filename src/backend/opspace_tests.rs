// Pace against a model of the card, see ui/js/Transfer.js.
use super::*;
use std::time::Duration;

// ui/js/Transfer.js sampled and itemDone, which is how the card counts what the lines say.
#[derive(Default)]
struct Client {
    index: usize,
    done: usize,
    bytes: u64,
    total: u64,
    moved: u64,
}
impl Client {
    fn sampled(&mut self, index: usize, bytes: u64, total: u64) {
        if index < self.done {
            self.moved += bytes;
        } else {
            (self.index, self.done, self.bytes, self.total) = (index, index, bytes, total);
        }
    }
    // A sample as Pace sends it: the bytes owed first, then the item's own.
    fn heard(&mut self, index: usize, line: Sampled) {
        if let Some((owed_index, _, bytes)) = line.owed {
            self.sampled(owed_index, bytes, 0);
        }
        self.sampled(index, line.bytes, line.total);
    }
    fn item_done(&mut self, index: usize) {
        let sampled = if self.index == index { if self.total > 0 { self.total } else { self.bytes } } else { 0 };
        (self.index, self.done, self.bytes, self.total, self.moved) = (index, index + 1, 0, 0, self.moved + sampled);
    }
    fn shown(&self) -> u64 {
        self.moved + self.bytes
    }
}

#[test]
fn a_thousand_items_inside_one_window_send_one_line_and_the_closing_one() {
    let pace = Pace::new();
    let base = Instant::now();
    let mut sent = Vec::new();
    for index in 0..1000usize {
        let now = base + Duration::from_micros(index as u64 * 100);
        if let Some(line) = pace.sample(now, index, 4096, 4096) {
            assert!(line.owed.is_none());
            sent.push((index, (line.bytes, line.total)));
        }
        pace.ended(index, "f");
    }
    assert_eq!(sent, vec![(0, (4096, 4096))]);
    assert_eq!(pace.take_owed(), Some((999, "f".to_string(), 999 * 4096)));
}

#[test]
fn a_one_gib_item_sends_one_line_per_window() {
    let pace = Pace::new();
    let base = Instant::now();
    let mut sent = 0;
    for step in 1..=1024u64 {
        let now = base + Duration::from_millis(step - 1);
        if let Some(line) = pace.sample(now, 0, step << 20, 1 << 30) {
            sent += 1;
            assert_eq!((line.bytes, line.total), (step << 20, 1 << 30), "a lone item reports its own bytes and total");
            assert!(line.owed.is_none());
        }
    }
    assert_eq!(sent, 7, "samples at 0, 150, 300, 450, 600, 750 and 900 ms");
    pace.ended(0, "big.bin");
    assert_eq!(pace.take_owed(), None, "the item's total was named, so nothing is owed");
}

#[test]
fn the_first_sample_of_a_later_item_waits_for_the_window_and_then_names_what_was_skipped_under_the_item_before() {
    let pace = Pace::new();
    let base = Instant::now();
    assert!(pace.sample(base, 0, 10, 10).is_some());
    pace.ended(0, "a");
    assert!(pace.sample(base + Duration::from_millis(50), 1, 20, 20).is_none());
    pace.ended(1, "b");
    let line = pace.sample(base + Duration::from_millis(150), 2, 5, 40).unwrap();
    assert_eq!(line.owed, Some((1, "b".to_string(), 20)));
    assert_eq!((line.bytes, line.total), (5, 40), "the item keeps its own bytes and total");
}

#[test]
fn a_large_file_after_skipped_ones_keeps_its_total_on_every_line() {
    let pace = Pace::new();
    let (mut client, base) = (Client::default(), Instant::now());
    let big = 4_200_000_000u64;
    for (index, size) in [(0usize, 100u64), (1, 200)] {
        if let Some(line) = pace.sample(base + Duration::from_millis(index as u64 * 10), index, size, size) {
            client.heard(index, line);
        }
        pace.ended(index, "small");
        client.item_done(index);
    }
    for (step, ms) in [(1u64, 150u64), (2, 300), (3, 450)] {
        let line = pace.sample(base + Duration::from_millis(ms), 2, big / 4 * step, big).expect("each window sends a line");
        assert_eq!((line.bytes, line.total), (big / 4 * step, big), "line {step} names the item's own bytes and total");
        assert_eq!(line.owed.is_some(), step == 1, "the bytes owed go out once, on the first line after the skipped item");
        client.heard(2, line);
        assert_eq!(client.total, big, "the card still names the large file's size");
        assert_eq!(client.shown(), 300 + big / 4 * step);
    }
    pace.ended(2, "big.mkv");
    client.item_done(2);
    assert_eq!(client.shown(), 300 + big);
    assert_eq!(pace.take_owed(), None);
}

#[test]
fn the_card_counts_every_byte_whatever_the_window_skipped() {
    let pace = Pace::new();
    let (mut client, mut copied) = (Client::default(), 0u64);
    let base = Instant::now();
    let mut clock = 0u64;
    // Mixed sizes, a few reports per item, and a clock that sometimes stands still for a run of items.
    for index in 0..400usize {
        let size = 1 + (index as u64 * 7919) % 5000;
        for part in 1..=3u64 {
            clock += if index % 40 < 30 { 1 } else { 90 };
            let done = size * part / 3;
            if let Some(line) = pace.sample(base + Duration::from_millis(clock), index, done, size) {
                client.heard(index, line);
                assert_eq!(client.shown(), copied + done, "item {index} part {part}");
            }
        }
        pace.ended(index, "f");
        copied += size;
        client.item_done(index);
        assert!(client.shown() <= copied, "the card never counts more than was copied");
    }
    if let Some((index, _, owed)) = pace.take_owed() {
        assert_eq!(index, 399);
        client.sampled(index, owed, 0);
    }
    assert_eq!(client.shown(), copied);
}

#[test]
fn an_item_that_ends_short_counts_whole_on_both_sides_so_a_later_skipped_item_is_still_reported() {
    let pace = Pace::new();
    let (mut client, base) = (Client::default(), Instant::now());
    let line = pace.sample(base, 0, 10, 100).expect("the first sample goes out at once");
    client.heard(0, line);
    assert!(pace.sample(base + Duration::from_millis(10), 0, 40, 100).is_none());
    pace.ended(0, "a");
    client.item_done(0);
    assert!(pace.sample(base + Duration::from_millis(50), 1, 50, 50).is_none());
    pace.ended(1, "b");
    client.item_done(1);
    let owed = pace.take_owed();
    assert_eq!(owed, Some((1, "b".to_string(), 50)), "the second item's bytes are still owed after the short one");
    client.sampled(1, 50, 0);
    assert_eq!(client.shown(), 100 + 50, "the card shows what an unthrottled one shows");
}

#[test]
fn a_window_after_skipped_items_puts_the_owed_line_on_the_wire_once_beside_the_items_own() {
    let pace = Pace::new();
    let (tx, rx) = std::sync::mpsc::channel();
    let settled = AtomicU64::new(0);
    pace.report(&tx, 1, (0, "a"), (10, 10), &settled);
    pace.ended(0, "a");
    pace.report(&tx, 1, (1, "b"), (10, 10), &settled);
    pace.ended(1, "b");
    std::thread::sleep(PROGRESS_EVERY + Duration::from_millis(20));
    pace.report(&tx, 1, (2, "c"), (10, 10), &settled);
    let lines: Vec<_> = rx.try_iter().map(|m| match m {
        OpMsg::Progress { index, bytes, total, .. } => (index, bytes, total),
        _ => panic!("only progress lines are sent"),
    }).collect();
    assert_eq!(lines, vec![(0, 10, 10), (1, 10, 0), (2, 10, 10)]);
}
