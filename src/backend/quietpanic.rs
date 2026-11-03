// One hook, installed once, keeps the deliberate worker panics quiet, so no test swaps the process-wide hook while others run.
use std::sync::Once;

// What every deliberate test panic says; any other panic still reaches the hook this one wraps.
pub const DELIBERATE: &str = "a decoder died";

pub fn quiet() {
    static INSTALL: Once = Once::new();
    INSTALL.call_once(|| {
        let previous = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            if info.payload_as_str() != Some(DELIBERATE) {
                previous(info);
            }
        }));
    });
}
