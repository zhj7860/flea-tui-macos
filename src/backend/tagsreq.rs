// The wire side of file tags: one write and one read, each naming rows of the listing in force.
use crate::backend::iomount::{internal_failure, is_remote, mount_body, slow_sentence, slow_write_with, CALL_DEADLINE, SlowWrite, SLOW_TAGS};
use crate::backend::opsdispatch::{pending_busy_for, resolve_rows, Ops, SlowClaim};
use crate::backend::opsreq::OpMsg;
use crate::backend::rowguard::stamped;
use crate::backend::proto::{error_line, slow_line, Request};
use crate::backend::state::State;
use crate::backend::undo::{Entry, Step};
use crate::error::FleaError;
use std::collections::HashSet;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::mpsc::Sender;
use std::time::Duration;

// What one tag change wrote: the number of files changed, one journal step for each, the op it applied, and the skipped rows by name.
pub(crate) type Written = Result<(usize, Vec<Step>, &'static str, Vec<String>), FleaError>;

// Sample output: {"t":"settagged","ok":2,"op":"remove"}
pub fn settagged_line(ok: usize, op: &str) -> String {
    format!(r#"{{"t":"settagged","ok":{},"op":"{}"}}"#, ok, op)
}

// Sample output with a skip: {"t":"settagged","ok":2,"op":"add","skipped":["c.lnk"]}.
fn settagged_skipped(ok: usize, op: &str, skipped: &[String]) -> String {
    if skipped.is_empty() {
        return settagged_line(ok, op);
    }
    format!(r#"{{"t":"settagged","ok":{},"op":"{}","skipped":{}}}"#, ok, op, crate::json::string_array(skipped))
}

// The listing's own name for a skipped row: its path under the base, as a search or listpaths row shows it, else the whole path.
fn row_name(base: &Path, path: &Path) -> String {
    path.strip_prefix(base).unwrap_or(path).to_string_lossy().into_owned()
}

// The tag wire's two requests (a change across rows, and the read of what those rows carry) answer the files whose tags changed in time, so the loop can tell an open search session; a late write reports through SetTagsDone.
pub fn handle(out: &mut impl Write, ops: &mut Ops, st: &State, request: Request) -> Vec<PathBuf> {
    match request {
        Request::SetTags { rows, op, tag } => return apply_tags(out, ops, st, rows, &op, &tag),
        Request::TagStates { rows, id } => ask_states(st, &rows, id, ops.tx.clone()),
        _ => {}
    }
    Vec::new()
}

fn carries(names: &[String], tag: &str) -> bool {
    names.iter().any(|name| name.eq_ignore_ascii_case(tag.trim()))
}

// A toggle over a set is one decision for all of them: remove where every target carries the tag, otherwise add.
pub(crate) fn resolved(op: &str, tag: &str, carried: &[Vec<String>]) -> &'static str {
    match op {
        "clear" => "clear",
        "add" => "add",
        "remove" => "remove",
        _ if !carried.is_empty() && carried.iter().all(|names| carries(names, tag)) => "remove",
        _ => "add",
    }
}

// Sample input: {"c":"tagstates","rows":[0,4000],"id":3,"listing":7}
// Read on a thread as shebang is, because a getxattr on a hung mount never returns.
pub fn ask_states(st: &State, rows: &[usize], id: usize, tx: Sender<OpMsg>) {
    let paths: Vec<PathBuf> = resolve_rows(Vec::new(), rows, &st.base, &st.listing).into_iter().map(PathBuf::from).collect();
    let generation = st.generation;
    let body = mount_body();
    // A stuck mount answers untagged at once, so no menu open parks a reader thread on it.
    if let Some(first) = paths.first() {
        let stuck = matches!(crate::backend::iomount::call(first, &body, "tagstates", || ()), Err(refused) if refused.msg.ends_with("is not responding."));
        if stuck {
            let _ = tx.send(OpMsg::Meta { line: stamped(states_line(id, &[]), generation) });
            return;
        }
    }
    std::thread::spawn(move || {
        let carried: Vec<Vec<String>> = paths.iter().map(|path| read_bounded(path, &body)).collect();
        let _ = tx.send(OpMsg::Meta { line: stamped(states_line_for(id, &carried), generation) });
    });
}

// One tag read under the mount bound, so a timeout marks its mount and the thread still answers.
fn read_bounded(path: &Path, body: &str) -> Vec<String> {
    let owned = path.to_path_buf();
    super::iomount::call(path, body, "tagstates", move || super::tags::read(&owned).unwrap_or_default())
        .unwrap_or_default()
}

// Sample output: {"t":"tagstates","id":3,"applied":["Red"],"mixed":["Blue"]}; a file that cannot be read counts as untagged.
pub fn states_line(id: usize, paths: &[PathBuf]) -> String {
    let carried: Vec<Vec<String>> = paths.iter().map(|path| super::tags::read(path).unwrap_or_default()).collect();
    states_line_for(id, &carried)
}

fn states_line_for(id: usize, carried: &[Vec<String>]) -> String {
    let (mut applied, mut mixed) = (Vec::new(), Vec::new());
    for name in super::tags::NAMES {
        match carried.iter().filter(|names| carries(names, name)).count() {
            0 => {}
            have if have == carried.len() => applied.push(format!("\"{}\"", name)),
            _ => mixed.push(format!("\"{}\"", name)),
        }
    }
    format!(r#"{{"t":"tagstates","id":{},"applied":[{}],"mixed":[{}]}}"#, id, applied.join(","), mixed.join(","))
}

fn refuse(out: &mut impl Write, e: &FleaError) {
    writeln!(out, "{}", error_line(e)).ok();
    out.flush().ok();
}

// Refused while the transfer slot runs, unlike a local rename; the write itself runs where rename's would.
pub fn apply_tags(out: &mut impl Write, ops: &mut Ops, st: &State, rows: Vec<usize>, op: &str, tag: &str) -> Vec<PathBuf> {
    if ops.live.running().is_some() {
        refuse(out, &FleaError { where_: "settags".into(), path: String::new(), msg: "an operation is already running".into() });
        return Vec::new();
    }
    // Validated before the filesystem is touched, so a bad op refuses with nothing read.
    if let Err(e) = super::tags::apply(&[], op, tag) {
        refuse(out, &e);
        return Vec::new();
    }
    let targets = resolve_rows(Vec::new(), &rows, &st.base, &st.listing);
    if targets.is_empty() {
        writeln!(out, "{}", settagged_line(0, resolved(op, tag, &[]))).ok();
        out.flush().ok();
        return Vec::new();
    }
    let paths: Vec<PathBuf> = targets.iter().map(PathBuf::from).collect();
    let (base, work_paths, op, tag) = (st.base.clone(), paths.clone(), op.to_string(), tag.to_string());
    apply_tags_with(out, ops, paths, CALL_DEADLINE, move || write_all(&base, &work_paths, &op, &tag))
}

// A local change answers inline; a remote one past the deadline answers slow and journals when its worker lands.
pub(crate) fn apply_tags_with<F>(out: &mut impl Write, ops: &mut Ops, paths: Vec<PathBuf>, deadline: Duration, work: F) -> Vec<PathBuf>
where
    F: FnOnce() -> Written + Send + 'static,
{
    // A target on a pending mount waits; writes elsewhere run beside the held write.
    if pending_busy_for(out, ops, "settags", &paths, &[]) {
        return Vec::new();
    }
    let body = mount_body();
    // The first target on a remote mount decides, so a search row on a share never runs inline beside local ones.
    let first = paths.iter().find(|path| is_remote(path, &body)).unwrap_or(&paths[0]);
    // The row's own mount decides: a row that is itself a remote mount root is remote even where its parent is local.
    match slow_write_with(first, &body, "settags", deadline, work) {
        SlowWrite::Ready(result) => return land(out, ops, result),
        SlowWrite::Slow { mount, rx } => {
            // The slow line names the row's own directory, as the parent key did.
            let path = first.parent().unwrap_or(Path::new("/")).to_string_lossy().into_owned();
            writeln!(out, "{}", slow_line("settags", &path, &slow_sentence(&mount, SLOW_TAGS))).ok();
            out.flush().ok();
            // The pending id is only a number: settags never takes the slot, so the transfer beside it keeps its own.
            let id = ops.claim_id();
            ops.pending.push(SlowClaim { id, path, mount });
            let tx = ops.tx.clone();
            let failed = internal_failure("settags", first);
            std::thread::spawn(move || {
                let result = rx.recv().unwrap_or(Err(failed));
                let _ = tx.send(OpMsg::SetTagsDone { id, result });
            });
        }
    }
    Vec::new()
}

// One journal entry per request, so one undo reverses the in-time answer and the late one alike; answers the files it changed.
pub(crate) fn land(out: &mut impl Write, ops: &mut Ops, result: Written) -> Vec<PathBuf> {
    let mut changed = Vec::new();
    match result {
        Ok((written, steps, op, skipped)) => {
            changed = super::undo::Reached::of(&steps).tags;
            ops.journal.push(Entry { op: "settags".into(), steps });
            writeln!(out, "{}", settagged_skipped(written, op, &skipped)).ok();
        }
        Err(e) => {
            writeln!(out, "{}", error_line(&e)).ok();
        }
    }
    out.flush().ok();
    changed
}

// Every file or none: each filesystem is probed and every attribute read before the first write, and a failed write puts back exactly the files written.
fn write_all(base: &Path, paths: &[PathBuf], op: &str, tag: &str) -> Written {
    // A link cannot carry a user attribute, so the pre-pass leaves out every row that is neither a file nor a folder and names it in the answer's skipped array.
    let mut skipped = Vec::new();
    let mut kept = Vec::with_capacity(paths.len());
    for path in paths {
        // symlink_metadata never follows, so a link to a folder still reads as a link; a vanished row fails later with its own sentence.
        let taggable = match path.symlink_metadata() {
            Ok(meta) => meta.file_type().is_file() || meta.file_type().is_dir(),
            Err(_) => true,
        };
        if taggable {
            kept.push(path.clone());
        } else {
            skipped.push(row_name(base, path));
        }
    }
    let paths = &kept;
    let mut devs = HashSet::new();
    let mut befores = Vec::with_capacity(paths.len());
    for path in paths {
        let missing = |e: FleaError| FleaError { where_: "settags".into(), path: path.to_string_lossy().into(), msg: e.msg };
        let (dev, ino) = super::tagsundo::identity(path).map_err(missing)?;
        // One probe per filesystem the targets sit on, so a search row under another mount refuses by name too.
        if devs.insert(dev) {
            if let Some(refused) = super::tags::support_error(path) {
                return Err(refused);
            }
        }
        let born = path.symlink_metadata().ok().and_then(|meta| super::permissions::born_of(&meta));
        befores.push((super::tags::read_raw(path).map_err(missing)?, dev, ino, (born, super::filegen::of_path(path))));
    }
    let carried: Vec<Vec<String>> =
        befores.iter().map(|(before, ..)| before.as_ref().map(|raw| super::tags::parse(raw)).unwrap_or_default()).collect();
    let op = resolved(op, tag, &carried);
    let mut steps = Vec::new();
    for ((path, (before, dev, ino, (born, generation))), names) in paths.iter().zip(befores).zip(carried) {
        let after = match super::tags::apply(&names, op, tag) {
            Ok(after) => after,
            // Unreachable after the caller's validation; rolls back rather than half-applying anyway.
            Err(e) => {
                rollback(&steps);
                return Err(e);
            }
        };
        if names == after {
            continue;
        }
        if let Err(e) = super::tags::write_names(path, &after) {
            rollback(&steps);
            return Err(FleaError { where_: "settags".into(), path: path.to_string_lossy().into(), msg: e.msg });
        }
        let after = (!after.is_empty()).then(|| super::tags::join(&after));
        steps.push(Step::Tags { path: path.clone(), before, after, dev, ino, born, generation });
    }
    Ok((steps.len(), steps, op, skipped))
}

// Puts back exactly the files this request wrote, newest first and best effort; the error names the failure, not this.
fn rollback(steps: &[Step]) {
    for step in steps.iter().rev() {
        if let Step::Tags { path, before, .. } = step {
            let _ = super::tags::restore(path, before);
        }
    }
}

#[cfg(test)]
#[path = "tagsreq_tests.rs"]
mod tests;

#[cfg(test)]
#[path = "tagsundo_tests.rs"]
mod undo_tests;
