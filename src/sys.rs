// The macOS stand-ins for the Linux calls the rest of the tree names directly.
//
// Linux reaches inotify, eventfd, pidfd_open, close_range and the glibc allocator hooks through a
// handful of symbols. macOS has none of those, so this module offers the same shapes over kqueue,
// pipes and plain fcntl loops, and the call sites keep their own logic. Every item here is
// `#[cfg(target_os = "macos")]`; the Linux build compiles the original code and never this file.
#![cfg(target_os = "macos")]

use std::ffi::{c_char, c_int, c_void};
use std::os::fd::RawFd;
use std::sync::Mutex;

#[repr(C)]
#[derive(Clone, Copy)]
struct Kevent {
    ident: usize,
    filter: i16,
    flags: u16,
    fflags: u32,
    data: isize,
    udata: *mut c_void,
}

// sys/event.h values on Darwin, never the Linux or FreeBSD ones.
const EVFILT_VNODE: i16 = -4;
const EVFILT_PROC: i16 = -5;
const EVFILT_USER: i16 = -10;
const NOTE_TRIGGER: u32 = 0x0100_0000;
const EV_ADD: u16 = 0x0001;
const EV_DELETE: u16 = 0x0002;
const EV_ONESHOT: u16 = 0x0010;
const EV_CLEAR: u16 = 0x0020;
const NOTE_DELETE: u32 = 0x0000_0001;
const NOTE_WRITE: u32 = 0x0000_0002;
const NOTE_EXTEND: u32 = 0x0000_0004;
const NOTE_ATTRIB: u32 = 0x0000_0008;
const NOTE_RENAME: u32 = 0x0000_0020;
const NOTE_REVOKE: u32 = 0x0000_0040;
const NOTE_EXIT: u32 = 0x8000_0000;

const O_EVTONLY: c_int = 0x0000_8000;
const O_CLOEXEC: c_int = 0x0100_0000;
const O_NONBLOCK: c_int = 0x0004;
const F_SETFD: c_int = 2;
const F_SETFL: c_int = 4;
const FD_CLOEXEC: c_int = 1;
const ESRCH: c_int = 3;
const EAGAIN: c_int = 35;

// The inotify masks the call sites classify bursts with; the same bit values Linux uses.
const IN_ATTRIB: u32 = 0x0000_0004;
const IN_CLOSE_WRITE: u32 = 0x0000_0008;
const IN_MOVED_FROM: u32 = 0x0000_0040;
const IN_MOVED_TO: u32 = 0x0000_0080;
const IN_CREATE: u32 = 0x0000_0100;
const IN_DELETE: u32 = 0x0000_0200;
const IN_DELETE_SELF: u32 = 0x0000_0400;
const IN_UNMOUNT: u32 = 0x0000_2000;
const IN_IGNORED: u32 = 0x0000_8000;
// One synthesized inotify_event is its fixed 16 byte header; the shim never carries a name.
const EVENT_HEADER: usize = 16;
// How many knotes one read reports before the caller comes back for the rest.
const BATCH: usize = 16;

extern "C" {
    fn __error() -> *mut c_int;
    fn kqueue() -> c_int;
    fn kevent(
        kq: c_int,
        changelist: *const Kevent,
        nchanges: c_int,
        eventlist: *mut Kevent,
        nevents: c_int,
        timeout: *const c_void,
    ) -> c_int;
    fn open(path: *const c_char, flags: c_int, ...) -> c_int;
    fn fcntl(fd: c_int, cmd: c_int, ...) -> c_int;
    fn close(fd: c_int) -> c_int;
    fn pipe(fds: *mut c_int) -> c_int;
    fn write(fd: c_int, buf: *const c_void, count: usize) -> isize;
    fn kill(pid: c_int, sig: c_int) -> c_int;
}

pub fn set_cloexec(fd: c_int) -> c_int {
    unsafe { fcntl(fd, F_SETFD, FD_CLOEXEC) }
}

