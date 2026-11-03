// The helper client against stub helpers: the real answer shapes, the refusals and the waits that must end.
use super::*;
use crate::backend::testdir::TestDir;
use std::sync::mpsc::channel;

// A stub that waits longer than any test lets it, to prove the bound and the kill.
const LONG_WAIT: &str = "60";
// A bound short enough for a test and long enough for python to start.
const SHORT_LIMIT: Duration = Duration::from_millis(400);
// What a test allows an open that must end on its own.
const ENDS_BY: Duration = Duration::from_secs(8);

// Sample shape: python3's json.dumps prints ", " and ": " between its tokens, which is what the helper printed.
const SPACED: &str = r#"{"drives": [{"dev": "nvme0n1", "system": true}, {"dev": "sda", "system": false}]}"#;

fn devs() -> Vec<String> {
    vec!["sda".to_string(), "nvme0n1".to_string()]
}

fn printing(d: &TestDir, name: &str, text: &str) -> String {
    d.script(name, &format!("#!/bin/sh\nprintf '%s' '{text}'\n")).to_string_lossy().to_string()
}

#[test]
fn only_a_system_drive_leaves_the_list() {
    let compact = r#"{"drives":[{"dev":"sda","system":false},{"dev":"nvme0n1","system":true}]}"#;
    assert_eq!(apply_drives(&devs(), compact), vec!["sda".to_string()]);
    assert_eq!(apply_drives(&devs(), SPACED), vec!["sda".to_string()], "the shape python prints parses the same");
    assert_eq!(apply_drives(&devs(), "not json"), devs(), "an unreadable answer keeps every drive");
    assert_eq!(apply_drives(&devs(), r#"{"drives": []}"#), devs(), "the list keeps a drive the helper never named");
}

// C16: layer 2 fails closed at flash time, so only a positive answer for this exact drive passes.
#[test]
fn a_flash_needs_a_positive_answer_for_its_own_drive() {
    let d = TestDir::new("flashhelper-confirm");
    let named = printing(&d, "named", SPACED);
    assert!(confirm_at(&named, "sda", HELPER_TIMEOUT), "sda is present and not a system disk");
    assert!(!confirm_at(&named, "nvme0n1", HELPER_TIMEOUT), "the daemon calls nvme0n1 a system disk");
    assert!(!confirm_at(&named, "sdb", HELPER_TIMEOUT), "a drive the helper did not name is not confirmed");
    let empty = printing(&d, "empty", r#"{"drives": []}"#);
    assert!(!confirm_at(&empty, "sda", HELPER_TIMEOUT), "an empty answer is no confirmation");
    let silent = d.script("silent", &format!("#!/bin/sh\nexec sleep {LONG_WAIT}\n")).to_string_lossy().to_string();
    assert!(!confirm_at(&silent, "sda", SHORT_LIMIT), "a helper that times out is no confirmation");
    assert!(!confirm_at("/nonexistent-helper", "sda", HELPER_TIMEOUT), "a helper that is missing is no confirmation");
    let broken = printing(&d, "broken", "not json");
    assert!(!confirm_at(&broken, "sda", HELPER_TIMEOUT), "an unreadable answer is no confirmation");
}

// C5: the eject answer in the shape python prints, with ": " after each key.
#[test]
fn the_eject_answer_is_read_in_the_shape_the_helper_prints() {
    assert_eq!(parse_eject(r#"{"ok": true}"#), Ok(()));
    assert_eq!(parse_eject(r#"{"ok":true}"#), Ok(()));
    assert_eq!(parse_eject(r#"{"ok": false, "err": "busy"}"#), Err("busy".to_string()));
    assert_eq!(parse_eject(r#"{"ok": false, "err": "gone"}"#), Err("gone".to_string()));
    assert_eq!(parse_eject(r#"{"ok": false, "err": "changed"}"#), Err("changed".to_string()));
    assert_eq!(parse_eject(r#"{"ok": false, "err": "weird"}"#), Err("error".to_string()));
    assert_eq!(parse_eject("garbage"), Err("error".to_string()));
    let d = TestDir::new("flashhelper-eject");
    let stub = printing(&d, "eject", r#"{"ok": true}"#);
    assert_eq!(eject_at(&stub, "sda", HELPER_TIMEOUT), Ok(()), "the printed shape ejects");
}

// An unanswered eject still answers the protocol word, never a free sentence.
#[test]
fn an_unanswered_eject_answers_the_protocol_word() {
    assert_eq!(eject_at("/nonexistent-helper", "sda", SHORT_LIMIT), Err("error".to_string()), "a missing helper is error");
    let d = TestDir::new("flashhelper-eject-silent");
    let silent = d.script("silent", &format!("#!/bin/sh\nexec sleep {LONG_WAIT}\n")).to_string_lossy().to_string();
    assert_eq!(eject_at(&silent, "sda", SHORT_LIMIT), Err("error".to_string()), "a helper that times out is error");
}

// C15: a cut on a byte index inside a two-byte character panics, so the cut moves to a boundary.
#[test]
fn elision_keeps_the_last_line_short_and_whole() {
    assert_eq!(elide(""), "");
    assert_eq!(elide("first\nsecond"), "second");
    let long = "x".repeat(200);
    assert!(elide(&long).len() <= ELIDE_BYTES + 3);
    let straddle = format!("{}é{}", "x".repeat(ELIDE_BYTES - 1), "y".repeat(40));
    assert_eq!(straddle.len(), ELIDE_BYTES + 41, "the two-byte character spans byte {ELIDE_BYTES}");
    let cut = elide(&straddle);
    assert!(cut.ends_with("..."), "{cut}");
    assert_eq!(cut.trim_end_matches("..."), "x".repeat(ELIDE_BYTES - 1), "the cut stops before the character it would split");
}

// F7: no privilege beyond one descriptor, so no flash source may name an escalation tool.
#[test]
fn no_flash_source_names_a_privilege_escalation() {
    // Built at runtime, so the needles themselves never trip the scan they run.
    let forbidden = ["su".to_string() + "do", "pk".to_string() + "exec"];
    let sources = escalation_sources();
    assert!(sources.iter().any(|s| s.ends_with("flashpump.rs")) && sources.iter().any(|s| s.ends_with("flea-udisks")), "{sources:?}");
    for source in &sources {
        let text = std::fs::read_to_string(source).unwrap_or_else(|_| panic!("{source} is read from the tree root"));
        for needle in &forbidden {
            assert!(!text.contains(needle), "{source} names an escalation tool");
        }
    }
}

// Every flash source in src/backend, the chunk hash and both helper halves, read from the tree so a new file is scanned unasked.
fn escalation_sources() -> Vec<String> {
    let mut sources: Vec<String> = std::fs::read_dir("src/backend").expect("src/backend is read from the tree root")
        .filter_map(|entry| entry.ok()?.file_name().into_string().ok())
        .filter(|name| name.starts_with("flash") && name.ends_with(".rs"))
        .map(|name| format!("src/backend/{name}"))
        .collect();
    sources.sort();
    sources.extend(["src/backend/xxh64.rs", "tools/flea-udisks", "tools/flea-udisks-seam"].map(String::from));
    sources
}

// F10: a localized stderr never changes the outcome; the status byte alone decides it.
#[test]
fn a_localized_refusal_still_refuses() {
    let d = TestDir::new("flashhelper-locale");
    let stub = d.script("stub-udisks", "#!/bin/sh\necho 'el demonio dice que no' >&2\nexec python3 -c 'import socket;s=socket.fromfd(0,socket.AF_UNIX,socket.SOCK_SEQPACKET);s.sendmsg([b\"D\"],[])'\n");
    let out = open_device_at(&stub.to_string_lossy(), "sda", "", 0, &mut || {}, ENDS_BY);
    assert!(matches!(out, Err(OpenFail::Denied)), "the D byte refuses whatever language stderr speaks");
}

#[test]
fn the_open_hands_back_the_descriptor_the_helper_sends() {
    let d = TestDir::new("flashhelper-fd");
    let file = d.file("target.img", "hello");
    let body = format!("#!/bin/sh\nexec python3 -c 'import socket;s=socket.fromfd(0,socket.AF_UNIX,socket.SOCK_SEQPACKET);f=open(\"{}\",\"rb\");socket.send_fds(s,[b\"O\"],[f.fileno()])'\n", file.display());
    let stub = d.script("fd-udisks", &body);
    let mut spawned = 0;
    let out = open_device_at(&stub.to_string_lossy(), "sda", "", 0, &mut || spawned += 1, ENDS_BY);
    let fd = match out { Ok(fd) => fd, Err(_) => panic!("the helper sent a descriptor") };
    use std::io::Read;
    let mut text = String::new();
    std::fs::File::from(fd).read_to_string(&mut text).unwrap();
    assert_eq!(text, "hello");
    assert_eq!(spawned, 1, "the spawned hook runs once, after the helper is up");
}

// C8: a helper that dies without answering hangs the socket up, and one that never answers is cut at the bound.
#[test]
fn an_open_ends_when_the_helper_dies_or_never_answers() {
    let d = TestDir::new("flashhelper-dies");
    let dies = d.script("dies", "#!/bin/sh\nexit 3\n").to_string_lossy().to_string();
    let (tx, rx) = channel();
    std::thread::spawn(move || {
        let _ = tx.send(matches!(open_device_at(&dies, "sda", "", 0, &mut || {}, OPEN_TIMEOUT), Err(OpenFail::Helper(_))));
    });
    assert_eq!(rx.recv_timeout(ENDS_BY), Ok(true), "a helper that exits unanswered ends the wait at once, not at the prompt's bound");
    let sleeps = d.script("sleeps", &format!("#!/bin/sh\nexec sleep {LONG_WAIT}\n")).to_string_lossy().to_string();
    let started = Instant::now();
    let out = open_device_at(&sleeps, "sda", "", 0, &mut || {}, SHORT_LIMIT);
    assert!(matches!(out, Err(OpenFail::Helper(_))), "a helper that never answers is a helper failure");
    assert!(started.elapsed() < ENDS_BY, "the wait ended at its bound");
}

// C8b: a helper that answers and then fills the stderr pipe ends by the drain alone, since the open bound is far past ENDS_BY and the kill never comes first.
#[test]
fn an_answer_followed_by_a_full_stderr_pipe_still_ends() {
    let d = TestDir::new("flashhelper-fullpipe");
    let body = "#!/bin/sh\nexec python3 -c 'import socket,sys;s=socket.fromfd(0,socket.AF_UNIX,socket.SOCK_SEQPACKET);s.sendmsg([b\"D\"],[]);sys.stderr.write(\"x\"*200000)'\n";
    let stub = d.script("full-udisks", body).to_string_lossy().to_string();
    let (tx, rx) = channel();
    std::thread::spawn(move || {
        let _ = tx.send(open_device_at(&stub, "sda", "", 0, &mut || {}, OPEN_TIMEOUT));
    });
    match rx.recv_timeout(ENDS_BY) {
        Ok(out) => assert!(matches!(out, Err(OpenFail::Denied)), "the D byte refuses once the pipe drains"),
        Err(_) => panic!("the reap waited out a full stderr pipe"),
    }
}

// The test binary again, running only the child half, so the helper client's own stderr is the process's stderr.
#[test]
fn stderr_child() {
    let Some(path) = std::env::var_os("FLEA_TEST_HELPER") else { return };
    let path = path.to_string_lossy().to_string();
    match std::env::var("FLEA_TEST_HELPER_CALL").as_deref() {
        Ok("eject") => drop(eject_at(&path, "sda", SHORT_LIMIT)),
        Ok("open") => drop(open_device_at(&path, "sda", "", 0, &mut || {}, SHORT_LIMIT)),
        _ => {}
    }
}

fn helper_stderr(call: &str, helper: &str) -> String {
    let out = std::process::Command::new("timeout")
        .arg("30")
        .arg(std::env::current_exe().expect("the test binary"))
        .args(["--exact", "backend::flashhelper::tests::stderr_child", "--nocapture", "--test-threads=1"])
        .env("FLEA_TEST_HELPER", helper)
        .env("FLEA_TEST_HELPER_CALL", call)
        .output()
        .expect("the client runs");
    String::from_utf8_lossy(&out.stderr).to_string()
}

// Every eject failure still answers the protocol word, and also says on stderr which helper failed and why.
#[test]
fn a_failed_eject_names_the_helper_and_the_reason() {
    let d = TestDir::new("flashhelper-eject-log");
    let silent = d.script("silent", &format!("#!/bin/sh\nexec sleep {LONG_WAIT}\n")).to_string_lossy().to_string();
    let exits = d.script("exits", "#!/bin/sh\nexit 3\n").to_string_lossy().to_string();
    let missing = helper_stderr("eject", "/nonexistent-helper");
    assert!(missing.contains("/nonexistent-helper") && missing.contains("No such file or directory"), "a missing helper names itself and the OS reason: {missing}");
    let slow = helper_stderr("eject", &silent);
    assert!(slow.contains(&silent) && slow.contains("timed out"), "a silent helper names itself and the timeout: {slow}");
    let bad = helper_stderr("eject", &exits);
    assert!(bad.contains(&exits) && bad.contains("exit status: 3"), "a failing helper names itself and its status: {bad}");
}

// An open that ends without an answer says on stderr which helper failed and why, beside the word it returns.
#[test]
fn an_open_without_an_answer_names_the_helper_and_the_reason() {
    let d = TestDir::new("flashhelper-open-log");
    let silent = d.script("silent", &format!("#!/bin/sh\nexec sleep {LONG_WAIT}\n")).to_string_lossy().to_string();
    let dies = d.script("dies", "#!/bin/sh\necho 'boom from the helper' >&2\nexit 3\n").to_string_lossy().to_string();
    let slow = helper_stderr("open", &silent);
    assert!(slow.contains(&silent) && slow.contains("/dev/sda") && slow.contains("timed out"), "a silent helper names itself and the timeout: {slow}");
    let gone = helper_stderr("open", &dies);
    assert!(gone.contains(&dies) && gone.contains("/dev/sda") && gone.contains("boom from the helper"), "a helper that dies names itself and its last line: {gone}");
}

#[test]
fn a_missing_helper_never_runs_the_spawned_hook() {
    let mut spawned = 0;
    let out = open_device_at("/nonexistent-helper", "sda", "", 0, &mut || spawned += 1, SHORT_LIMIT);
    assert!(matches!(out, Err(OpenFail::Helper(_))));
    assert_eq!(spawned, 0);
}

// A stub that records its arguments, one per line, in a file beside it.
fn recording(d: &TestDir) -> (String, std::path::PathBuf) {
    let log = d.join("args.txt");
    let body = format!("#!/bin/sh\nfor a in \"$@\"; do printf '%s\\n' \"$a\" >> '{}'; done\nprintf '%s' '{{\"drives\":[]}}'\n", log.display());
    (d.script("recorder", &body).to_string_lossy().to_string(), log)
}

#[test]
fn a_default_build_passes_the_helper_no_bench_root() {
    let d = TestDir::new("flashhelper-noseam");
    let (stub, log) = recording(&d);
    let _ = drives_text(&stub, &devs(), HELPER_TIMEOUT, Some(d.path()));
    let args = std::fs::read_to_string(&log).unwrap_or_default();
    assert_eq!(args.lines().collect::<Vec<_>>().contains(&"--loop-root"), cfg!(feature = "flash-test-seam"), "only the bench feature forwards its root: {args}");
}

// C10: the seam tells the helper its root, so a loop inside it is not called a system disk.
#[cfg(feature = "flash-test-seam")]
#[test]
fn the_seam_tells_the_helper_its_root() {
    let d = TestDir::new("flashhelper-seam");
    let (stub, log) = recording(&d);
    let _ = drives_text(&stub, &devs(), HELPER_TIMEOUT, Some(d.path()));
    let args: Vec<String> = std::fs::read_to_string(&log).unwrap().lines().map(str::to_string).collect();
    assert_eq!(args, ["drives", "--loop-root", &d.path().to_string_lossy(), "sda", "nvme0n1"]);
}
