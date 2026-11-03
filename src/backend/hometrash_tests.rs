// Issue 261: Replace on a location with no Trash keeps the old item in the home Trash.
use super::trashable;
use crate::backend::collide::tests::{asked, chosen, refusing_trash, text, transfer, StandIn};
use crate::backend::collide::TRASH_REFUSED;
use crate::backend::testdir::TestDir;
use crate::backend::trash;
use crate::backend::undo::Journal;
use std::os::unix::fs::{FileTypeExt, PermissionsExt};
use std::os::unix::process::ExitStatusExt;
use std::path::{Path, PathBuf};
use std::process::{ExitStatus, Output};
use std::rc::Rc;
use std::sync::atomic::{AtomicUsize, Ordering};

// Numbers the stand-in trash can's entries, so two items trashed from one path never share a URI.
static NEXT_ENTRY: AtomicUsize = AtomicUsize::new(0);
const URI: &str = "trash:///";
const ORIGINAL: &str = ".original";

// Points this thread's home Trash at the sandbox Trash, cleared on the way out like StandIn.
struct TestTrashRoot;
impl Drop for TestTrashRoot {
    fn drop(&mut self) {
        crate::backend::hometrash::set_test_trash_root(None);
    }
}

// Names the sandbox Trash as this thread's home Trash for one test, so the process env is never read.
fn test_trash_root(trash: &Path) -> TestTrashRoot {
    crate::backend::hometrash::set_test_trash_root(Some(trash.to_path_buf()));
    TestTrashRoot
}

fn exited(code: i32, stdout: String, stderr: &[u8]) -> Output {
    Output { status: ExitStatus::from_raw(code << 8), stdout: stdout.into_bytes(), stderr: stderr.to_vec() }
}

// gio, played faithfully: a GVFS mount path is refused as the daemon refuses it, anything else is trashed.
pub(crate) fn gio_like(can: &Path, xdg: &Path, args: &[&str]) -> Output {
    match args {
        ["trash", "--list"] => {
            let mut listed = String::new();
            if let Ok(items) = std::fs::read_dir(can) {
                for item in items.flatten() {
                    let name = item.file_name().to_string_lossy().to_string();
                    if let Some(n) = name.strip_suffix(ORIGINAL) {
                        listed.push_str(&format!("{}{}\t{}\n", URI, n, std::fs::read_to_string(item.path()).unwrap()));
                    }
                }
            }
            let files = xdg.join("Trash/files");
            let info = xdg.join("Trash/info");
            if let Ok(items) = std::fs::read_dir(&files) {
                for item in items.flatten() {
                    let name = item.file_name().to_string_lossy().to_string();
                    let body = std::fs::read_to_string(info.join(format!("{name}.trashinfo"))).unwrap_or_default();
                    let original = body.lines().find_map(|l| l.strip_prefix("Path=")).unwrap_or("");
                    listed.push_str(&format!("{URI}{}\t{}\n", encode(&name), decode(original)));
                }
            }
            exited(0, listed, b"")
        }
        ["trash", "--restore", uri] => {
            let n = decode(uri.strip_prefix(URI).unwrap_or(""));
            let sidecar = can.join(format!("{n}{ORIGINAL}"));
            if sidecar.is_file() {
                let original = PathBuf::from(std::fs::read_to_string(&sidecar).unwrap());
                if original.symlink_metadata().is_ok() {
                    return exited(1, String::new(), b"gio: restore failed");
                }
                std::fs::rename(can.join(n), &original).unwrap();
                std::fs::remove_file(&sidecar).unwrap();
                return exited(0, String::new(), b"");
            }
            let kept = xdg.join("Trash/files").join(&n);
            let info = xdg.join("Trash/info").join(format!("{n}.trashinfo"));
            if !kept.symlink_metadata().is_ok() || !info.is_file() {
                return exited(1, String::new(), b"gio: restore failed");
            }
            let body = std::fs::read_to_string(&info).unwrap();
            let original = PathBuf::from(decode(body.lines().find_map(|l| l.strip_prefix("Path=")).unwrap_or("")));
            if original.symlink_metadata().is_ok() {
                return exited(1, String::new(), b"gio: restore failed");
            }
            std::fs::rename(&kept, &original).unwrap();
            std::fs::remove_file(&info).unwrap();
            exited(0, String::new(), b"")
        }
        ["trash", "--", paths @ ..] => {
            for path in paths {
                if is_gvfs_mount_path(path) {
                    return exited(1, String::new(), b"gio: Operation not supported");
                }
            }
            for path in paths {
                let n = NEXT_ENTRY.fetch_add(1, Ordering::Relaxed).to_string();
                std::fs::rename(path, can.join(&n)).unwrap();
                std::fs::write(can.join(format!("{n}{ORIGINAL}")), path).unwrap();
            }
            exited(0, String::new(), b"")
        }
        _ => exited(1, String::new(), b"gio: unknown call"),
    }
}

