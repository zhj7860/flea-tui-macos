// Test-only: reads the host's process table so a test can follow a jailed child and everything below it.
use crate::backend::archivework::WORK_PREFIX;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

// How long a stub gets to reach its sleep before the watcher cancels anyway.
const BOUND: Duration = Duration::from_secs(10);
const STEP: Duration = Duration::from_millis(5);

pub struct Proc {
    pub pid: i32,
    pub ppid: i32,
    pub argv: Vec<u8>,
}

// What the watcher saw before it cancelled.
pub struct Seen {
    pub pids: Vec<i32>,
    pub slept: bool,
    // Whether a work directory under the `note` root held the `note` file when the sleep began; false with no note.
    pub noted: bool,
    pub at: Instant,
}

// Every process the host shows, the jail's pid namespace included; a pid that vanishes mid-scan is skipped.
pub fn table() -> Vec<Proc> {
    let found = std::fs::read_dir("/proc").expect("/proc").flatten().filter_map(|entry| {
        let pid = entry.file_name().to_string_lossy().parse::<i32>().ok()?;
        let stat = String::from_utf8_lossy(&std::fs::read(entry.path().join("stat")).ok()?).to_string();
        // The command name may hold spaces and parentheses, so the fields are counted from the last ')': state, then the parent.
        let ppid = stat.rsplit_once(')')?.1.split_whitespace().nth(1)?.parse().ok()?;
        Some(Proc { pid, ppid, argv: std::fs::read(entry.path().join("cmdline")).ok()? })
    });
    found.collect()
}

pub fn holds(argv: &[u8], marker: &str) -> bool {
    argv.windows(marker.len()).any(|w| w == marker.as_bytes())
}

// The root and every process below it, children first found first.
pub fn tree(procs: &[Proc], root: i32) -> Vec<&Proc> {
    let mut found: Vec<&Proc> = procs.iter().filter(|p| p.pid == root).collect();
    let mut at = 0;
    while at < found.len() {
        let parent = found[at].pid;
        found.extend(procs.iter().filter(|p| p.ppid == parent));
        at += 1;
    }
    found
}

// The stub's `sleep 20`, told by its own argv and not by the marker, which only the shell and the jail carry.
fn is_sleeper(argv: &[u8]) -> bool {
    let mut parts = argv.split(|b| *b == 0);
    parts.next().is_some_and(|name| name.ends_with(b"sleep")) && parts.next() == Some(b"20".as_slice())
}

// Sets `flag` once the jail this process spawned for a stub holding `marker` has its sleep running, so the cancel always lands on a live tree.
pub fn cancel_when_sleeping(marker: String, flag: Arc<AtomicBool>, note: Option<(PathBuf, String)>) -> std::thread::JoinHandle<Seen> {
    std::thread::spawn(move || {
        let me = std::process::id() as i32;
        let bound = Instant::now() + BOUND;
        let mut pids: Vec<i32> = Vec::new();
        let slept = loop {
            let procs = table();
            let below = procs.iter().find(|p| p.ppid == me && holds(&p.argv, &marker)).map(|root| tree(&procs, root.pid));
            let below = below.unwrap_or_default();
            for p in &below {
                if !pids.contains(&p.pid) {
                    pids.push(p.pid);
                }
            }
            let slept = below.iter().any(|p| is_sleeper(&p.argv));
            if slept || Instant::now() >= bound {
                break slept;
            }
            std::thread::sleep(STEP);
        };
        // The work directory dies with the job, so the file is read here, before the cancel lets the job end.
        let noted = note.is_some_and(|(root, file)| std::fs::read_dir(root).into_iter().flatten().flatten().any(|e| {
            e.file_name().to_string_lossy().starts_with(WORK_PREFIX) && e.path().join(&file).exists()
        }));
        flag.store(true, Ordering::Relaxed);
        Seen { pids, slept, noted, at: Instant::now() }
    })
}
