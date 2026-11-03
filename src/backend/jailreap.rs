// The bounded reap kill_tree ends a jail with: a killed child the kernel holds goes to a thread, so no caller waits on it.
use std::time::Duration;

// A killed child is reaped well inside this; one still unreaped past it is held by the kernel, so a thread takes its wait over.
const REAP_WAIT_MS: u64 = 500;
const REAP_STEP_MS: u64 = 5;

extern "C" {
    fn waitpid(pid: i32, status: *mut i32, options: i32) -> i32;
}

// Reaps a killed child within REAP_WAIT_MS; past that a detached thread owns the blocking wait, so the caller never waits on a child the kernel holds.
pub(crate) fn reap_or_hand_off(child: &mut std::process::Child) {
    for _ in 0..REAP_WAIT_MS / REAP_STEP_MS {
        if reaped(child) {
            return;
        }
        std::thread::sleep(Duration::from_millis(REAP_STEP_MS));
    }
    let pid = child.id() as i32;
    // A failed spawn leaves the zombie until the process exits, which costs less than a pool thread held for good.
    let _ = std::thread::Builder::new().name("flea-jail-reap".to_string()).spawn(move || {
        hold_until_released(pid);
        reap_pid(pid);
    });
}

// Whether the child is reaped or its status can no longer be read; a test hold answers no.
fn reaped(child: &mut std::process::Child) -> bool {
    if held(child.id() as i32) {
        return false;
    }
    matches!(child.try_wait(), Ok(Some(_)) | Err(_))
}

// Blocks until the kernel lets the child go; only EINTR retries.
fn reap_pid(pid: i32) {
    let mut status = 0;
    loop {
        let answer = unsafe { waitpid(pid, &mut status, 0) };
        if answer != -1 || std::io::Error::last_os_error().kind() != std::io::ErrorKind::Interrupted {
            return;
        }
    }
}

// A test holds a reap as an uninterruptible sleep would; production has no hold.
#[cfg(test)]
fn held(pid: i32) -> bool {
    crate::backend::reaphold::is_held(pid)
}

#[cfg(not(test))]
fn held(_pid: i32) -> bool {
    false
}

#[cfg(test)]
fn hold_until_released(pid: i32) {
    crate::backend::reaphold::wait_released(pid);
}

#[cfg(not(test))]
fn hold_until_released(_pid: i32) {}
