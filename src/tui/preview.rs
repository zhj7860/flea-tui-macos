use super::model::Model;
use crate::backend::regfile;
use crate::oflags::O_NOFOLLOW;
use std::io::Read;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::{atomic::{AtomicBool, Ordering}, mpsc::{self, Receiver}, Arc};

const TEXT_BYTES: u64 = 1024 * 1024;
#[derive(Default)]
pub struct Reader {
    pending: Option<(PathBuf, usize)>,
    running: Option<(usize, Arc<AtomicBool>, Receiver<Result<String, String>>)>,
}
impl Reader {
    fn request(&mut self, path: PathBuf, generation: usize) {
        self.cancel();
        self.pending = Some((path, generation));
        self.start();
    }
    // A read for this generation is still out: queued, or running and not cancelled.
    pub fn outstanding(&self, generation: usize) -> bool {
        self.pending.as_ref().is_some_and(|(_, queued)| *queued == generation)
            || self.running.as_ref().is_some_and(|(running, cancel, _)| *running == generation && !cancel.load(Ordering::Relaxed))
    }
    pub fn cancel(&mut self) {
        self.pending = None;
        if let Some((_, cancel, _)) = &self.running { cancel.store(true, Ordering::Relaxed); }
    }
    fn start(&mut self) {
        if self.running.is_some() { return; }
        let Some((path, generation)) = self.pending.take() else { return };
        let cancel = Arc::new(AtomicBool::new(false));
        let stopped = cancel.clone();
        let (tx, receiver) = mpsc::channel();
        std::thread::spawn(move || { let _ = tx.send(read_text(&path, &stopped)); });
        self.running = Some((generation, cancel, receiver));
    }
    fn poll(&mut self) -> Option<(usize, Result<String, String>)> {
        let (generation, cancel, receiver) = self.running.as_ref()?;
        let result = match receiver.try_recv() {
            Ok(result) => result,
            Err(mpsc::TryRecvError::Empty) => return None,
            Err(mpsc::TryRecvError::Disconnected) => Err("Text preview reader stopped.".into()),
        };
        let generation = *generation;
        let accepted = !cancel.load(Ordering::Relaxed);
        self.running = None;
        self.start();
        accepted.then_some((generation, result))
    }
}
impl Drop for Reader {
    fn drop(&mut self) { self.cancel(); }
}
fn read_text(path: &Path, cancel: &AtomicBool) -> Result<String, String> {
    const READ_FAILED: &str = "This file could not be read.";
    let before = path.symlink_metadata().map_err(|_| READ_FAILED)?;
    let mut file = regfile::open_if_regular(path, O_NOFOLLOW).map_err(|_| READ_FAILED)?;
    if !file.metadata().is_ok_and(|after| before.dev() == after.dev() && before.ino() == after.ino()) {
        return Err("Selected item changed".into());
    }
    let mut bytes = Vec::new();
    let mut chunk = [0; 8192];
    loop {
        if cancel.load(Ordering::Relaxed) { return Err("Preview cancelled".into()); }
        let count = file.read(&mut chunk).map_err(|_| READ_FAILED)?;
        if count == 0 { break; }
        if bytes.len() as u64 + count as u64 > TEXT_BYTES { return Err("This file is too large to preview.".into()); }
        bytes.extend_from_slice(&chunk[..count]);
    }
    if bytes.contains(&0) { return Ok(String::new()); }
    let mut body = String::new();
    for c in String::from_utf8_lossy(&bytes).chars() {
        if c == '\t' { body.push_str("        "); }
        else if c == '\n' || super::render::safe(c) { body.push(c); }
    }
    Ok(body)
}
pub fn load(m: &mut Model, force: bool) {
    // The answer under the cursor changes with every keystroke; decoding each one is work nobody asked
    // for, and Enter ends the query line.
    if m.editor.as_ref().is_some_and(|editor| editor.kind == "search") {
        m.preview_reader.cancel();
        m.preview_path.clear();
        m.preview.clear();
        m.preview_body.clear();
        return;
    }
    if m.selected.len() > 1 || (!m.preview_visible && !m.quicklook) {
        m.preview_reader.cancel();
        m.preview_path.clear();
        return;
    }
    let Some(path) = m.current_path() else {
        return;
    };
    if !force && path == m.preview_path {
        return;
    }
    m.preview_reader.cancel();
    m.preview_path = path.clone();
    m.preview_loaded = force || m.preview_auto || m.quicklook;
    m.preview_generation = m.preview_generation.wrapping_add(1);
    m.preview_failed = None;
    m.preview_scroll = 0;
    m.preview.clear();
    m.preview_body.clear();
    m.preview_metadata.clear();
    m.media_probe = None;
    m.preview_children = None;
    let Some(row) = m.rows.get(&m.cursor) else {
        return;
    };
    // A search result carries its whole path in the name, so the title is the file's own name and
    // the folder sits under it: a narrow preview then shows the name before the path wraps over it.
    let (parent, leaf) = row.name.rsplit_once('/').unwrap_or(("", row.name.as_str()));
    m.preview.push(leaf.to_string());
    if !parent.is_empty() {
        m.preview.push(format!("{parent}/"));
    }
    m.preview
        .push(format!("{} · {}", row.kind, super::render::bytes(row.size)));
    if row.modified > 0 {
        m.preview_metadata.push(format!(
            "Modified · {}",
            super::render::modified(row.modified)
        ));
    }
    if !row.link.is_empty() {
        m.preview.push(format!("→ {}", row.link));
        return;
    }
    if !m.preview_loaded {
        if !m.hints.load_preview.is_empty() {
            m.preview.push(format!("{} to load preview", m.hints.load_preview));
        }
        return;
    }
    if row.directory {
        m.preview.push("Folder".into());
        return;
    }
    if !row.icon.starts_with("text") && !row.kind.to_lowercase().contains("source") {
        return;
    }
    if row.size as u64 > TEXT_BYTES {
        m.preview.push("This file is too large to preview.".into());
        return;
    }
    m.preview.push("Loading…".into());
    m.preview_reader.request(path, m.preview_generation);
}
pub fn poll(m: &mut Model) {
    let Some((generation, result)) = m.preview_reader.poll() else { return };
    if generation != m.preview_generation { return; }
    // Keep every header line the load wrote (a name, possibly a folder, a kind and a size) and drop
    // the "Loading…" that stood in the body's place.
    match m.preview.iter().rposition(|line| line == "Loading…") {
        Some(at) => m.preview.truncate(at),
        None => m.preview.truncate(2),
    }
    match result {
        Ok(body) => { m.preview.push(String::new()); m.preview_body = body; }
        Err(error) => m.preview.push(error),
    }
    m.preview_width = 0;
}
pub fn request(m: &mut Model, wire: &mut super::wire::Wire) -> std::io::Result<()> {
    use super::wire::{number, word};
    use crate::jsondoc::Json;
    if !m.preview_loaded
        || m.preview_requested == m.preview_generation
        || m.selected.len() > 1
        || (!m.preview_visible && !m.quicklook)
    {
        return Ok(());
    }
    let Some(row) = m.rows.get(&m.cursor) else {
        return Ok(());
    };
    if m.current_path().as_ref() != Some(&m.preview_path) {
        return Ok(());
    }
    m.preview_requested = m.preview_generation;
    if row.directory {
        m.preview_children = Some(m.preview_path.clone());
        wire.send(vec![
            ("c", word("peek")),
            ("path", word(&m.preview_path.to_string_lossy())),
            ("first", number(m.height)),
            ("hidden", Json::Bool(m.hidden)),
        ])?;
    } else {
        wire.send(vec![
            ("c", word("meta")),
            ("row", number(m.cursor)),
            ("token", number(m.preview_requested)),
            ("text", Json::Bool(false)),
            (
                "media",
                Json::Bool(row.icon.starts_with("audio") || row.icon.starts_with("video")),
            ),
            ("archive", Json::Bool(row.icon.contains("package"))),
        ])?;
    }
    Ok(())
}
pub fn layout(m: &mut Model) {
    let columns = if m.quicklook || m.preview_visible { super::render::preview_area(m.columns, m.quicklook).1 } else { 0 };
    let changed = m.preview_width != columns || m.preview_layout_generation != m.preview_generation;
    if !changed
        && m.preview_layout_scroll == m.preview_scroll
        && m.preview_layout_height == m.height
    {
        return;
    }
    m.preview_width = columns;
    m.preview_layout_generation = m.preview_generation;
    let lines = || {
        m.preview
            .iter()
            .chain(m.preview_metadata.iter())
            .map(String::as_str)
            .chain(m.preview_body.lines())
            .flat_map(|line| super::render::Wrapped::new(line, columns))
    };
    if changed {
        m.preview_line_count = lines().count();
    }
    m.preview_scroll = m.preview_scroll.min(m.preview_line_count.saturating_sub(1));
    let shown: Vec<String> = lines()
        .skip(m.preview_scroll)
        .take(m.height)
        .map(super::render::clean)
        .collect();
    m.preview_display = shown;
    // The lines these cells named are gone (another file, a scroll, a resize).
    m.preview_select = None;
    m.preview_selecting = false;
    m.preview_layout_scroll = m.preview_scroll;
    m.preview_layout_height = m.height;
}
#[cfg(test)]
mod tests {
    use super::*;
    use crate::{backend::testdir::TestDir, jsondoc::Json, tui::model::Row};
    #[test]
    fn text_preview_neutralizes_controls_and_refuses_symlink() {
        let d = TestDir::new("tui-preview");
        d.file("note.txt", "hello\x1b[31m\n\u{202e}world");
        let mut m = Model::new(d.path().into(), &Json::Null);
        m.rows.insert(
            0,
            Row {
                name: "note.txt".into(),
                directory: false,
                size: 20,
                mode: 0o100644,
                link: String::new(),
                kind: "Plain text document".into(),
                thumbnail: false,
                modified: 0,
                icon: "text-x-generic".into(),
            },
        );
        load(&mut m, true);
        let body = read_text(&d.join("note.txt"), &AtomicBool::new(false)).unwrap();
        assert!(!body.contains('\x1b'));
        assert!(!body.contains('\u{202e}'));
        assert!(body.contains("hello"));
        m.preview_auto = false;
        d.file("next.txt", "next body");
        m.rows.get_mut(&0).unwrap().name = "next.txt".into();
        load(&mut m, false);
        assert!(m.preview_body.is_empty());
        assert!(!m.preview_loaded);
        assert_eq!(m.preview[0], "next.txt");
        load(&mut m, true);
        assert!(m.preview_loaded);
        assert_eq!(read_text(&d.join("next.txt"), &AtomicBool::new(false)).unwrap(), "next body");
        m.preview_visible = false;
        m.rows.get_mut(&0).unwrap().name = "note.txt".into();
        load(&mut m, true);
        assert!(m.preview_path.as_os_str().is_empty());
        assert!(m.preview_reader.pending.is_none());
        m.quicklook = true;
        load(&mut m, true);
        assert_eq!(m.preview_path, d.join("note.txt"));
        std::os::unix::fs::symlink(d.join("note.txt"), d.join("link")).unwrap();
        m.rows.get_mut(&0).unwrap().name = "link".into();
        load(&mut m, true);
        assert_eq!(read_text(&d.join("link"), &AtomicBool::new(false)).unwrap_err(), "This file could not be read.");
    }
    // A search result's row name is the whole path; the preview titles it with the file's own name
    // and puts the folder under it, so the narrow pane shows the name first.
    #[test]
    fn a_search_row_titles_the_preview_with_the_files_own_name() {
        let d = TestDir::new("tui-preview-search");
        let folder = "Final Signed FRS/Integration/ISD";
        let leaf = "Huawei CRM ISD Restful API Reference Guide.pdf";
        std::fs::create_dir_all(d.path().join(folder)).expect("the folders are made");
        d.file(&format!("{folder}/{leaf}"), "body");
        let mut m = Model::new(d.path().into(), &Json::Null);
        m.search_page = true;
        m.rows.insert(0, Row {
            name: d.join(folder).join(leaf).display().to_string(),
            directory: false,
            size: 4,
            mode: 0o100644,
            link: String::new(),
            kind: "PDF document".into(),
            thumbnail: false,
            modified: 0,
            icon: "application-pdf".into(),
        });
        m.preview_visible = true;
        m.preview_auto = false;
        load(&mut m, false);
        assert_eq!(m.preview[0], leaf);
        assert_eq!(m.preview[1], format!("{}/", d.join(folder).display()));
        assert_eq!(m.preview[2], "PDF document · 4 B");
        layout(&mut m);
        let shown = m.preview_display.join("");
        assert!(shown.contains("Final Signed FRS"), "{shown}");
        assert!(shown.contains("PDF document"), "{shown}");
    }
    // The hint under an unloaded preview names the key the keymap binds, and says nothing when none is bound.
    #[test]
    fn the_load_hint_names_the_key_the_keymap_binds() {
        let rebound = crate::tui::keymap::Map::parse(r##"
[[preset]]
name = "default"
mods = "ctrl"
key = "P"
action = "loadPreview"
context = "listing"
"##);
        let d = TestDir::new("tui-preview-hint");
        d.file("note.txt", "body");
        let mut m = Model::new(d.path().into(), &Json::Null);
        let row = Row { name: "note.txt".into(), directory: false, size: 4, mode: 0o100644, link: String::new(), kind: "Plain text document".into(), thumbnail: false, modified: 0, icon: "text-x-generic".into() };
        m.rows.insert(0, row);
        m.preview_visible = true;
        m.preview_auto = false;
        m.hints = crate::tui::keymap::Hints::new(&crate::tui::keymap::Map::load(), "default");
        load(&mut m, false);
        assert_eq!(m.preview.last().unwrap(), "Ctrl+Space to load preview");
        m.hints = crate::tui::keymap::Hints::new(&rebound, "default");
        m.preview_path.clear();
        load(&mut m, false);
        assert_eq!(m.preview.last().unwrap(), "Ctrl+P to load preview");
        m.hints.load_preview.clear();
        m.preview_path.clear();
        load(&mut m, false);
        assert!(!m.preview.iter().any(|line| line.contains("load preview")), "{:?}", m.preview);
    }
    #[test]
    fn text_reader_replaces_pending_work_and_discards_stale_results() {
        let sandbox = TestDir::new("tui-text-reader");
        let path = sandbox.file("next.txt", "current body");
        let (tx, receiver) = mpsc::channel();
        let cancel = Arc::new(AtomicBool::new(false));
        let mut reader = Reader::default();
        reader.running = Some((1, cancel.clone(), receiver));
        reader.request(path, 2);
        assert!(cancel.load(Ordering::Relaxed));
        tx.send(Ok("stale body".into())).unwrap();
        assert!(reader.poll().is_none());
        let (generation, _, receiver) = reader.running.take().unwrap();
        assert_eq!(generation, 2);
        assert_eq!(receiver.recv_timeout(std::time::Duration::from_secs(5)).unwrap().unwrap(), "current body");
    }
}
