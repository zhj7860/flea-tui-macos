use super::*;

#[test]
fn a_graphics_driver_never_clears_the_screen_around_the_pane() {
    for (protocol, driver) in [(Protocol::Kitty, "kitty"), (Protocol::Sixel, "sixel")] {
        let args = arguments(protocol, false, Path::new("/tmp/flea-tui-x/ipc"), (40, 30, 81, 3), (160, 50), (800, 600));
        assert!(args.contains(&format!("--vo-{driver}-config-clear=no")), "{driver}: {args:?}");
        assert!(args.contains(&format!("--vo-{driver}-alt-screen=no")), "{driver}: {args:?}");
        assert!(args.contains(&format!("--vo-{driver}-left=81")) && args.contains(&format!("--vo-{driver}-top=3")));
        assert!(args.contains(&"--pause=yes".to_string()) && args.contains(&format!("--vo={driver}")));
    }
}

#[test]
fn a_terminal_without_graphics_gets_the_null_driver_and_no_pane_options() {
    let args = arguments(Protocol::None, true, Path::new("/tmp/flea-tui-x/ipc"), (40, 30, 81, 3), (160, 50), (0, 0));
    assert!(args.contains(&"--vo=null".to_string()));
    assert!(!args.iter().any(|arg| arg.starts_with("--vo-null-")), "{args:?}");
    assert!(args.contains(&"--input-ipc-server=/tmp/flea-tui-x/ipc".to_string()));
}

fn run(chunks: &[&[u8]], poster: bool) -> (Vec<u8>, Handoff) {
    let mut handoff = Handoff { poster, drawing: false, shm: None };
    let mut pending = Vec::new();
    let mut out = Vec::new();
    for chunk in chunks {
        pending.extend_from_slice(chunk);
        let (bytes, used) = pass(&pending, &mut handoff);
        pending.drain(..used);
        out.extend_from_slice(&bytes);
    }
    assert!(pending.is_empty(), "left over: {pending:?}");
    (out, handoff)
}
const START: &[u8] = b"\x1b[?25l\x1b[?1003h\x1b_Ga=d;\x1b\\\x1b[3;81f\x1b_Ga=T,f=24,s=800,v=450,C=1,q=2,m=1;AAAA\x1b\\\x1b_Gm=1;BBBB\x1b\\\x1b_Gm=0;CC==\x1b\\";

#[test]
fn the_poster_stays_until_mpv_has_sent_its_whole_first_frame() {
    let (out, handoff) = run(&[START], true);
    let expected: &[u8] = b"\x1b[3;81f\x1b_Ga=T,f=24,s=800,v=450,C=1,q=2,m=1;AAAA\x1b\\\x1b_Gm=1;BBBB\x1b\\\x1b_Gm=0;CC==\x1b\\\x1b_Ga=d,d=I,i=42,q=2\x1b\\";
    assert_eq!(out, expected, "{}", String::from_utf8_lossy(&out));
    assert!(!handoff.poster && !handoff.drawing);
}

#[test]
fn a_shared_memory_frame_is_whole_in_one_escape_and_ends_the_poster() {
    // mpv 0.41 with --vo-kitty-use-shm=yes, as it wrote to a file: each frame names its shared memory object, marked m=1.
    let stream: &[u8] = b"\x1b[?25l\x1b[?1003h\x1b[?1049h\x1b_Ga=d;\x1b\\\x1b[0;0f\x1b_Ga=T,t=s,f=24,s=640,v=360,C=1,q=2,m=1;bXB2LWtpdHR5LTB4NTVkNjg4ZjE4ZDcw\x1b\\";
    let (out, handoff) = run(&[stream], true);
    // The name goes out absolute, base64 of "/mpv-kitty-0x55d688f18d70", which kitty 0.49 requires.
    let expected: &[u8] = b"\x1b[0;0f\x1b_Ga=T,t=s,f=24,s=640,v=360,C=1,q=2,m=1;L21wdi1raXR0eS0weDU1ZDY4OGYxOGQ3MA==\x1b\\\x1b_Ga=d,d=I,i=42,q=2\x1b\\";
    assert_eq!(out, expected, "{}", String::from_utf8_lossy(&out));
    assert!(!handoff.poster && !handoff.drawing);
    assert_eq!(handoff.shm.as_deref(), Some("/mpv-kitty-0x55d688f18d70"));
    // A name already absolute passes unchanged.
    let absolute = format!("\x1b_Ga=T,t=s,f=24,s=640,v=360,q=2;{}\x1b\\", crate::tui::graphics::base64(b"/mpv-kitty-1"));
    assert_eq!(run(&[absolute.as_bytes()], false).0, absolute.as_bytes());
}