// The daemon refuses what trashable refuses, read off the product so the two never drift.
fn is_gvfs_mount_path(path: &str) -> bool {
    !trashable(Path::new(path))
}

// Decodes the %XX triplets a .trashinfo Path carries back into the original path.
fn decode(s: &str) -> String {
    crate::paths::percent_decode(s)
}

// Encodes a Trash file name the way the home Trash names its URIs, mirroring the product.
fn encode(s: &str) -> String {
    crate::backend::hometrash::percent_encode(s.as_bytes())
}

// Points XDG_DATA_HOME at the sandbox and stands gio in for the whole transfer.
fn gvfs_trash(d: &TestDir, xdg: &Path) -> StandIn {
    let can = d.dir("can");
    let held = xdg.to_path_buf();
    trash::STAND_IN.with(|slot| *slot.borrow_mut() = Some(Rc::new(move |args: &[&str]| Some(gio_like(&can, &held, args)))));
    StandIn
}

// A destination folder shaped like a GVFS sftp mount under a fake run root, which has no Trash of its own; the seam clears with the test thread.
fn gvfs_dest(d: &TestDir) -> PathBuf {
    crate::backend::gvfsroot::set_test_run_user(Some(&d.dir("run")));
    d.dir("run/1000/gvfs/sftp:host=slot.test/home/gm")
}

#[test]
fn every_gvfs_mount_refuses_and_every_ordinary_folder_keeps_its_trash() {
    for refused in [
        "/run/user/1000/gvfs/smb-share:server=192.168.21.25,share=data",
        "/run/user/1000/gvfs/sftp:host=box,user=gm/home/gm",
        "/run/user/1000/gvfs/mtp:host=SAMSUNG_RQGL705T0NR/DCIM",
        "/run/user/1000/gvfs/gphoto2:host=usb%3A001%2C014/store",
        "/run/user/1000/gvfs/afc:host=00008130-001641411883401C/DCIM",
    ] {
        assert!(!trashable(Path::new(refused)), "{refused} has no Trash");
    }
    for kept in ["/home/gm/Downloads", "/home/gm/src/gvfs/daemon", "/run/user/1000/gvfs", "/", "/run/user/1000/GVFS/dav:host=slot,ssl=true/notes"] {
        assert!(trashable(Path::new(kept)), "{kept} keeps its Trash");
    }
}

// A plain folder named gvfs, even one holding a scheme-shaped folder, is no mount: only the root under /run/user/<uid> is.
#[test]
fn a_folder_named_gvfs_outside_the_run_root_keeps_its_trash() {
    for kept in ["/home/u/mirror/gvfs/proj/a.txt", "/home/u/mirror/gvfs/smb-share:server=n,share=x/a.txt", "/home/u/gvfs/sftp:host=box/f",
        "/run/user/1000/home/gvfs/mtp:host=X/DCIM", "/run/user/gvfs/mtp:host=X"] {
        assert!(trashable(Path::new(kept)), "{kept} keeps its Trash");
    }
    let d = TestDir::new("gvfs-fake-root");
    crate::backend::gvfsroot::set_test_run_user(Some(&d.dir("run")));
    assert!(!trashable(&d.dir("run/1000/gvfs/smb-share:server=n,share=x/a")), "the seam's run root holds a real gvfs root");
    assert!(trashable(&d.dir("mirror/gvfs/smb-share:server=n,share=x/a")), "the same shape off the run root is a plain folder");
    crate::backend::gvfsroot::set_test_run_user(None);
}

// A colon alone never names a mount: only letters, digits and hyphens may stand before it.
#[test]
fn a_colon_without_a_mount_name_keeps_its_trash() {
    for kept in ["/run/user/1000/gvfs/plain", "/run/user/1000/gvfs/:empty", "/run/user/1000/gvfs/smb share:server=n",
        "/run/user/1000/gvfs/smb_share:server=n"] {
        assert!(trashable(Path::new(kept)), "{kept} keeps its Trash");
    }
    assert!(!trashable(Path::new("/run/user/1000/gvfs/1:2")), "digits name a mount");
}

