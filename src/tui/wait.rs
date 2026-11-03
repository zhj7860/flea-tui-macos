// How long the TUI loop waits for a key before it draws again, and when a held Escape byte becomes the Escape key.

// The loop's longest wait for a key, and how long a lone Escape waits for the rest of a sequence.
const INPUT_TIMEOUT_MS: i32 = 100;

// FLEA_TUI_INPUT_TIMEOUT_MS lengthens the wait for tests/tui-wake.sh, so a backend event that does not wake the loop shows.
pub(super) fn input_timeout() -> std::time::Duration {
    let ms = std::env::var("FLEA_TUI_INPUT_TIMEOUT_MS").ok().and_then(|v| v.parse().ok()).filter(|&ms: &u64| ms > 0);
    std::time::Duration::from_millis(ms.unwrap_or(INPUT_TIMEOUT_MS as u64))
}

// A lone Escape is a key only once the timeout passes with no byte behind it, whatever woke the loop.
pub(super) fn escape_due(read_nothing: bool, since_input: std::time::Duration, timeout: std::time::Duration) -> bool {
    read_nothing && since_input >= timeout
}

// The poll's wait: the whole timeout, or only what is left of it while a lone Escape waits, rounded up so it never spins.
pub(super) fn poll_wait_ms(escape_waiting: bool, since_input: std::time::Duration, timeout: std::time::Duration) -> i32 {
    let wait = if escape_waiting { timeout.saturating_sub(since_input) } else { timeout };
    wait.as_micros().div_ceil(1000).min(i32::MAX as u128) as i32
}

#[cfg(test)]
mod tests {
    use super::{escape_due, poll_wait_ms};
    use std::time::Duration;

    const MS: fn(u64) -> Duration = Duration::from_millis;

    #[test]
    fn a_lone_escape_waits_out_the_timeout_whatever_woke_the_loop() {
        // A backend event 10 ms after the Escape byte wakes the loop with nothing read: still not a key.
        assert!(!escape_due(true, MS(10), MS(100)));
        // The rest of a sequence arrived: never a lone Escape, however long ago the last byte was.
        assert!(!escape_due(false, MS(500), MS(100)));
        // A microsecond short is short: the old millisecond count read 99.9 ms as 99 and waited another whole timeout.
        assert!(!escape_due(true, Duration::from_micros(99_999), MS(100)));
        assert!(escape_due(true, MS(100), MS(100)));
    }

    #[test]
    fn a_waiting_escape_polls_only_for_the_time_it_has_left() {
        // Woken 99 ms after the Escape, the loop waits 1 ms more, not another 100.
        assert_eq!(poll_wait_ms(true, MS(99), MS(100)), 1);
        // 99.4 ms rounds the wait up to 1 ms, so the loop sleeps instead of spinning on a 0 ms poll.
        assert_eq!(poll_wait_ms(true, Duration::from_micros(99_400), MS(100)), 1);
        assert_eq!(poll_wait_ms(true, MS(150), MS(100)), 0);
        // With nothing pending the loop waits the whole timeout, however long ago the last key was.
        assert_eq!(poll_wait_ms(false, MS(99), MS(100)), 100);
    }

    #[test]
    fn the_loop_holds_the_decoders_lone_escape_for_the_rest_of_the_timeout() {
        // The loop's own calls on a real decoder: an Escape byte, then a backend wake 99 ms later that reads nothing.
        let mut decoder = super::super::input::Decoder::default();
        assert!(decoder.feed(b"\x1b", escape_due(false, MS(0), MS(100))).is_empty());
        assert_eq!(poll_wait_ms(decoder.waiting(), MS(99), MS(100)), 1);
        assert!(decoder.feed(b"", escape_due(true, MS(99), MS(100))).is_empty());
        assert_eq!(decoder.feed(b"", escape_due(true, MS(100), MS(100))), vec![super::super::input::Key::named("Escape", "")]);
        // The start of a sequence is no lone Escape, so the poll waits the whole timeout for the rest of it.
        assert!(decoder.feed(b"\x1b[1;", false).is_empty());
        assert_eq!(poll_wait_ms(decoder.waiting(), MS(99), MS(100)), 100);
    }
}
