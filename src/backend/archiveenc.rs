// Whether a 7z-read archive asks for a password, from 7z's exit code and its technical listing keys, never its words.
use crate::backend::archive::Formats;
use crate::backend::archivelist::ARCHIVE_READ_MS;
use crate::backend::{jail, sandbox};
use std::io::{BufRead, BufReader, Read};
use std::path::Path;
use std::process::Stdio;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

// 7z exits 255 (Break signaled) when it must ask for a password and stdin is closed.
const NEEDS_PASSWORD_CODE: i32 = 255;
// One listing line is read in pieces this long, joined whole to LINE_LIMIT; a longer line is consumed untested, never matched.
const LINE_MAX: u64 = 64 * 1024;
const LINE_LIMIT: u64 = 1024 * 1024;
const POLL: Duration = Duration::from_millis(50);

// Sample `7z l -slt` lines: "Path = a.txt", "Encrypted = +". The keys are not localized.
fn encrypted_key(line: &str) -> bool {
    line.split_once(" = ").is_some_and(|(key, value)| key == "Encrypted" && value.trim_end() == "+")
}

fn verdict(code: Option<i32>, saw_encrypted: bool) -> bool {
    code == Some(NEEDS_PASSWORD_CODE) || (code == Some(0) && saw_encrypted)
}

fn scan(output: impl Read) -> bool {
    let mut reader = BufReader::new(output);
    let (mut saw, mut line) = (false, Vec::new());
    loop {
        line.clear();
        let mut whole = false;
        while (line.len() as u64) < LINE_LIMIT {
            match reader.by_ref().take(LINE_MAX).read_until(b'\n', &mut line) {
                // The listing's last line may end at EOF with no newline, and it still counts.
                Ok(0) => return saw || encrypted_key(&String::from_utf8_lossy(&line)),
                Err(_) => return saw,
                Ok(_) => {}
            }
            if line.last() == Some(&b'\n') {
                whole = true;
                break;
            }
        }
        if !whole {
            drain_line(&mut reader);
            continue;
        }
        saw |= encrypted_key(&String::from_utf8_lossy(&line));
    }
}

// The rest of an over-long line, consumed without matching so a key at a split never counts.
fn drain_line(reader: &mut impl BufRead) {
    loop {
        let mut tail = Vec::new();
        match reader.by_ref().take(LINE_MAX).read_until(b'\n', &mut tail) {
            Ok(0) | Err(_) => return,
            Ok(_) => {}
        }
        if tail.last() == Some(&b'\n') {
            return;
        }
    }
}

// The technical listing with stdin closed, in the readonly jail; None when 7z does not read the archive or nothing can be proved, or the job was cancelled.
pub fn password_needed(archive: &Path, formats: &Formats, cancel: &AtomicBool) -> Option<bool> {
    let inner = formats.technical_list_argv(archive)?;
    probe(&inner, archive, cancel)
}

// The jailed run of a technical listing argv; a cancel kills and reaps the child and answers None, which proves nothing.
fn probe(inner: &[String], archive: &Path, cancel: &AtomicBool) -> Option<bool> {
    if !sandbox::available() {
        return None;
    }
    let mut full = sandbox::wrap_readonly(inner, archive);
    sandbox::add_status(&mut full, inner.len());
    let mut jailed = jail::spawn_jailed(&full, |cmd| {
        cmd.stdin(Stdio::null());
        cmd.stdout(Stdio::piped());
        cmd.stderr(Stdio::null());
    })
    .ok()?;
    let Some(output) = jailed.child.stdout.take() else {
        jail::kill_tree(&mut jailed);
        return None;
    };
    let scanner = std::thread::spawn(move || scan(output));
    let deadline = Instant::now() + Duration::from_millis(ARCHIVE_READ_MS);
    loop {
        if cancel.load(Ordering::Relaxed) {
            jail::kill_tree(&mut jailed);
            return None;
        }
        match jailed.child.try_wait() {
            Ok(Some(status)) => return scanner.join().ok().map(|saw| verdict(status.code(), saw)),
            Ok(None) if Instant::now() < deadline => std::thread::sleep(POLL),
            _ => {
                jail::kill_tree(&mut jailed);
                return None;
            }
        }
    }
}

#[cfg(test)]
#[path = "archiveenc_tests.rs"]
mod tests;