fn set_nonblocking(fd: c_int) -> c_int {
    unsafe { fcntl(fd, F_SETFL, O_NONBLOCK) }
}

// pipe2(O_CLOEXEC) is Linux-only; macOS gets the same ends from pipe() plus two fcntl calls.
pub fn pipe_cloexec() -> std::io::Result<(RawFd, RawFd)> {
    let mut fds = [-1 as c_int; 2];
    if unsafe { pipe(fds.as_mut_ptr()) } != 0 {
        return Err(std::io::Error::last_os_error());
    }
    if set_cloexec(fds[0]) != 0 || set_cloexec(fds[1]) != 0 {
        let failure = std::io::Error::last_os_error();
        unsafe {
            close(fds[0]);
            close(fds[1]);
        }
        return Err(failure);
    }
    Ok((fds[0], fds[1]))
}

// eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK) was a write-anywhere counter that poll could watch. A
// nonblocking pipe pair is the same thing with the two ends named: the reader polls, the writer
// never blocks, and one pending ticket is enough to wake it.
pub fn wake_pair() -> std::io::Result<(RawFd, RawFd)> {
    let (reader, writer) = pipe_cloexec()?;
    if set_nonblocking(reader) != 0 || set_nonblocking(writer) != 0 {
        let failure = std::io::Error::last_os_error();
        unsafe {
            close(reader);
            close(writer);
        }
        return Err(failure);
    }
    Ok((reader, writer))
}

// The eight byte ticket an eventfd write carried; a full pipe already holds a wake nobody has read.
pub fn wake_signal(writer: RawFd) {
    if writer < 0 {
        return;
    }
    let ticket = 1u64.to_ne_bytes();
    loop {
        let done = unsafe { write(writer, ticket.as_ptr().cast(), ticket.len()) };
        if done >= 0 {
            return;
        }
        if std::io::Error::last_os_error().kind() != std::io::ErrorKind::Interrupted {
            return;
        }
    }
}


// An inotify-compatible descriptor backed by kqueue: init creates it, add/rm arm a vnode watch, and
// read answers the same 16 byte events the Linux parser walks. Only directories are watched here.
pub mod dirwatch {
    use super::*;
    use std::collections::HashMap;

    // One armed directory: which kqueue holds it, the descriptor the kernel keys its knote by, and
    // the path it was armed on.
    struct Armed {
        kq: c_int,
        dir: c_int,
    }

    // The path a watch was armed on, per kqueue, so arming the same directory twice on one watch
    // answers the same descriptor exactly as inotify does. Keyed by the kqueue too, because two
    // watches in one process each own their own table, as two inotify instances do.
    static ARMED: Mutex<Option<HashMap<(c_int, Vec<u8>), c_int>>> = Mutex::new(None);
    // Every live watch descriptor, so rm and a burst can name one by number.
    static WATCHES: Mutex<Option<HashMap<c_int, Armed>>> = Mutex::new(None);
    // The ikevent identifier (the directory's own descriptor) to the watch descriptor the callers
    // hold. A descriptor the kernel recycled for a later watch never answers the old watch's events.
    static BY_DIR: Mutex<Option<HashMap<(c_int, c_int), c_int>>> = Mutex::new(None);
    // Watch descriptors are synthetic and never reused, unlike the descriptors behind them.
    static NEXT_WD: Mutex<c_int> = Mutex::new(4096);
    // A descriptor opened with IN_NONBLOCK, so read answers EAGAIN instead of waiting.
    static NONBLOCK: Mutex<Option<std::collections::HashSet<c_int>>> = Mutex::new(None);
    // A removed watch's own IN_IGNORED, queued so the next read observes it as inotify does.
    static PENDING: Mutex<Option<HashMap<c_int, std::collections::VecDeque<(c_int, u32)>>>> = Mutex::new(None);

