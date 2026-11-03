// Fake compositors wait for a connection only until their test's hang guard expires.
use super::wire::{self, poll_in, Conn};
use super::protocol::REGISTRY_GLOBAL;
use crate::backend::testdir::TestDir;
use std::io::{self, ErrorKind};
use std::os::fd::AsRawFd;
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::time::{Duration, Instant};

// The one hang bound every fake compositor waits on, in both its forms.
pub(crate) const WATCHDOG_MS: u32 = 5000;

pub(crate) fn watchdog() -> Duration {
    Duration::from_millis(WATCHDOG_MS as u64)
}

pub(crate) fn accept(listener: &UnixListener, watchdog: Duration) -> io::Result<UnixStream> {
    listener.set_nonblocking(true)?;
    let started = Instant::now();
    loop {
        match listener.accept() {
            Ok((stream, _)) => return Ok(stream),
            Err(e) if matches!(e.kind(), ErrorKind::WouldBlock | ErrorKind::Interrupted) => {}
            Err(e) => return Err(e),
        }
        let remaining = watchdog.saturating_sub(started.elapsed());
        if remaining.is_zero() {
            return Err(io::Error::new(ErrorKind::TimedOut, "the fake compositor received no connection within the test watchdog"));
        }
        let timeout = remaining.as_millis().clamp(1, u32::MAX as u128) as u32;
        match poll_in(listener.as_raw_fd(), timeout) {
            Err(e) if e.kind() != ErrorKind::Interrupted => return Err(e),
            _ => {}
        }
    }
}

// The next event must be this request; its new_id (or only) word is the answer.
pub(crate) fn expect(conn: &mut Conn, sender: u32, opcode: u16) -> u32 {
    let event = conn.next_raw(WATCHDOG_MS).unwrap().expect("a request");
    assert_eq!((event.sender, event.opcode), (sender, opcode));
    let mut at = 0;
    wire::get_u32(&event.body, &mut at).unwrap()
}

pub(crate) fn over(stream: UnixStream) -> Conn {
    Conn::over(std::os::fd::OwnedFd::from(stream))
}

// One fake compositor's socket in the test's own sandbox.
pub(crate) fn serve(tag: &str) -> (TestDir, UnixListener, PathBuf) {
    let dir = TestDir::new(tag);
    let path = dir.join("fake-wayland");
    let listener = UnixListener::bind(&path).unwrap();
    (dir, listener, path)
}

// The registry globals the fake offers; the caller sends the sync's done.
pub(crate) fn advertise(conn: &mut Conn, registry: u32, globals: &[(&str, u32)]) {
    let mut payload = Vec::new();
    for (index, (interface, version)) in globals.iter().enumerate() {
        payload.clear();
        wire::put_u32(&mut payload, 10 + index as u32);
        wire::put_string(&mut payload, interface);
        wire::put_u32(&mut payload, *version);
        conn.send(registry, REGISTRY_GLOBAL, &payload, &[]).unwrap();
    }
}

// A child the test owns: killed and reaped on drop, so no path leaves a zombie behind.
pub(crate) struct Reaped(pub Option<std::process::Child>);

impl Drop for Reaped {
    fn drop(&mut self) {
        if let Some(mut child) = self.0.take() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}
