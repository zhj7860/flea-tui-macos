// Approved refusal sentences stay independent of the reason and detail supplied by the provider.
use super::*;
use Op::{Delete, Restore};

macro_rules! refusal {
    ($name:ident, $outcome:expr, $shown:literal) => {
        #[test]
        fn $name() {
            let detail = "provider path /raw/item, errno 5";
            let seen = logged().len();
            let refusal = Refusal::new($outcome, detail).because("permission denied.").logged();
            assert_eq!(refusal.shown(), $shown);
            assert_eq!(refusal.to_string(), $shown);
            assert_eq!(String::from(refusal), $shown);
            let lines = logged();
            assert_eq!(lines.len(), seen + 1);
            assert!(lines[seen].contains(detail), "{}", lines[seen]);
            assert!(!$shown.contains(detail));
        }
    };
}

refusal!(changed, Outcome::Changed,
    "The Trash changed, so nothing was done. Try again.");
refusal!(confirmagain, Outcome::ConfirmAgain,
    "The Trash changed, so nothing was done; confirm again.");
refusal!(nothingdeleted, Outcome::NothingDeleted,
    "The Trash changed, so nothing was deleted.");
refusal!(itemchanged, Outcome::ItemChanged,
    "The item changed after you confirmed, so nothing was deleted.");
refusal!(damaged, Outcome::Damaged,
    "The Trash record for this item is damaged, so nothing was restored.");
refusal!(kept_at, Outcome::Kept(PathBuf::from("/kept")),
    "The Trash changed, so nothing was done. Kept items are in /kept.");
refusal!(prepare_delete, Outcome::Prepare(Delete),
    "Could not prepare the deletion, so nothing was deleted: permission denied.");
refusal!(prepare_restore, Outcome::Prepare(Restore),
    "Could not prepare the restore, so nothing was restored: permission denied.");
refusal!(norecord_delete, Outcome::NoRecord(Delete),
    "Flea could not keep a record of this deletion, so nothing was deleted: permission denied.");
refusal!(norecord_restore, Outcome::NoRecord(Restore),
    "Flea could not keep a record of this restore, so nothing was restored: permission denied.");
refusal!(stuck_delete_at, Outcome::Stuck(Delete, PathBuf::from("/kept")),
    "The deletion could not finish: permission denied. The remaining items are kept at /kept.");
refusal!(stuck_restore_at, Outcome::Stuck(Restore, PathBuf::from("/kept")),
    "The restore could not finish: permission denied. The remaining items are kept at /kept.");
refusal!(stuckintrash_delete_at, Outcome::StuckInTrash(Delete, PathBuf::from("/kept")),
    "The deletion could not finish: permission denied. The remaining items are kept in the Trash and at /kept.");
refusal!(stuckintrash_restore_at, Outcome::StuckInTrash(Restore, PathBuf::from("/kept")),
    "The restore could not finish: permission denied. The remaining items are kept in the Trash and at /kept.");
refusal!(stuckatoriginal_at, Outcome::StuckAtOriginal(PathBuf::from("/kept")),
    "The deletion could not finish: permission denied. The remaining items are kept where they were and at /kept.");
refusal!(partial_delete, Outcome::Partial(Delete),
    "The item could not be fully deleted: permission denied. What is left stays in the Trash, and a folder may be partly deleted.");
refusal!(partial_restore, Outcome::Partial(Restore),
    "The item could not be restored: permission denied. It stays in the Trash.");
refusal!(partialatoriginal, Outcome::PartialAtOriginal,
    "The item could not be fully deleted: permission denied. What is left stays where it was, and a folder may be partly deleted.");
refusal!(infoleft_delete_at, Outcome::InfoLeft(Delete, PathBuf::from("/kept")),
    "The item was deleted, but a Trash record at /kept could not be removed: permission denied.");
refusal!(infoleft_restore_at, Outcome::InfoLeft(Restore, PathBuf::from("/kept")),
    "The item was restored, but a Trash record at /kept could not be removed: permission denied.");
refusal!(folderleft_delete, Outcome::FolderLeft(Delete, None),
    "The item was deleted, but Flea could not remove its temporary folder: permission denied.");
refusal!(folderleft_restore, Outcome::FolderLeft(Restore, None),
    "The item was restored, but Flea could not remove its temporary folder: permission denied.");
refusal!(recordleft_some_delete, Outcome::RecordLeft(Some(Delete)),
    "The item was deleted, but Flea could not remove its recovery record: permission denied.");
refusal!(recordleft_some_restore, Outcome::RecordLeft(Some(Restore)),
    "The item was restored, but Flea could not remove its recovery record: permission denied.");
refusal!(recordleft_none, Outcome::RecordLeft(None),
    "The interrupted operation was recovered, but Flea could not remove its recovery record: permission denied.");
refusal!(childchanged, Outcome::ChildChanged,
    "An item in the Trash changed, so the rest was kept.");
refusal!(childleft, Outcome::ChildLeft,
    "Some items in the Trash folder could not be deleted: permission denied.");
refusal!(blocked, Outcome::Blocked,
    "The item could not be restored: permission denied.");
refusal!(originalchanged, Outcome::OriginalChanged,
    "The item's original folder changed; select it again.");
refusal!(held_at, Outcome::Held(PathBuf::from("/kept")),
    "Flea found an interrupted Trash operation; its items are kept at /kept.");
refusal!(nothingmoved, Outcome::NothingMoved,
    "Flea found an interrupted Trash operation; nothing was moved.");
refusal!(unreadable, Outcome::Unreadable,
    "The Trash could not be read.");
refusal!(tooktoolong, Outcome::TookTooLong,
    "The Trash took too long to answer.");
refusal!(selectionchanged, Outcome::SelectionChanged,
    "The Trash selection changed; select the items again.");
refusal!(indistinct_true, Outcome::Indistinct(true),
    "Items in this Trash cannot be told apart, so they cannot be selected.");
refusal!(indistinct_false, Outcome::Indistinct(false),
    "Items in this Trash cannot be told apart, so nothing was done.");
refusal!(unchecked_delete, Outcome::Unchecked(Delete),
    "This Trash cannot be checked, so nothing can be deleted from it.");
refusal!(unchecked_restore, Outcome::Unchecked(Restore),
    "This Trash cannot be checked, so nothing can be restored from it.");
refusal!(text_text, Outcome::Text("Whole external sentence.".to_string()),
    "Whole external sentence.");