    fn nonblocking<T>(f: impl FnOnce(&mut std::collections::HashSet<c_int>) -> T) -> T {
        let mut slot = NONBLOCK.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        f(slot.get_or_insert_with(std::collections::HashSet::new))
    }

    fn pending<T>(f: impl FnOnce(&mut HashMap<c_int, std::collections::VecDeque<(c_int, u32)>>) -> T) -> T {
        let mut slot = PENDING.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        f(slot.get_or_insert_with(HashMap::new))
    }

    fn armed<T>(f: impl FnOnce(&mut HashMap<(c_int, Vec<u8>), c_int>) -> T) -> T {
        let mut slot = ARMED.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        f(slot.get_or_insert_with(HashMap::new))
    }

    fn watches<T>(f: impl FnOnce(&mut HashMap<c_int, Armed>) -> T) -> T {
        let mut slot = WATCHES.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        f(slot.get_or_insert_with(HashMap::new))
    }

    fn by_dir<T>(f: impl FnOnce(&mut HashMap<(c_int, c_int), c_int>) -> T) -> T {
        let mut slot = BY_DIR.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        f(slot.get_or_insert_with(HashMap::new))
    }

    fn next_wd() -> c_int {
        let mut slot = NEXT_WD.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
        let wd = *slot;
        *slot += 1;
        wd
    }

    // IN_NONBLOCK is O_NONBLOCK's number on Linux; the callers pass that bit to ask for EAGAIN reads.
    const IN_NONBLOCK: c_int = 0x800;

    // A closed kqueue's number is handed to the next one, so its tables are cleared before reuse;
    // otherwise a new watch could inherit an old one's queued events or its pending stop.
    fn forget_kq(kq: c_int) {
        pending(|queues| queues.remove(&kq));
        nonblocking(|set| set.remove(&kq));
        let stale: Vec<c_int> = watches(|map| {
            map.iter().filter(|(_, held)| held.kq == kq).map(|(wd, _)| *wd).collect()
        });
        for wd in stale {
            if let Some(held) = watches(|map| map.remove(&wd)) {
                by_dir(|map| map.remove(&(held.kq, held.dir)));
                armed(|map| map.retain(|_, guard| *guard != wd));
                unsafe { close(held.dir) };
            }
        }
    }

    // Sample input: flags 0 answers a kqueue descriptor, or -1 when the kernel refuses one.
    pub fn init1(flags: c_int) -> c_int {
        let fd = unsafe { kqueue() };
        if fd >= 0 {
            forget_kq(fd);
            set_cloexec(fd);
            if flags & IN_NONBLOCK != 0 {
                nonblocking(|set| set.insert(fd));
            }
        }
        fd
    }

    fn arm(kq: c_int, dir: c_int) -> bool {
        let change = Kevent {
            ident: dir as usize,
            filter: EVFILT_VNODE,
            flags: EV_ADD | EV_CLEAR,
            fflags: NOTE_WRITE
                | NOTE_EXTEND
                | NOTE_ATTRIB
                | NOTE_DELETE
                | NOTE_RENAME
                | NOTE_REVOKE,
            data: 0,
            udata: std::ptr::null_mut(),
        };
        (unsafe { kevent(kq, &change, 1, std::ptr::null_mut(), 0, std::ptr::null()) }) == 0
    }

    // Sample input: the same path twice answers the same descriptor, as inotify's one watch does.
    pub fn add_watch(kq: c_int, path: *const c_char, _mask: u32) -> c_int {
        if kq < 0 || path.is_null() {
            return -1;
        }
        let key = unsafe { std::ffi::CStr::from_ptr(path) }.to_bytes().to_vec();
        if let Some(held) = armed(|map| map.get(&(kq, key.clone())).copied()) {
            return held;
        }
        let dir = unsafe { open(path, O_EVTONLY | O_CLOEXEC) };
        if dir < 0 || !arm(kq, dir) {
            if dir >= 0 {
                unsafe { close(dir) };
            }
            return -1;
        }
        let wd = next_wd();
        watches(|map| map.insert(wd, Armed { kq, dir }));
        by_dir(|map| map.insert((kq, dir), wd));
        armed(|map| map.insert((kq, key), wd));
        wd
    }