#[test]
fn only_a_plain_shared_memory_name_is_ever_removed() {
    let root = std::path::Path::new("/dev/shm");
    assert_eq!(shm_leftover(root, "/mpv-kitty-0x55d688f18d70"), Some(root.join("mpv-kitty-0x55d688f18d70")));
    for name in ["", "/", "mpv-kitty-1", "/../etc", "/a/b", "/a.b", "/.."] {
        assert_eq!(shm_leftover(root, name), None, "{name}");
    }
}

#[test]
fn mpv_ending_removes_its_last_unread_frame_and_nothing_else() {
    let frame = |name: &str| format!("\x1b_Ga=T,t=s,f=24,s=1,v=1,q=2,m=1;{}\x1b\\", crate::tui::graphics::base64(name.as_bytes()));
    // Two reads, one frame each: a terminal that takes both leaves the second unread, one that refuses the first stops there.
    for (refuse, removed, kept) in [(false, "mpv-kitty-2", "mpv-kitty-1"), (true, "mpv-kitty-1", "mpv-kitty-2")] {
        let dir = crate::backend::testdir::TestDir::new("shm-relay");
        for name in ["mpv-kitty-1", "mpv-kitty-2", "mpv-kitty-3"] {
            std::fs::write(dir.path().join(name), b"rgb").unwrap();
        }
        let (first, second) = (frame("mpv-kitty-1"), frame("mpv-kitty-2"));
        let mut written = Vec::new();
        relay(first.as_bytes().chain(second.as_bytes()), &std::sync::atomic::AtomicBool::new(false), dir.path(), |bytes| {
            written.extend_from_slice(bytes);
            !refuse
        });
        assert!(String::from_utf8_lossy(&written).contains(&crate::tui::graphics::base64(b"/mpv-kitty-1")), "the name went out absolute");
        assert!(!dir.path().join(removed).exists(), "refuse {refuse}: the last frame read stayed in shared memory");
        assert!(dir.path().join(kept).exists() && dir.path().join("mpv-kitty-3").exists(), "refuse {refuse}: another object was removed");
    }
}

#[test]
fn without_a_poster_mpv_clears_its_own_images_and_only_terminal_modes_are_held_back() {
    let (out, _) = run(&[START, b"\x1b_Ga=d;\x1b\\"], false);
    assert!(out.starts_with(b"\x1b_Ga=d;\x1b\\\x1b[3;81f"), "{}", String::from_utf8_lossy(&out));
    assert!(out.ends_with(b"\x1b_Gm=0;CC==\x1b\\\x1b_Ga=d;\x1b\\"));
    assert!(!out.windows(3).any(|w| w == b"\x1b[?"), "no mode change reaches the terminal");
}

