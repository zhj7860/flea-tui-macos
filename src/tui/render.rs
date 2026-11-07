use super::{
    keymap::Map,
    model::{Model, Row},
    theme::Theme,
};
use std::io::{self, Write};

extern "C" {
    fn wcwidth(c: i32) -> i32;
    fn ctime_r(time: *const i64, buffer: *mut std::ffi::c_char) -> *mut std::ffi::c_char;
}
pub fn clean(text: &str) -> String {
    text.chars().filter(|c| safe(*c)).collect()
}
pub fn safe(c: char) -> bool {
    !c.is_control()
        && !matches!(c,'\u{202a}'..='\u{202e}'|'\u{2066}'..='\u{2069}'|'\u{200e}'|'\u{200f}'|'\u{061c}')
}
fn width(c: char) -> usize {
    let n = unsafe { wcwidth(c as i32) };
    if n < 0 {
        1
    } else {
        n as usize
    }
}
pub fn text_width(text: &str) -> usize {
    clean(text).chars().map(width).sum()
}
pub struct Wrapped<'a> {
    remaining: Option<&'a str>,
    columns: usize,
}
impl<'a> Wrapped<'a> {
    pub fn new(text: &'a str, columns: usize) -> Self {
        Self {
            remaining: (columns > 0).then_some(text),
            columns,
        }
    }
}
impl<'a> Iterator for Wrapped<'a> {
    type Item = &'a str;
    fn next(&mut self) -> Option<Self::Item> {
        let text = self.remaining.take()?;
        let mut used = 0;
        for (offset, c) in text.char_indices() {
            let cells = width(c);
            if used + cells > self.columns && offset > 0 {
                self.remaining = Some(&text[offset..]);
                return Some(&text[..offset]);
            }
            used += cells;
        }
        Some(text)
    }
}
// The layout without the parent rule, kept for the tests that pin the shared arithmetic.
#[cfg(test)]
pub fn panes(columns: usize, preview: bool) -> (usize, usize, usize) {
    panes_for(columns, preview, true)
}
// A path with no parent (the root) has no parent pane to draw, so the current column takes its
// width and its separator instead of leaving an empty first column on screen.
pub fn panes_for(columns: usize, preview: bool, has_parent: bool) -> (usize, usize, usize) {
    // Tui.html uses border-box widths: each separator belongs to the pane on its left.
    //
    // The first column carries only the levels above the folder on screen, so it is pinned to the
    // smallest width that still draws a mark and a name: 12 columns once the window is wide enough,
    // and a quarter of the window below that. The third column keeps half of the 38% the older
    // split gave it, and the listing takes everything the two give up.
    const LEFT_MIN: usize = 12;
    const PREVIEW_SHARE: usize = 19; // was 38%
    const PREVIEW_FLOOR: usize = 7; // the PDF controls and their arrows keep five columns of content
    let left = (columns / 8).min(LEFT_MIN);
    let right = if preview {
        (columns * PREVIEW_SHARE / 100).max(PREVIEW_FLOOR)
    } else {
        0
    };
    let middle = if preview {
        columns.saturating_sub(left + right + 2)
    } else {
        columns.saturating_sub(left + 1)
    };
    if has_parent {
        (left, middle, right)
    } else {
        (0, middle + left + 1, right)
    }
}
pub const BODY_ROW: usize = 3;
pub const CHROME_ROWS: usize = 4;
pub fn body_height(lines: usize) -> usize {
    lines.saturating_sub(CHROME_ROWS)
}
pub fn pane_padding(columns: usize) -> usize {
    const MIN_CONTENT: usize = 5; // A focused PDF control and both overflow arrows must remain visible.
    (columns.saturating_sub(MIN_CONTENT) / 2).min(1)
}
pub fn preview_area(columns: usize, quicklook: bool) -> (usize, usize) {
    preview_area_for(columns, quicklook, true)
}
pub fn preview_area_for(columns: usize, quicklook: bool, has_parent: bool) -> (usize, usize) {
    let (left, middle, right) = panes_for(columns, true, has_parent);
    let (start, width) = if quicklook { (0, columns) } else { (left + middle + 2, right) };
    let padding = pane_padding(width);
    (start + padding, width - padding * 2)
}
pub fn fit(text: &str, limit: usize) -> String {
    let mut result = String::new();
    let mut used = 0;
    for c in clean(text).chars() {
        let n = width(c);
        if used + n > limit {
            break;
        }
        result.push(c);
        used += n;
    }
    result.push_str(&" ".repeat(limit - used));
    result
}
fn display_path(m: &Model) -> String {
    let home = std::env::var("HOME").unwrap_or_default();
    if !home.is_empty() && m.path.starts_with(&home) {
        format!("~{}", &m.path.to_string_lossy()[home.len()..])
    } else { m.path.to_string_lossy().into_owned() }
}
fn header_title(m: &Model) -> String {
    if m.search_page {
        return match (m.search_query.is_empty(), m.searching) {
            (true, _) => "Search · every disk".into(),
            (false, true) => "Search · searching".into(),
            (false, false) => format!("Search · {} {}", grouped(m.total), word(m.total, "match", "matches")),
        };
    }
    format!("{} · {} {}", display_path(m), m.sort, if m.reverse { "▾" } else { "▴" })
}
pub fn tab_layout(m: &Model, columns: usize) -> Vec<(usize, String)> {
    let available = columns.saturating_sub(text_width(&header_title(m)).min(columns / 2));
    let label = |index: usize| format!("{} {}  ", index + 1, m.tabs[index].path.file_name().unwrap_or_default().to_string_lossy());
    let mut first = m.tab;
    let mut used = text_width(&label(m.tab)).min(available);
    while first > 0 {
        let width = text_width(&label(first - 1));
        if used + width > available { break; }
        used += width;
        first -= 1;
    }
    used = 0;
    let mut tabs = Vec::new();
    for index in first..m.tabs.len() {
        let text = label(index);
        let width = text_width(&text).min(available.saturating_sub(used));
        if width == 0 { break; }
        tabs.push((index, fit(&text, width)));
        used += width;
    }
    tabs
}
pub fn bytes(n: usize) -> String {
    const BYTES_PER_UNIT: f64 = 1000.0;
    const UNITS: [&str; 5] = ["B", "kB", "MB", "GB", "TB"];
    if n < BYTES_PER_UNIT as usize {
        return format!("{} B", n);
    }
    let mut value = n as f64;
    let mut unit = 0;
    while value >= BYTES_PER_UNIT && unit < UNITS.len() - 1 {
        value /= BYTES_PER_UNIT;
        unit += 1;
    }
    format!("{:.1} {}", value, UNITS[unit])
}
// The one-vs-many rule every counted line shares, so one item never reads "1 items".
pub fn word(n: usize, one: &'static str, many: &'static str) -> &'static str {
    if n == 1 { one } else { many }
}