    pub fn rm_watch(kq: c_int, wd: c_int) -> c_int {
        if kq < 0 || wd < 0 {
            return -1;
        }
        let held = watches(|map| map.remove(&wd));
        let Some(held) = held else { return -1 };
        retire(wd, held);
        queue_ignored(kq, wd);
        0
    }

    // The kqueue knote goes with the descriptor, and both tables forget the pair.
    fn retire(wd: c_int, held: Armed) {
        let change = Kevent {
            ident: held.dir as usize,
            filter: EVFILT_VNODE,
            flags: EV_DELETE,
            fflags: 0,
            data: 0,
            udata: std::ptr::null_mut(),
        };
        unsafe {
            kevent(held.kq, &change, 1, std::ptr::null_mut(), 0, std::ptr::null());
            close(held.dir);
        }
        by_dir(|map| map.remove(&(held.kq, held.dir)));
        armed(|map| map.retain(|_, guard| *guard != wd));
    }

    fn queue_ignored(kq: c_int, wd: c_int) {
        if kq >= 0 && wd >= 0 {
            pending(|queues| queues.entry(kq).or_default().push_back((wd, IN_IGNORED)));
        }
    }

    // kqueue reports that a directory's entries moved, never which entry: one changed event is all
    // the callers act on, so NOTE_WRITE answers the create/close/move masks together and
    // NOTE_DELETE/NOTE_RENAME answer the self events that retire the watch. A revoked vnode is the
    // mount going away.
    fn mask_for(fflags: u32) -> (u32, bool) {
        if fflags & NOTE_REVOKE != 0 {
            return (IN_UNMOUNT, false);
        }
        if fflags & (NOTE_DELETE | NOTE_RENAME) != 0 {
            return (IN_DELETE_SELF | IN_IGNORED, true);
        }
        if fflags & (NOTE_WRITE | NOTE_EXTEND) != 0 {
            return (IN_CREATE | IN_CLOSE_WRITE | IN_MOVED_TO | IN_DELETE | IN_MOVED_FROM, false);
        }
        (IN_ATTRIB, false)
    }

    fn header(wd: c_int, mask: u32) -> [u8; EVENT_HEADER] {
        let mut out = [0u8; EVENT_HEADER];
        out[0..4].copy_from_slice(&wd.to_ne_bytes());
        out[4..8].copy_from_slice(&mask.to_ne_bytes());
        out
    }

    // The blocking read an inotify pump makes: one kevent wait, answered as inotify_event records.
    // A burst naming a descriptor no watch owns any more is stale and answers nothing.
    pub fn read_events(kq: c_int, buf: *mut u8, count: usize) -> isize {
        if kq < 0 || buf.is_null() {
            return -1;
        }
        let queued: Vec<(c_int, u32)> = pending(|queues| {
            queues.get_mut(&kq).map(|queue| queue.drain(..).collect()).unwrap_or_default()
        });
        if !queued.is_empty() {
            let mut written = 0usize;
            for (wd, mask) in queued {
                if written + EVENT_HEADER > count {
                    break;
                }
                let bytes = header(wd, mask);
                unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf.add(written), EVENT_HEADER) };
                written += EVENT_HEADER;
            }
            return written as isize;
        }
        let nonblocking = nonblocking(|set| set.contains(&kq));
        // A zero timespec asks the kernel for what is ready and never waits, which is EAGAIN's shape.
        let timeout = [0i64, 0];
        let timeout_ptr = if nonblocking { timeout.as_ptr().cast::<c_void>() } else { std::ptr::null() };
        let mut events = [Kevent {
            ident: 0,
            filter: 0,
            flags: 0,
            fflags: 0,
            data: 0,
            udata: std::ptr::null_mut(),
        }; BATCH];
        let ready = unsafe {
            kevent(kq, std::ptr::null(), 0, events.as_mut_ptr(), BATCH as c_int, timeout_ptr)
        };
        if ready < 0 {
            return -1;
        }
        if ready == 0 {
            // Nothing ready on a nonblocking watch is EAGAIN, exactly what inotify's read answers.
            unsafe { *__error() = EAGAIN };
            return -1;
        }
        let mut written = 0usize;
        for event in &events[..ready as usize] {
            let Some(wd) = by_dir(|map| map.get(&(kq, event.ident as c_int)).copied()) else { continue };
            if written + EVENT_HEADER > count {
                break;
            }
            let (mask, gone) = mask_for(event.fflags);
            let bytes = header(wd, mask);
            unsafe { std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf.add(written), EVENT_HEADER) };
            written += EVENT_HEADER;
            if gone {
                if let Some(held) = watches(|map| map.remove(&wd)) {
                    retire(wd, held);
                }
            }
        }
        written as isize
    }
}

