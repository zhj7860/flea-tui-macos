//! Darwin stand-ins for the remaining Linux-only libc names used by Flea.
//!
//! The scanner and the watch layer already use `crate::sys`; these symbols are the
//! remaining direct `extern "C"` references. They keep the Linux call sites intact
//! while giving macOS a real implementation where one is meaningful and a safe
//! no-op where the kernel feature does not exist.

#![cfg(target_os = "macos")]

use std::ffi::{c_char, c_int, c_uint, c_ulong, c_void};

const FD_CLOEXEC: c_int = 1;
const F_SETFD: c_int = 2;
const O_NONBLOCK: c_int = 0x0004;
const ENOTSUP: c_int = 45;
const RENAME_EXCL: c_uint = 0x0000_0004;

extern "C" {
    fn __error() -> *mut c_int;
    fn fcntl(fd: c_int, cmd: c_int, ...) -> c_int;
    fn fsync(fd: c_int) -> c_int;
    fn getdtablesize() -> c_int;
    fn pipe(fds: *mut c_int) -> c_int;
    fn rename(old: *const c_char, new: *const c_char) -> c_int;
    fn renamex_np(old: *const c_char, new: *const c_char, flags: c_uint) -> c_int;
    fn sync();
    fn getxattr(
        path: *const c_char,
        name: *const c_char,
        value: *mut c_void,
        size: usize,
        position: u32,
        options: c_int,
    ) -> isize;
    fn setxattr(
        path: *const c_char,
        name: *const c_char,
        value: *const c_void,
        size: usize,
        position: u32,
        options: c_int,
    ) -> c_int;
    fn removexattr(path: *const c_char, name: *const c_char, options: c_int) -> c_int;
}

#[no_mangle]
pub unsafe extern "C" fn __errno_location() -> *mut c_int {
    __error()
}

/// Linux's close_range(CLOEXEC); the loop is the same fallback glibc uses.
#[no_mangle]
pub unsafe extern "C" fn close_range(first: u32, last: u32, flags: c_int) -> c_int {
    let _ = flags;
    let top = getdtablesize().max(3);
    let end = if last == u32::MAX {
        top as u32
    } else {
        last.min(top as u32 - 1)
    };
    let mut fd = first.max(3);
    while fd <= end {
        fcntl(fd as c_int, F_SETFD, FD_CLOEXEC);
        fd += 1;
    }
    0
}

/// pipe2 with the two flags the callers use; macOS has only pipe() plus fcntl().
#[no_mangle]
pub unsafe extern "C" fn pipe2(fds: *mut c_int, flags: c_int) -> c_int {
    if pipe(fds) != 0 {
        return -1;
    }
    if flags & 0o2000000 != 0 {
        fcntl(*fds, F_SETFD, FD_CLOEXEC);
        fcntl(*fds.add(1), F_SETFD, FD_CLOEXEC);
    }
    if flags & 0o4000 != 0 {
        fcntl(*fds, 4, O_NONBLOCK);
        fcntl(*fds.add(1), 4, O_NONBLOCK);
    }
    0
}

/// A wake descriptor is not a single-fd eventfd on Darwin; the TUI's own wake paths
/// use `sys::wake_pair`, while the clipboard owner-end has a harmless disabled path.
#[no_mangle]
pub unsafe extern "C" fn eventfd(_value: u32, _flags: c_int) -> c_int {
    let _ = __error();
    unsafe { *__error() = ENOTSUP };
    -1
}

/// The Linux process-exit descriptor; `crate::sys` provides the kqueue equivalent.
#[cfg(not(test))]
#[no_mangle]
pub unsafe extern "C" fn pidfd_open(pid: c_int, flags: u32) -> c_int {
    crate::sys::pidfd_open(pid, flags)
}

#[no_mangle]
pub unsafe extern "C" fn prctl(
    _option: c_int,
    _a: c_ulong,
    _b: c_ulong,
    _c: c_ulong,
    _d: c_ulong,
) -> c_int {
    0
}

#[no_mangle]
pub unsafe extern "C" fn mallopt(_param: c_int, _value: c_int) -> c_int {
    0
}

#[no_mangle]
pub unsafe extern "C" fn malloc_trim(_pad: usize) -> c_int {
    0
}

#[no_mangle]
pub unsafe extern "C" fn posix_fadvise(
    _fd: c_int,
    _offset: i64,
    _len: i64,
    _advice: c_int,
) -> c_int {
    0
}

#[no_mangle]
pub unsafe extern "C" fn sync_file_range(
    fd: c_int,
    _offset: i64,
    _nbytes: i64,
    _flags: u32,
) -> c_int {
    fsync(fd)
}

#[no_mangle]
pub unsafe extern "C" fn syncfs(_fd: c_int) -> c_int {
    sync();
    0
}

#[no_mangle]
pub unsafe extern "C" fn name_to_handle_at(
    _dirfd: c_int,
    _path: *const c_char,
    _handle: *mut c_void,
    _mount_id: *mut c_int,
    _flags: c_int,
) -> c_int {
    unsafe { *__error() = ENOTSUP };
    -1
}

#[no_mangle]
pub unsafe extern "C" fn renameat2(
    _olddirfd: c_int,
    oldpath: *const c_char,
    _newdirfd: c_int,
    newpath: *const c_char,
    flags: c_uint,
) -> c_int {
    if flags & 1 != 0 {
        // RENAME_NOREPLACE on Darwin is renamex_np(RENAME_EXCL).
        let result = renamex_np(oldpath, newpath, RENAME_EXCL);
        if result == 0 || unsafe { *__error() } != 22 {
            return result;
        }
    }
    rename(oldpath, newpath)
}

#[no_mangle]
pub unsafe extern "C" fn lgetxattr(
    path: *const c_char,
    name: *const c_char,
    value: *mut c_void,
    size: usize,
) -> isize {
    getxattr(path, name, value, size, 0, 0)
}

#[no_mangle]
pub unsafe extern "C" fn lsetxattr(
    path: *const c_char,
    name: *const c_char,
    value: *const c_void,
    size: usize,
    _flags: c_int,
) -> c_int {
    setxattr(path, name, value, size, 0, 0)
}

#[no_mangle]
pub unsafe extern "C" fn lremovexattr(path: *const c_char, name: *const c_char) -> c_int {
    removexattr(path, name, 0)
}

/// The inotify names the watch and peek layers use on Linux; on macOS they use
/// `crate::sys::dirwatch` directly, but keeping the symbols makes any remaining
/// direct declaration resolve to the same kqueue implementation.
#[cfg(not(test))]
#[no_mangle]
pub unsafe extern "C" fn inotify_init1(flags: c_int) -> c_int {
    crate::sys::inotify_init1(flags)
}

#[cfg(not(test))]
#[no_mangle]
pub unsafe extern "C" fn inotify_add_watch(fd: c_int, path: *const c_char, mask: u32) -> c_int {
    crate::sys::inotify_add_watch(fd, path, mask)
}

#[cfg(not(test))]
#[no_mangle]
pub unsafe extern "C" fn inotify_rm_watch(fd: c_int, wd: c_int) -> c_int {
    crate::sys::inotify_rm_watch(fd, wd)
}
