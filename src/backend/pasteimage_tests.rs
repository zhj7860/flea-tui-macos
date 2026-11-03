use super::*;
use crate::backend::testdir::TestDir;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::process::CommandExt;

const UMASK_CHILD_TEST: &str = "backend::pasteimage::paste_tests::a_paste_under_umask_077_child";
const UMASK_CHILD_DEST: &str = "FLEA_PASTE_UMASK_DEST";

// libc is no dependency here, so umask is declared, not linked: it lives in the libc every Linux process links.
extern "C" {
    fn umask(mask: u32) -> u32;
}

// A paste never touches another paste's temp: the old per-process name holding "other" survives a paste.
#[test]
fn a_paste_leaves_another_pastes_temp_alone() {
    let d = TestDir::new("pasteimage-othertemp");
    let dest = d.dir("dest");
    let old = dest.join(format!(".flea-paste-{}.tmp", std::process::id()));
    std::fs::write(&old, "other").unwrap();
    let argv = ["sh".to_string(), "-c".to_string(), "printf 'PNGDATA'".to_string()];
    let (line, _) = execute(&dest, "a.png", &argv);
    assert!(line.contains(r#""t":"made""#), "a paste answers made, got {}", line);
    assert_eq!(std::fs::read(&old).unwrap(), b"other", "the other paste's temp was clobbered");
}

// The child half of the umask test: it pastes only when the parent names a destination.
#[test]
fn a_paste_under_umask_077_child() {
    let Some(dest) = std::env::var_os(UMASK_CHILD_DEST) else { return };
    let argv = ["sh".to_string(), "-c".to_string(), "printf 'PNGDATA'".to_string()];
    let (line, _) = execute(std::path::Path::new(&dest), "a.png", &argv);
    assert!(line.contains(r#""t":"made""#), "a paste answers made, got {}", line);
}

// A paste takes the umask mode (0600 under 077, not a chmod'd 0644); the umask is process-wide, so the paste runs in a child test with its own.
#[test]
fn a_paste_takes_the_umask_mode() {
    let d = TestDir::new("pasteimage-umask");
    let dest = d.dir("dest");
    let mut child = std::process::Command::new(std::env::current_exe().expect("the test binary"));
    child.arg("--exact").arg(UMASK_CHILD_TEST).arg("--nocapture").env(UMASK_CHILD_DEST, &dest);
    unsafe { child.pre_exec(|| { umask(0o077); Ok(()) }); }
    let result = child.output().expect("the child test runs");
    let stdout = String::from_utf8_lossy(&result.stdout);
    assert!(result.status.success() && stdout.contains(&format!("test {} ... ok", UMASK_CHILD_TEST)), "child test: {}", stdout);
    let mode = dest.join("a.png").symlink_metadata().unwrap().permissions().mode() & 0o777;
    assert_eq!(mode, 0o600, "a paste under umask 077 lands 0600");
}

// The free name is chosen on the paste thread after the clipboard answers: a name taken meanwhile lands beside it.
#[test]
fn the_free_name_is_chosen_on_the_paste_thread() {
    let d = TestDir::new("pasteimage-racename");
    let dest = d.dir("dest");
    let gate = dest.join("gate");
    assert!(std::process::Command::new("mkfifo").arg(&gate).status().expect("mkfifo").success());
    let script = format!("cat '{}' > /dev/null; printf 'PNGDATA'", gate.display());
    let argv = vec!["sh".to_string(), "-c".to_string(), script];
    let held = dest.clone();
    let worker = std::thread::spawn(move || execute(&held, "a.png", &argv));
    // Opening the gate for writing blocks until the clipboard child holds it open for reading.
    let writer = std::fs::OpenOptions::new().write(true).open(&gate).expect("the paste holds the gate");
    std::fs::write(dest.join("a.png"), "taken").unwrap();
    drop(writer);
    let (line, _) = worker.join().expect("the paste thread");
    assert!(line.contains("a (2).png"), "the taken name lands beside it, got {}", line);
    assert_eq!(std::fs::read(dest.join("a (2).png")).unwrap(), b"PNGDATA");
}

// An image past the cap broke the reader and killed the pipe, so the writer's failure still answers too large.
#[test]
fn an_oversize_image_is_too_large_even_when_the_writer_dies() {
    let argv = ["sh".to_string(), "-c".to_string(), "head -c 280000000 /dev/zero; exit 1".to_string()];
    assert_eq!(read_paste(&argv), Err("the clipboard image is too large to paste".to_string()));
}

// A failed clipboard with little output is an empty clipboard, not a large image.
#[test]
fn a_failed_clipboard_with_little_output_is_nothing_to_paste() {
    let argv = ["sh".to_string(), "-c".to_string(), "printf 'x'; exit 3".to_string()];
    assert_eq!(read_paste(&argv), Ok(Vec::new()));
}
