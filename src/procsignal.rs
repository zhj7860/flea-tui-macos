// The one place Flea signals a process by pid, refusing any pid <= 1 before the syscall.
use std::io;

extern "C" {
    fn kill(pid: i32, sig: i32) -> i32;
}

fn refuse(pid: i32) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidInput, format!("refusing to signal pid {}", pid))
}

fn send(target: i32, sig: i32) -> io::Result<()> {
    #[cfg(test)]
    if counted() {
        return Ok(());
    }
    if unsafe { kill(target, sig) } != 0 {
        return Err(io::Error::last_os_error());
    }
    Ok(())
}

// Signals every member of the process group `pgid`, which must be a real group leader's pid above 1.
pub fn signal_group(pgid: i32, sig: i32) -> io::Result<()> {
    if pgid <= 1 {
        return Err(refuse(pgid));
    }
    send(-pgid, sig)
}

// Signals one process; signal 0 probes whether it exists. The pid must be above 1.
pub fn signal_process(pid: i32, sig: i32) -> io::Result<()> {
    if pid <= 1 {
        return Err(refuse(pid));
    }
    send(pid, sig)
}

#[cfg(test)]
thread_local! {
    // Set only by the unit test below: while on, this thread's calls are counted and never reach kill(2).
    static DRY: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
    static REACHED: std::cell::Cell<u32> = const { std::cell::Cell::new(0) };
}

// Called right before the syscall; in dry mode it counts the call and tells send() to skip the syscall.
#[cfg(test)]
fn counted() -> bool {
    let dry = DRY.with(|d| d.get());
    if dry {
        REACHED.with(|c| c.set(c.get() + 1));
    }
    dry
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_pid_that_names_every_process_is_refused_before_the_syscall() {
        DRY.with(|d| d.set(true));
        REACHED.with(|c| c.set(0));
        for pid in [0, 1, -1, i32::MIN] {
            for result in [signal_group(pid, 9), signal_process(pid, 9), signal_process(pid, 0)] {
                let error = result.unwrap_err();
                assert_eq!(error.kind(), io::ErrorKind::InvalidInput, "pid {}", pid);
                assert!(error.to_string().contains(&pid.to_string()), "{}", error);
            }
        }
        assert_eq!(REACHED.with(|c| c.get()), 0, "a refused pid must never reach the syscall");
        // The counter moves for a pid that passes, so a zero above is not a dead counter.
        signal_group(2, 9).unwrap();
        signal_process(2, 9).unwrap();
        assert_eq!(REACHED.with(|c| c.get()), 2);
        DRY.with(|d| d.set(false));
    }
}
