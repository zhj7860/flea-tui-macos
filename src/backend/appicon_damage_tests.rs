// A damaged image is the file's fault when 7z says so, so it is recorded as failed, the marker a later view finds.
use super::tests::{failed_and_recorded, fixture, listing, plain};
use super::*;
use crate::backend::testdir::TestDir;

#[test]
fn only_7z_calling_the_data_damaged_is_the_files_fault() {
    let err = |msg: &str| crate::backend::opsreq::op_err("appimage icon", "", msg);
    // The last stderr line 7z printed for a damaged image, quoted from 7-Zip 25.01 on a corrupted squashfs, zip and 7z.
    for line in ["ERROR: Data Error : .DirIcon", "Headers Error", "Unexpected end of archive", "ERROR: CRC Failed : src7/a.bin"] {
        assert_eq!(stop_for(&err(line), false), Stop::Refused, "{}", line);
    }
    assert_eq!(stop_for(&err("the appimage icon tool exited with status 2"), false), Stop::Fault);
}

// Runs the argv unjailed, but keeps stderr, so the stop is the one the jail would have judged.
fn judged(inner: Vec<String>, _image: &Path, _work: &mut Work, _limit: Duration) -> Result<(), Stop> {
    let out = std::process::Command::new(&inner[0]).args(&inner[1..]).stdin(std::process::Stdio::null()).stdout(std::process::Stdio::null()).stderr(std::process::Stdio::piped()).output().unwrap();
    if out.status.success() {
        return Ok(());
    }
    let msg = crate::backend::archivework::failure_message("appimage icon", &out.status, &String::from_utf8_lossy(&out.stderr));
    Err(stop_for(&crate::backend::opsreq::op_err("appimage icon", "", &msg), false))
}

#[test]
fn a_damaged_image_that_lists_but_will_not_extract_is_recorded_as_failed() {
    let d = TestDir::new("appicon-damaged");
    let count = d.path().join("runs");
    // The listing reads fine and the extract prints what 7z printed for a squashfs with a corrupted data block.
    let script = format!("mode=$1; shift\nfor a in \"$@\"; do last=$a; done\necho $mode >> {}\ncase $mode in l) cat \"$last\";; e) echo 'ERROR: Data Error : .DirIcon' >&2; exit 2;; esac", count.display());
    let tool = ["/usr/bin/sh", "-c", &script, "stub"].map(String::from).to_vec();
    let f = fixture("appicon-damaged-image", &listing(&[(".DirIcon", "")]));
    failed_and_recorded(&f, run_with(&tool, judged, plain, &f.tables, &f.job));
    let runs = std::fs::read_to_string(&count).unwrap();
    assert_eq!(runs.lines().collect::<Vec<_>>(), ["l", "e"]);
}
