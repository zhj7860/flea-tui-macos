use super::{line, thumb_of};
use crate::backend::aliases::Aliases;
use crate::backend::mime::Db;
use crate::backend::thumbcache::Cache;
use crate::backend::thumbwrite::write_marker;
use crate::backend::thumbspec::Thumbnailers;
use crate::backend::testdir::TestDir;
use std::os::unix::fs::MetadataExt;
use std::sync::Arc;

#[test]
fn answers_name_the_path_they_belong_to() {
    assert_eq!(
        line(Some("/home/gm/.cache/thumbnails/large/714c.png"), "/home/gm/Pictures/shot.png"),
        "/home/gm/.cache/thumbnails/large/714c.png\t/home/gm/Pictures/shot.png"
    );
}

#[test]
fn a_path_with_no_thumbnail_answers_none() {
    assert_eq!(line(None, "/home/gm/notes.md"), "none\t/home/gm/notes.md");
}

// A path with a space still answers on one line, because the tab is the only separator.
#[test]
fn a_space_in_a_path_is_not_a_separator() {
    assert_eq!(line(None, "/home/gm/two words.txt"), "none\t/home/gm/two words.txt");
}

// What the verb refuses before it ever reaches the cache, which is the half of thumb_of that does
// not depend on which thumbnailers this box has installed.
#[test]
fn a_directory_and_a_path_that_is_not_there_both_answer_none() {
    let dir = TestDir::new("shelfthumbof");
    let aliases = Arc::new(Aliases::load());
    let specs = Arc::new(Thumbnailers::load(&aliases));
    let mime = Db::load();
    let root = dir.path().join("cache");
    let cache = Cache::at(root.clone());
    assert_eq!(thumb_of(dir.path(), &mime, &aliases, &specs, &cache, &root), None,
               "a directory is not a file with a thumbnail");
    let missing = dir.path().join("no-such-file.png");
    assert_eq!(thumb_of(&missing, &mime, &aliases, &specs, &cache, &root), None,
               "a path that is not there answers none rather than failing");
    let text = dir.file("notes.md", "not an image");
    assert_eq!(thumb_of(&text, &mime, &aliases, &specs, &cache, &root), None,
               "and a kind no thumbnailer on this box claims answers none");
}

// A failure the loaded table recorded answers none without a job, so the marker file is the one that was there.
#[test]
fn a_failure_recorded_under_the_loaded_table_is_not_retried() {
    if crate::backend::sandboxprobe::skipped() { return; }
    let dir = TestDir::new("shelfthumbfailed");
    let aliases = Arc::new(Aliases::load());
    let body = "[Thumbnailer Entry]\nTryExec=/usr/bin/true\nExec=/usr/bin/true %i %o %s\nMimeType=image/png;\n";
    let specs = Arc::new(Thumbnailers::from_entries(&[("true.thumbnailer".to_string(), body.to_string())], &aliases));
    let (mime, root) = (Db::load(), dir.path().join("cache"));
    let cache = Cache::at(root.clone());
    let shot = dir.file("shot.png", "bytes no decoder is asked about");
    let uri = crate::backend::thumbcache::uri_for(&shot);
    let marker = cache.fail_path(&uri);
    std::fs::create_dir_all(marker.parent().unwrap()).unwrap();
    write_marker(&marker, &uri, std::fs::metadata(&shot).unwrap().mtime(), Some(specs.fingerprint())).unwrap();
    let before = std::fs::metadata(&marker).unwrap().ino();
    assert_eq!(thumb_of(&shot, &mime, &aliases, &specs, &cache, &root), None);
    assert_eq!(std::fs::metadata(&marker).unwrap().ino(), before, "a retried job rewrote the marker");
}
