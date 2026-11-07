// A whole-Mac name index, built once in the background and answered from memory: the Everything-like
// search without an external indexer. Roots are the user's files, the applications and every mounted
// volume; caches, trash, VCS objects and build products are listed but never descended.
use crate::backend::searchindex::{Index, LOCATE_MAX_ENTRIES};
use crate::backend::searchsyntax::Query;
use crate::backend::searchwalk::{fill_roots, locate_skip, WalkProbes};
use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

// A front end that searches the whole disk puts this in its backend's environment; the snapshot is
// then warmed in the background at launch, so the first search answers from memory. No other
// backend reads or builds it, and no front end pays its memory without asking.
pub const WARM_ENV: &str = "FLEA_INDEX_WARM";
// A cache older than this is answered from at once and rebuilt behind the answer.
pub const MAX_AGE: Duration = Duration::from_secs(12 * 60 * 60);
// How many ranked rows one answer carries; the listing asks for its own window from these.
const ANSWER_LIMIT: usize = 20_000;
const CACHE_FILE: &str = "locate.idx";

// The process's one index. The backend is a single process with one loop, so one global snapshot is
// the whole cache; a second Flea builds its own, and both write the same file through a rename.
static SLOT: Mutex<Option<Arc<Index>>> = Mutex::new(None);
// The background build and a search's root refresh can publish at once; one temp name per process
// means they must not write the same file together.
static STORE_LOCK: Mutex<()> = Mutex::new(());

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
// Each is stored as the filesystem spells it, because a filter compares its own path against these bytes
// and /var and /private/var are one folder with two spellings (macOS hands both to different callers).
pub fn roots() -> Vec<PathBuf> {
    let mut roots = Vec::new();
    if let Some(home) = std::env::var_os("HOME").map(PathBuf::from).filter(|home| home.is_absolute()) {
        roots.push(std::fs::canonicalize(&home).unwrap_or(home));
    }
    roots.push(PathBuf::from("/Applications"));
    if let Ok(entries) = std::fs::read_dir("/Volumes") {
        for entry in entries.flatten() {
            let ok = entry.file_type().map(|kind| kind.is_dir() && !kind.is_symlink()).unwrap_or(false);
            if ok {
                let path = entry.path();
                roots.push(std::fs::canonicalize(&path).unwrap_or(path));
            }
        }
    }
    roots.dedup();
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
    let _writer = STORE_LOCK.lock().unwrap_or_else(|poisoned| poisoned.into_inner());
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

// The snapshot's own mtime is its build time: a root directory newer than it holds entries the
// snapshot cannot know, which is exactly what an installed application looks like.
fn directory_time(path: &Path) -> Option<std::time::SystemTime> {
    std::fs::metadata(path).and_then(|meta| meta.modified()).ok()
}
// A root's children as the snapshot knows them, by the first path component under that root. The
// scan is byte-level and allocates only for a child's first sighting: one 700k-row index is the
// common case and this runs on the first search after an install.
fn known_children(main: &Index, roots: &[PathBuf]) -> HashSet<String> {
    let roots: Vec<(String, usize)> = roots
        .iter()
        .map(|root| {
            let text = root.to_string_lossy().into_owned();
            let len = text.len();
            (text, len)
        })
        .collect();
    let mut known = HashSet::with_capacity(256);
    for row in 0..main.len() {
        let path = main.path(row);
        for (root, len) in &roots {
            if path.len() > *len && path.starts_with(root.as_str()) && path.as_bytes()[*len] == b'/' {
                let rest = &path[*len + 1..];
                let end = rest.find('/').unwrap_or(rest.len());
                let child = &path[..*len + 1 + end];
                if !known.contains(child) {
                    known.insert(child.to_string());
                }
            }
        }
    }
    known
}
// The rows added under a changed root since the snapshot: an installed application is one bundle,
// so this walks the new child and nothing else instead of rebuilding the whole snapshot.
fn added_in(path: &Path, main: &Index, roots: &[PathBuf]) -> Option<(Vec<(PathBuf, std::time::SystemTime)>, Index)> {
    let built = directory_time(path)?;
    let stamps: Vec<(PathBuf, std::time::SystemTime)> = roots
        .iter()
        .filter_map(|root| directory_time(root).map(|then| (root.clone(), then)))
        .filter(|(_, then)| *then > built)
        .collect();
    if stamps.is_empty() {
        return None;
    }
    let enforced: Vec<PathBuf> = stamps.iter().map(|(root, _)| root.clone()).collect();
    let known = known_children(main, &enforced);
    let out = Mutex::new(Index::with_cap(LOCATE_MAX_ENTRIES));
    let mut walked: Vec<PathBuf> = Vec::new();
    for root in &enforced {
        let Ok(entries) = std::fs::read_dir(root) else { continue };
        for entry in entries.flatten() {
            // A skipped directory (.Trash, caches, VCS objects) is not in the snapshot by design, so
            // its absence there does not make it new.
            if locate_skip(&entry.file_name()) {
                continue;
            }
            let child = entry.path();
            if known.contains(&child.to_string_lossy().into_owned()) {
                continue;
            }
            let is_dir = entry.file_type().map(|kind| kind.is_dir()).unwrap_or(false);
            if is_dir && child.to_string_lossy().ends_with(".app") {
                if let Ok(mut index) = out.lock() {
                    index.push(&child, true);
                }
            }
            if is_dir {
                walked.push(child);
            } else if let Ok(mut index) = out.lock() {
                index.push(&child, false);
            }
        }
    }
    if !walked.is_empty() {
        let probes = Arc::new(WalkProbes::new());
        fill_roots(&out, &walked, &probes);
    }
    let index = out.into_inner().unwrap_or_else(|poisoned| poisoned.into_inner());
    Some((stamps, index))
}
// The side index and the stamps it was built for: one search after an install pays this walk, every
// later search in the process reuses it, and the next process walks only what is still new.
static ADDED: Mutex<Option<(Vec<(PathBuf, std::time::SystemTime)>, Arc<Index>)>> = Mutex::new(None);

fn added_index(path: &Path, main: &Index, roots: &[PathBuf]) -> Option<Arc<Index>> {
    let built = directory_time(path)?;
    let stamps: Vec<(PathBuf, std::time::SystemTime)> = roots
        .iter()
        .filter_map(|root| directory_time(root).map(|then| (root.clone(), then)))
        .filter(|(_, then)| *then > built)
        .collect();
    if stamps.is_empty() {
        return None;
    }
    if let Ok(slot) = ADDED.lock() {
        if let Some((previous, index)) = slot.as_ref() {
            if *previous == stamps {
                return Some(index.clone());
            }
        }
    }
    let (stamps, index) = added_in(path, main, roots)?;
    let index = Arc::new(index);
    if let Ok(mut slot) = ADDED.lock() {
        *slot = Some((stamps, index.clone()));
    }
    Some(index)
}
// The snapshot plus the rows added since it was written, in the snapshot's own name order.
fn query_union(main: &Index, extra: &Index, query: &Query, hidden: bool, under: Option<&str>, limit: usize) -> (Vec<(String, bool)>, usize, usize) {
    let (mut rows, matched_main, _) = query_in(main, query, hidden, under, limit);
    let (added, matched_extra, _) = query_in(extra, query, hidden, under, limit);
    rows.extend(added);
    rows.sort_by(|a, b| {
        crate::backend::sort::name_order(
            a.0.rsplit('/').next().unwrap_or("").as_bytes(),
            b.0.rsplit('/').next().unwrap_or("").as_bytes(),
        )
        .then_with(|| a.0.cmp(&b.0))
    });
    rows.truncate(limit.clamp(1, ANSWER_LIMIT));
    (rows, matched_main + matched_extra, main.len() + extra.len())
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

// One answer: the head's rows as absolute paths, every match, and the indexed population.
// None means the snapshot is not built yet, and the caller falls back to a live walk.
pub fn query(query: &Query, hidden: bool, under: Option<&str>, limit: usize) -> Option<(Vec<(String, bool)>, usize, usize)> {
    // The first whole-Mac search reads the snapshot itself, so it answers from the index rather than
    // from a walk; a missing or unreadable file leaves the caller to start the builder.
    let path = cache_path();
    let index = match ready() {
        Some(index) => index,
        None => {
            let index = load(path.as_ref()?)?;
            let stale = !fresh(path.as_ref()?);
            publish(index);
            // A stale snapshot answers now and is rebuilt behind the answer for the next launch.
            if stale {
                prepare();
            }
            ready()?
        }
    };
    // A root that moved since the snapshot was written has children the snapshot cannot know, and an
    // installed application is the common one: its new rows answer beside the snapshot's.
    if let Some(path) = path.as_ref() {
        if let Some(added) = added_index(path, &index, &roots()) {
            return Some(query_union(&index, &added, query, hidden, under, limit));
        }
    }
    Some(query_in(&index, query, hidden, under, limit))
}

// True when `path` is `dir` itself or sits in it; an empty dir means every row, as does the root.
fn inside(path: &str, dir: &str) -> bool {
    dir.is_empty()
        || (path.len() >= dir.len()
            && path.as_bytes()[..dir.len()] == *dir.as_bytes()
            && (path.len() == dir.len() || path.as_bytes()[dir.len()] == b'/'))
}

// The query itself, split out so a test answers from an index it built without the process's slot.
pub fn query_in(index: &Index, query: &Query, hidden: bool, under: Option<&str>, limit: usize) -> (Vec<(String, bool)>, usize, usize) {
    // The folder filter and the hidden rule run before matching, so a narrowed search never spends
    // its answer on rows it would drop. A bare prefix is not containment: /a/b does not hold /a/bc.
    // Directories are left out, because a whole-disk answer is a file list.
    let dir = under.unwrap_or("").trim_end_matches('/');
    let mut hits: Vec<usize> = (0..index.len())
        // Files are the answer, and so is an application bundle: a .app is a directory to the
        // filesystem but the thing a person searches for, and Enter launches it.
        .filter(|&row| {
            let path = index.path(row);
            (!index.is_dir(row) || path.ends_with(".app")) && inside(path, dir)
        })
        .filter(|&row| {
            let path = index.path(row);
            let name = path.rsplit('/').next().unwrap_or("");
            (hidden || !name.starts_with('.')) && query.matches(name, path)
        })
        .collect();
    let total = hits.len();
    // Everything answers in name order; the natural comparator is the one the listing sorts with.
    // Only the head is ever shown, so the rest is cut before it is ordered, as select_head does for
    // the walk: a query matching everything then costs one pass, not a full sort of the whole Mac.
    let name = |row: usize| index.path(row).rsplit('/').next().unwrap_or("");
    let cmp = |&a: &usize, &b: &usize| {
        crate::backend::sort::name_order(name(a).as_bytes(), name(b).as_bytes())
            .then_with(|| index.path(a).cmp(index.path(b)))
    };
    let window = limit.clamp(1, ANSWER_LIMIT).min(total);
    if window < total {
        hits.select_nth_unstable_by(window - 1, &cmp);
        hits.truncate(window);
    }
    hits.sort_by(&cmp);
    let rows = hits[..window].iter().map(|&row| (index.path(row).to_string(), index.is_dir(row))).collect();
    (rows, total, index.len())
}

#[cfg(test)]
#[path = "nameindex_tests.rs"]
mod tests;