#[test]
fn an_interrupted_read_retries_instead_of_ending_the_relay() {
    // One interrupted read, then the sample start, then EOF: the whole start still reaches the sink.
    struct Interrupting { calls: usize, bytes: &'static [u8] }
    impl std::io::Read for Interrupting {
        fn read(&mut self, buffer: &mut [u8]) -> std::io::Result<usize> {
            self.calls += 1;
            if self.calls == 1 {
                return Err(std::io::Error::from(std::io::ErrorKind::Interrupted));
            }
            if self.bytes.is_empty() {
                return Ok(0);
            }
            let take = self.bytes.len().min(buffer.len());
            buffer[..take].copy_from_slice(&self.bytes[..take]);
            self.bytes = &self.bytes[take..];
            Ok(take)
        }
    }
    let mut written = Vec::new();
    let dir = crate::backend::testdir::TestDir::new("shm-interrupt");
    relay(Interrupting { calls: 0, bytes: START }, &std::sync::atomic::AtomicBool::new(true), dir.path(), |bytes| {
        written.extend_from_slice(bytes);
        true
    });
    assert_eq!(written, run(&[START], true).0);
}

#[test]
fn the_start_path_pipes_every_child_through_the_relay() {
    // A stub child writing the START sample; the sink collects what the relay passes on.
    let seen = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
    let sink_seen = std::sync::Arc::clone(&seen);
    let mut command = Command::new("sh");
    command.args(["-c", r"printf '\033[?25l\033[?1003h\033_Ga=d;\033\\\033[3;81f\033_Ga=T,f=24,s=800,v=450,C=1,q=2,m=1;AAAA\033\\\033_Gm=1;BBBB\033\\\033_Gm=0;CC==\033\\'"]);
    let poster = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(true));
    let (mut child, forwarder) = spawn_relayed(command, std::sync::Arc::clone(&poster), move |bytes: &[u8]| {
        sink_seen.lock().expect("sink collects").extend_from_slice(bytes);
        true
    })
    .expect("stub starts");
    child.wait().expect("stub exits");
    forwarder.expect("the start path left a relay").join().expect("relay ends");
    assert_eq!(*seen.lock().expect("sink reads"), run(&[START], true).0);
    assert!(!poster.load(std::sync::atomic::Ordering::Relaxed));
}

#[test]
fn an_escape_split_across_reads_waits_for_its_end() {
    let whole = run(&[START], true).0;
    for cut in 1..START.len() {
        let (out, _) = run(&[&START[..cut], &START[cut..]], true);
        assert_eq!(out, whole, "cut at {cut}");
    }
}

#[test]
fn a_sixel_frame_and_an_osc_stay_whole_across_reads() {
    let units: [&[u8]; 4] = [b"\x1b[3;81f", b"\x1bPq#0;2;0;0;0#0~~-~~\x1b\\", b"\x1b]0;mpv\x07", b"\x1b_Gm=0;\x1b\\"];
    let stream = units.concat();
    let ends: Vec<usize> = units.iter().scan(0, |at, unit| { *at += unit.len(); Some(*at) }).collect();
    for cut in 1..stream.len() {
        let mut handoff = Handoff { poster: false, drawing: false, shm: None };
        let (first, used) = pass(&stream[..cut], &mut handoff);
        let whole = ends.iter().copied().filter(|&end| end <= cut).max().unwrap_or(0);
        assert_eq!(used, whole, "cut {cut}: a read may only end on a whole escape");
        let (second, rest) = pass(&stream[used..], &mut handoff);
        assert_eq!(rest, stream.len() - used, "cut {cut}");
        assert_eq!([first, second].concat(), stream, "cut {cut}");
    }
}

#[test]
fn shared_memory_frames_only_where_kitty_can_read_them() {
    let shm = |protocol, ok| arguments(protocol, ok, Path::new("/tmp/flea-tui-x/ipc"), (40, 30, 81, 3), (160, 50), (800, 600));
    assert!(shm(Protocol::Kitty, true).contains(&"--vo-kitty-use-shm=yes".to_string()));
    assert!(!shm(Protocol::Kitty, false).iter().any(|arg| arg.contains("use-shm")));
    assert!(!shm(Protocol::Sixel, true).iter().any(|arg| arg.contains("use-shm")));
}