#[test]
fn replace_on_a_location_with_no_trash_keeps_the_old_item_in_the_home_trash() {
    let d = TestDir::new("replace261-red");
    let xdg = d.dir("xdg");
    let dest = gvfs_dest(&d);
    d.dir("from");
    assert!(!trashable(&dest), "the GVFS-shaped destination has no Trash");
    let photo = d.file("from/my photo.png", "yours");
    let there = d.file("run/1000/gvfs/sftp:host=slot.test/home/gm/my photo.png", "there");
    let _root = test_trash_root(&xdg.join("Trash"));
    let _trash = gvfs_trash(&d, &xdg);
    let (ok, failed, _, errors, entry) = transfer(false, &[&photo], &dest, chosen("replace", asked(1, &[&photo], &dest), &dest));
    assert!(errors.is_empty(), "a Replace on a location with no Trash succeeds: {errors:?}");
    assert_eq!((ok, failed), (1, 0));
    assert_eq!(text(&there), "yours", "the new item landed on the GVFS-shaped path");
    let kept = xdg.join("Trash/files/my photo.png");
    assert_eq!(std::fs::read_to_string(&kept).unwrap(), "there", "the old item sits in the home Trash");
    let info = std::fs::read_to_string(xdg.join("Trash/info/my photo.png.trashinfo")).unwrap();
    assert!(info.starts_with("[Trash Info]\n"), "the info file opens with the section header: {info}");
    let path_line = info.lines().find_map(|l| l.strip_prefix("Path=")).expect("the info file names the original path");
    assert_eq!(decode(path_line), there.to_string_lossy(), "the info Path decodes to the original GVFS path");
    assert!(info.lines().any(|l| l.starts_with("DeletionDate=")), "the info file stamps the deletion date: {info}");
    use crate::backend::undo::Step;
    assert!(matches!(&entry.steps[..], [Step::Trashed(old), Step::Copied { .. }] if old.original == there && old.uri == "trash:///my%20photo.png"),
        "the journal carries the home Trash URI, so undo restores it: {:?}", entry.steps);
}

#[test]
fn a_replaced_folder_on_a_location_with_no_trash_lands_whole_in_the_home_trash() {
    let d = TestDir::new("replace261-dir");
    let xdg = d.dir("xdg");
    let dest = gvfs_dest(&d);
    d.dir("from/album");
    d.file("from/album/new.txt", "new");
    d.dir("run/1000/gvfs/sftp:host=slot.test/home/gm/album");
    d.file("run/1000/gvfs/sftp:host=slot.test/home/gm/album/old.txt", "old");
    let album = d.path().join("from/album");
    let _root = test_trash_root(&xdg.join("Trash"));
    let _trash = gvfs_trash(&d, &xdg);
    let (ok, failed, _, errors, _) = transfer(false, &[&album], &dest, chosen("replace", asked(1, &[&album], &dest), &dest));
    assert!(errors.is_empty(), "a folder Replace on a location with no Trash succeeds: {errors:?}");
    assert_eq!((ok, failed), (1, 0));
    assert_eq!(std::fs::read_to_string(dest.join("album/new.txt")).unwrap(), "new");
    assert_eq!(std::fs::read_to_string(xdg.join("Trash/files/album/old.txt")).unwrap(), "old");
}

#[test]
fn a_replaced_symlink_on_a_location_with_no_trash_stays_a_link_in_the_home_trash() {
    let d = TestDir::new("replace261-link");
    let xdg = d.dir("xdg");
    let dest = gvfs_dest(&d);
    d.dir("from");
    let target = d.file("from/target.txt", "target");
    let there = dest.join("photo.png");
    std::os::unix::fs::symlink(&target, &there).unwrap();
    let photo = d.file("from/photo.png", "yours");
    let _root = test_trash_root(&xdg.join("Trash"));
    let _trash = gvfs_trash(&d, &xdg);
    let (ok, failed, _, errors, _) = transfer(false, &[&photo], &dest, chosen("replace", asked(1, &[&photo], &dest), &dest));
    assert!(errors.is_empty(), "a symlink Replace on a location with no Trash succeeds: {errors:?}");
    assert_eq!((ok, failed), (1, 0));
    let kept = xdg.join("Trash/files/photo.png");
    assert_eq!(std::fs::read_link(&kept).unwrap(), target, "the trashed link still points at its target");
    assert_eq!(text(&there), "yours");
}