// The inotify names the call sites already use, answered by the kqueue shim above. They stay
// `unsafe` so the Linux call sites compile unchanged against either declaration.
pub unsafe fn inotify_init1(flags: c_int) -> c_int {
    dirwatch::init1(flags)
}

pub unsafe fn inotify_add_watch(fd: c_int, path: *const c_char, mask: u32) -> c_int {
    dirwatch::add_watch(fd, path, mask)
}

pub unsafe fn inotify_rm_watch(fd: c_int, wd: c_int) -> c_int {
    dirwatch::rm_watch(fd, wd)
}

pub unsafe fn watch_read(fd: c_int, buf: *mut c_void, count: usize) -> isize {
    dirwatch::read_events(fd, buf.cast(), count)
}

// pidfd_open is Linux-only. A kqueue with one EVFILT_PROC NOTE_EXIT knote polls readable the moment
// the process exits, which is the one thing clip/end.rs uses a pidfd for.
pub unsafe fn pidfd_open(pid: c_int, _flags: u32) -> c_int {
    // kill(pid, 0) answers ESRCH for a pid that is already gone, the check pidfd_open makes.
    if unsafe { kill(pid, 0) } != 0 {
        let errno = unsafe { *__error() };
        if errno == ESRCH {
            unsafe { *__error() = ESRCH };
        }
        return -1;
    }
    let fd = unsafe { kqueue() };
    if fd < 0 {
        return -1;
    }
    set_cloexec(fd);
    let change = Kevent {
        ident: pid as usize,
        filter: EVFILT_PROC,
        flags: EV_ADD | EV_ONESHOT,
        fflags: NOTE_EXIT,
        data: 0,
        udata: std::ptr::null_mut(),
    };
    if unsafe { kevent(fd, &change, 1, std::ptr::null_mut(), 0, std::ptr::null()) } != 0 {
        let failure = std::io::Error::last_os_error();
        // A child that exited before the wait began is a zombie: the kernel refuses a proc knote for it
        // with ESRCH, but the exit already happened, so the descriptor is made readable at once.
        if failure.raw_os_error() == Some(ESRCH) && unsafe { kill(pid, 0) } == 0 {
            let trigger = Kevent {
                ident: 0,
                filter: EVFILT_USER,
                flags: EV_ADD | EV_ONESHOT | EV_CLEAR,
                fflags: NOTE_TRIGGER,
                data: 0,
                udata: std::ptr::null_mut(),
            };
            if unsafe { kevent(fd, &trigger, 1, std::ptr::null_mut(), 0, std::ptr::null()) } == 0 {
                return fd;
            }
        }
        unsafe { close(fd) };
        if failure.raw_os_error() == Some(ESRCH) {
            unsafe { *__error() = ESRCH };
        }
        return -1;
    }
    fd
}
