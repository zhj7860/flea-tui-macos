use super::*;
use crate::backend::trashmanifest::logged;
use std::os::unix::fs::PermissionsExt;

#[test]
fn recovery_reports_restored_items_when_its_folder_cannot_be_reopened_for_sync() {
    let d = TestDir::new("recovery-cleanup-reopen");
    let (reviewed, quarantine, journal) = fixture(&d, None, None);
    claim(&d, &reviewed, &quarantine, true);
    let record = journal.path.clone();
    drop(journal);
    let root = d.join("recovery");
    guard(&d, &root);
    let entry = std::fs::read_dir(&root).unwrap().next().unwrap().unwrap();
    let seen = logged().len();
    std::fs::set_permissions(&root, std::fs::Permissions::from_mode(0o300)).unwrap();
    let report = recover_entries(&root, [Ok(entry)]);
    std::fs::set_permissions(&root, std::fs::Permissions::from_mode(0o700)).unwrap();
    let report = report.unwrap();
    assert_eq!(report.recovered, 0);
    assert_eq!(report.failures, [format!("{}: The interrupted operation was recovered, but after removing its recovery record, Flea could not confirm the removal on disk: permission denied.", record.display())]);
    assert!(logged()[seen..].iter().any(|line| line.contains("RecordUnconfirmed(None)") && line.contains("Could not open Trash folder") && line.contains("Permission denied")));
    assert_eq!(std::fs::read_to_string(&reviewed.path).unwrap(), "payload");
    assert_eq!(identity(&reviewed.info).unwrap(), reviewed.metadata);
    assert!(!quarantine.exists());
    assert!(!record.exists());
}

#[test]
fn recovery_keeps_completed_records_in_its_report_after_an_entry_read_error() {
    let d = TestDir::new("recovery-entry-error");
    let (reviewed, quarantine, journal) = fixture(&d, None, None);
    claim(&d, &reviewed, &quarantine, true);
    let record = journal.path.clone();
    drop(journal);
    let root = d.join("recovery");
    guard(&d, &root);
    let entry = std::fs::read_dir(&root).unwrap().next().unwrap().unwrap();
    let seen = logged().len();
    let entries = [Ok(entry), Err(std::io::Error::from_raw_os_error(5))].into_iter()
        .chain(std::iter::once_with(|| panic!("recovery must stop after an entry read error")));
    let unread = d.file("recovery/.flea-delete-unvisited.review", "unvisited record");
    let report = recover_entries(&root, entries).unwrap();
    assert_eq!(report.recovered, 1);
    assert_eq!(report.failures, [format!("{}: Flea could not read the recovery folder at {}: the drive could not read or write the data; records not yet read were left in place.", root.display(), root.display())]);
    assert!(logged()[seen..].iter().any(|line| line.contains("RecoveryUnreadable(") && line.contains("Could not read the recovery folder") && line.contains("Input/output error")));
    assert_eq!(std::fs::read_to_string(&reviewed.path).unwrap(), "payload");
    assert_eq!(identity(&reviewed.info).unwrap(), reviewed.metadata);
    assert!(!quarantine.exists());
    assert!(!record.exists());
    assert_eq!(std::fs::read_to_string(unread).unwrap(), "unvisited record");
}

#[test]
fn recovery_log_checks_exclude_lines_from_before_the_operation() {
    for detail in ["without overwriting", "without a completion record"] {
        crate::backend::trashmanifest::log(detail);
        let seen = logged().len();
        crate::backend::trashmanifest::log("the current operation failed elsewhere");
        assert!(!logged_after(seen, detail), "a stale line satisfied the current operation's log check");
        assert!(logged_after(seen, "the current operation failed elsewhere"));
    }
}

#[test]
fn recovery_finishes_marked_cleanup_before_and_after_quarantine_removal() {
    for removed in [false, true] {
        let d = TestDir::new("recovery-missing-completed");
        let (reviewed, quarantine, mut journal) = fixture(&d, None, None);
        claim(&d, &reviewed, &quarantine, true);
        remove_file(&d, &quarantine.join("payload"));
        remove_file(&d, &quarantine.join("metadata"));
        guard(&d, &quarantine);
        if removed {
            journal.remove_empty(&quarantine, &open_dir(&quarantine).unwrap(), &open_dir(&d.join("files")).unwrap()).unwrap();
        } else {
            journal.record.append(FINISHED).unwrap();
            journal.record.sync().unwrap();
        }
        let record = journal.path.clone();
        drop(journal);
        clean(&d, &quarantine, &record);
        assert!(!reviewed.path.exists());
        assert!(!reviewed.info.exists());
    }
}
