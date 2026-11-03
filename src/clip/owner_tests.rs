// Owner-side fakes for offer retirement and deadline writes.
use super::*;
use crate::clip::format;
use std::os::fd::OwnedFd;
use std::path::PathBuf;
use crate::clip::testutil::{advertise, expect, over, serve, watchdog, WATCHDOG_MS};

// The owner's setup round trip: globals, done, then everything up to the closing sync.
fn owner_hello(conn: &mut Conn) {
    let registry = expect(conn, DISPLAY, DISPLAY_GET_REGISTRY);
    let callback = expect(conn, DISPLAY, DISPLAY_SYNC);
    advertise(conn, registry, &[("wl_seat", 1), ("ext_data_control_manager_v1", 1)]);
    conn.send(callback, 0, &[], &[]).unwrap();
    loop {
        let event = conn.next_raw(WATCHDOG_MS).unwrap().expect("a request");
        if event.sender == DISPLAY && event.opcode == DISPLAY_SYNC {
            break;
        }
    }
    conn.send(8, 0, &[], &[]).unwrap();
}

fn start_owner(path: PathBuf, paths: Vec<String>) -> (std::thread::JoinHandle<()>, std::sync::mpsc::Receiver<()>) {
    let (tx, rx) = std::sync::mpsc::channel();
    let worker = std::thread::spawn(move || {
        let mut conn = Conn::connect_to(&path).unwrap();
        crate::clip::control::handshake(&mut conn).unwrap();
        let mut owner = own_on(conn, "copy", &paths, "ab12cd34ab12cd34ab12cd34ab12cd34").unwrap();
        serve_owner(&mut owner).unwrap();
        let _ = tx.send(());
    });
    (worker, rx)
}

#[test]
fn superseded_device_offers_are_destroyed() {
    let (_dir, listener, path) = serve("clip-owner-retire");
    let (worker, _done) = start_owner(path, vec!["/tmp/a.txt".to_string()]);
    let stream = crate::clip::testutil::accept(&listener, watchdog()).unwrap();
    let mut conn = over(stream);
    owner_hello(&mut conn);
    for id in [20u32, 21, 22] {
        let mut payload = Vec::new();
        wire::put_u32(&mut payload, id);
        conn.send(7, 0, &payload, &[]).unwrap();
    }
    let mut payload = Vec::new();
    wire::put_u32(&mut payload, 21);
    conn.send(7, 1, &payload, &[]).unwrap();
    // The two superseded offers are destroyed, in either order; the current one stays.
    let mut destroyed = Vec::new();
    for _ in 0..2 {
        let event = conn.next_raw(WATCHDOG_MS).unwrap().expect("a destroy");
        assert_eq!(event.opcode, 1);
        assert!(event.body.is_empty());
        destroyed.push(event.sender);
    }
    destroyed.sort_unstable();
    assert_eq!(destroyed, vec![20, 22]);
    conn.send(6, 1, &[], &[]).unwrap();
    worker.join().unwrap();
}

#[test]
fn a_reader_that_stops_reading_does_not_wedge_the_owner() {
    // A real pipe at 64 KiB and a payload near half a megabyte: a blocking write never returns.
    let paths: Vec<String> = (0..20000).map(|i| format!("/tmp/f{:05}.txt", i)).collect();
    let (_dir, listener, path) = serve("clip-owner-stuck");
    let (worker, done) = start_owner(path, paths);
    let stream = crate::clip::testutil::accept(&listener, watchdog()).unwrap();
    let mut conn = over(stream);
    owner_hello(&mut conn);
    // Asked for, never read, then replaced: only a write deadline lets the owner reach cancelled.
    extern "C" {
        fn pipe(fds: *mut std::os::raw::c_int) -> std::os::raw::c_int;
    }
    use std::os::fd::FromRawFd;
    let mut fds = [-1, -1];
    assert_eq!(unsafe { pipe(fds.as_mut_ptr()) }, 0);
    let mut payload = Vec::new();
    wire::put_string(&mut payload, format::URILIST);
    conn.send(6, 0, &payload, &[fds[1]]).unwrap();
    drop(unsafe { OwnedFd::from_raw_fd(fds[1]) });
    conn.send(6, 1, &[], &[]).unwrap();
    done.recv_timeout(watchdog()).expect("the owner completion hang guard expired");
    worker.join().unwrap();
    drop(unsafe { OwnedFd::from_raw_fd(fds[0]) });
}
