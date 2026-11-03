// The run child's hardening (R6): no Flea descriptor above fd 2 and none of its private variables reach a program the card starts; terminal::detach keeps the rest.
use std::ffi::OsString;
use std::os::raw::c_int;
use std::os::unix::process::CommandExt;

// Every Flea-private variable starts here; the child keeps PATH, HOME, the session bus and the rest of the operator's environment.
const PRIVATE_ENV_PREFIX: &[u8] = b"FLEA_";

extern "C" {
    fn close_range(first: u32, last: u32, flags: c_int) -> c_int;
    fn fcntl(fd: c_int, cmd: c_int, ...) -> c_int;
}

// Marking every inherited descriptor close-on-exec, never closing any: the error pipe std holds for a failed exec must survive until the exec does. CLOSE_RANGE_CLOEXEC is (1U << 2) in this tree's own headers, linux/close_range.h here.
const CLOSE_RANGE_CLOEXEC: c_int = 4;
const F_SETFD: c_int = 2;
const FD_CLOEXEC: c_int = 1;
// The fallback loop's own upper bound, where close_range is older than kernel 5.9.
const FALLBACK_FD_MAX: c_int = 1024;

// Best effort after the fork: close_range marks all of 3..MAX, and the loop sets the flag one descriptor at a time on older kernels. Either way 0, 1 and 2 survive.
fn close_inherited() -> std::io::Result<()> {
    let marked = unsafe { close_range(3, u32::MAX, CLOSE_RANGE_CLOEXEC) } == 0;
    if !marked {
        let mut fd: c_int = 3;
        while fd < FALLBACK_FD_MAX {
            unsafe {
                fcntl(fd, F_SETFD, FD_CLOEXEC);
            }
            fd += 1;
        }
    }
    Ok(())
}

// Strips the private variables off the spawn and closes every inherited descriptor above 2 in the child; Rust dups 0, 1 and 2 before pre_exec runs, so those survive.
pub fn harden(child: &mut std::process::Command) {
    // An explicitly set private variable goes the same way as an inherited one; whatever is set afterwards stays.
    let explicit: Vec<OsString> = child.get_envs().filter(|(_, value)| value.is_some()).map(|(key, _)| key.to_os_string()).collect();
    for key in private_keys(std::env::vars_os().map(|(key, _)| key), explicit) {
        child.env_remove(key);
    }
    unsafe {
        child.pre_exec(close_inherited);
    }
}

// The private keys among the inherited and the explicitly set ones, the only names harden strips.
pub(crate) fn private_keys(inherited: impl Iterator<Item = OsString>, explicit: Vec<OsString>) -> Vec<OsString> {
    inherited.chain(explicit).filter(|key| key.as_encoded_bytes().starts_with(PRIVATE_ENV_PREFIX)).collect()
}