// "1 item" or "1,204 items", so no caller builds a plural by hand.
pub fn items(n: usize) -> String {
    format!("{} {}", grouped(n), word(n, "item", "items"))
}

// "1 marked item" or "2 marked items", the selection count past the loaded rows.
fn marked(n: usize) -> String {
    format!("{} marked {}", grouped(n), word(n, "item", "items"))
}

// "1 row hidden by the filter", the body note the listing draws under a filtered view.
pub fn hidden_note(hidden: usize) -> String {
    format!("{} {} hidden by the filter", grouped(hidden), word(hidden, "row", "rows"))
}

// Counts of rows, items, files and matches group in thousands, the way the GUI formats them.
pub fn grouped(n: usize) -> String {
    let digits = n.to_string().into_bytes();
    let mut out = Vec::with_capacity(digits.len() + digits.len() / 3);
    for (i, &digit) in digits.iter().enumerate() {
        if i > 0 && (digits.len() - i) % 3 == 0 {
            out.push(b',');
        }
        out.push(digit);
    }
    String::from_utf8(out).unwrap_or_else(|_| n.to_string())
}
pub fn modified(mtime: i64) -> String {
    if mtime <= 0 {
        return String::new();
    }
    const SECONDS_PER_MINUTE: u64 = 60;
    const SECONDS_PER_HOUR: u64 = 3600;
    const SECONDS_PER_DAY: u64 = 86400;
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let age = now.saturating_sub(mtime as u64);
    if age < SECONDS_PER_HOUR {
        return format!("{} min", age / SECONDS_PER_MINUTE);
    }
    if age < SECONDS_PER_DAY {
        return format!("{} h", age / SECONDS_PER_HOUR);
    }
    if age < SECONDS_PER_DAY * 7 {
        return format!("{} d", age / SECONDS_PER_DAY);
    }
    let mut buffer = [0; 32];
    if unsafe { ctime_r(&mtime, buffer.as_mut_ptr()) }.is_null() {
        return String::new();
    }
    // Sample input: Mon Sep  7 23:16:02 2026; ctime_r supplies the local calendar without a subprocess.
    let stamp = unsafe { std::ffi::CStr::from_ptr(buffer.as_ptr()) }.to_string_lossy();
    let parts: Vec<&str> = stamp.split_whitespace().collect();
    if parts.len() >= 3 {
        format!("{} {}", parts[1], parts[2])
    } else {
        String::new()
    }
}
// The byte range of `text` covering drawn cells [from, to), a cell being a character's width.
fn cells_span(text: &str, from: usize, to: usize, columns: usize) -> (usize, usize) {
    if to <= from {
        return (text.len(), text.len());
    }
    let mut cell = 0;
    let mut start = text.len();
    let mut end = text.len();
    for (i, c) in text.char_indices() {
        let w = width(c);
        let next = cell + w;
        if cell >= columns {
            end = i;
            break;
        }
        if next > from && start == text.len() {
            start = i;
        }
        if next >= to {
            end = i + c.len_utf8();
            break;
        }
        cell = next;
    }
    (start.min(end), end)
}
// The text a preview selection covers: the anchor and head are (row, cell) in the pane's drawn
// grid, and the covered pieces of each row are joined with newlines.
pub fn preview_selection_text(lines: &[String], anchor: (usize, usize), head: (usize, usize), columns: usize) -> String {
    let (start, end) = if anchor <= head { (anchor, head) } else { (head, anchor) };
    if start == end {
        return String::new();
    }
    let mut out = String::new();
    for row in start.0..=end.0 {
        let Some(line) = lines.get(row) else { break };
        let from = if row == start.0 { start.1 } else { 0 };
        let to = if row == end.0 { end.1 } else { columns };
        let (a, b) = cells_span(line, from, to, columns);
        if row > start.0 {
            out.push('\n');
        }
        out.push_str(&line[a..b]);
    }
    out
}
// One preview line with the selected cells reversed; read-only, as a terminal's own selection is.
fn selected_preview(line: &str, row: usize, m: &Model, columns: usize, theme: &Theme) -> String {
    let Some(sel) = m.preview_select else { return fit(line, columns) };
    let (start, end) = if sel.0 <= sel.1 { (sel.0, sel.1) } else { (sel.1, sel.0) };
    if row < start.0 || row > end.0 || start == end {
        return fit(line, columns);
    }
    let from = if row == start.0 { start.1 } else { 0 };
    let to = if row == end.0 { end.1 } else { columns };
    let text = clean(line);
    let (a, b) = cells_span(&text, from, to, columns);
    let mut out = String::from(&text[..a]);
    if a < b {
        out.push_str("\x1b[7m");
        out.push_str(&text[a..b]);
        out.push_str(&format!("\x1b[0m{}{}", theme.background, theme.foreground));
    }
    let used = text_width(&text[..b]);
    out.push_str(&fit(&text[b..], columns.saturating_sub(used)));
    out
}
fn match_range(text: &str, query: &str) -> Option<(usize, usize)> {
    if query.is_empty() { return None; }
    let query = query.to_lowercase();
    let start = text.to_lowercase().find(&query)?;
    let end = start + query.len();
    let mut offset = 0;
    let mut first = None;
    for (index, c) in text.char_indices() {
        let length: usize = c.to_lowercase().map(char::len_utf8).sum();
        if offset <= start && start < offset + length { first = Some(index); }
        if offset < end && end <= offset + length { return first.map(|first| (first, index + c.len_utf8())); }
        offset += length;
    }
    None
}
fn mark(row: &Row) -> &'static str {
    if !row.link.is_empty() {
        "@"
    } else if row.directory {
        "›"
    } else if row.mode & 0o111 != 0 {
        "*"
    } else {
        "□"
    }
}
fn row(row: &Row, columns: usize) -> (String, String) {
    let label = format!(
        "{} {}{}{}",
        mark(row),
        row.name,
        if row.directory { "/" } else { "" },
        if row.link.is_empty() {
            String::new()
        } else {
            format!(" → {}", row.link)
        }
    );
    if columns > 18 && row.link.is_empty() {
        let size = if row.directory {
            modified(row.modified)
        } else {
            bytes(row.size)
        };
        (fit(&label, columns - size.len() - 1), format!(" {}", size))
    } else {
        (fit(&label, columns), String::new())
    }
}
// The search page's last column: "12 min", "3 h", "Nov 30"; eight columns hold the longest.
const DATE_WIDTH: usize = 8;
// The page's three columns, shared by its heading line and its rows: the mark and its space, the
// file's own name, a gap, the folder holding it, a gap, and the modification time.
fn search_page_widths(columns: usize) -> (usize, usize) {
    let room = columns.saturating_sub(2 + 1 + 1 + DATE_WIDTH);
    let name = if room < 16 { room } else { (room * 2 / 5).clamp(8, room - 8) };
    (name, room - name)
}
fn search_page_row(row: &Row, columns: usize) -> (String, String) {
    let (name_w, path_w) = search_page_widths(columns);
    let (parent, leaf) = row.name.rsplit_once('/').unwrap_or(("", row.name.as_str()));
    let name = elide_end(leaf, name_w);
    let path = if parent.is_empty() || path_w == 0 {
        String::new()
    } else {
        elide_start(parent.trim_end_matches('/'), path_w)
    };
    let label = format!(
        "{} {}{} {}{}",
        mark(row),
        name,
        " ".repeat(name_w.saturating_sub(text_width(&name))),
        path,
        " ".repeat(path_w.saturating_sub(text_width(&path)))
    );
    (label, format!(" {}", fit(&modified(row.modified), DATE_WIDTH)))
}
fn search_page_header(columns: usize) -> String {
    let (name_w, path_w) = search_page_widths(columns);
    let line = format!(
        "  Name{}{}Path{}{}Modified",
        " ".repeat(name_w.saturating_sub(4)),
        " ",
        " ".repeat(path_w.saturating_sub(4)),
        " "
    );
    fit(&line, columns)
}
// Fits text to `limit` columns, marking a cut with a trailing ellipsis.
fn elide_end(text: &str, limit: usize) -> String {
    if text_width(text) <= limit {
        return clean(text);
    }
    let mut out = String::new();
    let mut used = 0;
    for c in clean(text).chars() {
        let n = width(c);
        if used + n + 1 > limit {
            break;
        }
        out.push(c);
        used += n;
    }
    out.push('…');
    out
}
// Fits text to `limit` columns from its end, marking a cut with a leading ellipsis: a folder's
// tail is the part that says where the file is.
fn elide_start(text: &str, limit: usize) -> String {
    if text_width(text) <= limit {
        return clean(text);
    }
    let chars: Vec<char> = clean(text).chars().collect();
    let mut cut = chars.len();
    let mut used = 0;
    while cut > 0 {
        let n = width(chars[cut - 1]);
        if used + n + 1 > limit {
            break;
        }
        used += n;
        cut -= 1;
    }
    let mut out = String::from("…");
    out.extend(&chars[cut..]);
    out
}
pub fn draw(
    m: &Model,
    theme: &Theme,
    map: &Map,
    columns: usize,
    lines: usize,
    cell_pixels: Option<(usize, usize)>,
    elapsed: std::time::Duration,
    last: &mut String,
) -> io::Result<bool> {
    if columns < 12 || lines <= CHROME_ROWS {
        print!("\x1b[H\x1b[2J{}", fit("Window too small", columns));
        io::stdout().flush()?;
        return Ok(true);
    }
    // The search page has no parent column: it is not a place in the tree, and its first, blank
    // frame would otherwise draw the folder's parent and then lose it on the first query.
    let has_parent = !m.search_page && m.path.parent().is_some();
    let (left, middle, right) = panes_for(columns, m.preview_visible, has_parent);
    let left_padding = pane_padding(left);
    let middle_padding = pane_padding(middle);
    let preview_padding = pane_padding(if m.quicklook { columns } else { right });
    let (_, preview_width) = preview_area_for(columns, m.quicklook, has_parent);
    let filtered = (!m.filter.is_empty()).then(|| m.shown());
    let body = body_height(lines);
    let graphical = m.player.is_some() || m.pdf.is_some() || m.image_file.is_some();
    let details = m.preview_metadata.len().min(3);
    let details_start = body.saturating_sub(2 + details + usize::from(m.pdf.is_some()));
    let base = format!("\x1b[0m{}{}", theme.background, theme.foreground);
    let mut out = format!("\x1b[H{}", base);
    let title = header_title(m);
    let header_width = columns.saturating_sub(2);
    let title_width = text_width(&title).min(header_width / 2);
    let mut used = 0;
    out.push(' ');
    for (i, label) in tab_layout(m, header_width) {
        let width = text_width(&label);
        out.push_str(if i == m.tab {
            &theme.accent
        } else {
            &theme.foreground
        });
        out.push_str(&clean(&label));
        used += width;
    }
    out.push_str(&base);
    out.push_str(&" ".repeat(header_width.saturating_sub(used + title_width)));
    out.push_str(&fit(&title, title_width));
    out.push(' ');
    if m.search_page {
        out.push_str(&format!("\x1b[2;1H{}{}", base, theme.muted));
        out.push_str(&" ".repeat(middle_padding));
        out.push_str(&search_page_header(middle.saturating_sub(middle_padding * 2)));
        out.push_str(&" ".repeat(middle_padding));
        if m.preview_visible {
            out.push_str(&format!("{}│{}", theme.border, base));
        }
        out.push_str(&base);
    } else {
        out.push_str(&format!("\x1b[2;1H{}{}{}", theme.border, "─".repeat(columns), base));
    }
    for y in 0..body {
        out.push_str(&format!("\x1b[{};1H{}", y + BODY_ROW, base));
        if m.quicklook {
            let content = if m.selected.len() > 1 {
                selection_line(m, y, preview_width)
            } else if y == body.saturating_sub(2) {
                m.player
                    .as_ref()
                    .map(|p| p.line(preview_width))
                    .or_else(|| m.pdf.as_ref().map(|p| p.line(true, preview_width)))
                    .unwrap_or_default()
            } else if m.pdf.is_some() && y == body.saturating_sub(3) {
                m.pdf.as_ref().unwrap().prefix()
            } else if graphical && y >= details_start && y < details_start + details {
                m.preview_metadata[y - details_start].clone()
            } else if graphical && y >= 2 {
                String::new()
            } else {
                m.preview_display.get(y).cloned().unwrap_or_default()
            };
            out.push_str(&" ".repeat(preview_padding));
            out.push_str(&fit(&content, preview_width));
            out.push_str(&" ".repeat(preview_padding));
            continue;
        }
        // At the root there is no parent pane at all, so the current column starts the row.
        if left > 0 {
            if m.parents.is_empty() && m.parents_failed && y == 0 {
                out.push_str(&theme.muted);
                out.push_str(&" ".repeat(left_padding));
                out.push_str(&fit("Could not read", left - left_padding * 2));
                out.push_str(&" ".repeat(left_padding));
            } else if let Some(parent) = m.parents.get(y) {
                if m.path
                    .file_name()
                    .is_some_and(|name| name == parent.name.as_str())
                {
                    out.push_str(&theme.selected);
                }
                let label = format!(
                    "{} {}",
                    if parent.directory { "›" } else { "□" },
                    parent.name
                );
                out.push_str(&" ".repeat(left_padding));
                out.push_str(&fit(&label, left - left_padding * 2));
                out.push_str(&" ".repeat(left_padding));
            } else {
                out.push_str(&" ".repeat(left));
            }
            out.push_str(&base);
            out.push_str(&theme.border);
            out.push('│');
            out.push_str(&base);
        }
        let index = filtered.as_ref().map_or(m.top + y, |rows| rows.get(y).copied().unwrap_or(usize::MAX));
        if let Some(entry) = m.rows.get(&index) {
            let row_color = if index == m.cursor {
                format!("{}\x1b[7m", theme.accent)
            } else if m.selected.contains(&index) {
                format!("{}{}", theme.foreground, theme.selected)
            } else if !entry.link.is_empty() {
                theme.symlink.clone()
            } else if entry.mode & 0o111 != 0 && !entry.directory {
                theme.executable.clone()
            } else { theme.foreground.clone() };
            out.push_str(&row_color);
            out.push_str(&" ".repeat(middle_padding));
            let content_width = middle - middle_padding * 2;
            if let Some(editor) = m.editor.as_ref().filter(|e| e.kind == "rename" && e.path == m.row_path(entry)) {
                out.push_str(&base);
                out.push_str(&editor.line(&format!("{} ", mark(entry)), "", content_width, &base, &theme.muted, &theme.accent));
            } else {
                let (label, metadata) = if m.search_page {
                    search_page_row(entry, content_width)
                } else {
                    row(entry, content_width)
                };
                if let Some((start, end)) = (index != m.cursor).then(|| match_range(&label, &m.filter)).flatten() {
                    out.push_str(&label[..start]);
                    out.push_str(&theme.accent);
                    out.push_str(&label[start..end]);
                    out.push_str(&row_color);
                    out.push_str(&label[end..]);
                } else { out.push_str(&label); }
                if index != m.cursor { out.push_str(&theme.foreground); }
                out.push_str(&metadata);
            }
            out.push_str(&" ".repeat(middle_padding));
            out.push_str(&base);
        } else if m.total == 0 {
            if m.search_page {
                // One line, centred in the pane: the sentence is the page's state, not a row.
                let sentence = if y != body / 2 {
                    ""
                } else if m.search_query.is_empty() {
                    "Type a name to search every disk"
                } else if m.searching {
                    "Searching…"
                } else {
                    "No files match that name"
                };
                let pad = middle.saturating_sub(text_width(sentence)) / 2;
                out.push_str(&fit(&format!("{}{}", " ".repeat(pad), sentence), middle));
            } else if m.pending.is_some() {
                out.push_str(&fit(if y == body / 2 { "Loading…" } else { "" }, middle));
            } else {
                out.push_str(&super::empty::line(y, body, middle, cell_pixels, elapsed));
            }
        } else if filtered.as_ref().is_some_and(|rows| y == rows.len()) {
            let count = filtered.as_ref().unwrap().len();
            let note = if count == 0 { format!("Nothing matches {}", m.filter) }
                else { hidden_note(m.rows.len() - count) };
            out.push_str(&" ".repeat(middle_padding));
            out.push_str(&fit(&note, middle - middle_padding * 2));
            out.push_str(&" ".repeat(middle_padding));
        } else {
            out.push_str(&" ".repeat(middle));
        }
        if !m.preview_visible {
            continue;
        }
        out.push_str(&theme.border);
        out.push('│');
        out.push_str(&base);
        let mut text_row = false;
        let preview = if y == body.saturating_sub(2) && (m.player.is_some() || m.pdf.is_some()) {
            m.player
                .as_ref()
                .map(|p| p.line(preview_width))
                .or_else(|| m.pdf.as_ref().map(|p| p.line(false, preview_width)))
                .unwrap_or_default()
        } else if m.pdf.is_some() && y == body.saturating_sub(3) {
            m.pdf.as_ref().unwrap().prefix()
        } else if m.selected.len() > 1 {
            selection_line(m, y, preview_width)
        } else if graphical && y >= details_start && y < details_start + details {
            m.preview_metadata[y - details_start].clone()
        } else if graphical && y >= 2 {
            String::new()
        } else if m.preview_visible || m.quicklook {
            text_row = true;
            m.preview_display.get(y).cloned().unwrap_or_default()
        } else {
            String::new()
        };
        out.push_str(if m.selected.len() > 1 && y == 0 {
            &theme.accent
        } else {
            &theme.foreground
        });
        out.push_str(&" ".repeat(preview_padding));
        if text_row {
            out.push_str(&selected_preview(&preview, y, m, preview_width, theme));
        } else {
            out.push_str(&fit(&preview, preview_width));
        }
        out.push_str(&" ".repeat(preview_padding));
        out.push_str(&base);
    }
    out.push_str(&format!("\x1b[{};1H{}{}{}", lines - 1, theme.border, "─".repeat(columns), base));
    out.push_str(&format!("\x1b[{};1H{} ", lines, base));
    if let Some(editor) = &m.editor {
        if editor.kind == "rename" {
            let notice = if !editor.error.is_empty() { editor.error.as_str() }
                else if editor.pending { "Renaming…" }
                else { "Enter saves · Escape cancels · Ctrl+A selects the full name" };
            if !editor.error.is_empty() { out.push_str(&theme.error); }
            out.push_str(&fit(notice, header_width));
        } else {
        let prefix = if editor.kind == "path" {
            ": ".into()
        } else {
            format!("{}: ", editor.kind)
        };
        let suffix = if editor.pending {
            " · Working…".into()
        } else if editor.kind == "path" {
            m.completion
                .strip_prefix(&editor.value)
                .unwrap_or("")
                .into()
        } else if editor.kind == "search" {
            // The whole disk is the scope; this small chip is the only filter, and it narrows the
            // answer to the folder the search began in so a result never leaves what is on screen.
            let origin = m.search_from.clone().unwrap_or_else(|| editor.path.clone());
            let name = origin
                .file_name()
                .map(|name| name.to_string_lossy().into_owned())
                .filter(|name| !name.is_empty())
                .unwrap_or_else(|| origin.display().to_string());
            let mut suffix = if m.search_folder {
                format!(" [in {name}] · Tab: all disks")
            } else {
                " [all disks] · Tab: this folder".into()
            };
            // The answer follows the typing, so its count belongs on the line that asked for it.
            if !m.searching && !m.search_query.is_empty() && m.search_query == editor.value {
                suffix.push_str(&format!(" · {} {}", grouped(m.total), word(m.total, "match", "matches")));
            }
            suffix
        } else {
            String::new()
        };
        out.push_str(&editor.line(&prefix, &suffix, header_width, &base, &theme.muted, &theme.accent));
        }
    } else {
        out.push_str(&footer(m, theme, header_width, elapsed));
    }
    out.push(' ');
    if m.sheet {
        let sheet = panel_rows(m, map);
        overlay(
            &mut out,
            &sheet[m.sheet_top.min(sheet.len())..],
            columns,
            lines,
            &base,
            None,
            if m.properties.is_some() { "properties" } else { "keys" },
            None,
        );
    }
    if m.menu {
        let rows = menu_rows(m);
        let disabled: Vec<usize> = (0..rows.len()).filter(|index| !m.menu_enabled(m.menu_top + index)).collect();
        overlay(
            &mut out,
            &rows,
            columns,
            lines,
            &base,
            Some(m.menu_cursor.saturating_sub(m.menu_top)),
            if m.taildrop.submenu {
                "taildrop"
            } else {
                "open"
            },
            Some((&theme.muted, &disabled)),
        );
    }
    if m.tab_menu {
        let rows = tab_menu_rows();
        let disabled: Vec<usize> = (0..rows.len()).filter(|index| !m.tab_menu_enabled(*index)).collect();
        overlay(
            &mut out,
            &rows,
            columns,
            lines,
            &base,
            Some(m.tab_menu_cursor),
            "tab",
            Some((&theme.muted, &disabled)),
        );
    }
    if let Some(deletion) = &m.deletion {
        let rows = deletion_rows(m);
        let scroll = deletion.scroll.min(rows.len().saturating_sub(1));
        let shown = &rows[scroll..];
        overlay(&mut out, shown, columns, lines, &base, None, "Delete permanently?", None);
        for (destructive, x, y) in deletion_buttons(m) {
            let color = if destructive { if deletion.token == 0 { &theme.muted } else { &theme.error } } else { &theme.accent };
            out.push_str(&format!("\x1b[{};{}H{}{}{}{}{}", y, x, base, color,
                if deletion.destructive == destructive { "\x1b[7m" } else { "" },
                if destructive { "[ Delete ]" } else { "[ Cancel ]" }, base));
        }
    }
    if *last != out {
        print!("{}\x1b[0m", out);
        io::stdout().flush()?;
        *last = out;
        return Ok(true);
    }
    Ok(false)
}
pub fn deletion_rows(m: &Model) -> Vec<String> {
    let Some(deletion) = &m.deletion else { return Vec::new(); };
    let width = m.columns.saturating_sub(if m.columns < 30 { 4 } else { 8 }).max(1);
    let summary = if deletion.token == 0 { "Inspecting selected items…".into() }
        else { format!("{} {}, {}", grouped(deletion.count), if deletion.count == 1 { "item" } else { "items" }, bytes(deletion.bytes)) };
    let mut rows: Vec<String> = Wrapped::new(&summary, width).map(str::to_owned).collect();
    // One item is deleted as "it", several as "them", the same rule the window's confirm keeps.
    let scope = if deletion.count == 1 { "This deletes it from disk. This cannot be undone." }
        else { "This deletes them from disk. This cannot be undone." };
    rows.extend(Wrapped::new(scope, width).map(str::to_owned));
    rows.push(String::new());
    if m.columns < 30 { rows.extend([" ".repeat(10), " ".repeat(10)]); }
    else { rows.push(" ".repeat(22)); }
    rows
}
pub fn deletion_buttons(m: &Model) -> Vec<(bool, usize, usize)> {
    let rows = deletion_rows(m);
    let Some(deletion) = &m.deletion else { return Vec::new(); };
    let scroll = deletion.scroll.min(rows.len().saturating_sub(1));
    let (x, y, width, count) = overlay_rect(&rows[scroll..], m.columns, m.height + CHROME_ROWS);
    let stacked = m.columns < 30;
    [false, true].into_iter().filter_map(|destructive| {
        let row = rows.len() - 1 - usize::from(stacked && !destructive);
        if row < scroll || row >= scroll + count || width < 10 { return None; }
        let offset = if stacked { width - 10 } else { width.saturating_sub(22) + if destructive { 12 } else { 0 } };
        Some((destructive, x + 2 + offset, y + 2 + row - scroll))
    }).collect()
}
fn footer(m: &Model, theme: &Theme, columns: usize, elapsed: std::time::Duration) -> String {
    let base = format!("\x1b[0m{}{}", theme.background, theme.foreground);
    let help = if m.hints.keys.is_empty() { String::new() } else { format!("{} keys", m.hints.keys) };
    let available = columns.saturating_sub(text_width(&help) + 2);
    let mut parts = Vec::new();
    let chip = format!("{}\x1b[7m", theme.accent);
    if !m.selected.is_empty() { parts.push((chip.as_str(), format!(" V {} ", grouped(m.selected.len())))); }
    parts.push((theme.foreground.as_str(), items(m.total)));
    if !m.error.is_empty() {
        let queued = if m.errors.is_empty() { String::new() } else { format!(" (+{})", m.errors.len()) };
        let dismiss = if m.hints.dismiss.is_empty() { String::new() } else { format!(" · {} dismisses", m.hints.dismiss) };
        parts.push((theme.error.as_str(), format!("{}{}{}", m.error, queued, dismiss)));
    }
    if !m.transfer.is_empty() {
        const FRAMES: [&str; 3] = ["░▒▓", "▒▓░", "▓░▒"];
        const FRAME_MILLIS: u128 = 200;
        parts.push((theme.foreground.as_str(), format!("{} {}", m.transfer, FRAMES[(elapsed.as_millis() / FRAME_MILLIS) as usize % FRAMES.len()])));
    }
    // A fresh notice outranks the search line it would otherwise sit behind, so a copy made over a
    // result says so; the search state comes back when the notice expires.
    let noticed = !m.message.is_empty()
        && m.error.is_empty()
        && m.transfer.is_empty()
        && (m.search.is_empty() || m.message_at.elapsed() < super::MESSAGE_TIME);
    if !m.search.is_empty() && !noticed { parts.push((theme.foreground.as_str(), m.search.clone())); }
    if noticed { parts.push((theme.foreground.as_str(), m.message.clone())); }
    if !m.filter.is_empty() {
        let shown = m.shown().len();
        parts.push((theme.foreground.as_str(), format!("Filter {} · {} {} in {} {}", m.filter, grouped(shown), word(shown, "match", "matches"), grouped(m.rows.len()), word(m.rows.len(), "loaded row", "loaded rows"))));
    }
    let mut out = String::new();
    let mut used = 0;
    for (color, text) in parts {
        if used >= available { break; }
        if used > 0 {
            let gap = 2.min(available - used);
            out.push_str(&" ".repeat(gap));
            used += gap;
        }
        let width = text_width(&text).min(available - used);
        out.push_str(color);
        out.push_str(&fit(&text, width));
        out.push_str(&base);
        used += width;
    }
    out.push_str(&" ".repeat(columns.saturating_sub(used + text_width(&help))));
    out.push_str(&help);
    out
}
fn selection_line(m: &Model, y: usize, columns: usize) -> String {
    if y == 0 {
        return format!("{} selected", items(m.selected.len()));
    }
    if y == 1 {
        return "─".repeat(columns);
    }
    if let Some(row) = m.selected_rows.values().nth(y - 2) {
        let size = bytes(row.size);
        return format!(
            "{} {}",
            fit(&row.name, columns.saturating_sub(size.len() + 1)),
            size
        );
    }
    let footer = y.saturating_sub(m.selected_rows.len() + 2);
    if footer == 1 {
        if m.selected_rows.len() == m.selected.len() {
            let total = m
                .selected_rows
                .values()
                .fold(0usize, |sum, row| sum.saturating_add(row.size));
            return format!("Selection total · {}", bytes(total));
        }
        let outside = m.selected.len() - m.selected_rows.len();
        return format!("{} outside loaded rows", marked(outside));
    }
    if footer >= 2 {
        return Wrapped::new("Preview follows the marked set while visual mode is active.", columns).nth(footer - 2).unwrap_or("").into();
    }
    String::new()
}
// The tab strip's menu, drawn over the window when a tab is right-clicked.
pub fn tab_menu_rows() -> Vec<String> {
    ["Close Tab", "Close Other Tabs", "New Tab"].map(String::from).to_vec()
}
pub fn menu_rows(m: &Model) -> Vec<String> {
    if m.taildrop.submenu {
        return m.taildrop.peers.iter().skip(m.menu_top).map(|p| p.label.clone()).collect();
    }
    let reason = m.taildrop.reason();
    let taildrop = if reason.is_empty() { "taildrop  ▶".into() } else { format!("taildrop · {}", reason) };
    vec!["open".into(), "open path".into(), "copy path".into(), "remove".into(), if m.hidden { "hide hidden".into() } else { "show hidden".into() }, taildrop]
        .into_iter().skip(m.menu_top).collect()
}
pub fn panel_rows(m: &Model, map: &Map) -> Vec<String> {
    let rows = m.properties.clone().unwrap_or_else(|| map.sheet(&m.preset));
    rows.iter().flat_map(|line| Wrapped::new(line, m.columns.saturating_sub(8).max(1))).map(clean).collect()
}
pub fn overlay_rect(rows: &[String], columns: usize, lines: usize) -> (usize, usize, usize, usize) {
    let width = rows
        .iter()
        .map(|row| text_width(row))
        .max()
        .unwrap_or(0)
        .saturating_add(2)
        .max(13)
        .min(columns.saturating_sub(if columns < 30 { 2 } else { 6 }));
    let count = rows.len().min(lines.saturating_sub(4));
    (
        (columns.saturating_sub(width + 2)) / 2,
        (lines.saturating_sub(count + 2)) / 2,
        width,
        count,
    )
}
fn overlay(
    out: &mut String,
    rows: &[String],
    columns: usize,
    lines: usize,
    base: &str,
    selected: Option<usize>,
    title: &str,
    dim: Option<(&str, &[usize])>,
) {
    let (x, y, width, count) = overlay_rect(rows, columns, lines);
    let heading = format!("─ {} ", title);
    out.push_str(&format!(
        "\x1b[{};{}H{}┌{}{}┐",
        y + 1,
        x + 1,
        base,
        fit(&heading, text_width(&heading).min(width)),
        "─".repeat(width.saturating_sub(text_width(&heading)))
    ));
    for (i, row) in rows.iter().take(count).enumerate() {
        out.push_str(&format!(
            "\x1b[{};{}H{}│{}{} {} {}│",
            y + i + 2,
            x + 1,
            base,
            dim.filter(|(_, indices)| indices.contains(&i))
                .map(|(color, _)| color)
                .unwrap_or(""),
            if selected == Some(i) { "\x1b[7m" } else { "" },
            fit(row, width.saturating_sub(2)),
            base
        ));
    }
    out.push_str(&format!(
        "\x1b[{};{}H{}└{}┘",
        y + count + 2,
        x + 1,
        base,
        "─".repeat(width)
    ));
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn chrome_and_pane_insets_preserve_body_and_minimum_pdf_space() {
        assert_eq!(body_height(67), 63);
        assert_eq!(BODY_ROW + body_height(67), 66);
        assert_eq!(preview_area(277, false), (226, 50));
        assert_eq!(preview_area(277, true), (1, 275));
        for columns in 12..=277 {
            for quicklook in [false, true] {
                let (start, width) = preview_area(columns, quicklook);
                assert!(width >= 5 && start + width <= columns);
                let outer = if quicklook { columns } else { panes(columns, true).2 };
                assert_eq!(start + width + pane_padding(outer), columns);
            }
        }
    }
    // At / there is no parent pane, so the current column takes its width instead of leaving it blank.
    #[test]
    fn the_root_draws_no_empty_parent_pane() {
        assert_eq!(panes_for(100, true, false), (0, 80, 19));
        // The parent column is as narrow as a mark and a name allow, and the preview is half its
        // former 38%: the listing takes the rest.
        assert_eq!(panes_for(186, true, true), (12, 137, 35));
        assert_eq!(panes_for(100, false, false), (0, 100, 0));
        // The preview column keeps its width and starts where the drawing puts it.
        assert_eq!(preview_area_for(100, false, false).1, preview_area(100, false).1);
        let (start, width) = preview_area_for(100, false, false);
        assert_eq!(start + width, 100, "the preview pane still ends at the last column");
    }

    #[test]
    fn scrolled_root_menu_renders_the_selected_action() {
        let mut model = Model::new(std::path::PathBuf::from("/"), &crate::jsondoc::Json::Null);
        model.columns = 80;
        model.height = 4;
        model.menu_top = 1;
        model.menu_cursor = 4;
        let rows = menu_rows(&model);
        assert_eq!(rows, ["open path", "copy path", "remove", "show hidden", "taildrop  ▶"]);
        assert_eq!(overlay_rect(&rows, model.columns, model.height + CHROME_ROWS).3, 4);
        let mut output = String::new();
        overlay(&mut output, &rows, model.columns, model.height + CHROME_ROWS, "",
            Some(model.menu_cursor - model.menu_top), "open", None);
        assert!(output.contains("\x1b[7m show hidden │"));
        assert!(!output.contains("\x1b[7m taildrop"));
        assert!(output.contains("copy path"));
        model.hidden = true;
        assert_eq!(menu_rows(&model), ["open path", "copy path", "remove", "hide hidden", "taildrop  ▶"]);
        model.taildrop.error = "signed out".into();
        assert_eq!(menu_rows(&model), ["open path", "copy path", "remove", "hide hidden", "taildrop · signed out"]);
    }

    // A preview selection reads the drawn cells it covers, across lines and in either direction.
    #[test]
    fn a_preview_selection_reads_its_cells_across_lines() {
        let lines = vec![
            "alpha beta gamma".to_string(),
            "second line here".to_string(),
            "third".to_string(),
        ];
        assert_eq!(preview_selection_text(&lines, (0, 6), (0, 10), 40), "beta");
        assert_eq!(preview_selection_text(&lines, (0, 6), (1, 6), 40), "beta gamma\nsecond");
        assert_eq!(preview_selection_text(&lines, (1, 6), (0, 6), 40), "beta gamma\nsecond");
        assert!(preview_selection_text(&lines, (0, 6), (0, 6), 40).is_empty(), "a click selects nothing");
        assert_eq!(preview_selection_text(&lines, (2, 2), (3, 5), 40), "ird");
        assert_eq!(preview_selection_text(&lines, (0, 40), (1, 40), 40), "\nsecond line here");
    }

    // The search page draws three columns: the file's own name, the folder holding it, and its age.
    #[test]
    fn the_search_page_draws_name_path_and_modified_time() {
        let entry = Row {
            name: "/Users/gm/Projects/Rust/Cargo.toml".into(),
            mode: 0o100_644,
            size: 1013,
            modified: 1_700_000_000,
            directory: false,
            link: String::new(),
            kind: String::new(),
            thumbnail: false,
            icon: String::new(),
        };
        let (label, metadata) = search_page_row(&entry, 100);
        assert_eq!(text_width(&label) + text_width(&metadata), 100);
        assert!(label.starts_with("□ Cargo.toml "), "got {label:?}");
        assert!(label.contains("/Users/gm/Projects/Rust"), "got {label:?}");
        assert!(metadata.starts_with(' '), "the date is its own column, got {metadata:?}");
        // A folder wider than its share is cut from the front; the name keeps its start.
        let deep = Row { name: format!("/Users/gm/{}/deep.txt", "a".repeat(200)), ..entry.clone() };
        let (label, metadata) = search_page_row(&deep, 100);
        assert!(label.starts_with("□ deep.txt "), "got {label:?}");
        assert!(label.contains('…'), "got {label:?}");
        assert_eq!(text_width(&label) + text_width(&metadata), 100);
        // The headings sit exactly over the columns they name.
        let header = search_page_header(100);
        assert_eq!(text_width(&header), 100);
        assert!(header.starts_with("  Name"));
        let (name_w, _) = search_page_widths(100);
        assert_eq!(header.find("Path").unwrap(), 2 + name_w + 1);
        assert!(header.ends_with("Modified"));
        assert_eq!(100 - header.find("Modified").unwrap(), DATE_WIDTH);
    }

    // Open, Open path, Copy path and Remove are offered exactly when a row sits under the cursor,
    // so the four share one condition; the hidden-files toggle is always live.
    #[test]
    fn the_row_actions_are_offered_together_and_never_alone() {
        let mut model = Model::new(std::path::PathBuf::from("/"), &crate::jsondoc::Json::Null);
        assert!(!model.menu_enabled(0) && !model.menu_enabled(1) && !model.menu_enabled(2) && !model.menu_enabled(3));
        assert!(model.menu_enabled(4), "the hidden-files toggle is always live");
        model.menu_ready = true;
        model.menu_path = std::path::PathBuf::from("/tmp/a.txt");
        assert!(model.menu_enabled(0) && model.menu_enabled(1) && model.menu_enabled(2) && model.menu_enabled(3));
    }
    #[test]
    fn counted_lines_read_singular_for_one_and_plural_for_many() {
        let mut model = Model::new(std::path::PathBuf::from("/"), &crate::jsondoc::Json::Null);
        let theme = Theme::from_text("");
        model.total = 1;
        let one = footer(&model, &theme, 120, std::time::Duration::ZERO);
        assert!(one.contains("1 item") && !one.contains("1 items"), "one row in the footer: {one}");
        model.total = 1204;
        let many = footer(&model, &theme, 120, std::time::Duration::ZERO);
        assert!(many.contains("1,204 items"), "many rows in the footer: {many}");
        let row = || Row::parse(&crate::jsondoc::Json::Obj(vec![("n".into(), crate::tui::wire::word("a"))]), &[]);
        model.selected = [0].into_iter().collect();
        model.selected_rows.insert(0, row());
        assert_eq!(selection_line(&model, 0, 80), "1 item selected");
        model.selected = [0, 1].into_iter().collect();
        model.selected_rows.insert(1, row());
        assert_eq!(selection_line(&model, 0, 80), "2 items selected");
        model.selected = [0, 1].into_iter().collect();
        model.selected_rows = [(0, row())].into_iter().collect();
        assert_eq!(selection_line(&model, 4, 80), "1 marked item outside loaded rows");
        model.selected = [0, 1, 2].into_iter().collect();
        assert_eq!(selection_line(&model, 4, 80), "2 marked items outside loaded rows");
        model.selected.clear();
        model.selected_rows.clear();
        model.filter = "a".into();
        model.rows = [(0, row())].into_iter().collect();
        let filtered = footer(&model, &theme, 120, std::time::Duration::ZERO);
        assert!(filtered.contains("1 match in 1 loaded row"), "one match of one row: {filtered}");
        assert!(!filtered.contains("matches") && !filtered.contains("rows"), "no plural may survive it: {filtered}");
        model.rows.insert(1, row());
        let filtered = footer(&model, &theme, 120, std::time::Duration::ZERO);
        assert!(filtered.contains("2 matches in 2 loaded rows"), "two matches of two rows: {filtered}");
        assert_eq!(hidden_note(1), "1 row hidden by the filter");
        assert_eq!(hidden_note(1204), "1,204 rows hidden by the filter");
    }
    #[test]
    fn deletion_confirm_is_singular_for_one_item() {
        let mut model = Model::new(std::path::PathBuf::from("/"), &crate::jsondoc::Json::Null);
        model.deletion = Some(super::super::model::Deletion { token: 1, count: 1, bytes: 42, ..Default::default() });
        model.columns = 80;
        let confirmation = deletion_rows(&model).concat();
        assert!(confirmation.contains("1 item,"));
        assert!(confirmation.contains("This deletes it from disk. This cannot be undone."));
        assert!(!confirmation.contains("them"));
    }
    #[test]
    fn confirmation_buttons_stay_visible_and_hit_testable_at_small_sizes() {
        let mut model = Model::new(std::path::PathBuf::from("/"), &crate::jsondoc::Json::Null);
        model.deletion = Some(super::super::model::Deletion { token: 1, count: 3, bytes: 42, ..Default::default() });
        assert!(!model.deletion.as_ref().unwrap().destructive);
        for columns in [12, 28, 80] {
            for height in [4, 20] {
                model.columns = columns;
                model.height = height;
                let scroll = deletion_rows(&model).len().saturating_sub(height);
                model.deletion.as_mut().unwrap().scroll = scroll;
                let buttons = deletion_buttons(&model);
                assert_eq!(buttons.len(), 2);
                for (_, x, y) in &buttons {
                    assert!(*x > 0 && x + 9 <= columns);
                    assert!(*y > 0 && *y <= height + CHROME_ROWS);
                }
                assert_ne!((buttons[0].1, buttons[0].2), (buttons[1].1, buttons[1].2));
            }
        }
    }
    #[test]
    fn padded_overlays_preserve_confirmation_and_panel_text() {
        let mut model = Model::new(std::path::PathBuf::from("/"), &crate::jsondoc::Json::Null);
        model.deletion = Some(super::super::model::Deletion { token: 1, count: 3, bytes: 42, ..Default::default() });
        let map = Map::load();
        for columns in [12, 28, 30, 80] {
            model.columns = columns;
            let confirmation = deletion_rows(&model);
            assert!(confirmation.concat().contains("This deletes them from disk. This cannot be undone."));
            model.properties = None;
            let keys = panel_rows(&model, &map);
            model.properties = Some(vec!["Properties: a-long-file-name-with-an-extension.txt".into()]);
            let properties = panel_rows(&model, &map);
            for rows in [confirmation, keys, properties] {
                let (_, _, width, _) = overlay_rect(&rows, columns, rows.len() + 4);
                let mut output = String::new();
                overlay(&mut output, &rows, columns, rows.len() + 4, "", None, "panel", None);
                for row in rows.iter().filter(|row| !row.trim().is_empty()) {
                    assert!(text_width(row) <= width - 2, "clipped {row:?} at {columns} columns");
                    assert!(output.contains(&format!("│ {} │", fit(row, width - 2))));
                }
            }
        }
    }
    #[test]
    fn active_tab_remains_in_the_same_visible_hit_map() {
        let mut model = Model::new(std::path::PathBuf::from("/tab-one"), &crate::jsondoc::Json::Null);
        for index in 2..=12 {
            model.tabs.push(super::super::model::Tab { path: format!("/tab-{index}").into(), cursor: 0, back: Vec::new(), forward: Vec::new() });
        }
        model.tab = 11;
        for columns in [12, 40, 80, 200] {
            let tabs = tab_layout(&model, columns);
            assert!(tabs.iter().any(|(index, _)| *index == model.tab));
            assert!(tabs.iter().map(|(_, label)| text_width(label)).sum::<usize>() <= columns);
        }
    }
    #[test]
    fn footer_separates_error_color_and_preserves_secondary_progress() {
        let mut model = Model::new(std::path::PathBuf::from("/"), &crate::jsondoc::Json::Null);
        model.hints = crate::tui::keymap::Hints::new(&Map::load(), "default");
        model.fail("Denied".into());
        model.fail("Missing".into());
        model.transfer = "Copying 2 of 5".into();
        model.search = "Searching 12 matches".into();
        let theme = Theme::from_text("");
        let output = footer(&model, &theme, 120, std::time::Duration::ZERO);
        assert!(output.contains(&format!("{}Denied (+1) · Escape dismisses\x1b[0m", theme.error)));
        assert!(output.find("Denied").unwrap() < output.find("Copying").unwrap());
        assert!(output.find("Copying").unwrap() < output.find("Searching").unwrap());
        assert!(output.ends_with("? keys"));
        assert_eq!(output.matches(&theme.error).count(), 1);
    }
    #[test]
    fn footer_hints_follow_the_keymap_and_vanish_with_their_key() {
        let rebound = Map::parse(r##"
[[code]]
key = "Backspace"
action = "escape"
[[text]]
char = "h"
action = "keymapSheet"
"##);
        let mut model = Model::new(std::path::PathBuf::from("/"), &crate::jsondoc::Json::Null);
        model.fail("Denied".into());
        let theme = Theme::from_text("");
        model.hints = crate::tui::keymap::Hints::new(&rebound, "default");
        let output = footer(&model, &theme, 120, std::time::Duration::ZERO);
        assert!(output.contains("Denied · Backspace dismisses"), "{output:?}");
        assert!(output.ends_with("h keys"), "{output:?}");
        assert!(!output.contains("Esc"), "{output:?}");
        model.hints = crate::tui::keymap::Hints::default();
        let output = footer(&model, &theme, 120, std::time::Duration::ZERO);
        assert!(output.contains("Denied") && !output.contains("dismisses") && !output.contains("keys"), "{output:?}");
    }
    #[test]
    fn unsafe_names_cannot_emit_terminal_commands() {
        assert_eq!(clean("a\x1b]52;c;evil\x07\u{202e}b"), "a]52;c;evilb");
        assert_eq!(fit("abcdef", 3), "abc");
        assert_eq!(fit("a", 3), "a  ");
        assert_eq!(
            Wrapped::new("abcdef", 2).collect::<Vec<_>>(),
            vec!["ab", "cd", "ef"]
        );
        assert_eq!(Wrapped::new("", 2).collect::<Vec<_>>(), vec![""]);
        assert!(Wrapped::new("abc", 0).next().is_none());
        assert_eq!(panes(100, true), (12, 67, 19));
        assert_eq!(panes(100, false), (12, 87, 0));
        assert_eq!(bytes(999), "999 B");
        assert_eq!(bytes(1000), "1.0 kB");
        assert_eq!(bytes(1_200_000_000), "1.2 GB");
        assert_eq!(grouped(653), "653");
        assert_eq!(grouped(1204), "1,204");
        assert_eq!(grouped(1234567), "1,234,567");
        let text = "□ İ.txt";
        let (start, end) = match_range(text, "i").unwrap();
        assert_eq!(&text[start..end], "İ");
    }
}
