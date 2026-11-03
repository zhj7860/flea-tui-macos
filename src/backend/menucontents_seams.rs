// What a test holds of the remote walk: a stretch of each stop check and the silence that marks a mount.
#[cfg(test)]
use std::cell::Cell;
use std::time::Duration;

#[cfg(test)]
thread_local! {
    static TEST_PACE: Cell<Option<Duration>> = const { Cell::new(None) };
    static TEST_SILENCE: Cell<Option<Duration>> = const { Cell::new(None) };
}

// Read on the menu thread and moved onto the worker, so holding it never races the walk; production walks unpaced.
#[cfg(test)]
pub(super) fn test_pace() -> Option<Duration> {
    TEST_PACE.with(|slot| slot.get())
}

#[cfg(not(test))]
pub(super) fn test_pace() -> Option<Duration> {
    None
}

// Past the deadline, silence this long marks the mount; production holds the single call bound.
#[cfg(test)]
pub(super) fn stall_silence() -> Duration {
    TEST_SILENCE.with(|slot| slot.get()).unwrap_or(super::super::iomount::CALL_DEADLINE)
}

#[cfg(not(test))]
pub(super) fn stall_silence() -> Duration {
    super::super::iomount::CALL_DEADLINE
}

// Holds one stretch or silence until the guard drops, so one test's slow walk never leaks into the next.
#[cfg(test)]
pub(crate) struct Held(&'static std::thread::LocalKey<Cell<Option<Duration>>>);

#[cfg(test)]
pub(crate) fn test_hold_pace(pace: Duration) -> Held {
    TEST_PACE.with(|slot| slot.set(Some(pace)));
    Held(&TEST_PACE)
}

#[cfg(test)]
pub(crate) fn test_hold_silence(silence: Duration) -> Held {
    TEST_SILENCE.with(|slot| slot.set(Some(silence)));
    Held(&TEST_SILENCE)
}

#[cfg(test)]
impl Drop for Held {
    fn drop(&mut self) {
        self.0.with(|slot| slot.set(None));
    }
}