#[test]
fn a_failed_home_trash_copy_leaves_no_partial_and_the_original_in_place() {
    let d = TestDir::new("replace261-partial");
    let xdg = d.dir("xdg");
    let dest = gvfs_dest(&d);
    d.dir("from");
    let photo = d.file("from/photo.png", "yours");
    let there = d.file("run/1000/gvfs/sftp:host=slot.test/home/gm/photo.png", "there");
    std::fs::set_permissions(&there, std::fs::Permissions::from_mode(0o000)).unwrap();
    let _root = test_trash_root(&xdg.join("Trash"));
    let _trash = gvfs_trash(&d, &xdg);
    let (ok, failed, _, errors, entry) = transfer(false, &[&photo], &dest, chosen("replace", asked(1, &[&photo], &dest), &dest));
    assert!(entry.steps.is_empty(), "a failed home Trash copy journals nothing: {:?}", entry.steps);
    std::fs::set_permissions(&there, std::fs::Permissions::from_mode(0o644)).unwrap();
    assert_eq!((ok, failed), (0, 1));
    assert_eq!(errors, vec![crate::backend::hometrash::HOME_TRASH_FAILED.to_string()], "the refusal names the home Trash move: {errors:?}");
    assert_eq!(text(&there), "there", "the original never moved");
    assert_eq!(text(&photo), "yours");
    assert!(std::fs::read_dir(xdg.join("Trash/files")).map(|mut i| i.next().is_none()).unwrap_or(true), "no partial copy stays behind");
    assert!(std::fs::read_dir(xdg.join("Trash/info")).map(|mut i| i.next().is_none()).unwrap_or(true), "no orphan info file stays behind");
}

#[test]
fn a_home_trash_name_collision_gets_a_unique_name() {
    let d = TestDir::new("replace261-collision");
    let xdg = d.dir("xdg");
    let dest = gvfs_dest(&d);
    d.dir("from");
    let photo = d.file("from/photo.png", "yours");
    let there = d.file("run/1000/gvfs/sftp:host=slot.test/home/gm/photo.png", "there");
    std::fs::create_dir_all(xdg.join("Trash/files")).unwrap();
    std::fs::create_dir_all(xdg.join("Trash/info")).unwrap();
    std::fs::write(xdg.join("Trash/files/photo.png"), "earlier").unwrap();
    std::fs::write(xdg.join("Trash/info/photo.png.trashinfo"), "[Trash Info]\nPath=/earlier\nDeletionDate=2026-01-01T00:00:00\n").unwrap();
    let _root = test_trash_root(&xdg.join("Trash"));
    let _trash = gvfs_trash(&d, &xdg);
    let (ok, failed, _, errors, entry) = transfer(false, &[&photo], &dest, chosen("replace", asked(1, &[&photo], &dest), &dest));
    assert!(errors.is_empty(), "a collision still replaces: {errors:?}");
    assert_eq!((ok, failed), (1, 0));
    assert_eq!(text(&there), "yours");
    assert_eq!(std::fs::read_to_string(xdg.join("Trash/files/photo.png")).unwrap(), "earlier", "the earlier entry is untouched");
    use crate::backend::undo::Step;
    let uri = match &entry.steps[..] {
        [Step::Trashed(old), Step::Copied { .. }] => old.uri.clone(),
        other => panic!("the journal carries the colliding entry under its own URI: {other:?}"),
    };
    assert_ne!(uri, "trash:///photo.png", "the colliding entry takes a unique name");
    let name = decode(uri.strip_prefix(URI).expect("a trash URI names its file"));
    assert_eq!(std::fs::read_to_string(xdg.join("Trash/files").join(&name)).unwrap(), "there");
    assert!(xdg.join("Trash/info").join(format!("{name}.trashinfo")).is_file(), "the info file matches the unique name");
}

#[test]
fn undo_restores_a_home_trashed_replace_to_its_gvfs_path() {
    let d = TestDir::new("replace261-undo");
    let xdg = d.dir("xdg");
    let dest = gvfs_dest(&d);
    d.dir("from");
    let photo = d.file("from/photo.png", "yours");
    let there = d.file("run/1000/gvfs/sftp:host=slot.test/home/gm/photo.png", "there");
    let _root = test_trash_root(&xdg.join("Trash"));
    let _trash = gvfs_trash(&d, &xdg);
    let (ok, _, _, errors, entry) = transfer(false, &[&photo], &dest, chosen("replace", asked(1, &[&photo], &dest), &dest));
    assert!(errors.is_empty(), "the Replace lands first: {errors:?}");
    assert_eq!(ok, 1);
    let mut journal = Journal::new();
    journal.push(entry);
    d.assert_contains(&there);
    assert_eq!(journal.undo().unwrap(), "copy");
    assert_eq!(text(&there), "there", "one undo takes the new item away and restores the old one");
    assert_eq!(text(&photo), "yours");
}

