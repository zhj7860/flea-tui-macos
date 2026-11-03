// A test holds a child's reap as an uninterruptible sleep would, so a test can prove kill_tree never waits on one.
use std::sync::Mutex;
use std::time::Duration;

static HELD: Mutex<Vec<i32>> = Mutex::new(Vec::new());

// While held, the child reads as unreaped and its reap waits for release.
pub fn hold(pid: i32) {
    HELD.lock().unwrap_or_else(|poisoned| poisoned.into_inner()).push(pid);
}

pub fn release(pid: i32) {
    HELD.lock().unwrap_or_else(|poisoned| poisoned.into_inner()).retain(|&held| held != pid);
}

pub fn is_held(pid: i32) -> bool {
    HELD.lock().unwrap_or_else(|poisoned| poisoned.into_inner()).contains(&pid)
}

// The kernel's hold lasts until the child's sleep ends, so the wait ends only on release.
pub fn wait_released(pid: i32) {
    while is_held(pid) {
        std::thread::sleep(Duration::from_millis(1));
    }
}
