// How each listing tool shapes its output: which whitespace field holds the size, where the name
// starts, and how a directory is marked. One description per tool, with the exact line each was
// derived from. What a parse produces is archivelist.rs's job.

// bsdtar's own verbose listing puts the size in the fifth column, after the mode, the link count,
// the owner and the group.
// Sample input: -rw-r--r--  0 gm     gm         10 Sep  1 09:14 a.txt
const BSDTAR_SIZE_COLUMN: usize = 4;
// mode, links, owner, group, size, month, day, time, then the name, which may hold spaces.
const BSDTAR_NAME_AFTER: usize = 8;
// 7z's bare listing puts it in the fourth, after the date, the time and the attributes.
// Sample input: 2026-09-01 09:14:15 ....A           10           19  a.txt
const SEVENZIP_SIZE_COLUMN: usize = 3;


// How one tool's listing is read: which whitespace field holds the size, and how the name is found.
pub struct ListSpec {
    pub size_column: usize,
    pub name_after_fields: usize,
    // 7z right-aligns its numeric columns and can leave the packed one blank, so its name cannot be
    // found by counting fields; it is the last run separated by two or more spaces instead.
    pub name_after_double_space: bool,
    pub dir_marker: DirMarker,
}

pub enum DirMarker {
    // bsdtar: the mode string in field 0 begins with d.
    ModePrefix,
    // 7z: the attribute string in field 2 contains D.
    AttrFlag,
}

// The two tools this box lists archives with, each described once.
pub fn tar_spec() -> ListSpec {
    ListSpec { size_column: BSDTAR_SIZE_COLUMN, name_after_fields: BSDTAR_NAME_AFTER,
               name_after_double_space: false, dir_marker: DirMarker::ModePrefix }
}

pub fn seven_spec() -> ListSpec {
    ListSpec { size_column: SEVENZIP_SIZE_COLUMN, name_after_fields: 0,
               name_after_double_space: true, dir_marker: DirMarker::AttrFlag }
}

// Sample input, bsdtar -tvf: "-rw-r--r--  0 gm     gm          2 Sep  1 12:10 ./name with spaces.txt"
// One line, read once, borrowing rather than allocating: the streaming path runs this for every line
// of a 200k-entry index while an owned Entry is only built for the first few that reach the wire.
pub struct Row<'a> {
    // Trailing slash already trimmed, so "./a/" reads as "./a".
    pub name: &'a str,
    pub is_dir: bool,
}

impl Row<'_> {
    // THE INVARIANT the extract check is built on: a member produces an entry in the destination
    // unless it IS the destination. Extracting the archive root creates nothing new; every other
    // member, directory or not, produces something. "./a/" is a destination entry and "./" is not,
    // which is the distinction three predicates missed in turn.
    // corner: the root member is a tar-ism. Measured on this box, 7z emits no root at all: built
    // from inside a directory it lists "a", "b", "f.txt", and built naming one it lists "src",
    // "src/a" and so on, where the top name is itself a real destination entry. So this test excludes
    // nothing for 7z and is vacuously correct there rather than wrong.
    pub fn produces_destination_entry(&self) -> bool {
        !is_archive_root(self.name)
    }
}

// The root has more than one spelling and a predicate that knew only one refused a legal archive:
// bsdtar writes "./" for `-C dir .` and "././" for `-C dir ./.`, both of which extract to nothing.
// A name is the root when it names no component at all, so every part of it is empty or ".".
fn is_archive_root(name: &str) -> bool {
    name.split('/').all(|part| part.is_empty() || part == ".")
}

// Sample input, 7z l -ba:    "2026-09-01 12:10:26 ....A            2               arcfmt/a b.txt"
pub fn row_of<'a>(line: &'a str, spec: &ListSpec) -> Option<Row<'a>> {
    let is_dir = match spec.dir_marker {
        DirMarker::ModePrefix => line.trim_start().starts_with('d'),
        DirMarker::AttrFlag => nth_field(line, 2).is_some_and(|f| f.contains('D')),
    };
    let name = if spec.name_after_double_space {
        // corner: a filename holding two consecutive spaces would be cut here, which shortens a
        // displayed name and never changes a count.
        let mut last: Option<&str> = None;
        for part in line.split("  ") {
            if !part.trim().is_empty() {
                last = Some(part);
            }
        }
        last?.trim()
    } else {
        nth_field_rest(line, spec.name_after_fields)?
    };
    // Trimmed before the emptiness test, not after: a member named "/" survived the old order and
    // reached the wire as a preview row with no label on it.
    let name = name.trim_end_matches('/');
    if name.is_empty() {
        return None;
    }
    Some(Row { name, is_dir })
}


// One whitespace-separated field by index, without collecting the rest of them.
fn nth_field(line: &str, index: usize) -> Option<&str> {
    line.split_whitespace().nth(index)
}

// Everything after the first `skip` whitespace-separated fields, with the name's own spaces kept.
fn nth_field_rest(line: &str, skip: usize) -> Option<&str> {
    let mut rest = line.trim_start();
    for _ in 0..skip {
        let end = rest.find(char::is_whitespace)?;
        rest = rest[end..].trim_start();
    }
    Some(rest)
}


