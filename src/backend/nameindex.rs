// A whole-Mac name index, built once in the background and answered from memory: the Everything-like
// search without an external indexer. Roots are the user's files, the applications and every mounted
// volume; caches, trash, VCS objects and build products are listed but never descended.
use crate::backend::fuzzy::{rank_order, Fuzzy};
use crate::backend::searchindex::{self, Index, LOCATE_MAX_ENTRIES};
use crate::backend::searchwalk::{fill_roots, WalkProbes};
use std::cmp::Reverse;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, LazyLock, Mutex};
use std::time::Duration;

// A cache older than this is answered from at once and rebuilt behind the answer.
pub const MAX_AGE: Duration = Duration::from_secs(12 * 60 * 60);
// How many ranked rows one answer carries; the listing asks for its own window from these.
const ANSWER_LIMIT: usize = 20_000;
const CACHE_FILE: &str = "locate.idx";

// The process's one index. The backend is a single process with one loop, so one global snapshot is
// the whole cache; a second Flea builds its own, and both write the same file through a rename.
static SLOT: LazyLock<Mutex<Option<Arc<Index>>>> = LazyLock::new(|| Mutex::new(None));

fn slot() -> &'static Mutex<Option<Arc<Index>>> {
    &SLOT
}

fn publish(index: Index) {
    *slot().lock().unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(Arc::new(index));
}

fn ready() -> Option<Arc<Index>> {
    slot().lock().unwrap_or_else(|poisoned| poisoned.into_inner()).clone()
}

// Sample roots: the home tree, /Applications and every mounted volume; /Volumes/<boot> is a link and is skipped.
pub fn roots() -> Vec<PathBuf> {
    let mut roots = Vec::new();
    if let Some(home) = std::env::var_os("HOME").map(PathBuf::from).filter(|home| home.is_absolute()) {
        roots.push(home);
    }
    roots.push(PathBuf::from("/Applications"));
    if let Ok(entries) = std::fs::read_dir("/Volumes") {
        for entry in entries.flatten() {
            let ok = entry.file_type().map(|kind| kind.is_dir() && !kind.is_symlink()).unwrap_or(false);
            if ok {
                roots.push(entry.path());
            }
        }
    }
    roots
}

// $XDG_CACHE_HOME/flea on Linux, ~/Library/Caches/flea on a Mac, and the XDG dir when the session sets one.
pub fn cache_path() -> Option<PathBuf> {
    let dir = match std::env::var_os("XDG_CACHE_HOME").map(PathBuf::from).filter(|p| p.is_absolute()) {
        Some(cache) => cache.join("flea"),
        None => {
            let home = std::env::var_os("HOME").map(PathBuf::from).filter(|p| p.is_absolute())?;
            #[cfg(target_os = "macos")]
            {
                home.join("Library/Caches/flea")
            }
            #[cfg(not(target_os = "macos"))]
            {
                home.join(".cache/flea")
            }
        }
    };
    Some(dir.join(CACHE_FILE))
}

fn fresh(path: &Path) -> bool {
    std::fs::metadata(path)
        .and_then(|meta| meta.modified())
        .ok()
        .and_then(|then| then.elapsed().ok())
        .is_some_and(|age| age < MAX_AGE)
}

// The stored snapshot, or None when it is missing, foreign or truncated.
pub fn load(path: &Path) -> Option<Index> {
    Index::from_bytes(&std::fs::read(path).ok()?)
}

// A temp file in the same directory plus a rename, so a reader sees the old snapshot or the new one.
pub fn store(path: &Path, index: &Index) {
    use std::io::Write;
    use std::os::unix::fs::OpenOptionsExt;
    let Some(dir) = path.parent() else { return };
    if std::fs::create_dir_all(dir).is_err() {
        return;
    }
    let temp = dir.join(format!(".{}.{}.tmp", CACHE_FILE, std::process::id()));
    let write = || -> std::io::Result<()> {
        let mut file = std::fs::OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(&temp)?;
        file.write_all(&index.to_bytes())?;
        file.sync_all()
    };
    if write().is_ok() && std::fs::rename(&temp, path).is_ok() {
        return;
    }
    let _ = std::fs::remove_file(&temp);
}

// Builds the snapshot from the roots. Public so a test drives the real walk on its own tree.
pub fn build(roots: &[PathBuf]) -> Index {
    let out = Mutex::new(Index::with_cap(LOCATE_MAX_ENTRIES));
    let probes = Arc::new(WalkProbes::new());
    fill_roots(&out, roots, &probes);
    out.into_inner().unwrap_or_else(|poisoned| poisoned.into_inner())
}

// The one background load-or-build, started by the first whole-Mac search and never at launch: a
// snapshot is hundreds of megabytes, and most sessions never ask for one. An existing snapshot is
// published at once and a stale one is rebuilt behind it.
pub fn prepare() {
    static STARTED: AtomicBool = AtomicBool::new(false);
    if STARTED.swap(true, Ordering::SeqCst) {
        return;
    }
    let spawned = std::thread::Builder::new().name("flea-locate".into()).spawn(|| {
        let path = cache_path();
        let cached = path.as_ref().and_then(|path| load(path));
        let already_fresh = path.as_ref().is_some_and(|path| fresh(path));
        if let Some(cached) = cached {
            publish(cached);
            if already_fresh {
                return;
            }
        }
        let index = build(&roots());
        if let Some(path) = path.as_ref() {
            store(path, &index);
        }
        publish(index);
    });
    let _ = spawned;
}

// One ranked answer: the head's rows as absolute paths, every match, and the indexed population.
// None means the snapshot is not built yet, and the caller falls back to a live walk.
pub fn query(text: &str, hidden: bool, limit: usize) -> Option<(Vec<(String, bool)>, usize, usize)> {
    // The first whole-Mac search reads the snapshot itself, so it answers from the index rather than
    // from a walk; a missing or unreadable file leaves the caller to start the builder.
    let index = match ready() {
        Some(index) => index,
        None => {
            let path = cache_path()?;
            let index = load(&path)?;
            let stale = !fresh(&path);
            publish(index);
            // A stale snapshot answers now and is rebuilt behind the answer for the next launch.
            if stale {
                prepare();
            }
            ready()?
        }
    };
    Some(query_in(&index, text, hidden, limit))
}

// The query itself, split out so a test answers from an index it built without the process's slot.
pub fn query_in(index: &Index, text: &str, hidden: bool, limit: usize) -> (Vec<(String, bool)>, usize, usize) {
    let text = text.trim();
    if text.is_empty() {
        return (Vec::new(), 0, index.len());
    }
    let fuzzy = Fuzzy::new(text);
    let candidates: Vec<usize> = (0..index.len()).collect();
    let mut hits = searchindex::score_all(&fuzzy, &candidates, &index);
    if !hidden {
        // A result's own name is the last component; the index keeps hidden rows so one snapshot serves both toggles.
        hits.retain(|(_, row)| !index.path(*row).rsplit('/').next().is_some_and(|name| name.starts_with('.')));
    }
    let total = hits.len();
    let window = limit.clamp(1, ANSWER_LIMIT).min(hits.len());
    let cmp = |a: &(i32, usize), b: &(i32, usize)| rank_order(a.0, index.path(a.1), b.0, index.path(b.1));
    searchindex::select_head(&mut hits, window, |hit| (Reverse(hit.0), index.path_len(hit.1)), cmp);
    let rows = hits[..window].iter().map(|&(_, row)| (index.path(row).to_string(), index.is_dir(row))).collect();
    (rows, total, index.len())
}

#[cfg(test)]
#[path = "nameindex_tests.rs"]
mod tests;