#[test]
fn an_ordinary_destination_on_the_home_trash_filesystem_uses_the_home_trash() {
    let d = TestDir::new("replace261-gio");
    let xdg = d.dir("xdg");
    let _root = test_trash_root(&xdg.join("Trash"));
    let to = d.dir("to");
    d.dir("from");
    assert!(trashable(&to), "an ordinary destination keeps its Trash");
    let photo = d.file("from/photo.png", "yours");
    let there = d.file("to/photo.png", "there");
    let seen: Rc<std::cell::Cell<bool>> = Rc::new(std::cell::Cell::new(false));
    let flag = Rc::clone(&seen);
    let can = d.dir("can");
    let held = xdg.clone();
    trash::STAND_IN.with(|slot| *slot.borrow_mut() = Some(Rc::new(move |args: &[&str]| {
        if matches!(args, ["trash", "--", ..]) {
            flag.set(true);
        }
        Some(gio_like(&can, &held, args))
    })));
    let _trash = StandIn;
    let (ok, failed, _, errors, entry) = transfer(false, &[&photo], &to, chosen("replace", asked(1, &[&photo], &to), &to));
    assert!(errors.is_empty(), "the ordinary Replace succeeds: {errors:?}");
    assert_eq!((ok, failed), (1, 0));
    assert_eq!(text(&there), "yours");
    use crate::backend::undo::Step;
    assert!(matches!(&entry.steps[..], [Step::Trashed(old), Step::Copied { .. }] if old.uri.starts_with(URI)),
        "the journal carries the home Trash entry: {:?}", entry.steps);
    assert!(!seen.get(), "the home Trash handles the ordinary destination, never gio");
    assert_eq!(text(&xdg.join("Trash/files/photo.png")), "there", "the replaced item waits in the home Trash");
    assert!(xdg.join("Trash/info/photo.png.trashinfo").is_file(), "with its record beside it");
}

// A refusal for any other reason keeps today's message: gio refusing on an ordinary path still refuses.
#[test]
fn a_gio_refusal_on_an_ordinary_destination_keeps_todays_message() {
    let d = TestDir::new("replace261-refused");
    let to = d.dir("to");
    d.dir("from");
    let photo = d.file("from/photo.png", "yours");
    let there = d.file("to/photo.png", "there");
    let _trash = refusing_trash();
    let (ok, failed, _, errors, entry) = transfer(false, &[&photo], &to, chosen("replace", asked(1, &[&photo], &to), &to));
    assert_eq!((ok, failed), (0, 1));
    assert_eq!(errors, vec![TRASH_REFUSED.to_string()]);
    assert_eq!((text(&there), text(&photo)), ("there".to_string(), "yours".to_string()));
    assert!(entry.steps.is_empty());
}

#[test]
fn a_full_home_trash_filesystem_has_its_own_refusal_sentence() {
    use crate::backend::hometrash::{sentence_after_copy, sentence_for_io, HOME_TRASH_FAILED, HOME_TRASH_FULL};
    assert_eq!(sentence_after_copy(0), HOME_TRASH_FULL);
    assert_eq!(sentence_after_copy(1 << 30), HOME_TRASH_FAILED);
    assert_eq!(sentence_for_io(&std::io::Error::from_raw_os_error(28)), HOME_TRASH_FULL);
    assert_eq!(sentence_for_io(&std::io::Error::from_raw_os_error(13)), HOME_TRASH_FAILED);
}

#[test]
fn trash_file_names_encode_every_byte_outside_the_unreserved_set() {
    use crate::backend::hometrash::percent_encode;
    assert_eq!(percent_encode("photo.png".as_bytes()), "photo.png");
    assert_eq!(percent_encode("my photo.png".as_bytes()), "my%20photo.png");
    assert_eq!(percent_encode("sftp:host=x/y".as_bytes()), "sftp%3Ahost%3Dx/y");
    assert_eq!(decode(&percent_encode("café / 100%.txt".as_bytes())), "café / 100%.txt");
}

#[test]
fn without_an_override_a_test_never_names_a_real_trash() {
    use crate::backend::hometrash::{set_test_trash_root, trash_to_home, HOME_TRASH_FAILED};
    set_test_trash_root(None);
    let d = TestDir::new("replace261-no-override");
    let there = d.file("photo.png", "there");
    assert_eq!(trash_to_home(&there, &std::sync::atomic::AtomicBool::new(false)).expect_err("no override names no Trash"), HOME_TRASH_FAILED);
    assert_eq!(text(&there), "there", "the original never moved");
    assert!(!d.path().join("Trash").exists(), "no Trash directory was created in the sandbox");
}

#[path = "hometrashfix_tests.rs"]
mod fixes;
