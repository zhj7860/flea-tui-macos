// The typed Trash outcomes pin visible copy while diagnostics remain available to the log.
use super::super::trashmanifest::{Op, Outcome, Refusal};

fn live(source: &'static str) -> &'static str {
    source.rsplit_once("\n#[cfg(test)]\n").map_or(source, |(code, _)| code)
}

fn assert_shown(cases: &[(Outcome, &str)], retired: &[&str]) {
    for (file, source) in [
        ("trashbrowse.rs", live(include_str!("trashbrowse.rs"))),
        ("trashdelete.rs", live(include_str!("trashdelete.rs"))),
        ("trashdelete/recovery.rs", live(include_str!("trashdelete/recovery.rs"))),
    ] {
        for old in retired {
            assert!(!source.contains(old), "retired wording came back in {file}: {old}");
        }
    }
    for (outcome, plain) in cases {
        let shown = Refusal::new(outcome.clone(), "provider diagnostic").because("permission denied").shown();
        assert_eq!(&shown, plain);
        for old in retired {
            assert!(!shown.contains(old), "retired wording came back: {}", old);
        }
    }
}

#[test]
fn the_trash_browser_says_each_outcome_in_one_plain_sentence() {
    assert_shown(&[
        (Outcome::Unreadable, "The Trash could not be read."),
        (Outcome::TookTooLong, "The Trash took too long to answer."),
        (Outcome::ConfirmAgain, "The Trash changed, so nothing was done; confirm again."),
        (Outcome::SelectionChanged, "The Trash selection changed; select the items again."),
        (Outcome::Indistinct(true), "Items in this Trash cannot be told apart, so they cannot be selected."),
        (Outcome::Indistinct(false), "Items in this Trash cannot be told apart, so nothing was done."),
        (Outcome::Unchecked(Op::Delete), "This Trash cannot be checked, so nothing can be deleted from it."),
        (Outcome::Unchecked(Op::Restore), "This Trash cannot be checked, so nothing can be restored from it."),
    ], &[
        "Could not run the Trash helper", "GIO Trash request", "gio failed", "GIO returned", "GIO did not report", "review a fresh confirmation",
        "Trash selection has no reviewed", "Trash selection expired", "did not report stable item", "Trash backing identity",
    ]);
}

#[test]
fn the_trash_deletion_path_says_folder_and_confirm_again() {
    assert_shown(&[
        (Outcome::Changed, "The Trash changed, so nothing was done. Try again."),
        (Outcome::ConfirmAgain, "The Trash changed, so nothing was done; confirm again."),
        (Outcome::OriginalChanged, "The item's original folder changed; select it again."),
        (Outcome::Prepare(Op::Delete), "Could not prepare the deletion, so nothing was deleted: permission denied."),
        (Outcome::Prepare(Op::Restore), "Could not prepare the restore, so nothing was restored: permission denied."),
        (Outcome::NoRecord(Op::Delete), "Flea could not keep a record of this deletion, so nothing was deleted: permission denied."),
        (Outcome::NoRecord(Op::Restore), "Flea could not keep a record of this restore, so nothing was restored: permission denied."),
        (Outcome::NothingMoved, "Flea found an interrupted Trash operation; nothing was moved."),
        (Outcome::RecordUnconfirmed(Some(Op::Delete)), "The item was deleted, but after removing its recovery record, Flea could not confirm the removal on disk: permission denied."),
        (Outcome::RecordUnconfirmed(Some(Op::Restore)), "The item was restored, but after removing its recovery record, Flea could not confirm the removal on disk: permission denied."),
        (Outcome::RecordUnconfirmed(None), "The interrupted operation was recovered, but after removing its recovery record, Flea could not confirm the removal on disk: permission denied."),
        (Outcome::RecoveryUnreadable("/recovery".into()), "Flea could not read the recovery folder at /recovery: permission denied; records not yet read were left in place."),
        (Outcome::FolderLeft(Op::Delete, Some("/temporary".into())), "The item was deleted, but Flea could not remove its temporary folder at /temporary: permission denied."),
        (Outcome::FolderLeft(Op::Restore, Some("/temporary".into())), "The item was restored, but Flea could not remove its temporary folder at /temporary: permission denied."),
    ], &[
        "review a fresh confirmation", "Could not open Trash directory", "Trash original location changed", "recovery directory",
    ]);
}
